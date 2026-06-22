# Read The CSV

Expected result: You can open the CSV report in Excel and understand which rows belong to the same duplicate group.

The CSV is the main DupliView output. DupliView is report-only. It does not change the files listed in the report.

## Open The Report

1. After a scan finishes, read `Final report path`.
2. Click `Copy Report Path` if you want to paste the path somewhere else.
3. Open the CSV in Excel.

If the scan used a folder such as `C:\Users\Example\Documents\TestDuplicates`, the report rows will show full Windows paths from that folder.

## Columns To Know

`DuplicateGroup`: group label for exact matches, such as `Group001`. Rows with the same value are exact matches.

`GroupFileCount`: number of files in that duplicate group.

`RootScanned`: selected scan location that produced the row.

`DriveOrSource`: drive letter or shared source for the file.

`FileName`: file name only.

`FileExtension`: file extension, such as `.pdf`, `.docx`, or `.xlsx`.

`FolderPath`: folder containing the file.

`FullPath`: full path to each matching file.

`SizeBytes`: file size in bytes.

`SizeMiB`: file size in mebibytes.

`Hash`: exact-match fingerprint DupliView calculated for the file. Files in the same duplicate group have the same hash.

`LastModified`: Windows last-modified date and time for that file.

`ExportedAt`: date and time DupliView wrote the report row.

## A Simple Review Method

1. Sort by `DuplicateGroup`.
2. Keep rows with the same `DuplicateGroup` together.
3. Compare `FullPath`, `SizeMiB`, and `LastModified`.
4. Use the report to discuss the results with the file owner or team.

Do not change the report rows to make DupliView do something. The CSV is not an instruction file; it is only a record of what the scan found.

## What This Does Not Do

This guide does not tell you which file is best, change any listed file, or make DupliView act on the CSV. It only explains how to read the report.
