$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$CoreScript = Join-Path $ProjectRoot 'src\DupliView.Core.ps1'

if (Test-Path -LiteralPath $CoreScript) {
    . $CoreScript
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
    'SizeMB',
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

Describe 'DupliView production script safety scan' {
    It 'does not invoke dangerous commands from production scripts' {
        $productionScripts = @(
            (Join-Path $ProjectRoot 'DupliView.ps1'),
            (Join-Path $ProjectRoot 'src\DupliView.Core.ps1'),
            (Join-Path $ProjectRoot 'src\DupliView.Gui.ps1')
        ) | Where-Object { Test-Path -LiteralPath $_ }

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
            'reg.exe',
            'schtasks.exe',
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

        foreach ($scriptPath in $productionScripts) {
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
    }
}
