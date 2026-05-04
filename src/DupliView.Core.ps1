function Invoke-DupliViewProgress {
    param(
        [scriptblock] $ProgressCallback,
        [string] $Message
    )

    if ($ProgressCallback) {
        & $ProgressCallback $Message
    }
}

function Get-DupliViewSafeFileNamePart {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    $safe = $Name
    foreach ($invalidCharacter in [System.IO.Path]::GetInvalidFileNameChars()) {
        $safe = $safe.Replace([string] $invalidCharacter, '_')
    }

    $safe = $safe -replace '\s+', '_'
    $safe = $safe -replace '_+', '_'
    $safe = $safe.Trim([char[]] @('_', '.', ' '))

    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = 'SelectedLocation'
    }

    if ($safe.Length -gt 80) {
        $safe = $safe.Substring(0, 80).Trim([char[]] @('_', '.', ' '))
    }

    return $safe
}

function Get-DupliViewSafeSourceName {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $ScanLocations
    )

    if ($ScanLocations.Count -gt 1) {
        return 'MultipleLocations'
    }

    $location = ([string] $ScanLocations[0]).Trim()
    $withoutTrailingSlash = $location.TrimEnd([char[]] @('\', '/'))

    if ($withoutTrailingSlash -match '^([A-Za-z]):$') {
        return $Matches[1].ToUpperInvariant()
    }

    if ($location -match '^([A-Za-z]):[\\/]*(.*)$') {
        $drive = $Matches[1].ToUpperInvariant()
        $rest = $Matches[2].Trim([char[]] @('\', '/'))

        if ([string]::IsNullOrWhiteSpace($rest)) {
            return $drive
        }

        return Get-DupliViewSafeFileNamePart -Name ("{0}_{1}" -f $drive, $rest)
    }

    if ($location -match '^[\\/]{2}([^\\/]+)[\\/]([^\\/]+)(.*)$') {
        $server = $Matches[1]
        $share = $Matches[2]
        $rest = $Matches[3].Trim([char[]] @('\', '/'))
        if ([string]::IsNullOrWhiteSpace($rest)) {
            return Get-DupliViewSafeFileNamePart -Name ("{0}_{1}" -f $server, $share)
        }

        return Get-DupliViewSafeFileNamePart -Name ("{0}_{1}_{2}" -f $server, $share, $rest)
    }

    return Get-DupliViewSafeFileNamePart -Name $withoutTrailingSlash
}

function New-DupliViewReportFileName {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $ScanLocations,

        [datetime] $Timestamp = (Get-Date),

        [switch] $ErrorReport
    )

    $sourceName = Get-DupliViewSafeSourceName -ScanLocations $ScanLocations
    $datePart = $Timestamp.ToString('yyyy-MM-dd_HH-mm-ss')
    $errorSuffix = ''

    if ($ErrorReport) {
        $errorSuffix = '_errors'
    }

    return 'Duplicate_Report_{0}_{1}{2}.csv' -f $sourceName, $datePart, $errorSuffix
}

function Convert-DupliViewMinimumSizeToBytes {
    param(
        [double] $MinimumSizeMB
    )

    if ($MinimumSizeMB -lt 0) {
        throw 'Minimum size cannot be negative.'
    }

    return [int64] [math]::Round($MinimumSizeMB * 1MB, 0, [System.MidpointRounding]::AwayFromZero)
}

function New-DupliViewErrorRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Stage,

        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Error
    )

    return [pscustomobject] [ordered] @{
        Time = Get-Date
        Stage = $Stage
        Path = $Path
        Error = $Error
    }
}

function Get-DupliViewDriveOrSource {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FullPath
    )

    $root = [System.IO.Path]::GetPathRoot($FullPath)

    if ($root -match '^([A-Za-z]):') {
        return ('{0}:' -f $Matches[1].ToUpperInvariant())
    }

    if ($root -match '^[\\/]{2}([^\\/]+)[\\/]([^\\/]+)') {
        return ('\\{0}\{1}' -f $Matches[1], $Matches[2])
    }

    if ([string]::IsNullOrWhiteSpace($root)) {
        return 'Unknown'
    }

    return $root.TrimEnd([char[]] @('\', '/'))
}

function Get-DupliViewCandidateFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $ScanLocations,

        [int64] $MinimumSizeBytes = 0,

        [bool] $SkipEmptyFiles = $true
    )

    $files = New-Object System.Collections.ArrayList
    $errorRecords = New-Object System.Collections.ArrayList
    $seenFullPaths = @{}
    $skippedEmptyFileCount = 0
    $skippedMinimumSizeFileCount = 0

    foreach ($root in $ScanLocations) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            [void] $errorRecords.Add((New-DupliViewErrorRecord -Stage 'Scanning' -Path $root -Error 'Path does not exist or is not a folder.'))
            continue
        }

        $scanErrors = @()
        $items = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable scanErrors)

        foreach ($scanError in $scanErrors) {
            $errorPath = [string] $scanError.TargetObject
            [void] $errorRecords.Add((New-DupliViewErrorRecord -Stage 'Scanning' -Path $errorPath -Error $scanError.Exception.Message))
        }

        foreach ($item in $items) {
            try {
                if ($seenFullPaths.ContainsKey($item.FullName)) {
                    continue
                }

                $seenFullPaths[$item.FullName] = $true
                $sizeBytes = [int64] $item.Length

                if ($SkipEmptyFiles -and $sizeBytes -eq 0) {
                    $skippedEmptyFileCount++
                    continue
                }

                if ($sizeBytes -lt $MinimumSizeBytes) {
                    $skippedMinimumSizeFileCount++
                    continue
                }

                [void] $files.Add([pscustomobject] [ordered] @{
                    RootScanned = $root
                    FullPath = $item.FullName
                    FileName = $item.Name
                    FileExtension = $item.Extension
                    FolderPath = $item.DirectoryName
                    SizeBytes = $sizeBytes
                    LastModified = $item.LastWriteTime
                })
            }
            catch {
                [void] $errorRecords.Add((New-DupliViewErrorRecord -Stage 'Filtering' -Path $item.FullName -Error $_.Exception.Message))
            }
        }
    }

    return [pscustomobject] @{
        Files = $files
        ErrorRecords = $errorRecords
        CandidateFileCount = $files.Count
        SkippedEmptyFileCount = $skippedEmptyFileCount
        SkippedMinimumSizeFileCount = $skippedMinimumSizeFileCount
    }
}

