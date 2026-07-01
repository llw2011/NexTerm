/**
 * nexterm_rdp.c - FreeRDP 3.x Windows DLL bridge for Flutter FFI
 */
#define NEXTERM_RDP_EXPORTS
#include "nexterm_rdp.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <freerdp/freerdp.h>
#include <freerdp/client.h>
#include <freerdp/client/cliprdr.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/settings.h>
#include <freerdp/channels/channels.h>
#include <winpr/wtypes.h>
#include <winpr/synch.h>
#include <winpr/ssl.h>
#include <winpr/clipboard.h>
#include <winpr/thread.h>

#define TAG "NexTermRDP"

/* ── Extended context ──────────────────────────────────────────────── */
typedef struct {
    rdpClientContext base;
    CRITICAL_SECTION lock;
    HANDLE thread;
    volatile int running;
    volatile int connected;
    volatile int destroying;

    /* Clipboard */
    wClipboard* clipboard;
    CliprdrClientContext* cliprdr;
    BYTE* pendingClipUtf16;
    size_t pendingClipUtf16Bytes;
    CRITICAL_SECTION pendingClipLock;
    int pendingClipLockInit;

    /* Frame */
    FrameCallback frameCallback;
} NexContext;

static NexContext* nex(rdpContext* ctx) { return (NexContext*)ctx; }

static char g_last_error[512] = { 0 };
static ClipboardCallback g_clipboardCallback = NULL;

/* ── Clipboard format constants ────────────────────────────────────── */
#ifndef CF_TEXT
#define CF_TEXT 1
#endif
#ifndef CF_UNICODETEXT
#define CF_UNICODETEXT 13
#endif

/* ── Error helpers ─────────────────────────────────────────────────── */
static void set_last_error(const char* msg) {
    if (!msg) msg = "";
    _snprintf_s(g_last_error, sizeof(g_last_error), _TRUNCATE, "%s", msg);
}

static void set_last_errorf(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(g_last_error, sizeof(g_last_error), fmt, ap);
    va_end(ap);
}

/* ── Clipboard callbacks ───────────────────────────────────────────── */
static void on_remote_clipboard_changed(const char* text) {
    if (text && g_clipboardCallback) {
        g_clipboardCallback(text);
    }
}

static UINT nex_cliprdr_monitor_ready(CliprdrClientContext* cliprdr,
                                       const CLIPRDR_MONITOR_READY* monitorReady) {
    (void)monitorReady;
    NexContext* nc = (NexContext*)cliprdr->custom;
    if (!nc) return ERROR_INVALID_PARAMETER;

    CLIPRDR_CAPABILITIES caps = {0};
    CLIPRDR_GENERAL_CAPABILITY_SET general = {0};
    caps.cCapabilitiesSets = 1;
    caps.capabilitySets = (CLIPRDR_CAPABILITY_SET*)&general;
    general.capabilitySetType = CB_CAPSTYPE_GENERAL;
    general.capabilitySetLength = CB_CAPSTYPE_GENERAL_LEN;
    general.version = CB_CAPS_VERSION_2;
    general.generalFlags = CB_USE_LONG_FORMAT_NAMES;
    if (cliprdr->ClientCapabilities)
        cliprdr->ClientCapabilities(cliprdr, &caps);

    CLIPRDR_FORMAT_LIST formatList = {0};
    formatList.common.msgType = CB_FORMAT_LIST;
    formatList.numFormats = 1;
    formatList.formats = calloc(1, sizeof(CLIPRDR_FORMAT));
    if (formatList.formats) {
        formatList.formats[0].formatId = CF_UNICODETEXT;
        if (cliprdr->ClientFormatList)
            cliprdr->ClientFormatList(cliprdr, &formatList);
        free(formatList.formats);
    }
    return CHANNEL_RC_OK;
}

static UINT nex_cliprdr_server_capabilities(CliprdrClientContext* cliprdr,
                                            const CLIPRDR_CAPABILITIES* caps) {
    (void)cliprdr; (void)caps;
    return CHANNEL_RC_OK;
}

