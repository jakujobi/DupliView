$ErrorActionPreference = 'Stop'

# DupliView
# A safe, no-install Windows duplicate-file report tool.
#
# Safety policy:
# This tool is report-only. It reads files to compute hashes and writes CSV
# reports to the selected export folder. It must not modify scanned files.

# ============================================================
# USER CONFIGURATION
# ============================================================

$MinimumSizeMB = 0
$SkipEmptyFiles = $true
$CreateErrorLog = $false
$DefaultReportFolderName = 'Reports'
$HashAlgorithm = 'SHA256'
$ReportOnlyMode = $true

$CsvColumns = @(
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

# ============================================================

if (-not $ReportOnlyMode) {
    throw 'DupliView must run in report-only mode.'
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$CoreScript = Join-Path $ScriptRoot 'src\DupliView.Core.ps1'
. $CoreScript

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Add-DupliViewLogMessage {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.TextBox] $LogTextBox,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    $LogTextBox.AppendText($line + [Environment]::NewLine)
    $LogTextBox.SelectionStart = $LogTextBox.TextLength
    $LogTextBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Add-DupliViewScanLocation {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.ListBox] $ListBox,

        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $cleanPath = $Path.Trim()

    foreach ($existingPath in $ListBox.Items) {
        if ([string]::Equals([string] $existingPath, $cleanPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }

    [void] $ListBox.Items.Add($cleanPath)
}

function Show-DupliViewManualPathDialog {
    param(
        [System.Windows.Forms.IWin32Window] $Owner
    )

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Add Manual Path'
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ClientSize = New-Object System.Drawing.Size(520, 145)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = 'Enter a folder, drive, or network path:'
    $label.Location = New-Object System.Drawing.Point(12, 15)
    $label.Size = New-Object System.Drawing.Size(490, 20)
    [void] $dialog.Controls.Add($label)

    $pathTextBox = New-Object System.Windows.Forms.TextBox
    $pathTextBox.Location = New-Object System.Drawing.Point(12, 42)
    $pathTextBox.Size = New-Object System.Drawing.Size(490, 24)
    $pathTextBox.Anchor = 'Top,Left,Right'
    [void] $dialog.Controls.Add($pathTextBox)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = 'OK'
    $okButton.Location = New-Object System.Drawing.Point(326, 94)
    $okButton.Size = New-Object System.Drawing.Size(80, 28)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    [void] $dialog.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = 'Cancel'
    $cancelButton.Location = New-Object System.Drawing.Point(422, 94)
    $cancelButton.Size = New-Object System.Drawing.Size(80, 28)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    [void] $dialog.Controls.Add($cancelButton)

    $dialog.AcceptButton = $okButton
    $dialog.CancelButton = $cancelButton

    $result = $dialog.ShowDialog($Owner)
    $manualPath = $pathTextBox.Text.Trim()
    $dialog.Dispose()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $manualPath
    }

    return $null
}

$defaultReportFolder = Join-Path $ScriptRoot $DefaultReportFolderName
if (-not (Test-Path -LiteralPath $defaultReportFolder -PathType Container)) {
    [void] (New-Item -ItemType Directory -Path $defaultReportFolder -Force)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'DupliView'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(800, 620)
$form.MinimumSize = New-Object System.Drawing.Size(720, 560)
$script:DupliViewScanRunning = $false

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'DupliView'
$titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
$titleLabel.Location = New-Object System.Drawing.Point(18, 14)
$titleLabel.Size = New-Object System.Drawing.Size(740, 36)
$titleLabel.Anchor = 'Top,Left,Right'
[void] $form.Controls.Add($titleLabel)

$safetyLabel = New-Object System.Windows.Forms.Label
$safetyLabel.Text = 'This tool is report-only. It never deletes, moves, renames, or modifies scanned files.'
$safetyLabel.Location = New-Object System.Drawing.Point(22, 54)
$safetyLabel.Size = New-Object System.Drawing.Size(740, 22)
$safetyLabel.Anchor = 'Top,Left,Right'
[void] $form.Controls.Add($safetyLabel)

$locationsLabel = New-Object System.Windows.Forms.Label
$locationsLabel.Text = 'Selected scan locations'
$locationsLabel.Location = New-Object System.Drawing.Point(22, 92)
$locationsLabel.Size = New-Object System.Drawing.Size(220, 20)
[void] $form.Controls.Add($locationsLabel)

$locationsList = New-Object System.Windows.Forms.ListBox
$locationsList.Location = New-Object System.Drawing.Point(22, 116)
$locationsList.Size = New-Object System.Drawing.Size(740, 120)
$locationsList.Anchor = 'Top,Left,Right'
$locationsList.HorizontalScrollbar = $true
$locationsList.SelectionMode = 'MultiExtended'
[void] $form.Controls.Add($locationsList)

$addFolderButton = New-Object System.Windows.Forms.Button
$addFolderButton.Text = 'Add Folder'
$addFolderButton.Location = New-Object System.Drawing.Point(22, 248)
$addFolderButton.Size = New-Object System.Drawing.Size(105, 30)
[void] $form.Controls.Add($addFolderButton)

$addManualPathButton = New-Object System.Windows.Forms.Button
$addManualPathButton.Text = 'Add Manual Path'
$addManualPathButton.Location = New-Object System.Drawing.Point(137, 248)
$addManualPathButton.Size = New-Object System.Drawing.Size(130, 30)
[void] $form.Controls.Add($addManualPathButton)

$removeSelectedButton = New-Object System.Windows.Forms.Button
$removeSelectedButton.Text = 'Remove Selected'
$removeSelectedButton.Location = New-Object System.Drawing.Point(277, 248)
$removeSelectedButton.Size = New-Object System.Drawing.Size(130, 30)
[void] $form.Controls.Add($removeSelectedButton)

$clearAllButton = New-Object System.Windows.Forms.Button
$clearAllButton.Text = 'Clear All'
$clearAllButton.Location = New-Object System.Drawing.Point(417, 248)
$clearAllButton.Size = New-Object System.Drawing.Size(95, 30)
[void] $form.Controls.Add($clearAllButton)

$exportLabel = New-Object System.Windows.Forms.Label
$exportLabel.Text = 'Export folder'
$exportLabel.Location = New-Object System.Drawing.Point(22, 300)
$exportLabel.Size = New-Object System.Drawing.Size(120, 20)
[void] $form.Controls.Add($exportLabel)

$exportFolderTextBox = New-Object System.Windows.Forms.TextBox
$exportFolderTextBox.Location = New-Object System.Drawing.Point(22, 324)
$exportFolderTextBox.Size = New-Object System.Drawing.Size(595, 24)
$exportFolderTextBox.Anchor = 'Top,Left,Right'
$exportFolderTextBox.ReadOnly = $true
$exportFolderTextBox.Text = $defaultReportFolder
[void] $form.Controls.Add($exportFolderTextBox)

$chooseExportButton = New-Object System.Windows.Forms.Button
$chooseExportButton.Text = 'Choose Export Folder'
$chooseExportButton.Location = New-Object System.Drawing.Point(630, 322)
$chooseExportButton.Size = New-Object System.Drawing.Size(132, 28)
$chooseExportButton.Anchor = 'Top,Right'
[void] $form.Controls.Add($chooseExportButton)

$startScanButton = New-Object System.Windows.Forms.Button
$startScanButton.Text = 'Start Scan'
$startScanButton.Location = New-Object System.Drawing.Point(22, 368)
$startScanButton.Size = New-Object System.Drawing.Size(105, 32)
[void] $form.Controls.Add($startScanButton)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = 'Close'
$closeButton.Location = New-Object System.Drawing.Point(137, 368)
$closeButton.Size = New-Object System.Drawing.Size(90, 32)
[void] $form.Controls.Add($closeButton)

$logTextBox = New-Object System.Windows.Forms.TextBox
$logTextBox.Location = New-Object System.Drawing.Point(22, 420)
$logTextBox.Size = New-Object System.Drawing.Size(740, 120)
$logTextBox.Anchor = 'Top,Bottom,Left,Right'
$logTextBox.Multiline = $true
$logTextBox.ScrollBars = 'Vertical'
$logTextBox.ReadOnly = $true
[void] $form.Controls.Add($logTextBox)

$addFolderButton.Add_Click({
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderDialog.Description = 'Choose a folder or drive to scan'
    $folderDialog.ShowNewFolderButton = $false

    if ($folderDialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        Add-DupliViewScanLocation -ListBox $locationsList -Path $folderDialog.SelectedPath
    }

    $folderDialog.Dispose()
})

$addManualPathButton.Add_Click({
    $manualPath = Show-DupliViewManualPathDialog -Owner $form

    if ([string]::IsNullOrWhiteSpace($manualPath)) {
        return
    }

    if (-not (Test-Path -LiteralPath $manualPath -PathType Container)) {
        [void] [System.Windows.Forms.MessageBox]::Show($form, 'That path does not exist or is not a folder.', 'DupliView', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    Add-DupliViewScanLocation -ListBox $locationsList -Path $manualPath
})

$removeSelectedButton.Add_Click({
    for ($index = $locationsList.SelectedIndices.Count - 1; $index -ge 0; $index--) {
        $locationsList.Items.RemoveAt($locationsList.SelectedIndices[$index])
    }
})

$clearAllButton.Add_Click({
    $locationsList.Items.Clear()
})

$chooseExportButton.Add_Click({
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderDialog.Description = 'Choose where DupliView should save CSV reports'
    $folderDialog.ShowNewFolderButton = $true
    $folderDialog.SelectedPath = $exportFolderTextBox.Text

    if ($folderDialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $exportFolderTextBox.Text = $folderDialog.SelectedPath
    }

    $folderDialog.Dispose()
})

$startScanButton.Add_Click({
    if ($locationsList.Items.Count -eq 0) {
        [void] [System.Windows.Forms.MessageBox]::Show($form, 'Add at least one folder, drive, or network path before starting a scan.', 'DupliView', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    $scanLocations = @()
    foreach ($location in $locationsList.Items) {
        $path = [string] $location
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            [void] [System.Windows.Forms.MessageBox]::Show($form, ('This scan location no longer exists: {0}' -f $path), 'DupliView', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            return
        }
        $scanLocations += $path
    }

    $exportFolder = $exportFolderTextBox.Text

    $startScanButton.Enabled = $false
    $addFolderButton.Enabled = $false
    $addManualPathButton.Enabled = $false
    $removeSelectedButton.Enabled = $false
    $clearAllButton.Enabled = $false
    $chooseExportButton.Enabled = $false
    $closeButton.Enabled = $false
    $script:DupliViewScanRunning = $true
    $logTextBox.Clear()

    try {
        Add-DupliViewLogMessage -LogTextBox $logTextBox -Message 'Step 1: Preparing scan...'

        if (-not (Test-Path -LiteralPath $exportFolder -PathType Container)) {
            if ([string]::Equals($exportFolder, $defaultReportFolder, [System.StringComparison]::OrdinalIgnoreCase)) {
                [void] (New-Item -ItemType Directory -Path $exportFolder -Force)
            }
            else {
                throw 'Export folder no longer exists. Choose an existing export folder and try again.'
            }
        }

        $minimumSizeBytes = Convert-DupliViewMinimumSizeToBytes -MinimumSizeMB $MinimumSizeMB
        $scanResult = Get-DupliViewDuplicateRecords `
            -ScanLocations $scanLocations `
            -MinimumSizeBytes $minimumSizeBytes `
            -SkipEmptyFiles $SkipEmptyFiles `
            -HashAlgorithm $HashAlgorithm `
            -ProgressCallback {
                param($Message)
                Add-DupliViewLogMessage -LogTextBox $logTextBox -Message $Message
            }

        Add-DupliViewLogMessage -LogTextBox $logTextBox -Message 'Step 6: Writing CSV report...'
        $timestamp = Get-Date
        $reportFileName = New-DupliViewReportFileName -ScanLocations $scanLocations -Timestamp $timestamp
        $reportPath = Export-DupliViewDuplicateReport -Records $scanResult.DuplicateRecords -ExportFolder $exportFolder -FileName $reportFileName -CsvColumns $CsvColumns

        if ($CreateErrorLog -and $scanResult.ErrorRecords.Count -gt 0) {
            $errorFileName = New-DupliViewReportFileName -ScanLocations $scanLocations -Timestamp $timestamp -ErrorReport
            $errorReportPath = Export-DupliViewErrorReport -ErrorRecords $scanResult.ErrorRecords -ExportFolder $exportFolder -FileName $errorFileName
            Add-DupliViewLogMessage -LogTextBox $logTextBox -Message ('Error report saved to: {0}' -f $errorReportPath)
        }

        Add-DupliViewLogMessage -LogTextBox $logTextBox -Message 'Done.'
        Add-DupliViewLogMessage -LogTextBox $logTextBox -Message ('Report saved to: {0}' -f $reportPath)

        [void] [System.Windows.Forms.MessageBox]::Show($form, ('Report saved to:{0}{1}' -f [Environment]::NewLine, $reportPath), 'DupliView', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
    catch {
        Add-DupliViewLogMessage -LogTextBox $logTextBox -Message ('Scan stopped: {0}' -f $_.Exception.Message)
        [void] [System.Windows.Forms.MessageBox]::Show($form, ('DupliView could not finish the scan:{0}{1}' -f [Environment]::NewLine, $_.Exception.Message), 'DupliView', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
    finally {
        $script:DupliViewScanRunning = $false
        $startScanButton.Enabled = $true
        $addFolderButton.Enabled = $true
        $addManualPathButton.Enabled = $true
        $removeSelectedButton.Enabled = $true
        $clearAllButton.Enabled = $true
        $chooseExportButton.Enabled = $true
        $closeButton.Enabled = $true
    }
})

$closeButton.Add_Click({
    $form.Close()
})

$form.Add_FormClosing({
    param($Sender, $EventArgs)

    if ($script:DupliViewScanRunning) {
        $EventArgs.Cancel = $true
        [void] [System.Windows.Forms.MessageBox]::Show($form, 'A scan is running. Wait for it to finish before closing DupliView.', 'DupliView', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})

[void] $form.ShowDialog()