function Get-DupliViewHashText {
    param(
        [Parameter(Mandatory = $true)]
        $HashResult
    )

    if ($HashResult -is [string]) {
        return $HashResult
    }

    if ($HashResult.PSObject.Properties.Name -contains 'Hash') {
        return [string] $HashResult.Hash
    }

    throw 'Hash command did not return a Hash value.'
}

function Get-DupliViewDuplicateRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $ScanLocations,

        [int64] $MinimumSizeBytes = 0,

        [bool] $SkipEmptyFiles = $true,

        [string] $HashAlgorithm = 'SHA256',

        [scriptblock] $HashFileScriptBlock = {
            param($Path, $Algorithm)
            Get-FileHash -LiteralPath $Path -Algorithm $Algorithm -ErrorAction Stop
        },

        [scriptblock] $ProgressCallback
    )

    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message 'Step 2: Collecting files from selected locations...'
    $candidateResult = Get-DupliViewCandidateFiles -ScanLocations $ScanLocations -MinimumSizeBytes $MinimumSizeBytes -SkipEmptyFiles $SkipEmptyFiles
    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message ('Found {0:N0} readable files.' -f $candidateResult.CandidateFileCount)
    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message ('Skipped unreadable items: {0:N0}.' -f $candidateResult.ErrorRecords.Count)

    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message 'Step 3: Grouping files by size...'
    $sizeGroups = @($candidateResult.Files | Group-Object -Property SizeBytes | Where-Object { $_.Count -gt 1 })
    $matchingSizeFiles = @($sizeGroups | ForEach-Object { $_.Group })
    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message ('Found {0:N0} files with matching sizes.' -f $matchingSizeFiles.Count)

    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message 'Step 4: Hashing candidate files...'
    $hashRecords = New-Object System.Collections.ArrayList
    $errorRecords = New-Object System.Collections.ArrayList

    foreach ($errorRecord in $candidateResult.ErrorRecords) {
        [void] $errorRecords.Add($errorRecord)
    }

    foreach ($file in $matchingSizeFiles) {
        try {
            $hashResult = & $HashFileScriptBlock $file.FullPath $HashAlgorithm
            $hash = Get-DupliViewHashText -HashResult $hashResult

            if ([string]::IsNullOrWhiteSpace($hash)) {
                throw 'Hash command returned an empty hash.'
            }

            [void] $hashRecords.Add([pscustomobject] [ordered] @{
                RootScanned = $file.RootScanned
                FullPath = $file.FullPath
                FileName = $file.FileName
                FileExtension = $file.FileExtension
                FolderPath = $file.FolderPath
                SizeBytes = $file.SizeBytes
                LastModified = $file.LastModified
                Hash = $hash
            })
        }
        catch {
            [void] $errorRecords.Add((New-DupliViewErrorRecord -Stage 'Hashing' -Path $file.FullPath -Error $_.Exception.Message))
        }
    }

    if ($errorRecords.Count -ne $candidateResult.ErrorRecords.Count) {
        Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message ('Skipped unreadable or failed-hash items: {0:N0}.' -f $errorRecords.Count)
    }

    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message 'Step 5: Grouping files by hash...'
    $duplicateHashGroups = @(
        $hashRecords |
            Group-Object -Property Hash |
            Where-Object { $_.Count -gt 1 } |
            Sort-Object @{ Expression = { [int64] $_.Group[0].SizeBytes }; Descending = $true }, Name
    )

    $duplicateRecords = New-Object System.Collections.ArrayList
    $exportedAt = Get-Date
    $groupNumber = 1

    foreach ($hashGroup in $duplicateHashGroups) {
        $groupLabel = 'Group{0:000}' -f $groupNumber
        $groupFiles = @($hashGroup.Group | Sort-Object -Property FullPath)
        $groupFileCount = $groupFiles.Count

        foreach ($file in $groupFiles) {
            [void] $duplicateRecords.Add([pscustomobject] [ordered] @{
                DuplicateGroup = $groupLabel
                GroupFileCount = $groupFileCount
                RootScanned = $file.RootScanned
                DriveOrSource = Get-DupliViewDriveOrSource -FullPath $file.FullPath
                FileName = $file.FileName
                FileExtension = $file.FileExtension
                FolderPath = $file.FolderPath
                FullPath = $file.FullPath
                SizeBytes = $file.SizeBytes
                SizeMB = [math]::Round(($file.SizeBytes / 1MB), 2)
                Hash = $file.Hash
                LastModified = $file.LastModified
                ExportedAt = $exportedAt
            })
        }

        $groupNumber++
    }

    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message ('Found {0:N0} duplicate groups.' -f $duplicateHashGroups.Count)

    return [pscustomobject] @{
        DuplicateRecords = $duplicateRecords
        ErrorRecords = $errorRecords
        CandidateFileCount = $candidateResult.CandidateFileCount
        SkippedEmptyFileCount = $candidateResult.SkippedEmptyFileCount
        SkippedMinimumSizeFileCount = $candidateResult.SkippedMinimumSizeFileCount
        MatchingSizeFileCount = $matchingSizeFiles.Count
        HashedFileCount = $hashRecords.Count
        DuplicateGroupCount = $duplicateHashGroups.Count
        SkippedUnreadableItemCount = $errorRecords.Count
    }
}

