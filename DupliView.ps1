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

function New-DupliViewSize {
    param([int] $Width, [int] $Height)
    return New-Object System.Drawing.Size -ArgumentList $Width, $Height
}

function New-DupliViewPoint {
    param([int] $X, [int] $Y)
    return New-Object System.Drawing.Point -ArgumentList $X, $Y
}

function New-DupliViewPadding {
    param(
        [int] $Left,
        [int] $Top,
        [int] $Right,
        [int] $Bottom
    )

    return New-Object System.Windows.Forms.Padding -ArgumentList $Left, $Top, $Right, $Bottom
}

function New-DupliViewFont {
    param(
        [float] $Size,
        [System.Drawing.FontStyle] $Style = [System.Drawing.FontStyle]::Regular
    )

    return New-Object System.Drawing.Font -ArgumentList @('Segoe UI', $Size, $Style)
}

function Add-DupliViewRowStyle {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.TableLayoutPanel] $Layout,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.SizeType] $SizeType,

        [float] $Height = 0
    )

    $style = New-Object System.Windows.Forms.RowStyle
    $style.SizeType = $SizeType
    $style.Height = $Height
    [void] $Layout.RowStyles.Add($style)
}

function Add-DupliViewColumnStyle {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.TableLayoutPanel] $Layout,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.SizeType] $SizeType,

        [float] $Width = 0
    )

    $style = New-Object System.Windows.Forms.ColumnStyle
    $style.SizeType = $SizeType
    $style.Width = $Width
    [void] $Layout.ColumnStyles.Add($style)
}

function New-DupliViewGroupBox {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text
    )

    $groupBox = New-Object System.Windows.Forms.GroupBox
    $groupBox.Text = $Text
    $groupBox.Dock = 'Fill'
    $groupBox.Padding = New-DupliViewPadding 12 16 12 12
    $groupBox.Font = New-DupliViewFont 9 ([System.Drawing.FontStyle]::Regular)
    return $groupBox
}

function New-DupliViewButton {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,

        [int] $Width = 112,

        [switch] $Primary
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Width = $Width
    $button.Height = 32
    $button.Margin = New-DupliViewPadding 0 0 8 0
    $button.Font = New-DupliViewFont 9

    if ($Primary) {
        $button.UseVisualStyleBackColor = $false
        $button.BackColor = [System.Drawing.Color]::FromArgb(15, 108, 189)
        $button.ForeColor = [System.Drawing.Color]::White
        $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $button.FlatAppearance.BorderSize = 0
    }

    return $button
}

function New-DupliViewStatusLabel {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,

        [switch] $Value
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Dock = 'Fill'
    $label.AutoEllipsis = $true
    $label.TextAlign = 'MiddleLeft'
    $label.Margin = New-DupliViewPadding 0 2 8 2

    if ($Value) {
        $label.Font = New-DupliViewFont 10 ([System.Drawing.FontStyle]::Bold)
    }
    else {
        $label.ForeColor = [System.Drawing.Color]::FromArgb(88, 88, 88)
    }

    return $label
}

function New-DupliViewProgressMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Kind,

        [string] $Message,

        [string] $Phase
    )

    return [pscustomobject] @{
        Kind = $Kind
        Message = $Message
        Phase = $Phase
    }
}

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
    $dialog.ClientSize = New-DupliViewSize 540 150
    $dialog.Font = New-DupliViewFont 9

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'
    $layout.Padding = New-DupliViewPadding 14 12 14 12
    $layout.RowCount = 3
    $layout.ColumnCount = 1
    Add-DupliViewRowStyle -Layout $layout -SizeType ([System.Windows.Forms.SizeType]::Absolute) -Height 26
    Add-DupliViewRowStyle -Layout $layout -SizeType ([System.Windows.Forms.SizeType]::Absolute) -Height 34
    Add-DupliViewRowStyle -Layout $layout -SizeType ([System.Windows.Forms.SizeType]::Percent) -Height 100
    [void] $dialog.Controls.Add($layout)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = 'Enter a folder, drive, or network path:'
    $label.Dock = 'Fill'
    $label.TextAlign = 'MiddleLeft'
    [void] $layout.Controls.Add($label, 0, 0)

    $pathTextBox = New-Object System.Windows.Forms.TextBox
    $pathTextBox.Dock = 'Fill'
    [void] $layout.Controls.Add($pathTextBox, 0, 1)

    $buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonPanel.Dock = 'Fill'
    $buttonPanel.FlowDirection = 'RightToLeft'
    $buttonPanel.Padding = New-DupliViewPadding 0 12 0 0
    [void] $layout.Controls.Add($buttonPanel, 0, 2)

    $cancelButton = New-DupliViewButton -Text 'Cancel' -Width 86
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    [void] $buttonPanel.Controls.Add($cancelButton)

    $okButton = New-DupliViewButton -Text 'OK' -Width 86 -Primary
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    [void] $buttonPanel.Controls.Add($okButton)

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

