# First Scan

Expected result: You run a small local scan and get a CSV report path you can open later.

Use a small test folder first, such as `C:\Users\Example\Documents\TestDuplicates`. This helps you see how DupliView reports results before you scan a larger place.

## Before You Start

DupliView is report-only. It reads file details and writes a CSV report. It does not change your files.

For setup and basic requirements, see the README.

## Steps

1. Open DupliView.
2. Click `Add Folder`.
3. Choose `C:\Users\Example\Documents\TestDuplicates`.
4. Check `Report destination`.
   You can keep the default `Reports` folder or choose a different export folder.
   DupliView creates the default `Reports` folder when the scan starts.
   If the DupliView folder is read-only, click `Choose Folder` and pick a writable place you can find later.
5. In `Scan options`, leave `Minimum size (MB)` at the value you want for this first test.
6. Leave `Skip empty files` checked if you do not want zero-byte files included.
7. Check `Create error CSV` only if you want a separate report for files DupliView could not read.
8. Click `Start Scan`.
9. Watch `Phase`, `Readable files`, `Skipped`, and `Duplicate groups` while the scan runs.
10. When the scan finishes, read `Final report path`.
11. Click `Copy Report Path` if you want to paste the report path into File Explorer, an email, or a note.

## What The Status Area Means

`Phase` shows what DupliView is doing now.

`Readable files` shows how many files passed the selected filters.

`Skipped` shows files that were not included because they were unreadable, empty, or below the `Minimum size (MB)` setting.

`Duplicate groups` shows how many exact-match groups were found.

`Final report path` shows where the CSV report was saved.

`Live log` shows the scan steps as they happen. It is useful if a scan takes longer than expected.

## What This Does Not Do

This guide does not change files, choose which copy is best, or tell you to alter anything DupliView reports. It only helps you create and find the report.
