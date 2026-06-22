if (-not $script:DupliViewCoreScriptPath) {
    $script:DupliViewCoreScriptPath = $PSCommandPath
}

$script:DupliViewSupportedHashAlgorithms = @('SHA1', 'SHA256', 'SHA384', 'SHA512', 'MD5')

function Invoke-DupliViewProgress {
    param(
        [scriptblock] $ProgressCallback,
        [string] $Message
    )

    if ($ProgressCallback) {
        & $ProgressCallback $Message
    }
}

function Test-DupliViewShouldReportHashProgress {
    param(
        [int] $ProcessedCount,
        [int] $TotalCount,
        [switch] $HashFailed
    )

    if ($TotalCount -le 0 -or $ProcessedCount -le 0) {
        return $false
    }

    return $HashFailed -or
        $ProcessedCount -eq 1 -or
        $ProcessedCount -eq $TotalCount -or
        ($ProcessedCount % 100) -eq 0
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

function Normalize-DupliViewContainerPath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $trimmedPath = $Path.Trim()

    if ($trimmedPath -match '^([A-Za-z]):$') {
        $driveRoot = ('{0}:\' -f $Matches[1].ToUpperInvariant())
        if (-not (Test-Path -LiteralPath $driveRoot -PathType Container)) {
            throw 'Path does not exist or is not a folder.'
        }

        return $driveRoot
    }

    try {
        $resolvedPath = [string] (Convert-Path -LiteralPath $trimmedPath -ErrorAction Stop)
    }
    catch {
        throw 'Path does not exist or is not a folder.'
    }

    if ($resolvedPath -notmatch '^[A-Za-z]:\\' -and $resolvedPath -notmatch '^[\\/]{2}') {
        throw 'Choose a file-system folder, drive, or network path.'
    }

    if ($resolvedPath -match '^[A-Za-z]:\\$') {
        return $resolvedPath
    }

    if ($resolvedPath -match '^[\\/]{2}[^\\/]+[\\/]([^\\/]+)[\\/]?$') {
        return $resolvedPath.TrimEnd([char[]] @('\', '/'))
    }

    return $resolvedPath.TrimEnd([char[]] @('\', '/'))
}

function Test-DupliViewFolderWritable {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Folder
    )

    $probePath = Join-Path $Folder ('.dupliview_write_test_{0}.tmp' -f ([guid]::NewGuid().ToString('N')))
    $stream = $null

    try {
        $stream = New-Object System.IO.FileStream -ArgumentList @($probePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 4096, [System.IO.FileOptions]::DeleteOnClose)
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($stream) {
            $stream.Dispose()
        }

    }
}

function Ensure-DupliViewExportFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ExportFolder,

        [Parameter(Mandatory = $true)]
        [string] $DefaultExportFolder
    )

    if (Test-Path -LiteralPath $ExportFolder -PathType Container) {
        $resolvedExportFolder = [string] (Convert-Path -LiteralPath $ExportFolder)
        if (-not (Test-DupliViewFolderWritable -Folder $resolvedExportFolder)) {
            throw 'Export folder is not writable. Choose another export folder and try again.'
        }

        return $resolvedExportFolder
    }

    $comparisonExportFolder = $ExportFolder.Trim()
    $comparisonDefaultFolder = $DefaultExportFolder.Trim()

    if ($comparisonExportFolder -notmatch '^[A-Za-z]:\\$') {
        $comparisonExportFolder = $comparisonExportFolder.TrimEnd([char[]] @('\', '/'))
    }

    if ($comparisonDefaultFolder -notmatch '^[A-Za-z]:\\$') {
        $comparisonDefaultFolder = $comparisonDefaultFolder.TrimEnd([char[]] @('\', '/'))
    }

    $isDefaultExportFolder = [string]::Equals(
        $comparisonExportFolder,
        $comparisonDefaultFolder,
        [System.StringComparison]::OrdinalIgnoreCase
    )

    if (-not $isDefaultExportFolder) {
        throw 'Export folder no longer exists. Choose an existing export folder and try again.'
    }

    try {
        [void] [System.IO.Directory]::CreateDirectory($ExportFolder)
        $createdExportFolder = [string] (Convert-Path -LiteralPath $ExportFolder)
        if (-not (Test-DupliViewFolderWritable -Folder $createdExportFolder)) {
            throw 'not writable'
        }

        return $createdExportFolder
    }
    catch {
        throw 'The default Reports folder could not be created here. Choose another export folder and try again.'
    }
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

function Assert-DupliViewHashAlgorithm {
    param(
        [Parameter(Mandatory = $true)]
        [string] $HashAlgorithm
    )

    if ($script:DupliViewSupportedHashAlgorithms -notcontains $HashAlgorithm.ToUpperInvariant()) {
        throw ('Unsupported hash algorithm: {0}.' -f $HashAlgorithm)
    }
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

    Assert-DupliViewHashAlgorithm -HashAlgorithm $HashAlgorithm

    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message 'Step 2: Collecting files from selected locations...'
    $candidateResult = Get-DupliViewCandidateFiles -ScanLocations $ScanLocations -MinimumSizeBytes $MinimumSizeBytes -SkipEmptyFiles $SkipEmptyFiles
    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message ('Found {0:N0} files after size and empty-file filters.' -f $candidateResult.CandidateFileCount)
    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message ('Scan errors before hashing: {0:N0}.' -f $candidateResult.ErrorRecords.Count)

    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message 'Step 3: Grouping files by size...'
    $sizeGroups = @($candidateResult.Files | Group-Object -Property SizeBytes | Where-Object { $_.Count -gt 1 })
    $matchingSizeFiles = @($sizeGroups | ForEach-Object { $_.Group })
    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message ('Found {0:N0} files with matching sizes.' -f $matchingSizeFiles.Count)

    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message 'Step 4: Hashing candidate files...'
    $hashRecords = New-Object System.Collections.ArrayList
    $errorRecords = New-Object System.Collections.ArrayList
    $failedHashFileCount = 0

    foreach ($errorRecord in $candidateResult.ErrorRecords) {
        [void] $errorRecords.Add($errorRecord)
    }

    $hashCandidateCount = $matchingSizeFiles.Count
    $processedHashCandidateCount = 0
    $successfulHashCandidateCount = 0

    foreach ($file in $matchingSizeFiles) {
        $processedHashCandidateCount++
        $hashFailed = $false

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

            $successfulHashCandidateCount++
        }
        catch {
            $hashFailed = $true
            $failedHashFileCount++
            [void] $errorRecords.Add((New-DupliViewErrorRecord -Stage 'Hashing' -Path $file.FullPath -Error $_.Exception.Message))
        }

        if (Test-DupliViewShouldReportHashProgress -ProcessedCount $processedHashCandidateCount -TotalCount $hashCandidateCount -HashFailed:$hashFailed) {
            if ($hashFailed) {
                Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message ('Hashing progress: processed {0:N0} of {1:N0} files; hashed {2:N0}; skipped failed hash.' -f $processedHashCandidateCount, $hashCandidateCount, $successfulHashCandidateCount)
            }
            else {
                Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message ('Hashing progress: processed {0:N0} of {1:N0} files; hashed {2:N0}.' -f $processedHashCandidateCount, $hashCandidateCount, $successfulHashCandidateCount)
            }
        }
    }

    $readableFileCount = $candidateResult.CandidateFileCount - $failedHashFileCount
    $skippedFileCount = $errorRecords.Count + $candidateResult.SkippedEmptyFileCount + $candidateResult.SkippedMinimumSizeFileCount
    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message ('Readable files: {0:N0}.' -f $readableFileCount)
    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message ('Skipped files: {0:N0}.' -f $skippedFileCount)

    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message 'Step 5: Grouping files by hash...'
    $duplicateHashGroups = @(
        $hashRecords |
            Group-Object -Property SizeBytes, Hash |
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
                SizeMiB = [math]::Round(($file.SizeBytes / 1MB), 2)
                Hash = $file.Hash
                LastModified = $file.LastModified
                ExportedAt = $exportedAt
            })
        }

        $groupNumber++
    }

    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message ('Found {0:N0} duplicate groups.' -f $duplicateHashGroups.Count)
    Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message ('Duplicate groups: {0:N0}.' -f $duplicateHashGroups.Count)

    return [pscustomobject] @{
        DuplicateRecords = $duplicateRecords
        ErrorRecords = $errorRecords
        CandidateFileCount = $candidateResult.CandidateFileCount
        ReadableFileCount = $readableFileCount
        FailedHashFileCount = $failedHashFileCount
        SkippedEmptyFileCount = $candidateResult.SkippedEmptyFileCount
        SkippedMinimumSizeFileCount = $candidateResult.SkippedMinimumSizeFileCount
        MatchingSizeFileCount = $matchingSizeFiles.Count
        HashedFileCount = $hashRecords.Count
        DuplicateGroupCount = $duplicateHashGroups.Count
        SkippedErrorItemCount = $errorRecords.Count
        SkippedUnreadableItemCount = $errorRecords.Count
    }
}

function Invoke-DupliViewScanOperation {
    param(
        [Parameter(Mandatory = $true)]
        $Arguments,

        [scriptblock] $ProgressCallback
    )

    $scanResult = $null
    $reportPath = $null
    $errorReportPath = $null

    try {
        Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message 'Step 1: Preparing scan...'

        $minimumSizeBytes = Convert-DupliViewMinimumSizeToBytes -MinimumSizeMB $Arguments.MinimumSizeMB
        $scanResult = Get-DupliViewDuplicateRecords `
            -ScanLocations $Arguments.ScanLocations `
            -MinimumSizeBytes $minimumSizeBytes `
            -SkipEmptyFiles $Arguments.SkipEmptyFiles `
            -HashAlgorithm $Arguments.HashAlgorithm `
            -ProgressCallback $ProgressCallback

        Invoke-DupliViewProgress -ProgressCallback $ProgressCallback -Message 'Step 6: Writing CSV report...'

        $timestamp = Get-Date
        $reportFileName = New-DupliViewReportFileName -ScanLocations $Arguments.ScanLocations -Timestamp $timestamp
        $reportPath = Export-DupliViewDuplicateReport -Records $scanResult.DuplicateRecords -ExportFolder $Arguments.ExportFolder -FileName $reportFileName -CsvColumns $Arguments.CsvColumns

        if ($Arguments.CreateErrorLog -and $scanResult.ErrorRecords.Count -gt 0) {
            $errorFileName = New-DupliViewReportFileName -ScanLocations $Arguments.ScanLocations -Timestamp $timestamp -ErrorReport
            $errorReportPath = Export-DupliViewErrorReport -ErrorRecords $scanResult.ErrorRecords -ExportFolder $Arguments.ExportFolder -FileName $errorFileName
        }

        return [pscustomobject] @{
            Success = $true
            ScanResult = $scanResult
            ReportPath = $reportPath
            ErrorReportPath = $errorReportPath
        }
    }
    catch {
        $failure = [ordered] @{
            Success = $false
            Error = $_.Exception.Message
        }

        if ($scanResult) {
            $failure.ScanResult = $scanResult
        }

        if (-not [string]::IsNullOrWhiteSpace($reportPath)) {
            $failure.ReportPath = $reportPath
        }

        if (-not [string]::IsNullOrWhiteSpace($errorReportPath)) {
            $failure.ErrorReportPath = $errorReportPath
        }

        return [pscustomobject] $failure
    }
}

function Start-DupliViewAsyncScan {
    param(
        [Parameter(Mandatory = $true)]
        $Arguments,

        [string] $CoreScriptPath = $script:DupliViewCoreScriptPath
    )

    if ([string]::IsNullOrWhiteSpace($CoreScriptPath) -or -not (Test-Path -LiteralPath $CoreScriptPath -PathType Leaf)) {
        throw 'Core script path does not exist.'
    }

    $progressQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = [System.Threading.ApartmentState]::MTA
    $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $runspace.Open()

    $powershell = [System.Management.Automation.PowerShell]::Create()
    $powershell.Runspace = $runspace

    $scriptText = @'
param($CoreScriptPath, $ScanArguments, $ProgressQueue)

try {
    . $CoreScriptPath

    $progressCallback = {
        param($Message)
        $ProgressQueue.Enqueue([string] $Message)
    }

    Invoke-DupliViewScanOperation -Arguments $ScanArguments -ProgressCallback $progressCallback
}
catch {
    [pscustomobject] @{
        Success = $false
        Error = $_.Exception.Message
    }
}
'@

    [void] $powershell.AddScript($scriptText)
    [void] $powershell.AddArgument($CoreScriptPath)
    [void] $powershell.AddArgument($Arguments)
    [void] $powershell.AddArgument($progressQueue)

    try {
        $asyncResult = $powershell.BeginInvoke()
    }
    catch {
        $powershell.Dispose()
        $runspace.Close()
        $runspace.Dispose()
        throw
    }

    return [pscustomobject] @{
        PowerShell = $powershell
        Runspace = $runspace
        AsyncResult = $asyncResult
        ProgressQueue = $progressQueue
    }
}

function Receive-DupliViewAsyncScanProgress {
    param(
        [Parameter(Mandatory = $true)]
        $ScanOperation
    )

    $messages = New-Object System.Collections.ArrayList
    [string] $message = $null

    while ($ScanOperation.ProgressQueue.TryDequeue([ref] $message)) {
        [void] $messages.Add($message)
        $message = $null
    }

    return $messages
}

function Read-DupliViewAsyncScanUpdate {
    param(
        [Parameter(Mandatory = $true)]
        $ScanOperation
    )

    $messages = @(
        Receive-DupliViewAsyncScanProgress -ScanOperation $ScanOperation
    )
    $isCompleted = $false
    $result = $null

    if ($ScanOperation.AsyncResult.IsCompleted) {
        $isCompleted = $true
        $result = Complete-DupliViewAsyncScan -ScanOperation $ScanOperation
    }

    return [pscustomobject] @{
        Messages = $messages
        IsCompleted = $isCompleted
        Result = $result
    }
}

function Stop-DupliViewAsyncScan {
    param(
        $ScanOperation
    )

    if (-not $ScanOperation) {
        return
    }

    if ($ScanOperation.PowerShell) {
        if ($ScanOperation.AsyncResult -and -not $ScanOperation.AsyncResult.IsCompleted) {
            try {
                $ScanOperation.PowerShell.Stop()
            }
            catch {
            }
        }

        try {
            $ScanOperation.PowerShell.Dispose()
        }
        catch {
        }
    }

    if ($ScanOperation.Runspace) {
        try {
            $ScanOperation.Runspace.Close()
        }
        catch {
        }

        try {
            $ScanOperation.Runspace.Dispose()
        }
        catch {
        }
    }
}

function Complete-DupliViewAsyncScan {
    param(
        [Parameter(Mandatory = $true)]
        $ScanOperation
    )

    try {
        $results = $ScanOperation.PowerShell.EndInvoke($ScanOperation.AsyncResult)
        if ($results.Count -eq 0) {
            throw 'The async scan did not return a result.'
        }

        return $results[0]
    }
    finally {
        Stop-DupliViewAsyncScan -ScanOperation $ScanOperation
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

    if ([string]::IsNullOrWhiteSpace($FileName) -or $FileName -ne [System.IO.Path]::GetFileName($FileName)) {
        throw 'Report filename must be a file name, not a path.'
    }

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

function Write-DupliViewCsvLines {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string[]] $Lines
    )

    $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $true
    $stream = $null
    $writer = $null

    try {
        $stream = New-Object System.IO.FileStream -ArgumentList @($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $writer = New-Object System.IO.StreamWriter -ArgumentList @($stream, $encoding)
        $stream = $null

        foreach ($line in $Lines) {
            $writer.WriteLine($line)
        }
    }
    finally {
        if ($writer) {
            $writer.Dispose()
        }
        elseif ($stream) {
            $stream.Dispose()
        }
    }
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

    $lines = @()
    if ($recordList.Count -eq 0) {
        $lines = [string[]] @(Get-DupliViewCsvHeaderLine -Columns $CsvColumns)
    }
    else {
        $lines = [string[]] @($recordList | Select-Object -Property $CsvColumns | ConvertTo-Csv -NoTypeInformation)
    }

    Write-DupliViewCsvLines -Path $reportPath -Lines $lines

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

    $lines = @()
    if ($recordList.Count -eq 0) {
        $lines = [string[]] @(Get-DupliViewCsvHeaderLine -Columns $columns)
    }
    else {
        $lines = [string[]] @($recordList | Select-Object -Property $columns | ConvertTo-Csv -NoTypeInformation)
    }

    Write-DupliViewCsvLines -Path $reportPath -Lines $lines

    return $reportPath
}