function Set-DupliViewScanControlsEnabled {
    param(
        [bool] $Enabled
    )

    $addFolderButton.Enabled = $Enabled
    $addManualPathButton.Enabled = $Enabled
    $removeSelectedButton.Enabled = $Enabled
    $clearAllButton.Enabled = $Enabled
    $chooseExportButton.Enabled = $Enabled
    $minimumSizeControl.Enabled = $Enabled
    $skipEmptyFilesCheckBox.Enabled = $Enabled
    $createErrorCsvCheckBox.Enabled = $Enabled
    $startScanButton.Enabled = $Enabled
    $copyReportPathButton.Enabled = $Enabled -and -not [string]::IsNullOrWhiteSpace($reportPathTextBox.Text)
    $closeButton.Enabled = $Enabled
}

function Set-DupliViewPhase {
    param([string] $Phase)

    $phaseValueLabel.Text = $Phase
}

function Reset-DupliViewStatus {
    $phaseValueLabel.Text = 'Ready'
    $readableValueLabel.Text = '0'
    $skippedValueLabel.Text = '0'
    $duplicatesValueLabel.Text = '0'
    $reportPathTextBox.Text = ''
    $copyReportPathButton.Enabled = $false
}

function Complete-DupliViewStatus {
    param(
        [Parameter(Mandatory = $true)]
        $WorkerResult
    )

    $scanResult = $WorkerResult.ScanResult
    $skippedCount = $scanResult.SkippedUnreadableItemCount + $scanResult.SkippedEmptyFileCount + $scanResult.SkippedMinimumSizeFileCount
    $phaseValueLabel.Text = 'Done'
    $readableValueLabel.Text = ('{0:N0}' -f $scanResult.CandidateFileCount)
    $skippedValueLabel.Text = ('{0:N0}' -f $skippedCount)
    $duplicatesValueLabel.Text = ('{0:N0}' -f $scanResult.DuplicateGroupCount)
    $reportPathTextBox.Text = $WorkerResult.ReportPath
    $copyReportPathButton.Enabled = -not [string]::IsNullOrWhiteSpace($WorkerResult.ReportPath)
}

