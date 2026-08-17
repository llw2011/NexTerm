v1.0.70 - RDP move-only default and mode tips

Changes:

- RDP pointer mode now defaults to Move only.
- The toolbar mode buttons are ordered as Move only, Direct click, and Precision touchpad.
- Switching pointer modes now shows a short on-screen tip explaining the selected mode.
- The Move only label is used in the UI to make the default behavior explicit.

Notes:

- Move only does not send remote mouse input.
- Direct click and Precision touchpad remain one-tap toolbar options.
- This release does not change FreeRDP mouse flags or native input semantics.
