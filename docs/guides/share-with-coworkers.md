# Share With Coworkers

Expected result: You can give coworkers the DupliView folder and explain how to run a report-only scan.

DupliView is meant to be simple to run from its folder. It does not require coworkers to know PowerShell commands for normal use.

## Safety Message To Share

DupliView is report-only. It reads selected folders and writes CSV reports. It does not change files.

Use this message when sending it to a coworker:

DupliView makes CSV reports of exact duplicate files in folders you choose. It does not change your files. Start with a small folder such as `C:\Users\Example\Documents\TestDuplicates`, then review the CSV in Excel.

## What To Include

Give coworkers the DupliView folder with its launchers and project files together. They should keep the files together in one folder.

They can start DupliView with:

- `Run DupliView.cmd`
- `Run DupliView.bat`

They should not need admin rights for a normal report-only scan of folders their Windows account can read.

## Basic Instructions For Coworkers

1. Open DupliView.
2. Click `Add Folder` for a normal folder, or `Add Manual Path` for a path such as `L:\` or `\\server\share`.
   If they add the same location again with a trailing-slash difference, DupliView keeps one entry.
3. Check `Report destination`.
   They can keep the default `Reports` folder or choose another writable folder.
   If the DupliView folder is read-only, they should click `Choose Folder` before starting the scan.
4. Review `Scan options`.
5. Set `Minimum size (MB)` if needed.
6. Choose whether `Skip empty files` should be checked.
7. Choose whether to check `Create error CSV`.
8. Click `Start Scan`.
9. Watch `Phase`, `Readable files`, `Skipped`, `Duplicate groups`, and `Live log`.
10. When finished, read `Final report path` or click `Copy Report Path`.

## What This Does Not Do

This guide does not change coworker files, change permissions, or set up shared-drive access. It only explains how to share the DupliView folder and describe the report-only scan.