static UINT nex_cliprdr_server_format_list(CliprdrClientContext* cliprdr,
                                           const CLIPRDR_FORMAT_LIST* formatList) {
    NexContext* nc = (NexContext*)cliprdr->custom;
    if (!nc) return ERROR_INVALID_PARAMETER;

    for (UINT32 i = 0; i < formatList->numFormats; i++) {
        UINT32 fid = formatList->formats[i].formatId;
        if (fid == CF_UNICODETEXT || fid == CF_TEXT) {
            CLIPRDR_FORMAT_DATA_REQUEST req = {0};
            req.common.msgType = CB_FORMAT_DATA_REQUEST;
            req.requestedFormatId = fid;
            if (cliprdr->ClientFormatDataRequest)
                cliprdr->ClientFormatDataRequest(cliprdr, &req);
            break;
        }
    }
    return CHANNEL_RC_OK;
}

static UINT nex_cliprdr_server_format_data_response(CliprdrClientContext* cliprdr,
                                                    const CLIPRDR_FORMAT_DATA_RESPONSE* resp) {
    (void)cliprdr;
    if (resp->common.msgFlags != CB_RESPONSE_OK || !resp->requestedFormatData)
        return CHANNEL_RC_OK;

    UINT32 dataLen = resp->common.dataLen;
    if (dataLen == 0) return CHANNEL_RC_OK;

    /* Try UTF-16LE to UTF-8 conversion */
    int wideLen = (int)(dataLen / sizeof(WCHAR));
    int utf8Len = WideCharToMultiByte(CP_UTF8, 0, (LPCWCH)resp->requestedFormatData,
                                       wideLen, NULL, 0, NULL, NULL);
    if (utf8Len > 0) {
        char* utf8 = calloc(utf8Len + 1, 1);
        if (utf8) {
            WideCharToMultiByte(CP_UTF8, 0, (LPCWCH)resp->requestedFormatData,
                               wideLen, utf8, utf8Len, NULL, NULL);
            on_remote_clipboard_changed(utf8);
            free(utf8);
        }
    }
    return CHANNEL_RC_OK;
}

static UINT nex_cliprdr_server_format_list_response(CliprdrClientContext* c,
    const CLIPRDR_FORMAT_LIST_RESPONSE* r) { (void)c; (void)r; return CHANNEL_RC_OK; }
static UINT nex_cliprdr_server_format_data_request(CliprdrClientContext* cliprdr,
    const CLIPRDR_FORMAT_DATA_REQUEST* req) {
    NexContext* nc = (NexContext*)cliprdr->custom;
    if (!nc || !cliprdr->ClientFormatDataResponse) return CHANNEL_RC_OK;

    CLIPRDR_FORMAT_DATA_RESPONSE resp = {0};
    resp.common.msgType = CB_FORMAT_DATA_RESPONSE;
    resp.common.msgFlags = CB_RESPONSE_FAIL;
    resp.common.dataLen = 0;
    resp.requestedFormatData = NULL;

    BYTE* copy = NULL;
    size_t bytes = 0;
    if (nc->pendingClipLockInit) EnterCriticalSection(&nc->pendingClipLock);
    if (nc->pendingClipUtf16 && nc->pendingClipUtf16Bytes > 0 &&
        (req->requestedFormatId == CF_UNICODETEXT || req->requestedFormatId == CF_TEXT)) {
        bytes = nc->pendingClipUtf16Bytes;
        copy = (BYTE*)malloc(bytes);
        if (copy) memcpy(copy, nc->pendingClipUtf16, bytes);
    }
    if (nc->pendingClipLockInit) LeaveCriticalSection(&nc->pendingClipLock);

    if (copy) {
        resp.common.msgFlags = CB_RESPONSE_OK;
        resp.common.dataLen = (UINT32)bytes;
        resp.requestedFormatData = copy;
    }

    UINT rc = cliprdr->ClientFormatDataResponse(cliprdr, &resp);
    free(copy);
    return rc;
}
static UINT nex_cliprdr_server_lock(CliprdrClientContext* c,
    const CLIPRDR_LOCK_CLIPBOARD_DATA* r) { (void)c; (void)r; return CHANNEL_RC_OK; }
static UINT nex_cliprdr_server_unlock(CliprdrClientContext* c,
    const CLIPRDR_UNLOCK_CLIPBOARD_DATA* r) { (void)c; (void)r; return CHANNEL_RC_OK; }
