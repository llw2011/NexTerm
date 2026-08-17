v1.0.63 - Connection backup import/export

## New

- Added connection backup export from Settings.
- Added connection backup import from Settings.
- Backups include RDP/SSH connection metadata plus saved passwords, SSH private keys and key passphrases.
- Import merges connections; existing connections with the same ID are overwritten.
- Added warnings that exported backup JSON contains credentials in plain text.

## Test focus

- Export a backup with RDP and SSH connections.
- Uninstall/reinstall the app, then import the backup.
- Confirm RDP passwords, SSH password auth and SSH private-key auth are restored.
