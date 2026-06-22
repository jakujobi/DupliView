$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$CoreScript = Join-Path $ProjectRoot 'src\DupliView.Core.ps1'

if (Test-Path -LiteralPath $CoreScript) {
    . $CoreScript
}

if (-not (Get-Command Test-DupliViewFolderWritable -ErrorAction SilentlyContinue)) {
    function Test-DupliViewFolderWritable {
        param([string] $Folder)
        return $true
    }
}

function New-TestFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Content
    )

    $folder = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::UTF8)
}

function New-EmptyTestFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $folder = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    [System.IO.File]::WriteAllBytes($Path, [byte[]] @())
}

function New-DupliViewTestRoot {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("DupliViewTests_{0}" -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    return $root
}

function Test-HasUtf8Bom {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
}

function Wait-DupliViewAsyncScan {
    param(
        [Parameter(Mandatory = $true)]
        $ScanOperation,

        [int] $TimeoutMilliseconds = 15000
    )

    $messages = New-Object System.Collections.ArrayList
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    while (-not $ScanOperation.AsyncResult.IsCompleted) {
        foreach ($message in (Receive-DupliViewAsyncScanProgress -ScanOperation $ScanOperation)) {
            [void] $messages.Add($message)
        }

        if ($stopwatch.ElapsedMilliseconds -ge $TimeoutMilliseconds) {
            throw 'Timed out waiting for async scan completion.'
        }

        Start-Sleep -Milliseconds 50
    }

    foreach ($message in (Receive-DupliViewAsyncScanProgress -ScanOperation $ScanOperation)) {
        [void] $messages.Add($message)
    }

    return $messages
}

$TestCsvColumns = @(
    'DuplicateGroup',
    'GroupFileCount',
    'RootScanned',
    'DriveOrSource',
    'FileName',
    'FileExtension',
    'FolderPath',
    'FullPath',
    'SizeBytes',
    'SizeMiB',
    'Hash',
    'LastModified',
    'ExportedAt'
)

Describe 'DupliView core duplicate detection' {
    BeforeEach {
        $script:TestRoot = New-DupliViewTestRoot
    }

    AfterEach {
        if ($script:TestRoot -and (Test-Path -LiteralPath $script:TestRoot)) {
            Remove-Item -LiteralPath $script:TestRoot -Recurse -Force
        }
    }

    It 'reports exact duplicates with identical content in different folders' {
        New-TestFile -Path (Join-Path $script:TestRoot 'A\same1.txt') -Content 'hello duplicate'
        New-TestFile -Path (Join-Path $script:TestRoot 'B\same2.txt') -Content 'hello duplicate'

        $result = Get-DupliViewDuplicateRecords -ScanLocations @($script:TestRoot) -MinimumSizeBytes 0 -SkipEmptyFiles $true -HashAlgorithm 'SHA256'

        $result.DuplicateGroupCount | Should Be 1
        $result.DuplicateRecords.Count | Should Be 2
        $fileNames = @($result.DuplicateRecords | Select-Object -ExpandProperty FileName)
        ($fileNames -contains 'same1.txt') | Should Be $true
        ($fileNames -contains 'same2.txt') | Should Be $true
    }

    It 'does not report files with the same name but different content' {
        New-TestFile -Path (Join-Path $script:TestRoot 'A\report.txt') -Content 'first content'
        New-TestFile -Path (Join-Path $script:TestRoot 'B\report.txt') -Content 'second content'

        $result = Get-DupliViewDuplicateRecords -ScanLocations @($script:TestRoot) -MinimumSizeBytes 0 -SkipEmptyFiles $true -HashAlgorithm 'SHA256'

        $result.DuplicateGroupCount | Should Be 0
        $result.DuplicateRecords.Count | Should Be 0
    }

    It 'does not report files with the same byte length but different content' {
        New-TestFile -Path (Join-Path $script:TestRoot 'A\same_size_1.txt') -Content 'abc'
        New-TestFile -Path (Join-Path $script:TestRoot 'B\same_size_2.txt') -Content 'xyz'

        $result = Get-DupliViewDuplicateRecords -ScanLocations @($script:TestRoot) -MinimumSizeBytes 0 -SkipEmptyFiles $true -HashAlgorithm 'SHA256'

        $result.MatchingSizeFileCount | Should Be 2
        $result.DuplicateGroupCount | Should Be 0
        $result.DuplicateRecords.Count | Should Be 0
    }

    It 'reports files with different names but identical content' {
        New-TestFile -Path (Join-Path $script:TestRoot 'A\invoice.pdf') -Content 'same bytes'
        New-TestFile -Path (Join-Path $script:TestRoot 'B\archive-copy.bin') -Content 'same bytes'

        $result = Get-DupliViewDuplicateRecords -ScanLocations @($script:TestRoot) -MinimumSizeBytes 0 -SkipEmptyFiles $true -HashAlgorithm 'SHA256'

        $result.DuplicateGroupCount | Should Be 1
        $fileNames = @($result.DuplicateRecords | Select-Object -ExpandProperty FileName)
        ($fileNames -contains 'invoice.pdf') | Should Be $true
        ($fileNames -contains 'archive-copy.bin') | Should Be $true
    }

    It 'excludes files smaller than the configured minimum size' {
        New-TestFile -Path (Join-Path $script:TestRoot 'A\small1.txt') -Content 'tiny'
        New-TestFile -Path (Join-Path $script:TestRoot 'B\small2.txt') -Content 'tiny'

        $result = Get-DupliViewDuplicateRecords -ScanLocations @($script:TestRoot) -MinimumSizeBytes 10 -SkipEmptyFiles $true -HashAlgorithm 'SHA256'

        $result.CandidateFileCount | Should Be 0
        $result.DuplicateRecords.Count | Should Be 0
    }

    It 'skips zero-byte files when SkipEmptyFiles is true' {
        New-EmptyTestFile -Path (Join-Path $script:TestRoot 'A\empty1.txt')
        New-EmptyTestFile -Path (Join-Path $script:TestRoot 'B\empty2.txt')

        $result = Get-DupliViewDuplicateRecords -ScanLocations @($script:TestRoot) -MinimumSizeBytes 0 -SkipEmptyFiles $true -HashAlgorithm 'SHA256'

        $result.CandidateFileCount | Should Be 0
        $result.SkippedEmptyFileCount | Should Be 2
        $result.DuplicateRecords.Count | Should Be 0
    }

    It 'can include zero-byte files when SkipEmptyFiles is false' {
        New-EmptyTestFile -Path (Join-Path $script:TestRoot 'A\empty1.txt')
        New-EmptyTestFile -Path (Join-Path $script:TestRoot 'B\empty2.txt')

        $result = Get-DupliViewDuplicateRecords -ScanLocations @($script:TestRoot) -MinimumSizeBytes 0 -SkipEmptyFiles $false -HashAlgorithm 'SHA256'

        $result.CandidateFileCount | Should Be 2
        $result.DuplicateGroupCount | Should Be 1
        $result.DuplicateRecords.Count | Should Be 2
    }

    It 'records hash failures and continues scanning other files' {
        $badPath = Join-Path $script:TestRoot 'A\bad.txt'
        $goodPath1 = Join-Path $script:TestRoot 'A\good1.txt'
        $goodPath2 = Join-Path $script:TestRoot 'B\good2.txt'

        New-TestFile -Path $badPath -Content 'same-size-data'
        New-TestFile -Path $goodPath1 -Content 'good duplicate'
        New-TestFile -Path $goodPath2 -Content 'good duplicate'

        $hashScript = {
            param($Path, $Algorithm)
            if ($Path -eq $badPath) {
                throw 'simulated read failure'
            }
            Get-FileHash -LiteralPath $Path -Algorithm $Algorithm
        }

        $result = Get-DupliViewDuplicateRecords -ScanLocations @($script:TestRoot) -MinimumSizeBytes 0 -SkipEmptyFiles $true -HashAlgorithm 'SHA256' -HashFileScriptBlock $hashScript

        $result.ErrorRecords.Count | Should Be 1
        $result.ErrorRecords[0].Stage | Should Be 'Hashing'
        $result.ErrorRecords[0].Path | Should Be $badPath
        $result.DuplicateGroupCount | Should Be 1
        $result.DuplicateRecords.Count | Should Be 2
    }

    It 'does not report one file as a duplicate when scan locations overlap' {
        $childFolder = Join-Path $script:TestRoot 'Child'
        $filePath = Join-Path $childFolder 'only-once.txt'
        New-TestFile -Path $filePath -Content 'single physical file'

        $result = Get-DupliViewDuplicateRecords -ScanLocations @($script:TestRoot, $childFolder) -MinimumSizeBytes 0 -SkipEmptyFiles $true -HashAlgorithm 'SHA256'

        $result.CandidateFileCount | Should Be 1
        $result.DuplicateGroupCount | Should Be 0
        $result.DuplicateRecords.Count | Should Be 0
    }

    It 'keeps different file sizes in separate duplicate groups even when hashes collide' {
        New-TestFile -Path (Join-Path $script:TestRoot 'A\one-a.txt') -Content 'a'
        New-TestFile -Path (Join-Path $script:TestRoot 'B\one-b.txt') -Content 'b'
        New-TestFile -Path (Join-Path $script:TestRoot 'C\two-a.txt') -Content 'aa'
        New-TestFile -Path (Join-Path $script:TestRoot 'D\two-b.txt') -Content 'bb'

        $hashScript = {
            param($Path, $Algorithm)
            return 'CONSTANT_HASH'
        }

        $result = Get-DupliViewDuplicateRecords -ScanLocations @($script:TestRoot) -MinimumSizeBytes 0 -SkipEmptyFiles $true -HashAlgorithm 'SHA256' -HashFileScriptBlock $hashScript

        $result.DuplicateGroupCount | Should Be 2
        $sizeGroups = @($result.DuplicateRecords | Group-Object -Property SizeBytes)
        $sizeGroups.Count | Should Be 2
        @($sizeGroups | Where-Object { $_.Count -eq 2 }).Count | Should Be 2
        @($result.DuplicateRecords | Group-Object -Property DuplicateGroup | Where-Object { @($_.Group | Select-Object -ExpandProperty SizeBytes -Unique).Count -ne 1 }).Count | Should Be 0
    }

    It 'reports hash failures without counting failed hashes as readable files' {
        $badPath = Join-Path $script:TestRoot 'A\bad.txt'
        $goodPath1 = Join-Path $script:TestRoot 'A\good1.txt'
        $goodPath2 = Join-Path $script:TestRoot 'B\good2.txt'

        New-TestFile -Path $badPath -Content 'same-size-data'
        New-TestFile -Path $goodPath1 -Content 'good duplicate'
        New-TestFile -Path $goodPath2 -Content 'good duplicate'

        $hashScript = {
            param($Path, $Algorithm)
            if ($Path -eq $badPath) {
                throw 'simulated read failure'
            }
            Get-FileHash -LiteralPath $Path -Algorithm $Algorithm
        }

        $result = Get-DupliViewDuplicateRecords -ScanLocations @($script:TestRoot) -MinimumSizeBytes 0 -SkipEmptyFiles $true -HashAlgorithm 'SHA256' -HashFileScriptBlock $hashScript

        $result.ReadableFileCount | Should Be 2
        $result.FailedHashFileCount | Should Be 1
        $result.SkippedErrorItemCount | Should Be 1
    }

    It 'emits throttled hashing progress and live status messages' {
        New-TestFile -Path (Join-Path $script:TestRoot 'A\same1.txt') -Content 'hello duplicate'
        New-TestFile -Path (Join-Path $script:TestRoot 'B\same2.txt') -Content 'hello duplicate'
        New-TestFile -Path (Join-Path $script:TestRoot 'C\same3.txt') -Content 'hello duplicate'

        $messages = New-Object System.Collections.ArrayList
        $progressCallback = {
            param($Message)
            [void] $messages.Add($Message)
        }

        Get-DupliViewDuplicateRecords -ScanLocations @($script:TestRoot) -MinimumSizeBytes 0 -SkipEmptyFiles $true -HashAlgorithm 'SHA256' -ProgressCallback $progressCallback | Out-Null

        ($messages -contains 'Hashing progress: processed 1 of 3 files; hashed 1.') | Should Be $true
        ($messages -contains 'Hashing progress: processed 3 of 3 files; hashed 3.') | Should Be $true
        ($messages -contains 'Readable files: 3.') | Should Be $true
        ($messages -contains 'Skipped files: 0.') | Should Be $true
        ($messages -contains 'Duplicate groups: 1.') | Should Be $true
        @($messages | Where-Object { $_ -like 'Skipped unreadable*' }).Count | Should Be 0
    }

    It 'does not count failed hashes as hashed progress' {
        $badPath = Join-Path $script:TestRoot 'A\bad.txt'
        $goodPath1 = Join-Path $script:TestRoot 'A\good1.txt'
        $goodPath2 = Join-Path $script:TestRoot 'B\good2.txt'

        New-TestFile -Path $badPath -Content 'same-size-data'
        New-TestFile -Path $goodPath1 -Content 'good duplicate'
        New-TestFile -Path $goodPath2 -Content 'good duplicate'

        $hashScript = {
            param($Path, $Algorithm)
            if ($Path -eq $badPath) {
                throw 'simulated read failure'
            }
            Get-FileHash -LiteralPath $Path -Algorithm $Algorithm
        }

        $messages = New-Object System.Collections.ArrayList
        $progressCallback = {
            param($Message)
            [void] $messages.Add($Message)
        }

        Get-DupliViewDuplicateRecords -ScanLocations @($script:TestRoot) -MinimumSizeBytes 0 -SkipEmptyFiles $true -HashAlgorithm 'SHA256' -HashFileScriptBlock $hashScript -ProgressCallback $progressCallback | Out-Null

        @($messages | Where-Object { $_ -eq 'Hashing progress: processed 3 of 3 files; hashed 3.' }).Count | Should Be 0
        @($messages | Where-Object { $_ -like 'Hashing progress:*skipped failed hash.' }).Count | Should Be 1
        ($messages -contains 'Readable files: 2.') | Should Be $true
        ($messages -contains 'Skipped files: 1.') | Should Be $true
    }
}

Describe 'DupliView report filenames and size conversion' {
    It 'converts minimum size from MB to bytes' {
        Convert-DupliViewMinimumSizeToBytes -MinimumSizeMB 1.5 | Should Be 1572864
    }

    It 'creates a safe report filename for a single drive path' {
        $timestamp = Get-Date -Date '2026-04-29T14:32:05'

        $fileName = New-DupliViewReportFileName -ScanLocations @('L:\') -Timestamp $timestamp

        $fileName | Should Match '^Duplicate_Report_L_2026-04-29_14-32-05\.csv$'
        $fileName | Should Not Match '[<>:"/\\|?*]'
    }

    It 'creates a safe report filename for multiple scan locations' {
        $timestamp = Get-Date -Date '2026-04-29T14:32:05'

        $fileName = New-DupliViewReportFileName -ScanLocations @('L:\', 'M:\Shared') -Timestamp $timestamp

        $fileName | Should Match '^Duplicate_Report_MultipleLocations_2026-04-29_14-32-05\.csv$'
        $fileName | Should Not Match '[<>:"/\\|?*]'
    }

    It 'creates a matching error report filename' {
        $timestamp = Get-Date -Date '2026-04-29T14:32:05'

        $fileName = New-DupliViewReportFileName -ScanLocations @('L:\SharedProjects') -Timestamp $timestamp -ErrorReport

        $fileName | Should Match '^Duplicate_Report_L_SharedProjects_2026-04-29_14-32-05_errors\.csv$'
        $fileName | Should Not Match '[<>:"/\\|?*]'
    }

    It 'labels binary megabytes explicitly in the CSV configuration' {
        $tokens = $null
        $parseErrors = $null
        $guiAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $ProjectRoot 'DupliView.ps1'), [ref] $tokens, [ref] $parseErrors)
        $parseErrors.Count | Should Be 0

        $assignment = $guiAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -eq '$CsvColumns'
        }, $true)

        $configuredColumns = @($assignment.Right.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
        }, $true) | Select-Object -ExpandProperty Value)

        ($configuredColumns -contains 'SizeMiB') | Should Be $true
        ($configuredColumns -contains 'SizeMB') | Should Be $false
    }
}

