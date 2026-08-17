v1.0.67 - Diagnostics and RDP profile import/export

Changes:

- Added an in-app diagnostics page under Settings.
- RDP sessions now record recent create, settings, startup, connected, resume, health, reconnect, and destroy stages in an in-memory diagnostic log.
- Diagnostics can refresh the latest native RDP error and copy redacted logs for troubleshooting.
- Added standard `.rdp` profile import and export under Settings.
- `.rdp` import creates a new RDP connection from host, port, username, domain, desktop width, and desktop height.
- `.rdp` export saves a selected RDP connection as a standard profile.

Notes:

- Diagnostics logs are in-memory only and can be cleared from the diagnostics page.
- Copied diagnostics are redacted before entering the clipboard.
- `.rdp` import/export does not import or export saved passwords.
- This release does not add RD Gateway field support or bulk `.rdp` import.
