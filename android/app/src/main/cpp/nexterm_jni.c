/**
 * nexterm_jni.c  –  FreeRDP 3.x compatible JNI bridge
 */
#include <jni.h>
#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

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
#include <winpr/string.h>

#define TAG "NexTermJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

/* ── Extended context (FreeRDP 3.x: subclass rdpClientContext) ──────── */
typedef struct {
    rdpClientContext base;   /* MUST be first */
    ANativeWindow*   window;
    pthread_mutex_t  lock;
    BOOL             lock_initialized;
    pthread_t        thread;
    BOOL             thread_started;
    volatile int     running;
    volatile int     connected;
    volatile int     destroying;

    /* Clipboard: pending UTF-16LE payload waiting for server FormatDataRequest */
    wClipboard*     clipboard;
    CliprdrClientContext* cliprdr;
    UINT32          requestedServerClipboardFormat;
    BYTE*           pendingClipUtf16;
    size_t          pendingClipUtf16Bytes;
    pthread_mutex_t pendingClipLock;
    BOOL            pendingClipLockInit;
} NexContext;

/* Helper: get NexContext from any rdpContext* */
static NexContext* nex(rdpContext* ctx) { return (NexContext*)ctx; }

static char g_last_error[512] = { 0 };

/* ── Clipboard globals ─────────────────────────────────────────────── */
static JavaVM* g_jvm = NULL;
static jobject g_clipboardCallback = NULL;
static jobject g_clipboardCallbackMethod = NULL;
static jmethodID g_reflectMethodInvoke = NULL;
static pthread_mutex_t g_clipboard_lock = PTHREAD_MUTEX_INITIALIZER;

/* Clipboard format constants */
#ifndef CF_TEXT
#define CF_TEXT 1
#endif
#ifndef CF_UNICODETEXT
#define CF_UNICODETEXT 13
#endif

/* Forward declaration for clipboard callback */
static void on_remote_clipboard_changed_utf16(const WCHAR* text, size_t length);

static UINT nex_cliprdr_client_capabilities(CliprdrClientContext* cliprdr,
                                            const CLIPRDR_CAPABILITIES* capabilities) {
    LOGI("Cliprdr: Server capabilities received");
    return CHANNEL_RC_OK;
}

static UINT nex_cliprdr_monitor_ready(CliprdrClientContext* cliprdr,
                                       const CLIPRDR_MONITOR_READY* monitorReady) {
    LOGI("Cliprdr: Monitor ready");
    NexContext* nc = (NexContext*)cliprdr->custom;
    if (!nc) return ERROR_INVALID_PARAMETER;

    /* Send client capabilities */
    CLIPRDR_CAPABILITIES caps = {0};
    CLIPRDR_GENERAL_CAPABILITY_SET general = {0};
    caps.cCapabilitiesSets = 1;
    caps.capabilitySets = (CLIPRDR_CAPABILITY_SET*)&general;
    general.capabilitySetType = CB_CAPSTYPE_GENERAL;
    general.capabilitySetLength = CB_CAPSTYPE_GENERAL_LEN;
    general.version = CB_CAPS_VERSION_2;
    general.generalFlags = CB_USE_LONG_FORMAT_NAMES;

    if (cliprdr->ClientCapabilities) {
        cliprdr->ClientCapabilities(cliprdr, &caps);
    }

    /* Send format list (text only) */
    CLIPRDR_FORMAT_LIST formatList = {0};
    formatList.common.msgType = CB_FORMAT_LIST;
    formatList.common.msgFlags = 0;
    formatList.numFormats = 1;
    formatList.formats = calloc(1, sizeof(CLIPRDR_FORMAT));
    if (formatList.formats) {
        formatList.formats[0].formatId = CF_UNICODETEXT;
        formatList.formats[0].formatName = NULL;
        if (cliprdr->ClientFormatList) {
            cliprdr->ClientFormatList(cliprdr, &formatList);
        }
        free(formatList.formats);
    }

    return CHANNEL_RC_OK;
}

static UINT nex_cliprdr_server_format_list(CliprdrClientContext* cliprdr,
                                           const CLIPRDR_FORMAT_LIST* formatList) {
    LOGI("Cliprdr: Server format list (%u formats)", formatList->numFormats);
    NexContext* nc = (NexContext*)cliprdr->custom;
    if (!nc) return ERROR_INVALID_PARAMETER;

    UINT32 requestedFormat = 0;
    for (UINT32 i = 0; i < formatList->numFormats; i++) {
        UINT32 formatId = formatList->formats[i].formatId;
        if (formatId == CF_UNICODETEXT) {
            requestedFormat = CF_UNICODETEXT;
            break;
        }
    }
    if (requestedFormat == 0) {
        for (UINT32 i = 0; i < formatList->numFormats; i++) {
            UINT32 formatId = formatList->formats[i].formatId;
            if (formatId == CF_TEXT) {
                requestedFormat = CF_TEXT;
                break;
            }
        }
    }
    if (requestedFormat != 0 && cliprdr->ClientFormatDataRequest) {
        CLIPRDR_FORMAT_DATA_REQUEST request = {0};
        request.common.msgType = CB_FORMAT_DATA_REQUEST;
        request.common.msgFlags = 0;
        request.requestedFormatId = requestedFormat;
        nc->requestedServerClipboardFormat = requestedFormat;
        LOGI("Cliprdr: Requesting server clipboard format %u", requestedFormat);
        cliprdr->ClientFormatDataRequest(cliprdr, &request);
    }
    return CHANNEL_RC_OK;
}

