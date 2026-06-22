# Release Process

This is the maintainer workflow for publishing a DupliView ZIP.

## 1. Prepare The Tree

Confirm the working tree contains only intended release changes:

```powershell
git status --short
```

Remove generated local reports before packaging. `Reports/` should contain only `.gitkeep`.

## 2. Run Tests

Run the pinned Pester suite:

```powershell
Import-Module Pester -RequiredVersion 4.10.1 -Force
Invoke-Pester -Script .\tests\DupliView.Tests.ps1 -EnableExit
```

Also run the Windows PowerShell compatibility path:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Script .\tests\DupliView.Tests.ps1 -EnableExit"
```

Do not package the release if either run fails.

## 3. Run Hygiene Checks

Check whitespace and line endings:

```powershell
git diff --check
git ls-files --eol | Select-String 'mixed'
```

`git diff --check` should print no errors. The mixed-line-ending check should print no files.

## 4. Build The ZIP

Build the release package from the repository root:

```powershell
.\tools\New-ReleasePackage.ps1 -Version 0.2.0 -Force
```

This creates:

- `dist\DupliView-0.2.0.zip`
- `dist\DupliView-0.2.0.zip.sha256`

## 5. Inspect The ZIP

Confirm the ZIP contains the expected release files and no generated reports:

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path .\dist\DupliView-0.2.0.zip))
try {
    $zip.Entries | Select-Object -ExpandProperty FullName | Sort-Object
}
finally {
    $zip.Dispose()
}
```

The ZIP should not include `.git/`, `dist/`, generated `Reports/*.csv`, temporary folders, or private screenshots.

## 6. Verify The Checksum

Read the generated checksum:

```powershell
Get-Content .\dist\DupliView-0.2.0.zip.sha256
```

For recipient instructions, see [Checksum Verification](CHECKSUM_VERIFICATION.md).

## 7. Fresh-Folder Smoke Test

Extract the ZIP into a separate folder.

Confirm a normal user can immediately see:

- `START HERE.txt`
- `Run DupliView.cmd`
- `Run DupliView.bat`
- `README.md`

Run a small fake-folder scan. Confirm it writes a CSV report and does not change scanned files.

## 8. Publish

After local verification:

1. Commit the release-ready changes.
2. Create a release tag if this repository uses tags.
3. Upload or distribute `DupliView-0.2.0.zip` and `DupliView-0.2.0.zip.sha256` together.
4. Keep the checksum visible wherever the ZIP is shared.
