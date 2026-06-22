param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string] $Version,

    [string] $OutputDirectory,

    [switch] $Force
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot 'dist'
}

$packageName = 'DupliView-{0}' -f $Version
$zipPath = Join-Path $OutputDirectory ('{0}.zip' -f $packageName)
$checksumPath = Join-Path $OutputDirectory ('{0}.zip.sha256' -f $packageName)
$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('dupliview-release-' + [guid]::NewGuid().ToString('N'))

$requiredFiles = @(
    'DupliView.ps1',
    'Run DupliView.cmd',
    'Run DupliView.bat',
    'START HERE.txt',
    'README.md',
    'LICENSE',
    'CHANGELOG.md',
    'SECURITY.md',
    'CONTRIBUTING.md',
    'tools\New-ReleasePackage.ps1',
    'src\DupliView.Core.ps1',
    'tests\DupliView.Tests.ps1',
    'docs\README.md',
    'docs\developer_docs\CHECKSUM_VERIFICATION.md',
    'docs\developer_docs\RELEASE_CHECKLIST.md',
    'docs\developer_docs\RELEASE_PROCESS.md',
    'docs\SCREENSHOTS.md',
    'docs\guides\first-scan.md',
    'docs\guides\network-drive-scan.md',
    'docs\guides\read-the-csv.md',
    'docs\guides\share-with-coworkers.md',
    'docs\guides\skipped-files-and-errors.md',
    'docs\guides\troubleshooting.md',
    'docs\images\.gitkeep',
    'docs\images\dupliview-main-window.png',
    'docs\images\dupliview-completed-scan.png',
    'Reports\.gitkeep'
)

function Copy-DupliViewReleaseFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $RelativePath
    )

    $sourcePath = Join-Path $projectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw ('Required release file is missing: {0}' -f $RelativePath)
    }

    $destinationPath = Join-Path $stagingRoot $RelativePath
    $destinationFolder = Split-Path -Parent $destinationPath
    if (-not (Test-Path -LiteralPath $destinationFolder -PathType Container)) {
        [void] (New-Item -ItemType Directory -Path $destinationFolder -Force)
    }

    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
}

try {
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        [void] (New-Item -ItemType Directory -Path $OutputDirectory -Force)
    }

    if ((Test-Path -LiteralPath $zipPath) -or (Test-Path -LiteralPath $checksumPath)) {
        if (-not $Force) {
            throw ('Release package already exists for version {0}. Use -Force to replace it.' -f $Version)
        }

        Remove-Item -LiteralPath $zipPath, $checksumPath -Force -ErrorAction SilentlyContinue
    }

    [void] (New-Item -ItemType Directory -Path $stagingRoot -Force)

    foreach ($relativePath in $requiredFiles) {
        Copy-DupliViewReleaseFile -RelativePath $relativePath
    }

    Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $zipPath -Force

    $hash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
    Set-Content -LiteralPath $checksumPath -Value ('{0}  {1}' -f $hash.Hash.ToLowerInvariant(), (Split-Path -Leaf $zipPath)) -Encoding ASCII

    [pscustomobject] @{
        Package = $zipPath
        Checksum = $checksumPath
        FileCount = $requiredFiles.Count
    }
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}