static UINT nex_cliprdr_server_format_data_response(CliprdrClientContext* cliprdr,
                                                    const CLIPRDR_FORMAT_DATA_RESPONSE* formatDataResponse) {
    NexContext* nc = (NexContext*)cliprdr->custom;
    if (!nc) return ERROR_INVALID_PARAMETER;
    if (formatDataResponse->common.msgFlags != CB_RESPONSE_OK) return CHANNEL_RC_OK;

    const BYTE* data = formatDataResponse->requestedFormatData;
    UINT32 dataLen = formatDataResponse->common.dataLen;
    if (!data || dataLen == 0) return CHANNEL_RC_OK;

    LOGI("Cliprdr: Server format data response (format=%u, bytes=%u)",
         nc->requestedServerClipboardFormat, dataLen);

    if (nc->requestedServerClipboardFormat == CF_TEXT) {
        size_t textLen = dataLen;
        while (textLen > 0 && data[textLen - 1] == 0) textLen--;
        if (textLen == 0) return CHANNEL_RC_OK;

        WCHAR* wide = calloc(textLen, sizeof(WCHAR));
        if (!wide) return CHANNEL_RC_OK;
        for (size_t i = 0; i < textLen; i++) {
            wide[i] = (WCHAR)data[i];
        }
        on_remote_clipboard_changed_utf16(wide, textLen);
        free(wide);
        return CHANNEL_RC_OK;
    }

    size_t utf16Len = dataLen / sizeof(WCHAR);
    if (utf16Len == 0) return CHANNEL_RC_OK;
    while (utf16Len > 0 && ((const WCHAR*)data)[utf16Len - 1] == 0) utf16Len--;
    if (utf16Len == 0) return CHANNEL_RC_OK;

    on_remote_clipboard_changed_utf16((const WCHAR*)data, utf16Len);
    return CHANNEL_RC_OK;
}

static UINT nex_cliprdr_server_format_list_response(CliprdrClientContext* cliprdr,
                                                    const CLIPRDR_FORMAT_LIST_RESPONSE* formatListResponse) {
    return CHANNEL_RC_OK;
}

static UINT nex_cliprdr_server_format_data_request(CliprdrClientContext* cliprdr,
                                                   const CLIPRDR_FORMAT_DATA_REQUEST* formatDataRequest) {
    NexContext* nc = (NexContext*)cliprdr->custom;
    if (!nc || !cliprdr->ClientFormatDataResponse) return CHANNEL_RC_OK;

    CLIPRDR_FORMAT_DATA_RESPONSE response = {0};
    response.common.msgType = CB_FORMAT_DATA_RESPONSE;
    response.common.msgFlags = CB_RESPONSE_FAIL;
    response.common.dataLen = 0;
    response.requestedFormatData = NULL;

    BYTE* copy = NULL;
    size_t bytes = 0;
    if (nc->pendingClipLockInit) pthread_mutex_lock(&nc->pendingClipLock);
    if (nc->pendingClipUtf16 && nc->pendingClipUtf16Bytes > 0 &&
        (formatDataRequest->requestedFormatId == CF_UNICODETEXT ||
         formatDataRequest->requestedFormatId == CF_TEXT)) {
        bytes = nc->pendingClipUtf16Bytes;
        copy = malloc(bytes);
        if (copy) memcpy(copy, nc->pendingClipUtf16, bytes);
    }
    if (nc->pendingClipLockInit) pthread_mutex_unlock(&nc->pendingClipLock);

    if (copy) {
        response.common.msgFlags = CB_RESPONSE_OK;
        response.common.dataLen = (UINT32)bytes;
        response.requestedFormatData = copy;
    }

    UINT rc = cliprdr->ClientFormatDataResponse(cliprdr, &response);
    free(copy);
    return rc;
}

static UINT nex_cliprdr_server_lock_clipboard_data(CliprdrClientContext* cliprdr,
                                                   const CLIPRDR_LOCK_CLIPBOARD_DATA* lockClipboardData) {
    return CHANNEL_RC_OK;
}

static UINT nex_cliprdr_server_unlock_clipboard_data(CliprdrClientContext* cliprdr,
                                                   const CLIPRDR_UNLOCK_CLIPBOARD_DATA* unlockClipboardData) {
    return CHANNEL_RC_OK;
}

static UINT nex_cliprdr_server_file_contents_request(CliprdrClientContext* cliprdr,
                                                    const CLIPRDR_FILE_CONTENTS_REQUEST* fileContentsRequest) {
    return CHANNEL_RC_OK;
}

static UINT nex_cliprdr_server_file_contents_response(CliprdrClientContext* cliprdr,
                                                      const CLIPRDR_FILE_CONTENTS_RESPONSE* fileContentsResponse) {
    return CHANNEL_RC_OK;
}

/* Called when cliprdr channel connects */
static void nex_OnChannelConnected(void* context, const ChannelConnectedEventArgs* e) {
    if (!context || !e) return;
    NexContext* nc = (NexContext*)context;

    if (strcmp(e->name, CLIPRDR_SVC_CHANNEL_NAME) == 0) {
        LOGI("Cliprdr: Channel connected");
        CliprdrClientContext* cliprdr = (CliprdrClientContext*)e->pInterface;
        if (!cliprdr) return;

        /* Initialize clipboard */
        if (!nc->clipboard) {
            nc->clipboard = ClipboardCreate();
        }

        /* Setup cliprdr callbacks */
        cliprdr->custom = (void*)nc;
        cliprdr->MonitorReady = nex_cliprdr_monitor_ready;
        cliprdr->ServerCapabilities = nex_cliprdr_client_capabilities;
        cliprdr->ServerFormatList = nex_cliprdr_server_format_list;
        cliprdr->ServerFormatListResponse = nex_cliprdr_server_format_list_response;
        cliprdr->ServerFormatDataRequest = nex_cliprdr_server_format_data_request;
        cliprdr->ServerFormatDataResponse = nex_cliprdr_server_format_data_response;
        cliprdr->ServerLockClipboardData = nex_cliprdr_server_lock_clipboard_data;
        cliprdr->ServerUnlockClipboardData = nex_cliprdr_server_unlock_clipboard_data;
        cliprdr->ServerFileContentsRequest = nex_cliprdr_server_file_contents_request;
        cliprdr->ServerFileContentsResponse = nex_cliprdr_server_file_contents_response;
        nc->cliprdr = cliprdr;

        /* Create clipboard if needed */
        if (!nc->clipboard) {
            nc->clipboard = ClipboardCreate();
        }
    }
}

