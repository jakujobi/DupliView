# Security Policy

## Safety Boundary

DupliView is a report-only duplicate-file report tool. It never deletes, moves, renames, overwrites, uploads, or modifies scanned files.

This safety boundary is part of the project identity, not a temporary implementation detail.

## Prohibited Changes

Pull requests will be rejected if they add or require:

- File deletion.
- File cleanup.
- Moving scanned files.
- Renaming scanned files.
- Overwriting scanned files.
- Telemetry.
- Network behavior.
- Upload behavior.
- Administrator requirements.
- Installers.
- Registry changes.
- Scheduled tasks.
- Services.

Documentation may mention these behaviors only as warnings or safety commitments.

## Reporting Security Issues

Please report security concerns privately to the project owner or maintainer. Include:

- A clear description of the issue.
- Steps to reproduce, if available.
- The affected version or commit.
- Any relevant logs or CSV rows with sensitive local paths removed.

Do not include private file contents in reports.

## Maintainer Review

Maintainers should review every security-related change for preservation of the report-only boundary. Any change that expands DupliView beyond local CSV reporting requires rejection unless it is rewritten to preserve the safety guarantees above.