Describe 'DupliView path normalization and export folder handling' {
    BeforeEach {
        $script:TestRoot = New-DupliViewTestRoot
    }

    AfterEach {
        if ($script:TestRoot -and (Test-Path -LiteralPath $script:TestRoot)) {
            Remove-Item -LiteralPath $script:TestRoot -Recurse -Force
        }
    }

    It 'normalizes local container paths with or without trailing slash' {
        $folder = Join-Path $script:TestRoot 'FolderA'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null

        $normalized1 = Normalize-DupliViewContainerPath -Path $folder
        $normalized2 = Normalize-DupliViewContainerPath -Path ($folder + '\')

        $normalized1 | Should Be $normalized2
    }

    It 'normalizes a bare drive letter to the drive root' {
        $driveRoot = [System.IO.Path]::GetPathRoot($ProjectRoot)
        $bareDrive = $driveRoot.TrimEnd('\')

        Normalize-DupliViewContainerPath -Path $bareDrive | Should Be $driveRoot
    }

    It 'rejects non-file-system provider paths' {
        $threw = $false
        try {
            Normalize-DupliViewContainerPath -Path 'HKCU:\Software' | Out-Null
        }
        catch {
            $threw = $true
            $_.Exception.Message | Should Be 'Choose a file-system folder, drive, or network path.'
        }

        $threw | Should Be $true
    }

    It 'normalizes UNC share paths with or without trailing slash' {
        Mock -CommandName Test-Path -MockWith { $true } -ParameterFilter {
            $LiteralPath -in @('\\server\share', '\\server\share\')
        }
        Mock -CommandName Convert-Path -MockWith {
            if ($LiteralPath -eq '\\server\share\') {
                return '\\server\share\'
            }

            return '\\server\share'
        } -ParameterFilter {
            $LiteralPath -in @('\\server\share', '\\server\share\')
        }

        $normalized1 = Normalize-DupliViewContainerPath -Path '\\server\share'
        $normalized2 = Normalize-DupliViewContainerPath -Path '\\server\share\'

        $normalized1 | Should Be $normalized2
        $normalized1 | Should Be '\\server\share'
    }

    It 'returns an existing export folder unchanged' {
        $result = Ensure-DupliViewExportFolder -ExportFolder $script:TestRoot -DefaultExportFolder (Join-Path $script:TestRoot 'Reports')

        $result | Should Be (Convert-Path -LiteralPath $script:TestRoot)
    }

    It 'rejects an existing export folder that is not writable' {
        Mock -CommandName Test-DupliViewFolderWritable -MockWith { $false } -ParameterFilter {
            $Folder -eq $script:TestRoot
        }

        $threw = $false
        try {
            Ensure-DupliViewExportFolder -ExportFolder $script:TestRoot -DefaultExportFolder (Join-Path $script:TestRoot 'Reports') | Out-Null
        }
        catch {
            $threw = $true
            $_.Exception.Message | Should Be 'Export folder is not writable. Choose another export folder and try again.'
        }

        $threw | Should Be $true
    }

    It 'creates the default export folder lazily when it is missing' {
        $defaultFolder = Join-Path $script:TestRoot 'Reports'

        (Test-Path -LiteralPath $defaultFolder -PathType Container) | Should Be $false
        $result = Ensure-DupliViewExportFolder -ExportFolder $defaultFolder -DefaultExportFolder $defaultFolder

        (Test-Path -LiteralPath $defaultFolder -PathType Container) | Should Be $true
        $result | Should Be (Convert-Path -LiteralPath $defaultFolder)
    }

    It 'creates the default export folder when its path contains wildcard characters' {
        $defaultFolder = Join-Path $script:TestRoot 'Reports[2026]'

        (Test-Path -LiteralPath $defaultFolder -PathType Container) | Should Be $false
        $result = Ensure-DupliViewExportFolder -ExportFolder $defaultFolder -DefaultExportFolder $defaultFolder

        (Test-Path -LiteralPath $defaultFolder -PathType Container) | Should Be $true
        $result | Should Be (Convert-Path -LiteralPath $defaultFolder)
    }

    It 'rejects a missing non-default export folder' {
        $missingFolder = Join-Path $script:TestRoot 'MissingReports'
        $threw = $false

        try {
            Ensure-DupliViewExportFolder -ExportFolder $missingFolder -DefaultExportFolder (Join-Path $script:TestRoot 'Reports') | Out-Null
        }
        catch {
            $threw = $true
            $_.Exception.Message | Should Be 'Export folder no longer exists. Choose an existing export folder and try again.'
        }

        $threw | Should Be $true
    }

    It 'surfaces a clear message when the default export folder cannot be created' {
        $defaultFolder = Join-Path $script:TestRoot 'Reports:Invalid'

        $threw = $false
        try {
            Ensure-DupliViewExportFolder -ExportFolder $defaultFolder -DefaultExportFolder $defaultFolder | Out-Null
        }
        catch {
            $threw = $true
            $_.Exception.Message | Should Be 'The default Reports folder could not be created here. Choose another export folder and try again.'
        }

        $threw | Should Be $true
    }
}

Describe 'DupliView async scanning' {
    BeforeEach {
        $script:TestRoot = New-DupliViewTestRoot
    }

    AfterEach {
        if ($script:ScanOperation) {
            Stop-DupliViewAsyncScan -ScanOperation $script:ScanOperation
            $script:ScanOperation = $null
        }

        if ($script:TestRoot -and (Test-Path -LiteralPath $script:TestRoot)) {
            Remove-Item -LiteralPath $script:TestRoot -Recurse -Force
        }
    }

    It 'reads progress updates and completion state from an async scan' {
        New-TestFile -Path (Join-Path $script:TestRoot 'A\same1.txt') -Content 'hello duplicate'
        New-TestFile -Path (Join-Path $script:TestRoot 'B\same2.txt') -Content 'hello duplicate'

        $arguments = [pscustomobject] @{
            ScanLocations = @($script:TestRoot)
            ExportFolder = $script:TestRoot
            MinimumSizeMB = 0
            SkipEmptyFiles = $true
            CreateErrorLog = $false
            HashAlgorithm = 'SHA256'
            CsvColumns = $TestCsvColumns
        }

        $script:ScanOperation = Start-DupliViewAsyncScan -CoreScriptPath $CoreScript -Arguments $arguments
        $allMessages = Wait-DupliViewAsyncScan -ScanOperation $script:ScanOperation
        $update = Read-DupliViewAsyncScanUpdate -ScanOperation $script:ScanOperation
        $result = $update.Result

        $script:ScanOperation = $null

        $update.IsCompleted | Should Be $true
        $result.Success | Should Be $true
        $result.ScanResult.DuplicateGroupCount | Should Be 1
        (Test-Path -LiteralPath $result.ReportPath) | Should Be $true
        (@($allMessages) | Where-Object { $_ -like 'Step 2:*' }).Count | Should Be 1
        (@($allMessages) | Where-Object { $_ -like 'Step 6:*' }).Count | Should Be 1
    }
}

Describe 'DupliView scan operation validation' {
    BeforeEach {
        $script:TestRoot = New-DupliViewTestRoot
    }

    AfterEach {
        if ($script:TestRoot -and (Test-Path -LiteralPath $script:TestRoot)) {
            Remove-Item -LiteralPath $script:TestRoot -Recurse -Force
        }
    }

    It 'fails the scan before writing a report when the hash algorithm is invalid' {
        New-TestFile -Path (Join-Path $script:TestRoot 'A\same1.txt') -Content 'hello duplicate'
        New-TestFile -Path (Join-Path $script:TestRoot 'B\same2.txt') -Content 'hello duplicate'

        $arguments = [pscustomobject] @{
            ScanLocations = @($script:TestRoot)
            ExportFolder = $script:TestRoot
            MinimumSizeMB = 0
            SkipEmptyFiles = $true
            CreateErrorLog = $false
            HashAlgorithm = 'NOT_A_HASH'
            CsvColumns = $TestCsvColumns
        }

        $result = Invoke-DupliViewScanOperation -Arguments $arguments

        $result.Success | Should Be $false
        $result.Error | Should Be 'Unsupported hash algorithm: NOT_A_HASH.'
        @($result.PSObject.Properties.Name -contains 'ReportPath') | Should Be $false
        @(Get-ChildItem -LiteralPath $script:TestRoot -Filter '*.csv').Count | Should Be 0
    }

    It 'returns the duplicate report path when optional error report writing fails' {
        New-TestFile -Path (Join-Path $script:TestRoot 'A\same1.txt') -Content 'hello duplicate'
        New-TestFile -Path (Join-Path $script:TestRoot 'B\same2.txt') -Content 'hello duplicate'

        Mock -CommandName Get-DupliViewDuplicateRecords -MockWith {
            [pscustomobject] @{
                DuplicateRecords = @()
                ErrorRecords = @([pscustomobject] @{ Time = Get-Date; Stage = 'Hashing'; Path = 'bad.txt'; Error = 'Access denied' })
                CandidateFileCount = 1
                ReadableFileCount = 0
                FailedHashFileCount = 1
                SkippedEmptyFileCount = 0
                SkippedMinimumSizeFileCount = 0
                MatchingSizeFileCount = 1
                HashedFileCount = 0
                DuplicateGroupCount = 0
                SkippedErrorItemCount = 1
            }
        }
        Mock -CommandName Export-DupliViewErrorReport -MockWith { throw 'simulated error report failure' }

        $arguments = [pscustomobject] @{
            ScanLocations = @($script:TestRoot)
            ExportFolder = $script:TestRoot
            MinimumSizeMB = 0
            SkipEmptyFiles = $true
            CreateErrorLog = $true
            HashAlgorithm = 'SHA256'
            CsvColumns = $TestCsvColumns
        }

        $result = Invoke-DupliViewScanOperation -Arguments $arguments

        $result.Success | Should Be $false
        $result.ReportPath | Should Not Be $null
        (Test-Path -LiteralPath $result.ReportPath) | Should Be $true
        $result.Error | Should Match 'simulated error report failure'
    }
}

Describe 'DupliView CSV export' {
    BeforeEach {
        $script:TestRoot = New-DupliViewTestRoot
    }

    AfterEach {
        if ($script:TestRoot -and (Test-Path -LiteralPath $script:TestRoot)) {
            Remove-Item -LiteralPath $script:TestRoot -Recurse -Force
        }
    }

    It 'exports the configured duplicate report columns in configured order' {
        New-TestFile -Path (Join-Path $script:TestRoot 'A\same1.txt') -Content 'hello duplicate'
        New-TestFile -Path (Join-Path $script:TestRoot 'B\same2.txt') -Content 'hello duplicate'

        $result = Get-DupliViewDuplicateRecords -ScanLocations @($script:TestRoot) -MinimumSizeBytes 0 -SkipEmptyFiles $true -HashAlgorithm 'SHA256'
        $reportPath = Export-DupliViewDuplicateReport -Records $result.DuplicateRecords -ExportFolder $script:TestRoot -FileName 'duplicates.csv' -CsvColumns $TestCsvColumns

        $header = [System.IO.File]::ReadAllLines($reportPath)[0]
        $header | Should Be ('"{0}"' -f ($TestCsvColumns -join '","'))
    }

    It 'exports a header-only duplicate report when there are no duplicate rows' {
        $reportPath = Export-DupliViewDuplicateReport -Records @() -ExportFolder $script:TestRoot -FileName 'empty.csv' -CsvColumns $TestCsvColumns

        $lines = [System.IO.File]::ReadAllLines($reportPath)
        $lines.Count | Should Be 1
        $lines[0] | Should Be ('"{0}"' -f ($TestCsvColumns -join '","'))
    }

    It 'does not overwrite an existing duplicate report file' {
        $existingReportPath = Join-Path $script:TestRoot 'duplicates.csv'
        [System.IO.File]::WriteAllText($existingReportPath, 'existing report', [System.Text.Encoding]::UTF8)

        $reportPath = Export-DupliViewDuplicateReport -Records @() -ExportFolder $script:TestRoot -FileName 'duplicates.csv' -CsvColumns $TestCsvColumns

        $reportPath | Should Be (Join-Path $script:TestRoot 'duplicates_001.csv')
        [System.IO.File]::ReadAllText($existingReportPath, [System.Text.Encoding]::UTF8) | Should Be 'existing report'
    }

    It 'rejects duplicate report filenames that are not leaf names' {
        $outsidePath = Join-Path (Split-Path -Parent $script:TestRoot) 'outside.csv'
        if (Test-Path -LiteralPath $outsidePath) {
            Remove-Item -LiteralPath $outsidePath -Force
        }

        $threw = $false
        try {
            Export-DupliViewDuplicateReport -Records @() -ExportFolder $script:TestRoot -FileName '..\outside.csv' -CsvColumns $TestCsvColumns | Out-Null
        }
        catch {
            $threw = $true
            $_.Exception.Message | Should Be 'Report filename must be a file name, not a path.'
        }

        $threw | Should Be $true
        Test-Path -LiteralPath $outsidePath | Should Be $false
    }

    It 'rejects error report filenames that are not leaf names' {
        $outsidePath = Join-Path (Split-Path -Parent $script:TestRoot) 'outside_errors.csv'
        if (Test-Path -LiteralPath $outsidePath) {
            Remove-Item -LiteralPath $outsidePath -Force
        }

        $threw = $false
        try {
            Export-DupliViewErrorReport -ErrorRecords @() -ExportFolder $script:TestRoot -FileName '..\outside_errors.csv' | Out-Null
        }
        catch {
            $threw = $true
            $_.Exception.Message | Should Be 'Report filename must be a file name, not a path.'
        }

        $threw | Should Be $true
        Test-Path -LiteralPath $outsidePath | Should Be $false
    }

    It 'uses the same UTF-8 BOM policy for empty and populated duplicate reports' {
        $record = [pscustomobject] @{
            DuplicateGroup = 'Group001'
            GroupFileCount = 1
            RootScanned = $script:TestRoot
            DriveOrSource = 'C:'
            FileName = 'same1.txt'
            FileExtension = '.txt'
            FolderPath = $script:TestRoot
            FullPath = Join-Path $script:TestRoot 'same1.txt'
            SizeBytes = 1
            SizeMiB = 0
            Hash = 'ABC'
            LastModified = Get-Date
            ExportedAt = Get-Date
        }

        $emptyReport = Export-DupliViewDuplicateReport -Records @() -ExportFolder $script:TestRoot -FileName 'empty.csv' -CsvColumns $TestCsvColumns
        $populatedReport = Export-DupliViewDuplicateReport -Records @($record) -ExportFolder $script:TestRoot -FileName 'populated.csv' -CsvColumns $TestCsvColumns

        Test-HasUtf8Bom -Path $emptyReport | Should Be $true
        Test-HasUtf8Bom -Path $populatedReport | Should Be $true
    }

    It 'requires the export folder to already exist' {
        $missingFolder = Join-Path $script:TestRoot ("Missing_{0}" -f ([guid]::NewGuid().ToString('N')))

        (Test-Path -LiteralPath $missingFolder -PathType Container) | Should Be $false
        $threw = $false
        try {
            Export-DupliViewDuplicateReport -Records @() -ExportFolder $missingFolder -FileName 'report.csv' -CsvColumns $TestCsvColumns | Out-Null
        }
        catch {
            $threw = $true
        }

        $threw | Should Be $true
    }

    It 'exports the configured error report columns' {
        $errorRecords = @(
            [pscustomobject] @{
                Time = Get-Date -Date '2026-04-29T14:32:05'
                Stage = 'Hashing'
                Path = Join-Path $script:TestRoot 'locked.txt'
                Error = 'Access denied'
            }
        )

        $reportPath = Export-DupliViewErrorReport -ErrorRecords $errorRecords -ExportFolder $script:TestRoot -FileName 'duplicates_errors.csv'

        $header = [System.IO.File]::ReadAllLines($reportPath)[0]
        $header | Should Be '"Time","Stage","Path","Error"'
    }

    It 'uses the same UTF-8 BOM policy for empty and populated error reports' {
        $errorRecords = @(
            [pscustomobject] @{
                Time = Get-Date -Date '2026-04-29T14:32:05'
                Stage = 'Hashing'
                Path = Join-Path $script:TestRoot 'locked.txt'
                Error = 'Access denied'
            }
        )

        $emptyReport = Export-DupliViewErrorReport -ErrorRecords @() -ExportFolder $script:TestRoot -FileName 'empty_errors.csv'
        $populatedReport = Export-DupliViewErrorReport -ErrorRecords $errorRecords -ExportFolder $script:TestRoot -FileName 'populated_errors.csv'

        Test-HasUtf8Bom -Path $emptyReport | Should Be $true
        Test-HasUtf8Bom -Path $populatedReport | Should Be $true
    }

    It 'keeps the production GUI CSV configuration in the requested order' {
        $tokens = $null
        $parseErrors = $null
        $guiAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $ProjectRoot 'DupliView.ps1'), [ref] $tokens, [ref] $parseErrors)
        $parseErrors.Count | Should Be 0

        $assignment = $guiAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -eq '$CsvColumns'
        }, $true)

        $assignment -eq $null | Should Be $false
        $configuredColumns = @($assignment.Right.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
        }, $true) | Select-Object -ExpandProperty Value)

        $configuredColumns.Count | Should Be $TestCsvColumns.Count
        for ($index = 0; $index -lt $TestCsvColumns.Count; $index++) {
            $configuredColumns[$index] | Should Be $TestCsvColumns[$index]
        }
    }
}