/* Called when cliprdr channel disconnects */
static void nex_OnChannelDisconnected(void* context, const ChannelDisconnectedEventArgs* e) {
    if (!context || !e) return;
    NexContext* nc = (NexContext*)context;

    if (strcmp(e->name, CLIPRDR_SVC_CHANNEL_NAME) == 0) {
        LOGI("Cliprdr: Channel disconnected");
        nc->cliprdr = NULL;
    }
}

/* ── Send clipboard text from local to remote ─────────────────── */
static void nex_send_clipboard_to_server(NexContext* nc, const char* text) {
    if (!nc || !nc->cliprdr || !text) return;
    if (!nc->pendingClipLockInit) {
        if (pthread_mutex_init(&nc->pendingClipLock, NULL) == 0) {
            nc->pendingClipLockInit = TRUE;
        }
    }

    /* Convert UTF-8 → UTF-16LE for CF_UNICODETEXT. Append explicit terminator. */
    size_t utf16Chars = 0;
    WCHAR* utf16 = ConvertUtf8ToWCharAlloc(text, &utf16Chars);
    if (!utf16) {
        LOGE("nex_send_clipboard_to_server: utf8→utf16 conversion failed");
        return;
    }
    size_t bytes = (utf16Chars + 1) * sizeof(WCHAR); /* +1 for terminating NUL */
    BYTE* payload = malloc(bytes);
    if (!payload) { free(utf16); return; }
    memcpy(payload, utf16, utf16Chars * sizeof(WCHAR));
    payload[bytes - 2] = 0;
    payload[bytes - 1] = 0;
    free(utf16);

    LOGI("nex_send_clipboard_to_server: queued %zu UTF-16 bytes (%zu chars)", bytes, utf16Chars);

    if (nc->pendingClipLockInit) pthread_mutex_lock(&nc->pendingClipLock);
    free(nc->pendingClipUtf16);
    nc->pendingClipUtf16 = payload;
    nc->pendingClipUtf16Bytes = bytes;
    if (nc->pendingClipLockInit) pthread_mutex_unlock(&nc->pendingClipLock);

    /* Advertise CF_UNICODETEXT format to server. Server will call back with
     * ServerFormatDataRequest which we answer from pendingClipUtf16. */
    CLIPRDR_FORMAT_LIST formatList = {0};
    formatList.common.msgType = CB_FORMAT_LIST;
    formatList.common.msgFlags = 0;
    formatList.numFormats = 1;
    formatList.formats = calloc(1, sizeof(CLIPRDR_FORMAT));
    if (formatList.formats) {
        formatList.formats[0].formatId = CF_UNICODETEXT;
        formatList.formats[0].formatName = NULL;
        if (nc->cliprdr->ClientFormatList) {
            nc->cliprdr->ClientFormatList(nc->cliprdr, &formatList);
        }
        free(formatList.formats);
    }
}

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved) {
    (void)reserved;
    g_jvm = vm;
    return JNI_VERSION_1_6;
}

/* Set clipboard callback from Kotlin */
JNIEXPORT void JNICALL Java_com_nexterm_nexterm_RdpBridge_nativeSetClipboardCallback(
    JNIEnv* env, jclass clazz, jobject callback, jobject method)
{
    (void)clazz;
    jobject newCallback = NULL;
    jobject newMethod = NULL;

    if (callback && method) {
        if (!g_reflectMethodInvoke) {
            jclass methodClass = (*env)->FindClass(env, "java/lang/reflect/Method");
            if (methodClass) {
                g_reflectMethodInvoke = (*env)->GetMethodID(
                    env, methodClass, "invoke",
                    "(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;");
                if ((*env)->ExceptionCheck(env)) {
                    LOGE("Reflective clipboard callback method lookup failed");
                    (*env)->ExceptionClear(env);
                    g_reflectMethodInvoke = NULL;
                }
                (*env)->DeleteLocalRef(env, methodClass);
            }
        }
        if (g_reflectMethodInvoke) {
            newCallback = (*env)->NewGlobalRef(env, callback);
            newMethod = (*env)->NewGlobalRef(env, method);
            LOGI("Clipboard callback registered via reflection");
        }
    }

    pthread_mutex_lock(&g_clipboard_lock);
    if (g_clipboardCallback) {
        (*env)->DeleteGlobalRef(env, g_clipboardCallback);
        g_clipboardCallback = NULL;
    }
    if (g_clipboardCallbackMethod) {
        (*env)->DeleteGlobalRef(env, g_clipboardCallbackMethod);
        g_clipboardCallbackMethod = NULL;
    }
    g_clipboardCallback = newCallback;
    g_clipboardCallbackMethod = newMethod;
    pthread_mutex_unlock(&g_clipboard_lock);
}

/* Called from JNI when remote clipboard changes. Input is UTF-16LE from
 * CLIPRDR; build Java String directly instead of using NewStringUTF. */
