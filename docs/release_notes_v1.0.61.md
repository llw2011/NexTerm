v1.0.61 - Stabilize RDP remote clipboard cut/copy

## Fixes

- Fixed a crash triggered when cutting or copying selected text inside the RDP remote desktop.
- Remote clipboard download now prefers `CF_UNICODETEXT` over `CF_TEXT`.
- JNI now builds Java strings directly from CLIPRDR UTF-16 data instead of converting to UTF-8 and calling `NewStringUTF`.
- JNI clipboard callbacks no longer hold the global callback mutex while calling into Kotlin.
- Kotlin callback exceptions are contained so they cannot bring down the FreeRDP worker thread.

## Test focus

- Select text in the RDP remote desktop and use Cut.
- Select text in the RDP remote desktop and use Copy.
- Paste into a phone-side input field.
- Verify both English and Chinese text.