Describe 'DupliView GUI refresh' {
    BeforeAll {
        $script:GuiScriptPath = Join-Path $ProjectRoot 'DupliView.ps1'
        $script:GuiScriptContent = [System.IO.File]::ReadAllText($script:GuiScriptPath)
    }

    It 'uses native layout containers for a resizable guided single-screen interface' {
        $script:GuiScriptContent | Should Match 'TableLayoutPanel'
        $script:GuiScriptContent | Should Match 'FlowLayoutPanel'
        $script:GuiScriptContent | Should Match 'GroupBox'
    }

    It 'exposes the planned user-facing sections and scan options' {
        $requiredText = @(
            'Scan locations',
            'Report destination',
            'Scan options',
            'Scan status',
            'Live log',
            'Minimum size \(MB\)',
            'Skip empty files',
            'Create error CSV',
            'Copy Report Path'
        )

        foreach ($text in $requiredText) {
            $script:GuiScriptContent | Should Match $text
        }
    }

    It 'uses a runspace-backed scan runner instead of a background worker' {
        $script:GuiScriptContent | Should Match 'Start-DupliViewAsyncScan'
        $script:GuiScriptContent | Should Match 'Read-DupliViewAsyncScanUpdate'
        $script:GuiScriptContent | Should Not Match 'System\.ComponentModel\.BackgroundWorker'
        $script:GuiScriptContent | Should Not Match 'RunWorkerAsync'
    }

    It 'does not eagerly create the default report folder during startup' {
        $script:GuiScriptContent | Should Not Match '(?s)\$defaultReportFolder\s*=\s*Join-Path\s+\$ScriptRoot\s+\$DefaultReportFolderName\s*if\s*\(-not\s*\(Test-Path\s+-LiteralPath\s+\$defaultReportFolder\s+-PathType\s+Container\)\)\s*\{\s*\[void\]\s*\(New-Item\s+-ItemType\s+Directory\s+-Path\s+\$defaultReportFolder\s+-Force\)\s*\}'
    }

    It 'tracks summary status fields and the final report path' {
        $requiredVariables = @(
            'phaseValueLabel',
            'readableValueLabel',
            'skippedValueLabel',
            'duplicatesValueLabel',
            'reportPathTextBox'
        )

        foreach ($variableName in $requiredVariables) {
            $script:GuiScriptContent | Should Match ([regex]::Escape('$' + $variableName))
        }
    }

    It 'counts scan errors, empty-file, and minimum-size skips in the skipped status summary' {
        $script:GuiScriptContent | Should Match 'SkippedErrorItemCount\s*\+\s*\$scanResult\.SkippedEmptyFileCount\s*\+\s*\$scanResult\.SkippedMinimumSizeFileCount'
    }

    It 'uses hash-success count for readable files in the final status summary' {
        $script:GuiScriptContent | Should Match 'readableValueLabel\.Text\s*=\s*\(''\{0:N0\}''\s*-f\s*\$scanResult\.ReadableFileCount\)'
    }

    It 'updates live status counts from scan progress messages' {
        $coreScriptContent = [System.IO.File]::ReadAllText((Join-Path $ProjectRoot 'src\DupliView.Core.ps1'))

        $script:GuiScriptContent | Should Match 'Update-DupliViewLiveStatusFromMessage'
        $coreScriptContent | Should Match 'Readable files:\s*\{0:N0\}'
        $coreScriptContent | Should Match 'Skipped files:\s*\{0:N0\}'
        $coreScriptContent | Should Match 'Duplicate groups:\s*\{0:N0\}'
    }

    It 'resets status and clears the log before start validation can fail' {
        $startIndex = $script:GuiScriptContent.IndexOf('$startScanButton.Add_Click')
        $resetIndex = $script:GuiScriptContent.IndexOf('Reset-DupliViewStatus', $startIndex)
        $validationIndex = $script:GuiScriptContent.IndexOf('$locationsList.Items.Count -eq 0', $startIndex)
        $clearIndex = $script:GuiScriptContent.IndexOf('$logTextBox.Clear()', $startIndex)

        $resetIndex -ge 0 | Should Be $true
        $startIndex -ge 0 | Should Be $true
        $validationIndex -ge 0 | Should Be $true
        $clearIndex -ge 0 | Should Be $true
        $resetIndex | Should BeLessThan $validationIndex
        $clearIndex | Should BeLessThan $validationIndex
    }

    It 'offers an in-window cancel action while a scan is running' {
        $script:GuiScriptContent | Should Match 'cancelScanButton'
        $script:GuiScriptContent | Should Match 'Cancel Scan'
        $script:GuiScriptContent | Should Match 'Cancel-DupliViewActiveScan'
        $script:GuiScriptContent | Should Match '\$cancelScanButton\.Add_Click'
    }

    It 'keeps the close button available while a scan is running' {
        $script:GuiScriptContent | Should Not Match '\$closeButton\.Enabled\s*=\s*\$Enabled'
    }
}

