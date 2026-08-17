v1.0.58 — Fix RDP session dying silently after backgrounding

## Bug
After connecting RDP and switching the app to the background, the OS
(Android Doze / battery saver) or the RDP server's idle timeout could
kill the underlying TCP socket. The native rdp_thread would exit
(nc->running = 0) but the Dart side still showed "Connected" and the
canvas. Subsequent mouse/keyboard input was silently dropped by the
JNI layer because every input function gates on nc->running. Result:
the user came back to a dead session that looked alive — toggling the
toolbar did nothing useful.

## Fix
- RdpScreen now observes WidgetsBindingObserver lifecycle.
- On resume: probe RDP session with isRunning + isConnected. If the
  session died while in background, switch to the error state and show
  a Reconnect button.
- While foreground: a 5s health-check timer catches in-flight
  disconnects (server idle timeout, network drop) and surfaces them.
- While backgrounded: stop clipboard polling and health-check timers
  (less wakelock, less battery).
- Reconnect button (i18n: 重新连接 / Reconnect) tears down the dead
  handle and reissues the full connect flow without leaving the screen.