static UINT nex_cliprdr_server_file_req(CliprdrClientContext* c,
    const CLIPRDR_FILE_CONTENTS_REQUEST* r) { (void)c; (void)r; return CHANNEL_RC_OK; }
static UINT nex_cliprdr_server_file_resp(CliprdrClientContext* c,
    const CLIPRDR_FILE_CONTENTS_RESPONSE* r) { (void)c; (void)r; return CHANNEL_RC_OK; }

/* ── Channel events ────────────────────────────────────────────────── */
static void nex_OnChannelConnected(void* context, const ChannelConnectedEventArgs* e) {
    if (!context || !e) return;
    NexContext* nc = (NexContext*)context;
    if (strcmp(e->name, CLIPRDR_SVC_CHANNEL_NAME) == 0) {
        CliprdrClientContext* cliprdr = (CliprdrClientContext*)e->pInterface;
        if (!cliprdr) return;
        if (!nc->clipboard) nc->clipboard = ClipboardCreate();
        cliprdr->custom = (void*)nc;
        cliprdr->MonitorReady = nex_cliprdr_monitor_ready;
        cliprdr->ServerCapabilities = nex_cliprdr_server_capabilities;
        cliprdr->ServerFormatList = nex_cliprdr_server_format_list;
        cliprdr->ServerFormatListResponse = nex_cliprdr_server_format_list_response;
        cliprdr->ServerFormatDataRequest = nex_cliprdr_server_format_data_request;
        cliprdr->ServerFormatDataResponse = nex_cliprdr_server_format_data_response;
        cliprdr->ServerLockClipboardData = nex_cliprdr_server_lock;
        cliprdr->ServerUnlockClipboardData = nex_cliprdr_server_unlock;
        cliprdr->ServerFileContentsRequest = nex_cliprdr_server_file_req;
        cliprdr->ServerFileContentsResponse = nex_cliprdr_server_file_resp;
        nc->cliprdr = cliprdr;
    }
}

static void nex_OnChannelDisconnected(void* context, const ChannelDisconnectedEventArgs* e) {
    if (!context || !e) return;
    NexContext* nc = (NexContext*)context;
    if (strcmp(e->name, CLIPRDR_SVC_CHANNEL_NAME) == 0)
        nc->cliprdr = NULL;
}

/* ── Send clipboard to server ──────────────────────────────────────── */
static void nex_send_clipboard_to_server(NexContext* nc, const char* text) {
    if (!nc || !nc->cliprdr || !text) return;

    /* Convert UTF-8 to UTF-16LE; -1 includes terminating NUL. */
    int wideChars = MultiByteToWideChar(CP_UTF8, 0, text, -1, NULL, 0);
    if (wideChars <= 0) return;
    size_t bytes = (size_t)wideChars * sizeof(WCHAR);
    BYTE* payload = (BYTE*)malloc(bytes);
    if (!payload) return;
    if (MultiByteToWideChar(CP_UTF8, 0, text, -1, (LPWSTR)payload, wideChars) <= 0) {
        free(payload);
        return;
    }

    if (nc->pendingClipLockInit) EnterCriticalSection(&nc->pendingClipLock);
    free(nc->pendingClipUtf16);
    nc->pendingClipUtf16 = payload;
    nc->pendingClipUtf16Bytes = bytes;
    if (nc->pendingClipLockInit) LeaveCriticalSection(&nc->pendingClipLock);

    CLIPRDR_FORMAT_LIST formatList = {0};
    formatList.common.msgType = CB_FORMAT_LIST;
    formatList.numFormats = 1;
    formatList.formats = calloc(1, sizeof(CLIPRDR_FORMAT));
    if (formatList.formats) {
        formatList.formats[0].formatId = CF_UNICODETEXT;
        if (nc->cliprdr->ClientFormatList)
            nc->cliprdr->ClientFormatList(nc->cliprdr, &formatList);
        free(formatList.formats);
    }
}

/* ── GDI callbacks ─────────────────────────────────────────────────── */
static BOOL cb_begin_paint(rdpContext* ctx) { (void)ctx; return TRUE; }