function Get-DupliViewCsvHeaderLine {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Columns
    )

    $escapedColumns = @($Columns | ForEach-Object { $_ -replace '"', '""' })
    return '"{0}"' -f ($escapedColumns -join '","')
}

function Get-DupliViewAvailableReportPath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ExportFolder,

        [Parameter(Mandatory = $true)]
        [string] $FileName
    )

    $initialPath = Join-Path $ExportFolder $FileName

    if (-not (Test-Path -LiteralPath $initialPath)) {
        return $initialPath
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [System.IO.Path]::GetExtension($FileName)

    for ($attempt = 1; $attempt -le 999; $attempt++) {
        $candidateName = '{0}_{1:000}{2}' -f $baseName, $attempt, $extension
        $candidatePath = Join-Path $ExportFolder $candidateName

        if (-not (Test-Path -LiteralPath $candidatePath)) {
            return $candidatePath
        }
    }

    throw 'Could not create a non-colliding report filename.'
}

function Export-DupliViewDuplicateReport {
    param(
        [Parameter(Mandatory = $true)]
        $Records,

        [Parameter(Mandatory = $true)]
        [string] $ExportFolder,

        [Parameter(Mandatory = $true)]
        [string] $FileName,

        [Parameter(Mandatory = $true)]
        [string[]] $CsvColumns
    )

    if (-not (Test-Path -LiteralPath $ExportFolder -PathType Container)) {
        throw 'Export folder does not exist.'
    }

    $reportPath = Get-DupliViewAvailableReportPath -ExportFolder $ExportFolder -FileName $FileName
    $recordList = @($Records)

    if ($recordList.Count -eq 0) {
        $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $true
        [System.IO.File]::WriteAllLines($reportPath, [string[]] @(Get-DupliViewCsvHeaderLine -Columns $CsvColumns), $encoding)
    }
    else {
        $recordList |
            Select-Object -Property $CsvColumns |
            Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
    }

    return $reportPath
}

function Export-DupliViewErrorReport {
    param(
        [Parameter(Mandatory = $true)]
        $ErrorRecords,

        [Parameter(Mandatory = $true)]
        [string] $ExportFolder,

        [Parameter(Mandatory = $true)]
        [string] $FileName
    )

    if (-not (Test-Path -LiteralPath $ExportFolder -PathType Container)) {
        throw 'Export folder does not exist.'
    }

    $reportPath = Get-DupliViewAvailableReportPath -ExportFolder $ExportFolder -FileName $FileName
    $columns = @('Time', 'Stage', 'Path', 'Error')
    $recordList = @($ErrorRecords)

    if ($recordList.Count -eq 0) {
        $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $true
        [System.IO.File]::WriteAllLines($reportPath, [string[]] @(Get-DupliViewCsvHeaderLine -Columns $columns), $encoding)
    }
    else {
        $recordList |
            Select-Object -Property $columns |
            Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
    }

    return $reportPath
}
