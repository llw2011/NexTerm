v1.0.57 — Clipboard upload fix + RDP/SSH polish

## Fixes
- Android + Windows CLIPRDR: local→remote clipboard was a no-op. The
  client advertised CF_UNICODETEXT but never answered the server's
  follow-up FormatDataRequest. Now caches the UTF-16LE payload on
  upload and replies properly when the server asks for it.
- Clipboard download: UTF-16LE→UTF-8 conversion was string-pattern
  guessed (and would mojibake real Unicode). Replaced with
  winpr ConvertWCharNToUtf8Alloc / Win32 WideCharToMultiByte.
- Windows RDP screen: right mouse button never released — _onPointerUp
  always sent leftUp regardless of which button was pressed. Now tracks
  pressed buttons and releases the right one(s).
- SSH session leak: when the desktop tab was closed, dispose() did not
  close the SSH session/client/socket. Added explicit cleanup.
- file_picker: removed null-deref on file.bytes when picker returns
  null content.
- Smaller: clipboard / pending-payload buffers freed in client_free.

## Notes
- Same APK still ships fresh CMake-built libnexterm_jni.so (treatment-C
  intact).
- TlsSecLevel=0 fix from v1.0.52 preserved.