static BOOL cb_end_paint(rdpContext* ctx) {
    rdpGdi* gdi = ctx->gdi;
    if (!gdi || !gdi->primary_buffer) return TRUE;
    NexContext* nc = nex(ctx);
    if (nc->frameCallback)
        nc->frameCallback(gdi->primary_buffer, (int)gdi->width, (int)gdi->height);
    return TRUE;
}

static BOOL cb_desktop_resize(rdpContext* ctx) {
    rdpSettings* s = ctx->settings;
    return gdi_resize(ctx->gdi,
        freerdp_settings_get_uint32(s, FreeRDP_DesktopWidth),
        freerdp_settings_get_uint32(s, FreeRDP_DesktopHeight));
}

/* ── Pre/post connect ──────────────────────────────────────────────── */
static BOOL client_pre_connect(freerdp* inst) {
    rdpSettings* settings = inst->context->settings;
    PubSub_SubscribeChannelConnected(inst->context->pubSub, nex_OnChannelConnected);
    PubSub_SubscribeChannelDisconnected(inst->context->pubSub, nex_OnChannelDisconnected);

    if (!freerdp_settings_set_bool(settings, FreeRDP_SoftwareGdi, TRUE) ||
        !freerdp_settings_set_uint32(settings, FreeRDP_ColorDepth, 32) ||
        !freerdp_settings_set_bool(settings, FreeRDP_BitmapCacheEnabled, FALSE) ||
        !freerdp_settings_set_bool(settings, FreeRDP_SupportGraphicsPipeline, FALSE)) {
        set_last_error("PreConnect: failed to configure graphics");
        return FALSE;
    }
    return TRUE;
}

static BOOL client_post_connect(freerdp* inst) {
    if (!gdi_init(inst, PIXEL_FORMAT_BGRA32)) {
        set_last_error("PostConnect: gdi_init failed");
        return FALSE;
    }
    inst->context->update->BeginPaint = cb_begin_paint;
    inst->context->update->EndPaint = cb_end_paint;
    inst->context->update->DesktopResize = cb_desktop_resize;
    return TRUE;
}

static void client_post_disconnect(freerdp* inst) {
    if (inst && inst->context && inst->context->gdi)
        gdi_free(inst);
}

static DWORD client_verify_certificate_ex(freerdp* inst, const char* host, UINT16 port,
    const char* cn, const char* subj, const char* issuer, const char* fp, DWORD flags) {
    (void)inst; (void)cn; (void)subj; (void)issuer; (void)fp; (void)host; (void)port; (void)flags;
    return 2;
}

static DWORD client_verify_changed_certificate_ex(freerdp* inst, const char* host, UINT16 port,
    const char* cn, const char* subj, const char* issuer, const char* nfp,
    const char* os, const char* oi, const char* ofp, DWORD flags) {
    (void)inst; (void)cn; (void)subj; (void)issuer; (void)nfp;
    (void)os; (void)oi; (void)ofp; (void)host; (void)port; (void)flags;
    return 2;
}

/* ── Client entry points ───────────────────────────────────────────── */
static BOOL client_new(freerdp* inst, rdpContext* ctx) {
    NexContext* nc = nex(ctx);
    InitializeCriticalSection(&nc->lock);
    InitializeCriticalSection(&nc->pendingClipLock);
    nc->pendingClipLockInit = 1;
    nc->thread = NULL;
    nc->running = 0;
    nc->connected = 0;
    nc->destroying = 0;
    nc->clipboard = NULL;
    nc->cliprdr = NULL;
    nc->pendingClipUtf16 = NULL;
    nc->pendingClipUtf16Bytes = 0;
    nc->frameCallback = NULL;

    inst->PreConnect = client_pre_connect;
    inst->PostConnect = client_post_connect;
    inst->PostDisconnect = client_post_disconnect;
    inst->VerifyCertificateEx = client_verify_certificate_ex;
    inst->VerifyChangedCertificateEx = client_verify_changed_certificate_ex;
    return TRUE;
}