$defaultReportFolder = Join-Path $ScriptRoot $DefaultReportFolderName
if (-not (Test-Path -LiteralPath $defaultReportFolder -PathType Container)) {
    [void] (New-Item -ItemType Directory -Path $defaultReportFolder -Force)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'DupliView'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-DupliViewSize 960 720
$form.MinimumSize = New-DupliViewSize 860 660
$form.Font = New-DupliViewFont 9
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
$script:DupliViewScanRunning = $false

$mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
$mainLayout.Dock = 'Fill'
$mainLayout.Padding = New-DupliViewPadding 18 16 18 16
$mainLayout.RowCount = 6
$mainLayout.ColumnCount = 1
Add-DupliViewRowStyle -Layout $mainLayout -SizeType ([System.Windows.Forms.SizeType]::Absolute) -Height 86
Add-DupliViewRowStyle -Layout $mainLayout -SizeType ([System.Windows.Forms.SizeType]::Absolute) -Height 188
Add-DupliViewRowStyle -Layout $mainLayout -SizeType ([System.Windows.Forms.SizeType]::Absolute) -Height 104
Add-DupliViewRowStyle -Layout $mainLayout -SizeType ([System.Windows.Forms.SizeType]::Absolute) -Height 118
Add-DupliViewRowStyle -Layout $mainLayout -SizeType ([System.Windows.Forms.SizeType]::Percent) -Height 100
Add-DupliViewRowStyle -Layout $mainLayout -SizeType ([System.Windows.Forms.SizeType]::Absolute) -Height 48
[void] $form.Controls.Add($mainLayout)

$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock = 'Fill'
$headerPanel.Padding = New-DupliViewPadding 2 0 2 8
[void] $mainLayout.Controls.Add($headerPanel, 0, 0)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'DupliView'
$titleLabel.Font = New-DupliViewFont 22 ([System.Drawing.FontStyle]::Bold)
$titleLabel.Location = New-DupliViewPoint 0 0
$titleLabel.Size = New-DupliViewSize 500 38
$titleLabel.Anchor = 'Top,Left,Right'
[void] $headerPanel.Controls.Add($titleLabel)

$taglineLabel = New-Object System.Windows.Forms.Label
$taglineLabel.Text = 'A safe, no-install Windows duplicate-file report tool.'
$taglineLabel.Font = New-DupliViewFont 9
$taglineLabel.ForeColor = [System.Drawing.Color]::FromArgb(74, 74, 74)
$taglineLabel.Location = New-DupliViewPoint 2 38
$taglineLabel.Size = New-DupliViewSize 620 20
[void] $headerPanel.Controls.Add($taglineLabel)

$safetyLabel = New-Object System.Windows.Forms.Label
$safetyLabel.Text = 'Report-only: DupliView never deletes, moves, renames, or modifies scanned files.'
$safetyLabel.BackColor = [System.Drawing.Color]::FromArgb(232, 244, 253)
$safetyLabel.ForeColor = [System.Drawing.Color]::FromArgb(32, 82, 119)
$safetyLabel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$safetyLabel.Location = New-DupliViewPoint 0 62
$safetyLabel.Size = New-DupliViewSize 900 22
$safetyLabel.Anchor = 'Left,Right,Bottom'
$safetyLabel.TextAlign = 'MiddleLeft'
$safetyLabel.Padding = New-DupliViewPadding 8 0 8 0
[void] $headerPanel.Controls.Add($safetyLabel)

$locationsGroup = New-DupliViewGroupBox -Text 'Scan locations'
[void] $mainLayout.Controls.Add($locationsGroup, 0, 1)

$locationsLayout = New-Object System.Windows.Forms.TableLayoutPanel
$locationsLayout.Dock = 'Fill'
$locationsLayout.RowCount = 2
$locationsLayout.ColumnCount = 1
Add-DupliViewRowStyle -Layout $locationsLayout -SizeType ([System.Windows.Forms.SizeType]::Percent) -Height 100
Add-DupliViewRowStyle -Layout $locationsLayout -SizeType ([System.Windows.Forms.SizeType]::Absolute) -Height 38
[void] $locationsGroup.Controls.Add($locationsLayout)

$locationsList = New-Object System.Windows.Forms.ListBox
$locationsList.Dock = 'Fill'
$locationsList.HorizontalScrollbar = $true
$locationsList.SelectionMode = 'MultiExtended'
$locationsList.IntegralHeight = $false
$locationsList.BackColor = [System.Drawing.Color]::White
[void] $locationsLayout.Controls.Add($locationsList, 0, 0)

$locationsButtonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$locationsButtonPanel.Dock = 'Fill'
$locationsButtonPanel.FlowDirection = 'LeftToRight'
$locationsButtonPanel.WrapContents = $false
$locationsButtonPanel.Padding = New-DupliViewPadding 0 8 0 0
[void] $locationsLayout.Controls.Add($locationsButtonPanel, 0, 1)

$addFolderButton = New-DupliViewButton -Text 'Add Folder' -Width 112
$addManualPathButton = New-DupliViewButton -Text 'Add Manual Path' -Width 132
$removeSelectedButton = New-DupliViewButton -Text 'Remove Selected' -Width 132
$clearAllButton = New-DupliViewButton -Text 'Clear All' -Width 92
[void] $locationsButtonPanel.Controls.Add($addFolderButton)
[void] $locationsButtonPanel.Controls.Add($addManualPathButton)
[void] $locationsButtonPanel.Controls.Add($removeSelectedButton)
[void] $locationsButtonPanel.Controls.Add($clearAllButton)

$middleLayout = New-Object System.Windows.Forms.TableLayoutPanel
$middleLayout.Dock = 'Fill'
$middleLayout.ColumnCount = 2
$middleLayout.RowCount = 1
Add-DupliViewColumnStyle -Layout $middleLayout -SizeType ([System.Windows.Forms.SizeType]::Percent) -Width 62
Add-DupliViewColumnStyle -Layout $middleLayout -SizeType ([System.Windows.Forms.SizeType]::Percent) -Width 38
[void] $mainLayout.Controls.Add($middleLayout, 0, 2)

$destinationGroup = New-DupliViewGroupBox -Text 'Report destination'
$destinationGroup.Margin = New-DupliViewPadding 0 3 8 3
[void] $middleLayout.Controls.Add($destinationGroup, 0, 0)

$destinationLayout = New-Object System.Windows.Forms.TableLayoutPanel
$destinationLayout.Dock = 'Fill'
$destinationLayout.ColumnCount = 2
$destinationLayout.RowCount = 1
Add-DupliViewColumnStyle -Layout $destinationLayout -SizeType ([System.Windows.Forms.SizeType]::Percent) -Width 100
Add-DupliViewColumnStyle -Layout $destinationLayout -SizeType ([System.Windows.Forms.SizeType]::Absolute) -Width 150
[void] $destinationGroup.Controls.Add($destinationLayout)

$exportFolderTextBox = New-Object System.Windows.Forms.TextBox
$exportFolderTextBox.Dock = 'Fill'
$exportFolderTextBox.ReadOnly = $true
$exportFolderTextBox.Text = $defaultReportFolder
$exportFolderTextBox.Margin = New-DupliViewPadding 0 8 8 0
[void] $destinationLayout.Controls.Add($exportFolderTextBox, 0, 0)

$chooseExportButton = New-DupliViewButton -Text 'Choose Folder' -Width 132
$chooseExportButton.Margin = New-DupliViewPadding 0 6 0 0
[void] $destinationLayout.Controls.Add($chooseExportButton, 1, 0)

$optionsGroup = New-DupliViewGroupBox -Text 'Scan options'
$optionsGroup.Margin = New-DupliViewPadding 8 3 0 3
[void] $middleLayout.Controls.Add($optionsGroup, 1, 0)

$optionsLayout = New-Object System.Windows.Forms.TableLayoutPanel
$optionsLayout.Dock = 'Fill'
$optionsLayout.ColumnCount = 2
$optionsLayout.RowCount = 2
Add-DupliViewColumnStyle -Layout $optionsLayout -SizeType ([System.Windows.Forms.SizeType]::Absolute) -Width 150
Add-DupliViewColumnStyle -Layout $optionsLayout -SizeType ([System.Windows.Forms.SizeType]::Percent) -Width 100
Add-DupliViewRowStyle -Layout $optionsLayout -SizeType ([System.Windows.Forms.SizeType]::Absolute) -Height 34
Add-DupliViewRowStyle -Layout $optionsLayout -SizeType ([System.Windows.Forms.SizeType]::Percent) -Height 100
[void] $optionsGroup.Controls.Add($optionsLayout)

$minimumSizeLabel = New-Object System.Windows.Forms.Label
$minimumSizeLabel.Text = 'Minimum size (MB)'
$minimumSizeLabel.Dock = 'Fill'
$minimumSizeLabel.TextAlign = 'MiddleLeft'
[void] $optionsLayout.Controls.Add($minimumSizeLabel, 0, 0)

$minimumSizeControl = New-Object System.Windows.Forms.NumericUpDown
$minimumSizeControl.DecimalPlaces = 2
$minimumSizeControl.Minimum = 0
$minimumSizeControl.Maximum = 1048576
$minimumSizeControl.Increment = 1
$minimumSizeControl.Value = [decimal] $MinimumSizeMB
$minimumSizeControl.Width = 76
$minimumSizeControl.Anchor = 'Left'
$minimumSizeControl.Margin = New-DupliViewPadding 0 6 10 0
[void] $optionsLayout.Controls.Add($minimumSizeControl, 1, 0)

$skipEmptyFilesCheckBox = New-Object System.Windows.Forms.CheckBox
$skipEmptyFilesCheckBox.Text = 'Skip empty files'
$skipEmptyFilesCheckBox.Checked = $SkipEmptyFiles
$skipEmptyFilesCheckBox.Dock = 'Fill'
$skipEmptyFilesCheckBox.AutoSize = $true
$skipEmptyFilesCheckBox.Margin = New-DupliViewPadding 0 8 8 0
[void] $optionsLayout.Controls.Add($skipEmptyFilesCheckBox, 0, 1)

$createErrorCsvCheckBox = New-Object System.Windows.Forms.CheckBox
$createErrorCsvCheckBox.Text = 'Create error CSV'
$createErrorCsvCheckBox.Checked = $CreateErrorLog
$createErrorCsvCheckBox.Dock = 'Fill'
$createErrorCsvCheckBox.AutoSize = $true
$createErrorCsvCheckBox.Margin = New-DupliViewPadding 0 8 0 0
[void] $optionsLayout.Controls.Add($createErrorCsvCheckBox, 1, 1)

$statusGroup = New-DupliViewGroupBox -Text 'Scan status'
[void] $mainLayout.Controls.Add($statusGroup, 0, 3)

$statusLayout = New-Object System.Windows.Forms.TableLayoutPanel
$statusLayout.Dock = 'Fill'
$statusLayout.RowCount = 3
$statusLayout.ColumnCount = 8
Add-DupliViewRowStyle -Layout $statusLayout -SizeType ([System.Windows.Forms.SizeType]::Absolute) -Height 28
Add-DupliViewRowStyle -Layout $statusLayout -SizeType ([System.Windows.Forms.SizeType]::Absolute) -Height 32
Add-DupliViewRowStyle -Layout $statusLayout -SizeType ([System.Windows.Forms.SizeType]::Percent) -Height 100
for ($columnIndex = 0; $columnIndex -lt 8; $columnIndex++) {
    Add-DupliViewColumnStyle -Layout $statusLayout -SizeType ([System.Windows.Forms.SizeType]::Percent) -Width 12.5
}
[void] $statusGroup.Controls.Add($statusLayout)

[void] $statusLayout.Controls.Add((New-DupliViewStatusLabel -Text 'Phase'), 0, 0)
$phaseValueLabel = New-DupliViewStatusLabel -Text 'Ready' -Value
[void] $statusLayout.Controls.Add($phaseValueLabel, 1, 0)

[void] $statusLayout.Controls.Add((New-DupliViewStatusLabel -Text 'Readable files'), 2, 0)
$readableValueLabel = New-DupliViewStatusLabel -Text '0' -Value
[void] $statusLayout.Controls.Add($readableValueLabel, 3, 0)

[void] $statusLayout.Controls.Add((New-DupliViewStatusLabel -Text 'Skipped'), 4, 0)
$skippedValueLabel = New-DupliViewStatusLabel -Text '0' -Value
[void] $statusLayout.Controls.Add($skippedValueLabel, 5, 0)

[void] $statusLayout.Controls.Add((New-DupliViewStatusLabel -Text 'Duplicate groups'), 6, 0)
$duplicatesValueLabel = New-DupliViewStatusLabel -Text '0' -Value
[void] $statusLayout.Controls.Add($duplicatesValueLabel, 7, 0)

$reportPathLabel = New-DupliViewStatusLabel -Text 'Final report path'
[void] $statusLayout.Controls.Add($reportPathLabel, 0, 1)
$statusLayout.SetColumnSpan($reportPathLabel, 2)

$reportPathTextBox = New-Object System.Windows.Forms.TextBox
$reportPathTextBox.Dock = 'Fill'
$reportPathTextBox.ReadOnly = $true
$reportPathTextBox.Margin = New-DupliViewPadding 0 4 8 0
[void] $statusLayout.Controls.Add($reportPathTextBox, 2, 1)
$statusLayout.SetColumnSpan($reportPathTextBox, 4)

$copyReportPathButton = New-DupliViewButton -Text 'Copy Report Path' -Width 140
$copyReportPathButton.Enabled = $false
$copyReportPathButton.Margin = New-DupliViewPadding 0 2 0 0
[void] $statusLayout.Controls.Add($copyReportPathButton, 6, 1)
$statusLayout.SetColumnSpan($copyReportPathButton, 2)

$logGroup = New-DupliViewGroupBox -Text 'Live log'
$logGroup.Margin = New-DupliViewPadding 0 4 0 6
[void] $mainLayout.Controls.Add($logGroup, 0, 4)

$logTextBox = New-Object System.Windows.Forms.TextBox
$logTextBox.Dock = 'Fill'
$logTextBox.Multiline = $true
$logTextBox.ScrollBars = 'Vertical'
$logTextBox.ReadOnly = $true
$logTextBox.BackColor = [System.Drawing.Color]::White
$logTextBox.Font = New-Object System.Drawing.Font -ArgumentList @('Consolas', 9, [System.Drawing.FontStyle]::Regular)
[void] $logGroup.Controls.Add($logTextBox)

$actionPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$actionPanel.Dock = 'Fill'
$actionPanel.FlowDirection = 'RightToLeft'
$actionPanel.WrapContents = $false
$actionPanel.Padding = New-DupliViewPadding 0 7 0 0
[void] $mainLayout.Controls.Add($actionPanel, 0, 5)

$closeButton = New-DupliViewButton -Text 'Close' -Width 92
$startScanButton = New-DupliViewButton -Text 'Start Scan' -Width 132 -Primary
[void] $actionPanel.Controls.Add($closeButton)
[void] $actionPanel.Controls.Add($startScanButton)

$scanWorker = New-Object System.ComponentModel.BackgroundWorker
$scanWorker.WorkerReportsProgress = $true

$scanWorker.Add_DoWork({
    param($Sender, $EventArgs)

    $arguments = $EventArgs.Argument
    $worker = $Sender

    try {
        $worker.ReportProgress(0, (New-DupliViewProgressMessage -Kind 'Phase' -Phase 'Preparing'))
        $worker.ReportProgress(0, (New-DupliViewProgressMessage -Kind 'Log' -Message 'Step 1: Preparing scan...'))

        $minimumSizeBytes = Convert-DupliViewMinimumSizeToBytes -MinimumSizeMB $arguments.MinimumSizeMB

        $scanResult = Get-DupliViewDuplicateRecords `
            -ScanLocations $arguments.ScanLocations `
            -MinimumSizeBytes $minimumSizeBytes `
            -SkipEmptyFiles $arguments.SkipEmptyFiles `
            -HashAlgorithm $arguments.HashAlgorithm `
            -ProgressCallback {
                param($Message)
                $phase = $null

                if ($Message -like 'Step 2:*') { $phase = 'Collecting files' }
                elseif ($Message -like 'Step 3:*') { $phase = 'Grouping by size' }
                elseif ($Message -like 'Step 4:*') { $phase = 'Hashing' }
                elseif ($Message -like 'Step 5:*') { $phase = 'Grouping by hash' }

                if ($phase) {
                    $worker.ReportProgress(0, (New-DupliViewProgressMessage -Kind 'Phase' -Phase $phase))
                }

                $worker.ReportProgress(0, (New-DupliViewProgressMessage -Kind 'Log' -Message $Message))
            }

        $worker.ReportProgress(0, (New-DupliViewProgressMessage -Kind 'Phase' -Phase 'Writing report'))
        $worker.ReportProgress(0, (New-DupliViewProgressMessage -Kind 'Log' -Message 'Step 6: Writing CSV report...'))

        $timestamp = Get-Date
        $reportFileName = New-DupliViewReportFileName -ScanLocations $arguments.ScanLocations -Timestamp $timestamp
        $reportPath = Export-DupliViewDuplicateReport -Records $scanResult.DuplicateRecords -ExportFolder $arguments.ExportFolder -FileName $reportFileName -CsvColumns $arguments.CsvColumns

        $errorReportPath = $null
        if ($arguments.CreateErrorLog -and $scanResult.ErrorRecords.Count -gt 0) {
            $errorFileName = New-DupliViewReportFileName -ScanLocations $arguments.ScanLocations -Timestamp $timestamp -ErrorReport
            $errorReportPath = Export-DupliViewErrorReport -ErrorRecords $scanResult.ErrorRecords -ExportFolder $arguments.ExportFolder -FileName $errorFileName
        }

        $EventArgs.Result = [pscustomobject] @{
            Success = $true
            ScanResult = $scanResult
            ReportPath = $reportPath
            ErrorReportPath = $errorReportPath
        }
    }
    catch {
        $EventArgs.Result = [pscustomobject] @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
})

$scanWorker.Add_ProgressChanged({
    param($Sender, $EventArgs)

    $message = $EventArgs.UserState
    if (-not $message) {
        return
    }

    if ($message.Kind -eq 'Phase') {
        Set-DupliViewPhase -Phase $message.Phase
    }
    elseif ($message.Kind -eq 'Log') {
        Add-DupliViewLogMessage -LogTextBox $logTextBox -Message $message.Message
    }
})

$scanWorker.Add_RunWorkerCompleted({
    param($Sender, $EventArgs)

    $script:DupliViewScanRunning = $false
    Set-DupliViewScanControlsEnabled -Enabled $true

    if ($EventArgs.Error) {
        $phaseValueLabel.Text = 'Stopped'
        Add-DupliViewLogMessage -LogTextBox $logTextBox -Message ('Scan stopped: {0}' -f $EventArgs.Error.Message)
        [void] [System.Windows.Forms.MessageBox]::Show($form, ('DupliView could not finish the scan:{0}{1}' -f [Environment]::NewLine, $EventArgs.Error.Message), 'DupliView', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $result = $EventArgs.Result
    if (-not $result.Success) {
        $phaseValueLabel.Text = 'Stopped'
        Add-DupliViewLogMessage -LogTextBox $logTextBox -Message ('Scan stopped: {0}' -f $result.Error)
        [void] [System.Windows.Forms.MessageBox]::Show($form, ('DupliView could not finish the scan:{0}{1}' -f [Environment]::NewLine, $result.Error), 'DupliView', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    Complete-DupliViewStatus -WorkerResult $result

    if ($result.ErrorReportPath) {
        Add-DupliViewLogMessage -LogTextBox $logTextBox -Message ('Error report saved to: {0}' -f $result.ErrorReportPath)
    }

    Add-DupliViewLogMessage -LogTextBox $logTextBox -Message 'Done.'
    Add-DupliViewLogMessage -LogTextBox $logTextBox -Message ('Report saved to: {0}' -f $result.ReportPath)
    [void] [System.Windows.Forms.MessageBox]::Show($form, ('Report saved to:{0}{1}' -f [Environment]::NewLine, $result.ReportPath), 'DupliView', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
})

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

$copyReportPathButton.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($reportPathTextBox.Text)) {
        [System.Windows.Forms.Clipboard]::SetText($reportPathTextBox.Text)
        Add-DupliViewLogMessage -LogTextBox $logTextBox -Message 'Report path copied.'
    }
})

$startScanButton.Add_Click({
    if ($scanWorker.IsBusy) {
        return
    }

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
    if (-not (Test-Path -LiteralPath $exportFolder -PathType Container)) {
        if ([string]::Equals($exportFolder, $defaultReportFolder, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void] (New-Item -ItemType Directory -Path $exportFolder -Force)
        }
        else {
            [void] [System.Windows.Forms.MessageBox]::Show($form, 'Export folder no longer exists. Choose an existing export folder and try again.', 'DupliView', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            return
        }
    }

    Reset-DupliViewStatus
    $logTextBox.Clear()
    $script:DupliViewScanRunning = $true
    Set-DupliViewScanControlsEnabled -Enabled $false

    $workerArguments = [pscustomobject] @{
        ScanLocations = $scanLocations
        ExportFolder = $exportFolder
        MinimumSizeMB = [double] $minimumSizeControl.Value
        SkipEmptyFiles = [bool] $skipEmptyFilesCheckBox.Checked
        CreateErrorLog = [bool] $createErrorCsvCheckBox.Checked
        HashAlgorithm = $HashAlgorithm
        CsvColumns = $CsvColumns
    }

    $scanWorker.RunWorkerAsync($workerArguments)
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

Reset-DupliViewStatus
[void] $form.ShowDialog()
