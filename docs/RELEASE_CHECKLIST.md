# Release Checklist

Use this checklist before publishing a DupliView ZIP.

## Version Check

- Confirm the version or release name.
- Update `CHANGELOG.md`.
- Confirm `LICENSE` uses the correct copyright name.
- Confirm `README.md` matches the current GUI.

## Test Check

Run from the repository root:

```powershell
Invoke-Pester -Script .\tests\DupliView.Tests.ps1
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
- `Remove Selected` and `Clear All` work.
- `Choose Folder` changes the report destination.
- `Minimum size (MB)`, `Skip empty files`, and `Create error CSV` can be changed.
- `Start Scan` writes a CSV report.
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
- Make network calls.
- Send telemetry.
- Require administrator rights.
- Install anything.
- Create services or scheduled tasks.
- Modify the registry.
- Build or include an executable.

## ZIP Contents

Include:

- `DupliView.ps1`
- `Run DupliView.cmd`
- `Run DupliView.bat`
- `START HERE.txt`
- `README.md`
- `LICENSE`
- `CHANGELOG.md`
- `SECURITY.md`
- `CONTRIBUTING.md`
- `src/`
- `tests/`
- `docs/`
- `Reports/.gitkeep`

For a coworker ZIP, keep `START HERE.txt`, the launchers, `DupliView.ps1`, `src/`, `Reports/`, and the main safety docs easy to see at the top level.

Do not include:

- `Reports/*.csv`
- `Reports/*.log`
- `Reports/*.tmp`
- Temporary test folders.
- Private screenshots.
- Local editor settings.
- `.git/`

## Final Read

Open the ZIP in a separate folder and check that a normal user can see the launchers and README immediately.