static void on_remote_clipboard_changed_utf16(const WCHAR* text, size_t length) {
    if (!text || length == 0 || !g_jvm) return;

    JNIEnv* env = NULL;
    jint attached = (*g_jvm)->GetEnv(g_jvm, (void**)&env, JNI_VERSION_1_6);
    if (attached == JNI_EDETACHED) {
        if ((*g_jvm)->AttachCurrentThread(g_jvm, &env, NULL) != 0) {
            return;
        }
    }

    pthread_mutex_lock(&g_clipboard_lock);
    jobject callback = g_clipboardCallback ? (*env)->NewLocalRef(env, g_clipboardCallback) : NULL;
    jobject callbackMethod = g_clipboardCallbackMethod ? (*env)->NewLocalRef(env, g_clipboardCallbackMethod) : NULL;
    jmethodID reflectInvoke = g_reflectMethodInvoke;
    pthread_mutex_unlock(&g_clipboard_lock);

    if (!callback || !callbackMethod || !reflectInvoke) {
        if (callback) {
            (*env)->DeleteLocalRef(env, callback);
        }
        if (callbackMethod) {
            (*env)->DeleteLocalRef(env, callbackMethod);
        }
        if (attached == JNI_EDETACHED) {
            (*g_jvm)->DetachCurrentThread(g_jvm);
        }
        return;
    }

    if (length > 0x7FFFFFFF) length = 0x7FFFFFFF;
    jstring jtext = NULL;
    if (sizeof(WCHAR) == sizeof(jchar)) {
        jtext = (*env)->NewString(env, (const jchar*)text, (jsize)length);
    } else {
        jchar* chars = malloc(length * sizeof(jchar));
        if (chars) {
            for (size_t i = 0; i < length; i++) {
                chars[i] = (jchar)text[i];
            }
            jtext = (*env)->NewString(env, chars, (jsize)length);
            free(chars);
        }
    }

    if (jtext) {
        jclass objectClass = (*env)->FindClass(env, "java/lang/Object");
        jobjectArray args = NULL;
        if (objectClass) {
            args = (*env)->NewObjectArray(env, 1, objectClass, NULL);
            (*env)->DeleteLocalRef(env, objectClass);
        }
        if (args) {
            (*env)->SetObjectArrayElement(env, args, 0, jtext);
            (*env)->CallObjectMethod(env, callbackMethod, reflectInvoke, callback, args);
            (*env)->DeleteLocalRef(env, args);
        }
        if ((*env)->ExceptionCheck(env)) {
            LOGE("Clipboard callback threw an exception");
            (*env)->ExceptionClear(env);
        }
        (*env)->DeleteLocalRef(env, jtext);
    }
    (*env)->DeleteLocalRef(env, callbackMethod);
    (*env)->DeleteLocalRef(env, callback);

    if (attached == JNI_EDETACHED) {
        (*g_jvm)->DetachCurrentThread(g_jvm);
    }
}

/* ── GDI callbacks ─────────────────────────────────────────────────── */
static void set_last_error(const char* message)
{
    if (!message) message = "";
    snprintf(g_last_error, sizeof(g_last_error), "%s", message);
}

static void set_last_errorf(const char* fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(g_last_error, sizeof(g_last_error), fmt, ap);
    va_end(ap);
}

static BOOL cb_begin_paint(rdpContext* ctx) { (void)ctx; return TRUE; }

/* ── GDI callbacks ──────────────────────────────────────────────────── */
static BOOL cb_end_paint(rdpContext* ctx)
{
    rdpGdi* gdi = ctx->gdi;
    if (!gdi || !gdi->primary_buffer) return TRUE;

    NexContext* nc = nex(ctx);

    int w = (int)gdi->width;
    int h = (int)gdi->height;

    pthread_mutex_lock(&nc->lock);
    ANativeWindow* window = nc->window;
    if (window && ANativeWindow_setBuffersGeometry(window, w, h, WINDOW_FORMAT_RGBX_8888) == 0) {
        ANativeWindow_Buffer buf;
        if (ANativeWindow_lock(window, &buf, NULL) == 0) {
            uint8_t* src = gdi->primary_buffer;
            uint8_t* dst = (uint8_t*)buf.bits;
            int src_stride = w * 4;
            int dst_stride = buf.stride * 4;
            for (int y = 0; y < h; y++)
                memcpy(dst + y * dst_stride, src + y * src_stride, (size_t)src_stride);
            ANativeWindow_unlockAndPost(window);
        }
    }
    pthread_mutex_unlock(&nc->lock);
    return TRUE;
}

static BOOL cb_desktop_resize(rdpContext* ctx)
{
    rdpSettings* s = ctx->settings;
    return gdi_resize(ctx->gdi,
        freerdp_settings_get_uint32(s, FreeRDP_DesktopWidth),
        freerdp_settings_get_uint32(s, FreeRDP_DesktopHeight));
}

/* ── Pre/post connect ───────────────────────────────────────────────── */
static BOOL client_pre_connect(freerdp* inst)
{
    rdpSettings* settings = inst->context->settings;
    LOGI("PreConnect: begin");

    /* Subscribe to channel connected/disconnected events for cliprdr */
    PubSub_SubscribeChannelConnected(inst->context->pubSub, nex_OnChannelConnected);
    PubSub_SubscribeChannelDisconnected(inst->context->pubSub, nex_OnChannelDisconnected);

    if (!freerdp_settings_set_bool(settings, FreeRDP_SoftwareGdi, TRUE) ||
        !freerdp_settings_set_uint32(settings, FreeRDP_ColorDepth, 32) ||
        !freerdp_settings_set_bool(settings, FreeRDP_BitmapCacheEnabled, FALSE) ||
        !freerdp_settings_set_bool(settings, FreeRDP_BitmapCachePersistEnabled, FALSE) ||
        !freerdp_settings_set_bool(settings, FreeRDP_SupportGraphicsPipeline, FALSE)) {
        set_last_error("PreConnect: failed to configure graphics settings");
        LOGE("%s", g_last_error);
        return FALSE;
    }
    LOGI("PreConnect: ok");
    return TRUE;
}

