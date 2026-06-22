# Release Checklist

Use this checklist before publishing a DupliView ZIP.

## 0.2.0 Release Status

Status: release package built and locally verified on 2026-06-22.

Artifacts:

- `dist/DupliView-0.2.0.zip`
- `dist/DupliView-0.2.0.zip.sha256`

Completed checks:

- [x] Version is documented as `0.2.0`.
- [x] `CHANGELOG.md` has a dated `0.2.0 - 2026-06-22` entry.
- [x] `README.md` matches the current GUI, dependencies, and first-run workflow.
- [x] `START HERE.txt` tells users to extract the ZIP first and keep files together.
- [x] Screenshots use sample paths only.
- [x] Pester suite passes.
- [x] Release ZIP was generated with `tools/New-ReleasePackage.ps1`.
- [x] Release ZIP contents were inspected.
- [x] Checksum verification instructions are documented.
- [x] Release process instructions are documented.
- [x] `Reports/` contains only `.gitkeep`.
- [x] `dist/` contains only the current `0.2.0` ZIP and checksum.
- [x] Whitespace and line-ending checks are clean.

Not completed by this local checklist:

- [ ] Commit the release-ready changes.
- [ ] Create a release tag, if this repository uses tags.
- [ ] Upload or distribute the ZIP through the chosen release channel.

## Version Check

- Confirm the version or release name. The current release candidate is `0.2.0`.
- Update `CHANGELOG.md`.
- Confirm `LICENSE` uses the correct copyright name.
- Confirm `README.md` matches the current GUI.
- Confirm `README.md` still lists normal-user, optional, and developer-only dependencies accurately.
- Confirm `docs/SCREENSHOTS.md` screenshots match the current GUI.
- Confirm screenshots use sample paths only and do not show private folders, client names, or personal data.

## Test Check

Use Windows PowerShell 5.1 with Pester 4.10.1.

Run from the repository root:

```powershell
Import-Module Pester -RequiredVersion 4.10.1 -Force
Invoke-Pester -Script .\tests\DupliView.Tests.ps1 -EnableExit
```

The release is not ready if any test fails.

## Manual Smoke Check

Use a small fake folder, not real user data:

```text
C:\Users\Example\Documents\TestDuplicates
```

Check:

- `Run DupliView.cmd` opens the GUI.
- `Add Folder` adds a folder.
- `Add Manual Path` accepts a valid existing path.
- Entering the same location again with a trailing-slash difference keeps one list entry.
- `Remove Selected` and `Clear All` work.
- `Choose Folder` changes the report destination.
- Leaving the default `Reports` folder selected creates it when `Start Scan` begins, not when the GUI opens.
- `Minimum size (MB)`, `Skip empty files`, and `Create error CSV` can be changed.
- `Start Scan` writes a CSV report.
- If the app folder is read-only, choosing another export folder still lets the scan start.
- `Copy Report Path` copies the final report path.
- The window stays responsive during a scan.
- The final CSV opens in Excel or a text editor.

## Safety Check

Confirm DupliView still does not:

- Delete scanned files.
- Move scanned files.
- Rename scanned files.
- Overwrite scanned files.
- Modify scanned files.
- Upload files.
- Make internet calls or network connections outside user-selected file shares.
- Send telemetry.
- Require administrator rights.
- Install anything.
- Create services or scheduled tasks.
- Modify the registry.
- Build or include an executable.

## ZIP Contents

Create the ZIP from the repository root:

```powershell
.\tools\New-ReleasePackage.ps1 -Version 0.2.0
```

The script writes `dist\DupliView-0.2.0.zip` and `dist\DupliView-0.2.0.zip.sha256`.

The release ZIP is source-inclusive. Normal users start with `START HERE.txt`; maintainers can inspect the source, tests, and packaging script.

The ZIP should include:

- `DupliView.ps1`
- `Run DupliView.cmd`
- `Run DupliView.bat`
- `START HERE.txt`
- `README.md`
- `LICENSE`
- `CHANGELOG.md`
- `SECURITY.md`
- `CONTRIBUTING.md`
- `tools/New-ReleasePackage.ps1`
- `src/`
- `tests/`
- `docs/`
- `docs/developer_docs/CHECKSUM_VERIFICATION.md`
- `docs/developer_docs/RELEASE_PROCESS.md`
- `Reports/.gitkeep`

For a coworker ZIP, keep `START HERE.txt`, the launchers, `DupliView.ps1`, `src/`, `Reports/`, and the main safety docs easy to see at the top level.

Do not include:

- `Reports/*.csv`
- `Reports/*.log`
- `Reports/*.tmp`
- `dist/`
- Temporary test folders.
- Private screenshots.
- Local editor settings.
- `.git/`

## Final Read

Open the ZIP in a separate folder and check that a normal user can see the launchers and README immediately.
