# Contributing to DupliView

Thanks for helping with DupliView. The project is small on purpose: it finds exact duplicate files and writes reports. It does not clean up files.

## Safety Rules

DupliView is report-only. Pull requests must not add:

- File deletion.
- File moving.
- File renaming.
- File overwriting.
- File content edits.
- Cleanup modes.
- Quarantine or recycle-bin workflows.
- Uploads, telemetry, or network behavior outside user-selected file shares.
- Installers, compiled executables, services, scheduled tasks, or registry edits.
- Administrator requirements.

It is fine for docs to mention these behaviors as things DupliView does not do.

## Before You Change Code

Read:

- `README.md`
- `SECURITY.md`
- `docs/README.md`

For GUI changes, keep the labels used in the guides in sync with the labels in `DupliView.ps1`.

## Development Setup

Normal users do not need Pester. Contributors use Pester for tests. Use Windows PowerShell 5.1 with Pester 4.10.1 so local runs match GitHub Actions.

Run tests from the repository root:

```powershell
Import-Module Pester -RequiredVersion 4.10.1 -Force
Invoke-Pester -Script .\tests\DupliView.Tests.ps1 -EnableExit
```

If Pester is missing:

```powershell
Install-Module Pester -RequiredVersion 4.10.1 -Scope CurrentUser
```

Do not add production dependencies for normal users.

## Release Packaging

Build release ZIPs with the packaging script instead of selecting files by hand:

```powershell
.\tools\New-ReleasePackage.ps1 -Version 0.2.0
```

The script creates a ZIP and SHA-256 checksum under `dist\` while excluding generated reports, prior ZIPs, `.git`, and local temp files.

## Code Style

- Use simple PowerShell that works on Windows PowerShell 5.1.
- Keep scan logic testable outside the GUI.
- Prefer clear function names over clever code.
- Add comments only where they explain safety or non-obvious behavior.
- Keep writes limited to the lazily created default `Reports` folder and selected report output files.
- Do not require the DupliView folder to be writable before a user starts a scan.

## Documentation Style

- Write for non-technical Windows users.
- Use plain Windows examples such as `L:\` and `\\server\share`.
- Keep private paths and client names out of examples.
- Say clearly that DupliView is report-only.
- Do not write cleanup instructions.

## Pull Requests

Before opening a pull request:

1. Run the Pester tests.
2. Check that the static safety scan still passes.
3. Smoke-test the GUI if you changed `DupliView.ps1`.
4. Update README or guides if labels or behavior changed.
5. Confirm generated CSV files are not committed.

Pull requests that add cleanup, deletion, telemetry, uploads, network behavior outside user-selected file shares, installers, services, scheduled tasks, registry changes, or admin-only behavior will be rejected.
