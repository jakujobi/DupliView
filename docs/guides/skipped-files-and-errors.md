# Skipped Files And Errors

Expected result: You understand why `Skipped` may be greater than zero and when an error CSV may help.

DupliView is report-only. When it cannot read something, it records what happened and keeps scanning the files it can read.

## What Skipped Means

`Skipped` can include:

- Files Windows would not let DupliView read.
- Files locked by another program.
- Empty files when `Skip empty files` is checked.
- Files smaller than the `Minimum size (MB)` setting.

Skipped files are not included in duplicate matching for that scan.

## Use The Error CSV

1. In `Scan options`, check `Create error CSV`.
2. Run the scan with `Start Scan`.
3. When the scan finishes, read `Final report path`.
4. Look near the main report for the separate error CSV.

The error CSV is useful when you need to explain why a location had unreadable files. It can also help IT understand whether your Windows account needs read access to a folder such as `L:\` or `\\server\share`.

## Check The Status During A Scan

`Phase` shows what DupliView is doing.

`Readable files` shows files included after filters and access checks.

`Skipped` shows files left out for the reasons above.

`Duplicate groups` shows exact-match groups found among readable files.

`Live log` gives a step-by-step record of the scan.

## What This Does Not Do

This guide does not bypass Windows access rules, change locked files, or change file ownership. It only explains why DupliView may skip files in a report-only scan.
