package com.nexterm.nexterm

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.lang.reflect.Method

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
    context: Context,
    private val engine: FlutterEngine,
    private val textureRegistry: TextureRegistry
) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val clipboardCallback = object : ClipboardCallback {
        override fun onClipboardChanged(text: String) {
            publishRemoteClipboard(text)
        }
    }

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
            width: Int, height: Int,
            securityProtocol: Int  // 0=auto, 1=rdp, 2=nla, 3=tls, 4=ext
        ): Long

        @JvmStatic external fun nativeSetSurface(handle: Long, surface: Surface?)
        @JvmStatic external fun nativeConnect(handle: Long)
        @JvmStatic external fun nativeDisconnect(handle: Long)
        @JvmStatic external fun nativeSendMouseEvent(handle: Long, x: Int, y: Int, flags: Int)
        @JvmStatic external fun nativeSendKeyEvent(handle: Long, keycode: Int, down: Boolean, extended: Boolean)
        @JvmStatic external fun nativeSendUnicodeEvent(handle: Long, codepoint: Int)
        @JvmStatic external fun nativeIsRunning(handle: Long): Boolean
        @JvmStatic external fun nativeIsConnected(handle: Long): Boolean
        @JvmStatic external fun nativeDestroy(handle: Long)
        @JvmStatic external fun nativeGetLastError(): String
        @JvmStatic external fun nativeSendClipboardText(handle: Long, text: String?)
        @JvmStatic external fun nativeSetClipboardCallback(callback: ClipboardCallback?, method: Method?)

        interface ClipboardCallback {
            fun onClipboardChanged(text: String)
        }
    }

    // handle -> (textureEntry, surface)
    private val sessions = mutableMapOf<Long, Pair<TextureRegistry.SurfaceTextureEntry, Surface>>()

    fun register() {
        if (loadError == null) {
            try {
                nativeSetClipboardCallback(clipboardCallback, clipboardCallbackMethod(clipboardCallback))
            } catch (e: Throwable) {
                Log.e("NexTermJNI", "nativeSetClipboardCallback failed", e)
            }
        }

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
                        val security = call.argument<Int>("security") ?: 0  // 0=auto

                        val entry = textureRegistry.createSurfaceTexture()
                        val st    = entry.surfaceTexture()
                        st.setDefaultBufferSize(width, height)
                        val surface = Surface(st)

                        val handle = nativeCreate(host, port, user, pass, domain, width, height, security)
                        if (handle == 0L) {
                            val error = nativeGetLastError().ifBlank { "nativeCreate returned 0" }
                            entry.release()
                            surface.release()
                            result.error("CREATE_FAILED", error, null)
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
                    "unicodeEvent" -> {
                        val handle = call.argument<Long>("handle") ?: 0L
                        val codepoint = call.argument<Int>("codepoint") ?: 0
                        nativeSendUnicodeEvent(handle, codepoint)
                        result.success(null)
                    }
                    "keyEvent" -> {
                        val handle  = call.argument<Long>("handle")    ?: 0L
                        val keycode = call.argument<Int>("keycode")    ?: 0
                        val down    = call.argument<Boolean>("down")   ?: false
                        val extended = call.argument<Boolean>("extended") ?: false
                        val debugLabel = call.argument<String>("debugLabel")
                        if (!debugLabel.isNullOrBlank()) {
                            Log.i(
                                "NexTermJNI",
                                "RDP key test label=$debugLabel scan=0x${keycode.toString(16)} down=$down extended=$extended"
                            )
                        }
                        nativeSendKeyEvent(handle, keycode, down, extended)
                        result.success(null)
                    }
                    "isRunning" -> {
                        val handle = call.argument<Long>("handle") ?: 0L
                        result.success(nativeIsRunning(handle))
                    }
                    "isConnected" -> {
                        val handle = call.argument<Long>("handle") ?: 0L
                        result.success(nativeIsConnected(handle))
                    }
                    "lastError" -> {
                        result.success(nativeGetLastError())
                    }
                    "sendClipboard" -> {
                        val handle = call.argument<Long>("handle") ?: 0L
                        val text = call.argument<String>("text")
                        nativeSendClipboardText(handle, text)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun publishRemoteClipboard(text: String) {
        if (text.isEmpty()) return
        mainHandler.post {
            try {
                val manager = appContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                manager.setPrimaryClip(ClipData.newPlainText("RDP Clipboard", text))
                Log.i("NexTermJNI", "Remote clipboard copied to Android clipboard (${text.length} chars)")
            } catch (e: Throwable) {
                Log.e("NexTermJNI", "Failed to copy remote clipboard to Android clipboard", e)
            }
        }
    }

    private fun clipboardCallbackMethod(callback: ClipboardCallback): Method? {
        val method = callback.javaClass.declaredMethods.firstOrNull { method ->
            method.parameterTypes.size == 1
        } ?: callback.javaClass.methods.firstOrNull { method ->
            method.parameterTypes.size == 1 && method.name !in setOf("equals", "wait")
        }
        method?.isAccessible = true
        return method
    }
}