static BOOL client_post_connect(freerdp* inst)
{
    LOGI("PostConnect: begin");
    if (!gdi_init(inst, PIXEL_FORMAT_RGBX32)) {
        set_last_error("PostConnect: gdi_init failed");
        LOGE("%s", g_last_error);
        return FALSE;
    }
    inst->context->update->BeginPaint    = cb_begin_paint;
    inst->context->update->EndPaint      = cb_end_paint;
    inst->context->update->DesktopResize = cb_desktop_resize;
    LOGI("PostConnect: ok");
    return TRUE;
}

static void client_post_disconnect(freerdp* inst)
{
    if (inst && inst->context && inst->context->gdi)
        gdi_free(inst);
}

static DWORD client_verify_certificate_ex(
        freerdp* inst, const char* host, UINT16 port,
        const char* common_name, const char* subject,
        const char* issuer, const char* fingerprint, DWORD flags)
{
    (void)inst; (void)common_name; (void)subject; (void)issuer; (void)fingerprint;
    LOGI("accepting certificate for %s:%u (flags=0x%08X)", host ? host : "", port, flags);
    return 2; /* accept for this session */
}

static DWORD client_verify_changed_certificate_ex(
        freerdp* inst, const char* host, UINT16 port,
        const char* common_name, const char* subject,
        const char* issuer, const char* new_fingerprint,
        const char* old_subject, const char* old_issuer,
        const char* old_fingerprint, DWORD flags)
{
    (void)inst; (void)common_name; (void)subject; (void)issuer; (void)new_fingerprint;
    (void)old_subject; (void)old_issuer; (void)old_fingerprint;
    LOGI("accepting changed certificate for %s:%u (flags=0x%08X)", host ? host : "", port, flags);
    return 2; /* accept for this session */
}

static int client_verify_x509_certificate(
        freerdp* inst, const BYTE* data, size_t length,
        const char* hostname, UINT16 port, DWORD flags)
{
    (void)inst; (void)data; (void)length;
    LOGI("accepting X509 certificate for %s:%u (flags=0x%08X)", hostname ? hostname : "", port, flags);
    return 2; /* accept for this session */
}

/* ── RDP_CLIENT_ENTRY_POINTS callbacks ──────────────────────────────── */
static BOOL client_new(freerdp* inst, rdpContext* ctx)
{
    NexContext* nc = nex(ctx);
    if (pthread_mutex_init(&nc->lock, NULL) == 0)
        nc->lock_initialized = TRUE;
    else
        return FALSE;
    nc->window  = NULL;
    nc->thread_started = FALSE;
    nc->running = 0;
    nc->connected = 0;
    nc->destroying = 0;
    nc->clipboard = NULL;
    nc->cliprdr = NULL;
    nc->requestedServerClipboardFormat = 0;
    nc->pendingClipUtf16 = NULL;
    nc->pendingClipUtf16Bytes = 0;
    nc->pendingClipLockInit = (pthread_mutex_init(&nc->pendingClipLock, NULL) == 0);

    inst->PreConnect                 = client_pre_connect;
    inst->PostConnect                = client_post_connect;
    inst->PostDisconnect             = client_post_disconnect;
    inst->VerifyCertificateEx        = client_verify_certificate_ex;
    inst->VerifyChangedCertificateEx = client_verify_changed_certificate_ex;
    inst->VerifyX509Certificate      = client_verify_x509_certificate;
    return TRUE;
}

static void client_free(freerdp* inst, rdpContext* ctx)
{
    (void)inst;
    NexContext* nc = nex(ctx);
    if (nc->lock_initialized) {
        pthread_mutex_lock(&nc->lock);
        if (nc->window) {
            ANativeWindow_release(nc->window);
            nc->window = NULL;
        }
        pthread_mutex_unlock(&nc->lock);
        pthread_mutex_destroy(&nc->lock);
        nc->lock_initialized = FALSE;
    } else if (nc->window) {
        ANativeWindow_release(nc->window);
        nc->window = NULL;
    }
    if (nc->pendingClipLockInit) {
        pthread_mutex_lock(&nc->pendingClipLock);
        free(nc->pendingClipUtf16);
        nc->pendingClipUtf16 = NULL;
        nc->pendingClipUtf16Bytes = 0;
        pthread_mutex_unlock(&nc->pendingClipLock);
        pthread_mutex_destroy(&nc->pendingClipLock);
        nc->pendingClipLockInit = FALSE;
    } else if (nc->pendingClipUtf16) {
        free(nc->pendingClipUtf16);
        nc->pendingClipUtf16 = NULL;
    }
    if (nc->clipboard) {
        ClipboardDestroy(nc->clipboard);
        nc->clipboard = NULL;
    }
}

static void nexterm_client_entry(RDP_CLIENT_ENTRY_POINTS* ep)
{
    memset(ep, 0, sizeof(*ep));
    ep->Size        = sizeof(RDP_CLIENT_ENTRY_POINTS_V1);
    ep->Version     = RDP_CLIENT_INTERFACE_VERSION;
    ep->ContextSize = sizeof(NexContext);
    ep->ClientNew   = client_new;
    ep->ClientFree  = client_free;
}

