# Changelog

## 0.2.0 - 2026-06-22

- Fixed CI test failure reporting by running Pester with `-EnableExit`.
- Fixed scan path normalization for bare drive letters and non-file-system provider paths.
- Added export-folder writability validation before scans begin.
- Added scan cancellation from the GUI.
- Added current GUI screenshots to the README and documentation set.
- Added a repeatable release packaging script that creates a ZIP and SHA-256 checksum.
- Fixed stale status/log behavior after failed scan-start validation.
- Fixed invalid hash algorithm handling so configuration errors fail the scan.
- Fixed duplicate grouping to keep file sizes separate even if hashes collide.
- Fixed report filename validation to prevent path traversal outside the export folder.
- Fixed CSV export encoding consistency and exclusive report file creation.
- Renamed the binary size report column from `SizeMB` to `SizeMiB`.
- Improved live status and hashing progress messages.
- Expanded regression tests for core, GUI, CI, docs, CSV export, and safety-scan behavior.

## 0.1.0 - Initial development

- Initial DupliView project structure.
- Added PowerShell GUI.
- Refreshed the GUI with grouped sections, scan options, live status, and background scanning.
- Added duplicate detection by size + SHA-256 hash.
- Added CSV report export.
- Added report-only safety policy.
- Added launchers.
- Added tests.
- Added GitHub Actions test workflow.
- Updated documentation for the refreshed GUI.
- Added tutorials, troubleshooting, release, and contributor guides.
- Added coworker start-here guide.