static void client_free(freerdp* inst, rdpContext* ctx) {
    (void)inst;
    NexContext* nc = nex(ctx);
    DeleteCriticalSection(&nc->lock);
    if (nc->pendingClipLockInit) {
        EnterCriticalSection(&nc->pendingClipLock);
        free(nc->pendingClipUtf16);
        nc->pendingClipUtf16 = NULL;
        nc->pendingClipUtf16Bytes = 0;
        LeaveCriticalSection(&nc->pendingClipLock);
        DeleteCriticalSection(&nc->pendingClipLock);
        nc->pendingClipLockInit = 0;
    } else if (nc->pendingClipUtf16) {
        free(nc->pendingClipUtf16);
        nc->pendingClipUtf16 = NULL;
    }
    if (nc->clipboard) {
        ClipboardDestroy(nc->clipboard);
        nc->clipboard = NULL;
    }
}

static void nexterm_client_entry(RDP_CLIENT_ENTRY_POINTS* ep) {
    memset(ep, 0, sizeof(*ep));
    ep->Size = sizeof(RDP_CLIENT_ENTRY_POINTS_V1);
    ep->Version = RDP_CLIENT_INTERFACE_VERSION;
    ep->ContextSize = sizeof(NexContext);
    ep->ClientNew = client_new;
    ep->ClientFree = client_free;
}

/* ── RDP thread ────────────────────────────────────────────────────── */
static DWORD WINAPI rdp_thread(LPVOID arg) {
    rdpContext* ctx = (rdpContext*)arg;
    NexContext* nc = nex(ctx);
    freerdp* inst = ctx->instance;

    if (!freerdp_connect(inst)) {
        UINT32 err = freerdp_get_last_error(ctx);
        set_last_errorf("freerdp_connect failed (0x%08X: %s)",
                        err, freerdp_get_last_error_string(err));
        nc->running = 0;
        return 1;
    }
    nc->connected = 1;

    while (nc->running) {
        HANDLE events[64];
        DWORD count = freerdp_get_event_handles(ctx, events, 64);
        if (count == 0) break;
        WaitForMultipleObjects(count, events, FALSE, 100);
        if (!freerdp_check_event_handles(ctx)) {
            if (freerdp_get_last_error(ctx) == FREERDP_ERROR_SUCCESS) continue;
            break;
        }
    }

    freerdp_disconnect(inst);
    nc->connected = 0;
    nc->running = 0;
    return 0;
}

/* ── Exported API ──────────────────────────────────────────────────── */
NEXTERM_API int64_t nex_create(
    const char* host, int port,
    const char* user, const char* pass, const char* domain,
    int width, int height, int securityProtocol)
{
    set_last_error("");
    winpr_InitializeSSL(WINPR_SSL_INIT_DEFAULT);

    RDP_CLIENT_ENTRY_POINTS ep = {0};
    nexterm_client_entry(&ep);

    rdpContext* ctx = freerdp_client_context_new(&ep);
    if (!ctx) {
        set_last_error("freerdp_client_context_new failed");
        return 0;
    }

    freerdp* inst = ctx->instance;
    rdpSettings* settings = ctx->settings;

    UINT32 w = (width > 0) ? (UINT32)width : 1280;
    UINT32 h = (height > 0) ? (UINT32)height : 720;

    BOOL ok = TRUE;
    ok &= freerdp_settings_set_string(settings, FreeRDP_ServerHostname, host);
    ok &= freerdp_settings_set_uint32(settings, FreeRDP_ServerPort, (UINT32)port);
    ok &= freerdp_settings_set_string(settings, FreeRDP_Username, user);
    ok &= freerdp_settings_set_string(settings, FreeRDP_Password, pass);
    if (domain && domain[0])
        ok &= freerdp_settings_set_string(settings, FreeRDP_Domain, domain);
    ok &= freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth, w);
    ok &= freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight, h);
    ok &= freerdp_settings_set_uint32(settings, FreeRDP_ColorDepth, 32);
    ok &= freerdp_settings_set_bool(settings, FreeRDP_IgnoreCertificate, TRUE);
    ok &= freerdp_settings_set_bool(settings, FreeRDP_AutoAcceptCertificate, TRUE);
    ok &= freerdp_settings_set_bool(settings, FreeRDP_UnicodeInput, TRUE);
    ok &= freerdp_settings_set_uint32(settings, FreeRDP_TlsSecLevel, 0);

    /* Security protocol */
    switch (securityProtocol) {
        case 1:
            ok &= freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, TRUE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, FALSE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, FALSE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_NegotiateSecurityLayer, FALSE);
            break;
        case 2:
            ok &= freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, FALSE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, TRUE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, FALSE);
            break;
        case 3:
            ok &= freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, FALSE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, FALSE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, TRUE);
            break;
        default:
            ok &= freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, TRUE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, TRUE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, TRUE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_NegotiateSecurityLayer, TRUE);
            break;
    }

    if (!ok) {
        set_last_error("Failed to configure settings");
        freerdp_client_context_free(ctx);
        return 0;
    }
    return (int64_t)(uintptr_t)ctx;
}