Describe 'DupliView documentation set' {
    It 'includes the planned user guides and support docs' {
        $requiredDocs = @(
            'CONTRIBUTING.md',
            'START HERE.txt',
            'docs\README.md',
            'docs\developer_docs\CHECKSUM_VERIFICATION.md',
            'docs\developer_docs\RELEASE_CHECKLIST.md',
            'docs\developer_docs\RELEASE_PROCESS.md',
            'docs\SCREENSHOTS.md',
            'docs\guides\first-scan.md',
            'docs\guides\network-drive-scan.md',
            'docs\guides\read-the-csv.md',
            'docs\guides\skipped-files-and-errors.md',
            'docs\guides\share-with-coworkers.md',
            'docs\guides\troubleshooting.md'
        )

        foreach ($relativePath in $requiredDocs) {
            Test-Path -LiteralPath (Join-Path $ProjectRoot $relativePath) | Should Be $true
        }
    }

    It 'keeps each user guide report-only and avoids cleanup instructions' {
        $guidePaths = @(
            'docs\guides\first-scan.md',
            'docs\guides\network-drive-scan.md',
            'docs\guides\read-the-csv.md',
            'docs\guides\skipped-files-and-errors.md',
            'docs\guides\share-with-coworkers.md',
            'docs\guides\troubleshooting.md'
        )

        foreach ($relativePath in $guidePaths) {
            $content = [System.IO.File]::ReadAllText((Join-Path $ProjectRoot $relativePath))
            $content | Should Match 'report-only'
            $content | Should Match 'What this does not do'
            $content | Should Not Match '(?im)^\s*\d+\.\s+.*\b(delete|remove|move|rename|cleanup|quarantine|recycle)\b'
            $content | Should Not Match '(?im)^\s*-\s+.*\b(delete|remove|move|rename|cleanup|quarantine|recycle)\b'
        }
    }

    It 'documents release and contribution safety checks' {
        $releaseChecklist = [System.IO.File]::ReadAllText((Join-Path $ProjectRoot 'docs\developer_docs\RELEASE_CHECKLIST.md'))
        $contributing = [System.IO.File]::ReadAllText((Join-Path $ProjectRoot 'CONTRIBUTING.md'))

        $releaseChecklist | Should Match 'Invoke-Pester'
        $releaseChecklist | Should Match 'New-ReleasePackage\.ps1 -Version 0\.2\.0'
        $releaseChecklist | Should Match 'Reports/\*\.csv'
        $releaseChecklist | Should Match 'CHECKSUM_VERIFICATION\.md'
        $releaseChecklist | Should Match 'RELEASE_PROCESS\.md'
        $contributing | Should Match 'report-only'
        $contributing | Should Match 'New-ReleasePackage\.ps1 -Version 0\.2\.0'
        $contributing | Should Match 'Pull requests'
    }

    It 'keeps the skipped-files guide aligned with error CSV columns' {
        $guide = [System.IO.File]::ReadAllText((Join-Path $ProjectRoot 'docs\guides\skipped-files-and-errors.md'))

        $guide | Should Match '`Time`'
        $guide | Should Match '`Stage`'
        $guide | Should Match '`Path`'
        $guide | Should Match '`Error`'
        $guide | Should Not Match '`Message`'
        $guide | Should Not Match '`ExportedAt`'
    }

    It 'uses screenshots as published docs instead of process notes' {
        $screenshots = [System.IO.File]::ReadAllText((Join-Path $ProjectRoot 'docs\SCREENSHOTS.md'))

        $screenshots | Should Match 'single-screen Windows Forms utility'
        $screenshots | Should Not Match 'Screenshots To Capture'
        $screenshots | Should Not Match 'Current Status'
        Test-Path -LiteralPath (Join-Path $ProjectRoot 'docs\images\README.md') | Should Be $false
    }

    It 'includes a coworker start-here guide for release ZIPs' {
        $startHere = [System.IO.File]::ReadAllText((Join-Path $ProjectRoot 'START HERE.txt'))

        $startHere | Should Match 'Double-click "Run DupliView\.cmd"'
        $startHere | Should Match 'report-only'
        $startHere | Should Match 'never deletes, moves, renames, overwrites, uploads, or modifies scanned files'
    }
}

