/**
 * nexterm_jni.c  –  FreeRDP 3.x compatible JNI bridge
 */
#include <jni.h>
#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#include <freerdp/freerdp.h>
#include <freerdp/client.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/settings.h>
#include <winpr/wtypes.h>
#include <winpr/synch.h>

#define TAG "NexTermJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

/* ── Extended context (FreeRDP 3.x: subclass rdpClientContext) ──────── */
typedef struct {
    rdpClientContext base;   /* MUST be first */
    ANativeWindow*   window;
    pthread_mutex_t  lock;
    volatile int     running;
} NexContext;

/* Helper: get NexContext from any rdpContext* */
static NexContext* nex(rdpContext* ctx) { return (NexContext*)ctx; }

/* ── GDI callbacks ──────────────────────────────────────────────────── */
static BOOL cb_begin_paint(rdpContext* ctx) { (void)ctx; return TRUE; }

static BOOL cb_end_paint(rdpContext* ctx)
{
    rdpGdi* gdi = ctx->gdi;
    if (!gdi || !gdi->primary_buffer) return TRUE;

    NexContext* nc = nex(ctx);
    if (!nc->window) return TRUE;

    int w = (int)gdi->width;
    int h = (int)gdi->height;

    pthread_mutex_lock(&nc->lock);
    if (ANativeWindow_setBuffersGeometry(nc->window, w, h, WINDOW_FORMAT_RGBX_8888) == 0) {
        ANativeWindow_Buffer buf;
        if (ANativeWindow_lock(nc->window, &buf, NULL) == 0) {
            uint8_t* src = gdi->primary_buffer;
            uint8_t* dst = (uint8_t*)buf.bits;
            int src_stride = w * 4;
            int dst_stride = buf.stride * 4;
            for (int y = 0; y < h; y++)
                memcpy(dst + y * dst_stride, src + y * src_stride, (size_t)src_stride);
            ANativeWindow_unlockAndPost(nc->window);
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
    freerdp_settings_set_bool(inst->context->settings, FreeRDP_SoftwareGdi, TRUE);
    freerdp_settings_set_uint32(inst->context->settings, FreeRDP_ColorDepth, 32);
    return TRUE;
}

static BOOL client_post_connect(freerdp* inst)
{
    if (!gdi_init(inst, PIXEL_FORMAT_RGBX32)) return FALSE;
    inst->context->update->BeginPaint    = cb_begin_paint;
    inst->context->update->EndPaint      = cb_end_paint;
    inst->context->update->DesktopResize = cb_desktop_resize;
    return TRUE;
}

static void client_post_disconnect(freerdp* inst) { gdi_free(inst); }

/* ── RDP_CLIENT_ENTRY_POINTS callbacks ──────────────────────────────── */
static BOOL client_new(freerdp* inst, rdpContext* ctx)
{
    (void)inst;
    NexContext* nc = nex(ctx);
    pthread_mutex_init(&nc->lock, NULL);
    nc->window  = NULL;
    nc->running = 0;
    return TRUE;
}

static void client_free(freerdp* inst, rdpContext* ctx)
{
    (void)inst;
    NexContext* nc = nex(ctx);
    pthread_mutex_destroy(&nc->lock);
    if (nc->window) { ANativeWindow_release(nc->window); nc->window = NULL; }
}

/* ── Connection thread ──────────────────────────────────────────────── */
static void* rdp_thread(void* arg)
{
    rdpContext* ctx  = (rdpContext*)arg;
    NexContext* nc   = nex(ctx);
    freerdp*    inst = ctx->instance;

    if (!freerdp_connect(inst)) {
        LOGE("freerdp_connect failed (error 0x%08X)",
             freerdp_get_last_error(ctx));
        nc->running = 0;
        return NULL;
    }
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
    nc->running = 0;
    LOGI("RDP thread exited");
    return NULL;
}

/* ══════════════════════════════════════════════════════════════════════
   JNI exports
   ══════════════════════════════════════════════════════════════════════ */

JNIEXPORT jlong JNICALL
Java_com_nexterm_nexterm_RdpBridge_nativeCreate(
        JNIEnv* env, jobject thiz,
        jstring jhost, jint port,
        jstring juser, jstring jpass, jstring jdomain,
        jint width, jint height)
{
    (void)thiz;
    LOGI("nativeCreate: start");

    RDP_CLIENT_ENTRY_POINTS ep = { 0 };
    ep.Size        = sizeof(RDP_CLIENT_ENTRY_POINTS);
    ep.Version     = RDP_CLIENT_INTERFACE_VERSION;
    ep.ContextSize = sizeof(NexContext);
    ep.ClientNew   = client_new;
    ep.ClientFree  = client_free;

    LOGI("nativeCreate: calling freerdp_client_context_new (ContextSize=%zu)", sizeof(NexContext));
    rdpContext* ctx = freerdp_client_context_new(&ep);
    if (!ctx) {
        LOGE("freerdp_client_context_new failed (returned NULL)");
        /* Fallback: try freerdp_new directly */
        LOGI("nativeCreate: trying freerdp_new fallback");
        freerdp* inst2 = freerdp_new();
        if (!inst2) { LOGE("freerdp_new also failed"); return 0; }
        inst2->ContextSize = sizeof(NexContext);
        if (!freerdp_context_new(inst2)) {
            LOGE("freerdp_context_new failed");
            freerdp_free(inst2);
            return 0;
        }
        ctx = inst2->context;
        NexContext* nc2 = (NexContext*)ctx;
        pthread_mutex_init(&nc2->lock, NULL);
        nc2->window  = NULL;
        nc2->running = 0;
        LOGI("nativeCreate: fallback succeeded");
    }
    LOGI("nativeCreate: context created successfully");

    freerdp* inst = ctx->instance;
    if (!inst) {
        LOGE("ctx->instance is NULL");
        freerdp_client_context_free(ctx);
        return 0;
    }

    inst->PreConnect     = client_pre_connect;
    inst->PostConnect    = client_post_connect;
    inst->PostDisconnect = client_post_disconnect;

    rdpSettings* settings = ctx->settings;
    if (!settings) {
        LOGE("ctx->settings is NULL");
        freerdp_client_context_free(ctx);
        return 0;
    }

    const char* host   = (*env)->GetStringUTFChars(env, jhost,   NULL);
    const char* user   = (*env)->GetStringUTFChars(env, juser,   NULL);
    const char* pass   = (*env)->GetStringUTFChars(env, jpass,   NULL);
    const char* domain = (*env)->GetStringUTFChars(env, jdomain, NULL);

    LOGI("nativeCreate: configuring settings (host=%s, port=%d, user=%s)", host, port, user);

    freerdp_settings_set_string(settings, FreeRDP_ServerHostname, host);
    freerdp_settings_set_uint32(settings, FreeRDP_ServerPort,     (UINT32)port);
    freerdp_settings_set_string(settings, FreeRDP_Username,       user);
    freerdp_settings_set_string(settings, FreeRDP_Password,       pass);
    if (domain && domain[0])
        freerdp_settings_set_string(settings, FreeRDP_Domain, domain);
    freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth,  (UINT32)width);
    freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight, (UINT32)height);
    freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, TRUE);
    freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, TRUE);

    (*env)->ReleaseStringUTFChars(env, jhost,   host);
    (*env)->ReleaseStringUTFChars(env, juser,   user);
    (*env)->ReleaseStringUTFChars(env, jpass,   pass);
    (*env)->ReleaseStringUTFChars(env, jdomain, domain);

    LOGI("nativeCreate: success, handle=%p", (void*)ctx);
    return (jlong)(uintptr_t)ctx;
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
    nc->running = 1;
    pthread_t t;
    pthread_create(&t, NULL, rdp_thread, &nc->base.context);
    pthread_detach(t);
}