/* ── Connection thread ──────────────────────────────────────────────── */
static void* rdp_thread(void* arg)
{
    rdpContext* ctx  = (rdpContext*)arg;
    NexContext* nc   = nex(ctx);
    freerdp*    inst = ctx->instance;

    if (!freerdp_connect(inst)) {
        const UINT32 error = freerdp_get_last_error(ctx);
        set_last_errorf("freerdp_connect failed (error 0x%08X: %s)",
                        error, freerdp_get_last_error_string(error));
        LOGE("%s", g_last_error);
        nc->running = 0;
        return NULL;
    }
    nc->connected = 1;
    LOGI("RDP connected");

    while (nc->running) {
        HANDLE events[64];
        DWORD count = freerdp_get_event_handles(ctx, events, 64);
        if (count == 0) break;

        DWORD rc = WaitForMultipleObjects(count, events, FALSE, 100);
        (void)rc;

        if (!freerdp_check_event_handles(ctx)) {
            if (freerdp_get_last_error(ctx) == FREERDP_ERROR_SUCCESS) continue;
            break;
        }
    }

    freerdp_disconnect(inst);
    nc->connected = 0;
    nc->running = 0;
    LOGI("RDP thread exited");
    return NULL;
}

static void request_rdp_stop(NexContext* nc)
{
    if (!nc) return;
    nc->running = 0;
    nc->connected = 0;
    freerdp_abort_connect_context(&nc->base.context);
}

static void join_rdp_thread(NexContext* nc)
{
    if (!nc || !nc->thread_started) return;
    if (pthread_equal(pthread_self(), nc->thread)) return;
    pthread_join(nc->thread, NULL);
    nc->thread_started = FALSE;
}

/* ══════════════════════════════════════════════════════════════════════
   JNI exports
   ══════════════════════════════════════════════════════════════════════ */