Describe 'DupliView release packaging' {
    BeforeEach {
        $script:PackageTestRoot = New-DupliViewTestRoot
        $script:PackageDistCleanupPaths = @()
    }

    AfterEach {
        if ($script:PackageTestRoot -and (Test-Path -LiteralPath $script:PackageTestRoot)) {
            Remove-Item -LiteralPath $script:PackageTestRoot -Recurse -Force
        }

        foreach ($cleanupPath in $script:PackageDistCleanupPaths) {
            if ($cleanupPath -and (Test-Path -LiteralPath $cleanupPath)) {
                $resolvedPath = [string] (Resolve-Path -LiteralPath $cleanupPath)
                $distRoot = ([System.IO.Path]::GetFullPath((Join-Path $ProjectRoot 'dist'))).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
                $resolvedFullPath = [System.IO.Path]::GetFullPath($resolvedPath)
                if (-not $resolvedFullPath.StartsWith($distRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw ('Refusing to remove package test output outside dist: {0}' -f $resolvedPath)
                }

                Remove-Item -LiteralPath $resolvedPath -Force
            }
        }
    }

    It 'creates a release ZIP and SHA-256 checksum with only intended files' {
        $packageScript = Join-Path $ProjectRoot 'tools\New-ReleasePackage.ps1'
        Test-Path -LiteralPath $packageScript | Should Be $true

        $result = & $packageScript -Version 'test.1' -OutputDirectory $script:PackageTestRoot
        $zipPath = Join-Path $script:PackageTestRoot 'DupliView-test.1.zip'
        $checksumPath = Join-Path $script:PackageTestRoot 'DupliView-test.1.zip.sha256'

        Test-Path -LiteralPath $zipPath | Should Be $true
        Test-Path -LiteralPath $checksumPath | Should Be $true
        $result.Package | Should Be $zipPath
        $result.Checksum | Should Be $checksumPath

        $checksum = [System.IO.File]::ReadAllText($checksumPath).Trim()
        $checksum | Should Match '^[a-f0-9]{64}  DupliView-test\.1\.zip$'

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $entries = @($archive.Entries | ForEach-Object { $_.FullName.Replace('/', '\') })

            ($entries -contains 'START HERE.txt') | Should Be $true
            ($entries -contains 'Run DupliView.cmd') | Should Be $true
            ($entries -contains 'DupliView.ps1') | Should Be $true
            ($entries -contains 'CONTRIBUTING.md') | Should Be $true
            ($entries -contains 'tools\New-ReleasePackage.ps1') | Should Be $true
            ($entries -contains 'src\DupliView.Core.ps1') | Should Be $true
            ($entries -contains 'tests\DupliView.Tests.ps1') | Should Be $true
            ($entries -contains 'docs\developer_docs\CHECKSUM_VERIFICATION.md') | Should Be $true
            ($entries -contains 'docs\developer_docs\RELEASE_PROCESS.md') | Should Be $true
            ($entries -contains 'docs\images\dupliview-main-window.png') | Should Be $true
            ($entries -contains 'docs\images\dupliview-completed-scan.png') | Should Be $true
            ($entries -contains 'Reports\.gitkeep') | Should Be $true

            @($entries | Where-Object { $_ -like '.git\*' }).Count | Should Be 0
            @($entries | Where-Object { $_ -like 'dist\*' }).Count | Should Be 0
            @($entries | Where-Object { $_ -like 'Reports\*.csv' }).Count | Should Be 0
            @($entries | Where-Object { $_ -like 'Reports\*.log' }).Count | Should Be 0
            @($entries | Where-Object { $_ -like 'Reports\*.tmp' }).Count | Should Be 0
        }
        finally {
            $archive.Dispose()
        }
    }

    It 'does not overwrite an existing release package unless Force is used' {
        $packageScript = Join-Path $ProjectRoot 'tools\New-ReleasePackage.ps1'

        & $packageScript -Version 'test.2' -OutputDirectory $script:PackageTestRoot | Out-Null
        { & $packageScript -Version 'test.2' -OutputDirectory $script:PackageTestRoot } | Should Throw 'already exists'

        & $packageScript -Version 'test.2' -OutputDirectory $script:PackageTestRoot -Force | Out-Null
        Test-Path -LiteralPath (Join-Path $script:PackageTestRoot 'DupliView-test.2.zip') | Should Be $true
    }

    It 'uses the repository dist folder when no output directory is provided' {
        $packageScript = Join-Path $ProjectRoot 'tools\New-ReleasePackage.ps1'
        $zipPath = Join-Path $ProjectRoot 'dist\DupliView-test.default.zip'
        $checksumPath = Join-Path $ProjectRoot 'dist\DupliView-test.default.zip.sha256'
        $script:PackageDistCleanupPaths = @($zipPath, $checksumPath)

        $result = & $packageScript -Version 'test.default' -Force

        Test-Path -LiteralPath $zipPath | Should Be $true
        Test-Path -LiteralPath $checksumPath | Should Be $true
        $result.Package | Should Be $zipPath
        $result.Checksum | Should Be $checksumPath
    }
}

Describe 'DupliView GitHub Actions CI' {
    It 'runs the Pester suite on Windows' {
        $workflowPath = Join-Path $ProjectRoot '.github\workflows\tests.yml'
        Test-Path -LiteralPath $workflowPath | Should Be $true

        $workflow = [System.IO.File]::ReadAllText($workflowPath)
        $workflow | Should Match 'windows-latest'
        $workflow | Should Match 'actions/checkout@v4'
        $workflow | Should Match 'shell: powershell'
        $workflow | Should Match 'Install-Module Pester -RequiredVersion 4\.10\.1'
        $workflow | Should Match 'Import-Module Pester -RequiredVersion 4\.10\.1'
        $workflow | Should Match 'Invoke-Pester -Script \.\\tests\\DupliView\.Tests\.ps1 -EnableExit'
    }
}

Describe 'DupliView production script safety scan' {
    It 'does not invoke dangerous commands from production scripts' {
        $productionPowerShellScripts = @(
            (Join-Path $ProjectRoot 'DupliView.ps1'),
            (Join-Path $ProjectRoot 'src\DupliView.Core.ps1')
        )

        foreach ($scriptPath in $productionPowerShellScripts) {
            Test-Path -LiteralPath $scriptPath | Should Be $true
        }

        $productionLaunchers = @(
            (Join-Path $ProjectRoot 'Run DupliView.cmd'),
            (Join-Path $ProjectRoot 'Run DupliView.bat')
        )

        foreach ($launcherPath in $productionLaunchers) {
            Test-Path -LiteralPath $launcherPath | Should Be $true
        }

        $forbiddenCommands = @(
            'Remove-Item',
            'Move-Item',
            'Rename-Item',
            'Clear-Content',
            'Set-Content',
            'Invoke-WebRequest',
            'Invoke-RestMethod',
            'Start-BitsTransfer',
            'New-Service',
            'New-ScheduledTask',
            'Register-ScheduledTask',
            'Start-Process',
            'Set-ItemProperty',
            'New-ItemProperty',
            'Invoke-Item',
            'reg.exe',
            'schtasks.exe',
            'explorer.exe',
            'curl',
            'wget',
            'iwr',
            'irm',
            'del',
            'erase',
            'rmdir',
            'rm'
        )

        $forbiddenTextPatterns = @(
            '\[System\.IO\.File\]::Delete',
            '\[System\.IO\.File\]::Move',
            '\[System\.IO\.Directory\]::Delete',
            '\[System\.IO\.Directory\]::Move',
            '\.Delete\(',
            '\.MoveTo\('
        )

        foreach ($scriptPath in $productionPowerShellScripts) {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref] $tokens, [ref] $parseErrors) | Out-Null
            $parseErrors.Count | Should Be 0

            $commandTokens = @($tokens | Where-Object { $_.Kind -eq 'Generic' -or $_.Kind -eq 'Identifier' } | Select-Object -ExpandProperty Text)
            foreach ($forbiddenCommand in $forbiddenCommands) {
                ($commandTokens -contains $forbiddenCommand) | Should Be $false
            }

            $content = [System.IO.File]::ReadAllText($scriptPath)
            foreach ($forbiddenPattern in $forbiddenTextPatterns) {
                ($content -match $forbiddenPattern) | Should Be $false
            }
        }

        foreach ($launcherPath in $productionLaunchers) {
            $content = [System.IO.File]::ReadAllText($launcherPath)
            foreach ($forbiddenCommand in $forbiddenCommands) {
                ($content -match ('(?i)(^|[^\w.-]){0}([^\w.-]|$)' -f [regex]::Escape($forbiddenCommand))) | Should Be $false
            }
        }
    }
}
