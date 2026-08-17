v1.0.71 - OTA startup fail-open guard

Changes:

- Startup update check failures no longer lock the app, even when startup updates are required.
- The startup update failure screen now keeps a Continue option so network-only GitHub/API failures cannot block normal use.
- OTA checks now send GitHub API headers and show more useful failure details.
- APK downloads now validate HTTP status before opening the Android installer.

Notes:

- The GitHub Release backend and v1.0.70 APK asset were verified healthy; the reported failure was caused by phone-side network access to the release API.
- Detected updates can still be required before continuing when the startup update setting is enabled.
