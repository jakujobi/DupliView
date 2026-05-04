# Network Drive Scan

Expected result: You add a mapped drive or shared path and understand why the scan may take longer than a local scan.

Use generic shared-drive examples such as `L:\` or `\\server\share`. Do not use private client names or personal paths when sharing screenshots or reports.

## Before You Start

DupliView is report-only. It reads files it can access and writes a CSV report. It does not change files or shared-drive settings.

For setup and basic requirements, see the README.

## Add A Mapped Drive

1. Open DupliView.
2. Click `Add Manual Path`.
3. Enter a mapped drive path such as `L:\`.
4. Confirm the path.
5. Check `Report destination`.
6. Review `Scan options`.
7. Set `Minimum size (MB)` if you want to ignore very small files.
8. Leave `Skip empty files` checked if zero-byte files are not useful for this scan.
9. Check `Create error CSV` if you want a separate CSV for unreadable or locked files.
10. Click `Start Scan`.

## Add A Shared Path

1. Click `Add Manual Path`.
2. Enter a shared path such as `\\server\share`.
3. Confirm the path.
4. Click `Start Scan` when your locations and options are ready.

## Why It Can Take Time

Shared drives can contain many folders and large files. DupliView may also wait while Windows responds to read requests.

Watch `Phase` and `Live log` to see whether DupliView is collecting files, grouping by size, hashing, grouping by hash, or writing the report.

`Readable files` and `Skipped` can help explain the final count. Some files may be locked by another program or hidden from your account. If many expected files are skipped, ask IT whether your Windows account has read access to that location.

## What This Does Not Do

This guide does not change shared-drive contents, permissions, or Windows drive setup. It only explains how to include a mapped drive or shared path in a report-only scan.
