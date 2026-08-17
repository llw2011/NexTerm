v1.0.66 - Connection search focus fix

Changes:

- Fixed the connection search field staying focused after tapping other parts of the home screen.
- The search field now explicitly loses focus when tapping outside it.
- Pressing the keyboard search action also releases the search field focus.
- Added a widget regression test for grouped home search focus behavior.

Notes:

- This is a focused OTA patch for the Phase 4.2 connection grouping test feedback.
- No connection data format changes are included beyond the existing v1.0.65 group field.
