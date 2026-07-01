#ifndef NEXTERM_RDP_H
#define NEXTERM_RDP_H

#include <stdint.h>

#ifdef NEXTERM_RDP_EXPORTS
#define NEXTERM_API __declspec(dllexport)
#else
#define NEXTERM_API __declspec(dllimport)
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*ClipboardCallback)(const char* text);
typedef void (*FrameCallback)(const uint8_t* buffer, int width, int height);

NEXTERM_API int64_t nex_create(
    const char* host, int port,
    const char* user, const char* pass, const char* domain,
    int width, int height, int securityProtocol);

NEXTERM_API void nex_connect(int64_t handle);
NEXTERM_API void nex_disconnect(int64_t handle);
NEXTERM_API void nex_destroy(int64_t handle);

NEXTERM_API int nex_is_running(int64_t handle);
NEXTERM_API int nex_is_connected(int64_t handle);
NEXTERM_API const char* nex_get_last_error(void);

NEXTERM_API void nex_send_mouse_event(int64_t handle, int x, int y, int flags);
NEXTERM_API void nex_send_key_event(int64_t handle, int keycode, int down, int extended);
NEXTERM_API void nex_send_unicode_event(int64_t handle, int codepoint);
NEXTERM_API void nex_send_clipboard_text(int64_t handle, const char* text);

NEXTERM_API void nex_set_clipboard_callback(ClipboardCallback cb);
NEXTERM_API void nex_set_frame_callback(int64_t handle, FrameCallback cb);

NEXTERM_API const uint8_t* nex_get_frame_buffer(int64_t handle);
NEXTERM_API int nex_get_frame_width(int64_t handle);
NEXTERM_API int nex_get_frame_height(int64_t handle);

#ifdef __cplusplus
}
#endif

#endif
