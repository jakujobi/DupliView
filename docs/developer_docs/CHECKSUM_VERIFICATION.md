# Checksum Verification

Use the checksum file to confirm that the release ZIP has not changed since it was built.

## Files

A release should include these two files together:

- `DupliView-0.2.0.zip`
- `DupliView-0.2.0.zip.sha256`

The `.sha256` file contains the expected SHA-256 hash for the ZIP.

## Verify On Windows

Open PowerShell in the folder that contains the ZIP and checksum file.

Run:

```powershell
Get-FileHash .\DupliView-0.2.0.zip -Algorithm SHA256
```

Compare the `Hash` value to the value in:

```powershell
Get-Content .\DupliView-0.2.0.zip.sha256
```

The values must match. Letter case does not matter.

## If The Hash Does Not Match

Do not run the ZIP contents if the hash does not match.

Get a fresh copy of both files from the release owner. A mismatch can mean the ZIP was rebuilt, corrupted during transfer, or changed after it was packaged.

## Maintainer Notes

The checksum changes every time the ZIP changes. If you rebuild the release package, distribute the new `.zip` and the new `.zip.sha256` together.

Do not edit the ZIP after generating the checksum.
