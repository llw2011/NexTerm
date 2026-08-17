v1.0.69 - Tiled RDP pointer mode controls

Changes:

- Replaced the RDP pointer mode bottom sheet with always-visible tiled controls in the toolbar.
- Direct click, Move view, and Precision touchpad are now available as one-tap toolbar buttons.
- The active pointer mode is highlighted directly in the toolbar.
- Switching pointer mode no longer requires opening a modal or cycling through unrelated modes.

Notes:

- This release does not change FreeRDP mouse flags or native input semantics.
- Direct click remains the default interaction path.
- Move view still only pans/zooms the local viewport.
- Precision touchpad still uses relative remote mouse movement.
