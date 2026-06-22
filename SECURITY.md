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
- Network behavior outside user-selected file shares.
- Upload behavior.
- Administrator requirements.
- Installers.
- Registry changes.
- Scheduled tasks.
- Services.
- Compiled executables or installers.

Documentation may mention these behaviors only as warnings or safety commitments.

## Documentation Safety

Tutorials and screenshots should keep the same safety line as the app:

- Do not teach deletion, cleanup, quarantine, recycle-bin, move, or rename workflows.
- Do not suggest uploading files or reports to any service.
- Do not include private file contents.
- Redact personal names, client names, and sensitive paths in screenshots.
- Use local sample folders for examples.

## Reporting Security Issues

Please report security concerns through GitHub issues or the repository's chosen contact method. Include:

- A clear description of the issue.
- Steps to reproduce, if available.
- The affected version or commit.
- Any relevant logs or CSV rows with sensitive local paths removed.

Do not include private file contents in reports.

## Maintainer Review

Maintainers should review every security-related change for preservation of the report-only boundary. Any change that expands DupliView beyond local CSV reporting requires rejection unless it is rewritten to preserve the safety guarantees above.

Pull requests adding deletion, cleanup, telemetry, uploads, or network behavior outside user-selected file shares will be rejected.
