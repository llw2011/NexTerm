v1.0.68 - RDP native IME input and pointer mode clarity

Changes:

- RDP text input now uses the Android system keyboard as the primary input path.
- Chinese IME composition is no longer handled by NexTerm's built-in pinyin panel.
- Added a remote text input bar with explicit remote Backspace, Enter, and control-keys entry points.
- Converted the old RDP built-in keyboard overlay into a control-keys panel for Ctrl/Alt/Win, Esc, Tab, navigation keys, Insert/Delete, and F1-F12.
- Replaced blind pointer-mode cycling with a clear mode selector: Direct click, Move view, and Precision touchpad.

Notes:

- Text input is still sent through the existing RDP Unicode path and currently supports BMP characters.
- RDP control keys continue to use FreeRDP scan code plus extended flags, not Windows virtual-key codes.
- Precision touchpad is now treated as an advanced mode for relative mouse movement.
- This release does not change JNI input semantics or add emoji/surrogate-pair support.