NEXTERM_API void nex_connect(int64_t handle) {
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc || nc->thread || nc->running || nc->destroying) return;
    set_last_error("");
    nc->running = 1;
    nc->thread = CreateThread(NULL, 0, rdp_thread, &nc->base.context, 0, NULL);
    if (!nc->thread) {
        nc->running = 0;
        set_last_error("CreateThread failed");
    }
}

NEXTERM_API void nex_disconnect(int64_t handle) {
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc) return;
    nc->running = 0;
    nc->connected = 0;
    freerdp_abort_connect_context(&nc->base.context);
}

NEXTERM_API void nex_destroy(int64_t handle) {
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc) return;
    nc->destroying = 1;
    nex_disconnect(handle);
    if (nc->thread) {
        WaitForSingleObject(nc->thread, 5000);
        CloseHandle(nc->thread);
        nc->thread = NULL;
    }
    freerdp_client_context_free(&nc->base.context);
}

NEXTERM_API int nex_is_running(int64_t handle) {
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    return (nc && !nc->destroying && nc->running) ? 1 : 0;
}

NEXTERM_API int nex_is_connected(int64_t handle) {
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    return (nc && !nc->destroying && nc->connected) ? 1 : 0;
}

NEXTERM_API const char* nex_get_last_error(void) { return g_last_error; }

NEXTERM_API void nex_send_mouse_event(int64_t handle, int x, int y, int flags) {
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc || !nc->running || nc->destroying || !nc->base.context.input) return;
    freerdp_input_send_mouse_event(nc->base.context.input, (UINT16)flags, (UINT16)x, (UINT16)y);
}

NEXTERM_API void nex_send_key_event(int64_t handle, int keycode, int down, int extended) {
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc || !nc->running || nc->destroying || !nc->base.context.input) return;
    UINT16 flags = extended ? KBD_FLAGS_EXTENDED : 0;
    if (!down) flags |= KBD_FLAGS_RELEASE;
    freerdp_input_send_keyboard_event(nc->base.context.input, flags, (UINT16)keycode);
}

NEXTERM_API void nex_send_unicode_event(int64_t handle, int codepoint) {
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc || !nc->running || nc->destroying || !nc->base.context.input) return;
    if (codepoint <= 0 || codepoint > 0xFFFF) return;
    freerdp_input_send_unicode_keyboard_event(nc->base.context.input, 0, (UINT16)codepoint);
    freerdp_input_send_unicode_keyboard_event(nc->base.context.input, KBD_FLAGS_RELEASE, (UINT16)codepoint);
}

NEXTERM_API void nex_send_clipboard_text(int64_t handle, const char* text) {
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc || !text) return;
    nex_send_clipboard_to_server(nc, text);
}

NEXTERM_API void nex_set_clipboard_callback(ClipboardCallback cb) {
    g_clipboardCallback = cb;
}

NEXTERM_API void nex_set_frame_callback(int64_t handle, FrameCallback cb) {
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (nc) nc->frameCallback = cb;
}

NEXTERM_API const uint8_t* nex_get_frame_buffer(int64_t handle) {
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc || !nc->base.context.gdi) return NULL;
    return nc->base.context.gdi->primary_buffer;
}

NEXTERM_API int nex_get_frame_width(int64_t handle) {
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc || !nc->base.context.gdi) return 0;
    return (int)nc->base.context.gdi->width;
}

NEXTERM_API int nex_get_frame_height(int64_t handle) {
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc || !nc->base.context.gdi) return 0;
    return (int)nc->base.context.gdi->height;
}
