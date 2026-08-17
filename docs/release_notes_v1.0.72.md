v1.0.72 - Forced update download failure guard

Changes:

- Startup update check failures remain fail-open, even when startup updates are required.
- APK download failures are now tracked separately after a real update has been detected.
- When startup updates are required, a detected update can no longer be skipped after its APK download fails.
- Retrying a download failure retries the same release directly instead of discarding it and repeating the update check.
- Optional updates can still be skipped after a download failure.
- Added clearer update-download error messages and regression coverage for all three paths.

Notes:

- This release preserves the v1.0.71 protection against GitHub/API check failures locking the app.
- No connection credentials or user data are included in this release.
