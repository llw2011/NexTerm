package com.nexterm.nexterm

import android.graphics.SurfaceTexture
import android.view.Surface
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * RdpBridge: Flutter MethodChannel <-> JNI <-> FreeRDP
 *
 * Flutter side calls:
 *   rdp/create   → returns textureId (Long)
 *   rdp/connect
 *   rdp/disconnect
 *   rdp/destroy
 *   rdp/mouseEvent  { x, y, flags }
 *   rdp/keyEvent    { keycode, down }
 *
 * Flutter side listens on EventChannel "rdp/events/{handle}" for:
 *   { "type": "connected" | "disconnected" | "error", "message": "..." }
 */
class RdpBridge(
    private val engine: FlutterEngine,
    private val textureRegistry: TextureRegistry
) {
    companion object {
        private var loadError: String? = null

        init {
            try {
                System.loadLibrary("winpr3")
                System.loadLibrary("freerdp3")
                System.loadLibrary("freerdp-client3")
                System.loadLibrary("nexterm_jni")
            } catch (e: UnsatisfiedLinkError) {
                loadError = "Library load failed: ${e.message}"
                android.util.Log.e("NexTermJNI", "loadLibrary failed", e)
            }
        }

        @JvmStatic external fun nativeCreate(
            host: String, port: Int,
            user: String, pass: String, domain: String,
            width: Int, height: Int
        ): Long

        @JvmStatic external fun nativeSetSurface(handle: Long, surface: Surface?)
        @JvmStatic external fun nativeConnect(handle: Long)
        @JvmStatic external fun nativeDisconnect(handle: Long)
        @JvmStatic external fun nativeSendMouseEvent(handle: Long, x: Int, y: Int, flags: Int)
        @JvmStatic external fun nativeSendKeyEvent(handle: Long, keycode: Int, down: Boolean)
        @JvmStatic external fun nativeDestroy(handle: Long)
    }

    // handle -> (textureEntry, surface)
    private val sessions = mutableMapOf<Long, Pair<TextureRegistry.SurfaceTextureEntry, Surface>>()

    fun register() {
        MethodChannel(engine.dartExecutor.binaryMessenger, "rdp/bridge")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "create" -> {
                        loadError?.let {
                            result.error("LOAD_FAILED", it, null)
                            return@setMethodCallHandler
                        }
                        val host   = call.argument<String>("host")   ?: ""
                        val port   = call.argument<Int>("port")      ?: 3389
                        val user   = call.argument<String>("user")   ?: ""
                        val pass   = call.argument<String>("pass")   ?: ""
                        val domain = call.argument<String>("domain") ?: ""
                        val width  = call.argument<Int>("width")     ?: 1280
                        val height = call.argument<Int>("height")    ?: 720

                        val entry = textureRegistry.createSurfaceTexture()
                        val st    = entry.surfaceTexture()
                        st.setDefaultBufferSize(width, height)
                        val surface = Surface(st)

                        val handle = nativeCreate(host, port, user, pass, domain, width, height)
                        if (handle == 0L) {
                            entry.release()
                            surface.release()
                            result.error("CREATE_FAILED", "nativeCreate returned 0", null)
                            return@setMethodCallHandler
                        }
                        nativeSetSurface(handle, surface)
                        sessions[handle] = Pair(entry, surface)
                        result.success(mapOf("handle" to handle, "textureId" to entry.id()))
                    }
                    "connect" -> {
                        val handle = call.argument<Long>("handle") ?: 0L
                        nativeConnect(handle)
                        result.success(null)
                    }
                    "disconnect" -> {
                        val handle = call.argument<Long>("handle") ?: 0L
                        nativeDisconnect(handle)
                        result.success(null)
                    }
                    "destroy" -> {
                        val handle = call.argument<Long>("handle") ?: 0L
                        nativeDisconnect(handle)
                        nativeSetSurface(handle, null)
                        sessions.remove(handle)?.let { (entry, surface) ->
                            surface.release()
                            entry.release()
                        }
                        nativeDestroy(handle)
                        result.success(null)
                    }
                    "mouseEvent" -> {
                        val handle = call.argument<Long>("handle") ?: 0L
                        val x      = call.argument<Int>("x")      ?: 0
                        val y      = call.argument<Int>("y")      ?: 0
                        val flags  = call.argument<Int>("flags")  ?: 0
                        nativeSendMouseEvent(handle, x, y, flags)
                        result.success(null)
                    }
                    "keyEvent" -> {
                        val handle  = call.argument<Long>("handle")    ?: 0L
                        val keycode = call.argument<Int>("keycode")    ?: 0
                        val down    = call.argument<Boolean>("down")   ?: false
                        nativeSendKeyEvent(handle, keycode, down)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