JNIEXPORT jlong JNICALL
Java_com_nexterm_nexterm_RdpBridge_nativeCreate(
        JNIEnv* env, jobject thiz,
        jstring jhost, jint port,
        jstring juser, jstring jpass, jstring jdomain,
        jint width, jint height,
        jint securityProtocol)
{
    (void)thiz;
    LOGI("nativeCreate: start (security=%d)", securityProtocol);
    set_last_error("");

    if (setenv("HOME", "/data/data/com.nexterm.nexterm/files", 1) != 0) {
        LOGE("nativeCreate: failed to set HOME");
    }

    if (!winpr_InitializeSSL(WINPR_SSL_INIT_DEFAULT)) {
        set_last_error("winpr_InitializeSSL failed");
        LOGE("%s", g_last_error);
        return 0;
    }

    RDP_CLIENT_ENTRY_POINTS ep = { 0 };
    nexterm_client_entry(&ep);

    LOGI("nativeCreate: calling freerdp_client_context_new (ContextSize=%zu)", sizeof(NexContext));
    rdpContext* ctx = freerdp_client_context_new(&ep);
    if (!ctx) {
        LOGE("freerdp_client_context_new failed (returned NULL)");
        /* Fallback: try freerdp_new directly */
        LOGI("nativeCreate: trying freerdp_new fallback");
        freerdp* inst2 = freerdp_new();
        if (!inst2) {
            set_last_error("freerdp_new failed after freerdp_client_context_new returned NULL");
            LOGE("%s", g_last_error);
            return 0;
        }
        inst2->ContextSize = sizeof(NexContext);
        inst2->ContextNew = client_new;
        inst2->ContextFree = client_free;
        if (!freerdp_context_new(inst2)) {
            set_last_error("freerdp_context_new failed after freerdp_client_context_new returned NULL");
            LOGE("%s", g_last_error);
            freerdp_free(inst2);
            return 0;
        }
        ctx = inst2->context;
        LOGI("nativeCreate: fallback succeeded");
    }
    LOGI("nativeCreate: context created successfully");

    freerdp* inst = ctx->instance;
    if (!inst) {
        set_last_error("ctx->instance is NULL");
        LOGE("%s", g_last_error);
        freerdp_client_context_free(ctx);
        return 0;
    }

    inst->PreConnect     = client_pre_connect;
    inst->PostConnect    = client_post_connect;
    inst->PostDisconnect = client_post_disconnect;

    rdpSettings* settings = ctx->settings;
    if (!settings) {
        set_last_error("ctx->settings is NULL");
        LOGE("%s", g_last_error);
        freerdp_client_context_free(ctx);
        return 0;
    }

    const char* host   = (*env)->GetStringUTFChars(env, jhost,   NULL);
    const char* user   = (*env)->GetStringUTFChars(env, juser,   NULL);
    const char* pass   = (*env)->GetStringUTFChars(env, jpass,   NULL);
    const char* domain = (*env)->GetStringUTFChars(env, jdomain, NULL);

    LOGI("nativeCreate: configuring settings (host=%s, port=%d, user=%s)", host, port, user);

    const UINT32 safe_width = (width > 0) ? (UINT32)width : 1280;
    const UINT32 safe_height = (height > 0) ? (UINT32)height : 720;

    BOOL ok = TRUE;
    ok &= freerdp_settings_set_string(settings, FreeRDP_ServerHostname, host);
    ok &= freerdp_settings_set_uint32(settings, FreeRDP_ServerPort, (UINT32)port);
    ok &= freerdp_settings_set_string(settings, FreeRDP_Username, user);
    ok &= freerdp_settings_set_string(settings, FreeRDP_Password, pass);
    ok &= freerdp_settings_set_string(settings, FreeRDP_ClientHostname, "NexTerm");
    ok &= freerdp_settings_set_string(settings, FreeRDP_ComputerName, "NexTerm");
    if (domain && domain[0])
        ok &= freerdp_settings_set_string(settings, FreeRDP_Domain, domain);
    ok &= freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth, safe_width);
    ok &= freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight, safe_height);
    ok &= freerdp_settings_set_uint32(settings, FreeRDP_ColorDepth, 32);
    ok &= freerdp_settings_set_uint32(settings, FreeRDP_ClientBuild, 22621);
    ok &= freerdp_settings_set_uint32(settings, FreeRDP_DesktopScaleFactor, 100);
    ok &= freerdp_settings_set_uint32(settings, FreeRDP_DeviceScaleFactor, 100);
    rdpMonitor monitor = { 0 };
    monitor.x = 0;
    monitor.y = 0;
    monitor.width = (INT32)safe_width;
    monitor.height = (INT32)safe_height;
    monitor.is_primary = TRUE;
    monitor.orig_screen = 0;
    monitor.attributes.desktopScaleFactor = 100;
    monitor.attributes.deviceScaleFactor = 100;
    ok &= freerdp_settings_set_bool(settings, FreeRDP_Fullscreen, FALSE);
    ok &= freerdp_settings_set_bool(settings, FreeRDP_Workarea, FALSE);
    ok &= freerdp_settings_set_bool(settings, FreeRDP_UseMultimon, FALSE);
    ok &= freerdp_settings_set_bool(settings, FreeRDP_SpanMonitors, FALSE);
    ok &= freerdp_settings_set_monitor_def_array_sorted(settings, &monitor, 1);
    ok &= freerdp_settings_set_bool(settings, FreeRDP_Authentication, TRUE);
    ok &= freerdp_settings_set_bool(settings, FreeRDP_NegotiateSecurityLayer, TRUE);
    ok &= freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, TRUE);
    ok &= freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, TRUE);
    ok &= freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, TRUE);
    ok &= freerdp_settings_set_bool(settings, FreeRDP_IgnoreCertificate, TRUE);
    ok &= freerdp_settings_set_bool(settings, FreeRDP_AutoAcceptCertificate, TRUE);
    ok &= freerdp_settings_set_bool(settings, FreeRDP_GatewayEnabled, FALSE);
    ok &= freerdp_settings_set_bool(settings, FreeRDP_UnicodeInput, TRUE);

    /* OpenSSL 3.x defaults SECLEVEL=2 which rejects the weak ciphers and
       self-signed certs commonly served by stock Windows Server RDP hosts,
       producing BIO_do_handshake failed → 0x00020008. Force SECLEVEL=0 so
       handshake completes; RDP carries its own transport encryption. */
    ok &= freerdp_settings_set_uint32(settings, FreeRDP_TlsSecLevel, 0);
    LOGI("TlsSecLevel=0 applied");

    // Security protocol selection (0=auto, 1=rdp, 2=nla, 3=tls, 4=ext)
    // Note: FreeRDP 3.x may still have TLS compatibility issues with Windows Server 2008 R2
    switch (securityProtocol) {
        case 1: // RDP only (no TLS/NLA) - best for old servers
            ok &= freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, TRUE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, FALSE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, FALSE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_NegotiateSecurityLayer, FALSE);
            LOGI("Security: RDP only (no TLS/NLA)");
            break;
        case 2: // NLA only
            ok &= freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, FALSE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, TRUE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, FALSE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_NegotiateSecurityLayer, TRUE);
            LOGI("Security: NLA only");
            break;
        case 3: // TLS only with TLS 1.0 fallback
            ok &= freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, FALSE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, FALSE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, TRUE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_NegotiateSecurityLayer, FALSE);
            // Try to allow TLS 1.0 for older servers
            // FreeRDP 3.x: TLS_VERSION_1_0 = 1, TLS_VERSION_1_1 = 2, TLS_VERSION_1_2 = 3
            #ifdef TLS_VERSION_1_0
            ok &= freerdp_settings_set_uint32(settings, FreeRDP_TlsMinVersion, TLS_VERSION_1_0);
            ok &= freerdp_settings_set_uint32(settings, FreeRDP_TlsMaxVersion, TLS_VERSION_1_2);
            LOGI("Security: TLS only with TLS 1.0-1.2 fallback");
            #else
            LOGI("Security: TLS only (TLS version settings not available)");
            #endif
            break;
        case 4: // Extended (all enabled)
            ok &= freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, TRUE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, TRUE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, TRUE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_NegotiateSecurityLayer, TRUE);
            LOGI("Security: Extended (all protocols)");
            break;
        default: // Auto (0) - enable all, let server negotiate
            ok &= freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, TRUE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, TRUE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, TRUE);
            ok &= freerdp_settings_set_bool(settings, FreeRDP_NegotiateSecurityLayer, TRUE);
            LOGI("Security: Auto (negotiate)");
            break;
    }

    if (!ok) {
        set_last_error("nativeCreate: failed to configure one or more FreeRDP settings");
        LOGE("%s", g_last_error);
        (*env)->ReleaseStringUTFChars(env, jhost,   host);
        (*env)->ReleaseStringUTFChars(env, juser,   user);
        (*env)->ReleaseStringUTFChars(env, jpass,   pass);
        (*env)->ReleaseStringUTFChars(env, jdomain, domain);
        freerdp_client_context_free(ctx);
        return 0;
    }

    LOGI("nativeCreate: settings ok (desktop=%ux%u, nla=%d, tls=%d, rdp=%d)",
         safe_width, safe_height,
         freerdp_settings_get_bool(settings, FreeRDP_NlaSecurity),
         freerdp_settings_get_bool(settings, FreeRDP_TlsSecurity),
         freerdp_settings_get_bool(settings, FreeRDP_RdpSecurity));
    (*env)->ReleaseStringUTFChars(env, jhost,   host);
    (*env)->ReleaseStringUTFChars(env, juser,   user);
    (*env)->ReleaseStringUTFChars(env, jpass,   pass);
    (*env)->ReleaseStringUTFChars(env, jdomain, domain);

    LOGI("nativeCreate: success, handle=%p", (void*)ctx);
    return (jlong)(uintptr_t)ctx;
}

