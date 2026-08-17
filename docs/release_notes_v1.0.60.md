v1.0.60 - Fix RDP remote clipboard download to Android

## Fixes

- Fixed RDP remote-to-phone clipboard sync on Android.
- The JNI CLIPRDR path already received remote clipboard text, but Kotlin never registered `nativeSetClipboardCallback`, so the callback was never delivered.
- `RdpBridge` now registers the native clipboard callback when the bridge starts.
- Remote clipboard text is copied onto the Android system clipboard through `ClipboardManager` on the main thread.
- The existing phone-to-RDP clipboard upload path is unchanged.

## Notes

- This release also refreshes the project spec and AGENTS work diary for the current v1.0.59/v1.0.60 codebase.
- Test focus: copy English and Chinese text inside the RDP remote desktop, then paste into a phone-side input field.
