# Troubleshooting

Expected result: You can tell whether DupliView is blocked by Windows, blocked by security software, or waiting on a slow scan.

DupliView is report-only. It reads selected folders and writes CSV reports. It does not change scanned files.

## The window opens and then closes

If DupliView opens for a moment and disappears, check the launcher window. `Run DupliView.cmd` and `Run DupliView.bat` both pause after PowerShell exits so you can read the message.

Common causes:

- Windows blocked the PowerShell script because the folder came from a downloaded ZIP.
- Antivirus or endpoint security blocked the PowerShell command line.
- The DupliView folder was copied without all project files.
- The user account cannot read the selected folder or write to the report folder.

Do not disable antivirus to run DupliView. If a work computer blocks PowerShell scripts, ask IT to review the DupliView folder and the source files.

## Antivirus reports suspicious PowerShell activity

Some security tools treat PowerShell launchers cautiously, especially when a command starts a script from a `.cmd` or `.bat` file. DupliView uses PowerShell because it is a no-install Windows script, not because it needs admin access.

The production app does not make network calls, upload files, create services, edit the registry, or change scanned files. The launchers only start `DupliView.ps1`.

If security software blocks the app:

1. Keep the warning visible.
2. Check that the folder came from the project repository or a trusted internal share.
3. Ask IT or the repository owner to review `DupliView.ps1`, `src/DupliView.Core.ps1`, and the launchers.
4. Share the warning text with the maintainer if it looks like a false positive.

## A scan seems stuck

Large folders and shared drives can take time. A scan may spend a long time collecting files or hashing large matching-size groups.

Check:

- `Phase` to see the current scan step.
- `Readable files` to see how many files passed the selected filters.
- `Skipped` to see whether unreadable, empty, or below-minimum-size files were excluded.
- `Live log` for the latest scan message.

For a first test, scan a small folder before scanning a full shared drive.

## The CSV is empty

An empty report means DupliView did not find duplicate groups with matching file content.

Possible reasons:

- The files have the same name but different content.
- The files have the same size but different content.
- `Minimum size (MB)` excluded the files.
- `Skip empty files` excluded zero-byte files.
- The selected folder did not contain readable duplicate files.

## What this does not do

This guide does not change Windows security settings, disable antivirus, alter files, or clean up duplicate results. It only helps explain report-only startup and scan issues.