JNIEXPORT jstring JNICALL
Java_com_nexterm_nexterm_RdpBridge_nativeGetLastError(JNIEnv* env, jclass clazz)
{
    (void)clazz;
    return (*env)->NewStringUTF(env, g_last_error);
}

JNIEXPORT void JNICALL
Java_com_nexterm_nexterm_RdpBridge_nativeSetSurface(
        JNIEnv* env, jobject thiz, jlong handle, jobject surface)
{
    (void)thiz;
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc) return;
    pthread_mutex_lock(&nc->lock);
    if (nc->window) ANativeWindow_release(nc->window);
    nc->window = surface ? ANativeWindow_fromSurface(env, surface) : NULL;
    pthread_mutex_unlock(&nc->lock);
}

JNIEXPORT void JNICALL
Java_com_nexterm_nexterm_RdpBridge_nativeConnect(
        JNIEnv* env, jobject thiz, jlong handle)
{
    (void)env; (void)thiz;
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc) return;
    set_last_error("");
    if (nc->thread_started || nc->running || nc->destroying) return;
    nc->running = 1;
    if (pthread_create(&nc->thread, NULL, rdp_thread, &nc->base.context) != 0) {
        nc->running = 0;
        set_last_error("nativeConnect: pthread_create failed");
        LOGE("%s", g_last_error);
        return;
    }
    nc->thread_started = TRUE;
}

JNIEXPORT void JNICALL
Java_com_nexterm_nexterm_RdpBridge_nativeDisconnect(
        JNIEnv* env, jobject thiz, jlong handle)
{
    (void)env; (void)thiz;
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    request_rdp_stop(nc);
}

JNIEXPORT void JNICALL
Java_com_nexterm_nexterm_RdpBridge_nativeSendMouseEvent(
        JNIEnv* env, jobject thiz, jlong handle,
        jint x, jint y, jint flags)
{
    (void)env; (void)thiz;
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc || !nc->running || nc->destroying || !nc->base.context.input) return;
    freerdp_input_send_mouse_event(nc->base.context.input,
                                   (UINT16)flags, (UINT16)x, (UINT16)y);
}

JNIEXPORT void JNICALL
Java_com_nexterm_nexterm_RdpBridge_nativeSendKeyEvent(
        JNIEnv* env, jobject thiz, jlong handle,
        jint keycode, jboolean down, jboolean extended)
{
    (void)env; (void)thiz;
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc || !nc->running || nc->destroying || !nc->base.context.input) return;
    UINT16 flags = extended ? KBD_FLAGS_EXTENDED : 0;
    if (!down)
        flags |= KBD_FLAGS_RELEASE;
    freerdp_input_send_keyboard_event(nc->base.context.input,
                                      flags, (UINT16)keycode);
}

JNIEXPORT void JNICALL
Java_com_nexterm_nexterm_RdpBridge_nativeSendUnicodeEvent(
        JNIEnv* env, jobject thiz, jlong handle,
        jint codepoint)
{
    (void)thiz;
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc || !nc->running || nc->destroying || !nc->base.context.input ||
        codepoint <= 0 || codepoint > 0xFFFF) return;
    const UINT16 unicode = (UINT16)codepoint;
    const BOOL down_ok = freerdp_input_send_unicode_keyboard_event(nc->base.context.input, 0, unicode);
    const BOOL up_ok = freerdp_input_send_unicode_keyboard_event(nc->base.context.input, KBD_FLAGS_RELEASE, unicode);
    if (!down_ok || !up_ok) {
        LOGE("unicode input failed for U+%04X", unicode);
    }
}

JNIEXPORT void JNICALL
Java_com_nexterm_nexterm_RdpBridge_nativeSendClipboardText(
        JNIEnv* env, jobject thiz,
        jlong handle, jstring jtext)
{
    (void)thiz;
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc || !jtext) return;

    const char* text = (*env)->GetStringUTFChars(env, jtext, NULL);
    if (!text) return;

    LOGI("nativeSendClipboardText: sending %zu bytes", strlen(text));
    nex_send_clipboard_to_server(nc, text);

    (*env)->ReleaseStringUTFChars(env, jtext, text);
}

JNIEXPORT jboolean JNICALL
Java_com_nexterm_nexterm_RdpBridge_nativeIsRunning(
        JNIEnv* env, jobject thiz, jlong handle)
{
    (void)env; (void)thiz;
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc || nc->destroying) return JNI_FALSE;
    return nc->running ? JNI_TRUE : JNI_FALSE;
}
JNIEXPORT jboolean JNICALL
Java_com_nexterm_nexterm_RdpBridge_nativeIsConnected(
        JNIEnv* env, jobject thiz, jlong handle)
{
    (void)env; (void)thiz;
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc || nc->destroying) return JNI_FALSE;
    return nc->connected ? JNI_TRUE : JNI_FALSE;
}
JNIEXPORT void JNICALL
Java_com_nexterm_nexterm_RdpBridge_nativeDestroy(
        JNIEnv* env, jobject thiz, jlong handle)
{
    (void)env; (void)thiz;
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc) return;
    nc->destroying = 1;
    request_rdp_stop(nc);
    join_rdp_thread(nc);
    freerdp_client_context_free(&nc->base.context);
    /* client_free callback handles window + mutex cleanup */
}