JNIEXPORT void JNICALL
Java_com_nexterm_nexterm_RdpBridge_nativeDisconnect(
        JNIEnv* env, jobject thiz, jlong handle)
{
    (void)env; (void)thiz;
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (nc) nc->running = 0;
}

JNIEXPORT void JNICALL
Java_com_nexterm_nexterm_RdpBridge_nativeSendMouseEvent(
        JNIEnv* env, jobject thiz, jlong handle,
        jint x, jint y, jint flags)
{
    (void)env; (void)thiz;
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc || !nc->running) return;
    freerdp_input_send_mouse_event(nc->base.context.input,
                                   (UINT16)flags, (UINT16)x, (UINT16)y);
}

JNIEXPORT void JNICALL
Java_com_nexterm_nexterm_RdpBridge_nativeSendKeyEvent(
        JNIEnv* env, jobject thiz, jlong handle,
        jint keycode, jboolean down)
{
    (void)env; (void)thiz;
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc || !nc->running) return;
    freerdp_input_send_keyboard_event(nc->base.context.input,
                                      down ? KBD_FLAGS_DOWN : KBD_FLAGS_RELEASE,
                                      (UINT16)keycode);
}

JNIEXPORT void JNICALL
Java_com_nexterm_nexterm_RdpBridge_nativeDestroy(
        JNIEnv* env, jobject thiz, jlong handle)
{
    (void)env; (void)thiz;
    NexContext* nc = (NexContext*)(uintptr_t)handle;
    if (!nc) return;
    nc->running = 0;
    freerdp_client_context_free(&nc->base.context);
    /* client_free callback handles window + mutex cleanup */
}
