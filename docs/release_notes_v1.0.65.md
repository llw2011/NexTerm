v1.0.65 - Connection groups

Changes:

- Added a single-level connection group field for RDP and SSH profiles.
- Added an optional Group field to the connection editor.
- Home now shows grouped section headers when any visible connection has a group.
- Ungrouped connections remain visible under an Ungrouped section when grouping is active.
- Search now matches connection name, host, username, and group.
- Duplicated connections keep their group, while still not inheriting favorite or last-used status.
- Plain and encrypted connection backups preserve the group field through import/export.
- Updated recovery, development, and roadmap documentation for Phase 4.2.

Notes:

- Groups are intentionally single-level in this release.
- This release does not add tree folders, drag ordering, or a separate group management screen.
- Group is plain connection metadata only; credentials remain in secure storage and are not stored in the group field.
