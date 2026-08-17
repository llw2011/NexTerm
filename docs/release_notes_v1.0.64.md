v1.0.64 - SSH Jump Host and RDP key test tools

Changes:

- Added one-hop SSH Jump Host / ProxyJump support for SSH shell sessions.
- SFTP now uses the same SSH connection path and supports configured Jump Hosts.
- Local SSH port forwarding works through the target SSH connection, including when the target is reached via a Jump Host.
- Added a hidden RDP key test panel for scan code + extended-key validation.
- Added Android logcat output for RDP key test events when the hidden test panel is used.
- Updated recovery and development documentation for the new SSH and RDP validation workflows.

Notes:

- Jump Host support is intentionally one-hop only in this release.
- Remote forwarding, Dynamic SOCKS, SSH agent forwarding, and multi-hop ProxyJump chains are not included.
- The RDP key test panel is a validation tool; advanced keys should still be verified on a real device before being promoted into the normal remote keyboard UI.
