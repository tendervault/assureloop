# SPDX-License-Identifier: Apache-2.0

[CmdletBinding()]
param(
    [string] $Python = $(if ($env:PYTHON) { $env:PYTHON } else { "py" }),
    [string] $West = $(if ($env:WEST) { $env:WEST } else { "west" }),
    [string] $BuildDir = $(if ($env:BUILD_DIR) { $env:BUILD_DIR } else { "build" }),
    [string] $OutputDir = $(if ($env:FIRMWARE_RELEASE_DIR) { $env:FIRMWARE_RELEASE_DIR } else { "dist/firmware-release" }),
    [string] $Product = $(if ($env:ASSURELOOP_PRODUCT) { $env:ASSURELOOP_PRODUCT } else { "assureloop-controller-demo" }),
    [string] $Version = $(if ($env:ASSURELOOP_VERSION) { $env:ASSURELOOP_VERSION } else { "0.1.0-dev" }),
    [string] $Target = $(if ($env:ASSURELOOP_TARGET) { $env:ASSURELOOP_TARGET } else { "qemu_cortex_m3" }),
    [string] $BuildProfile = $(if ($env:ASSURELOOP_BUILD_PROFILE) { $env:ASSURELOOP_BUILD_PROFILE } else { "dev" }),
    [switch] $GenerateSbom
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$TrimChars = [char[]] @(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE"
    }
}

function Convert-ToManifestPath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $Full = [System.IO.Path]::GetFullPath($Path)
    $RepoFull = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd($TrimChars)
    $RepoPrefix = $RepoFull + [System.IO.Path]::DirectorySeparatorChar

    if ($Full.StartsWith($RepoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Full.Substring($RepoPrefix.Length).Replace("\", "/")
    }

    return $Full
}

function Find-SbomFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $Root -Recurse -File |
            Where-Object {
                $_.Name -like "*.spdx" -or
                $_.Name -like "*.spdx.*" -or
                $_.Name -like "*.sbom" -or
                $_.Name -like "*.sbom.*" -or
                $_.Name -like "*.cdx" -or
                $_.Name -like "*.cdx.*"
            } |
            Sort-Object FullName
    )
}

Push-Location -LiteralPath $RepoRoot
try {
    $BuildRoot = if ([System.IO.Path]::IsPathRooted($BuildDir)) {
        [System.IO.Path]::GetFullPath($BuildDir)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $BuildDir))
    }

    $BuildDirForWest = if ([System.IO.Path]::IsPathRooted($BuildDir)) {
        $BuildRoot
    }
    else {
        $BuildDir
    }

    $ZephyrBuild = Join-Path $BuildRoot "zephyr"
    if (-not (Test-Path -LiteralPath $ZephyrBuild -PathType Container)) {
        throw "Zephyr build directory not found: $ZephyrBuild. Run 'west build -b qemu_cortex_m3 firmware/app' first."
    }

    $ArtifactArgs = @()
    $BundleIncludeArgs = @()
    $FoundFirmwareImage = $false
    $Candidates = @(
        @{ Name = "zephyr.elf"; Kind = "firmware-elf"; Firmware = $true },
        @{ Name = "zephyr.bin"; Kind = "firmware-bin"; Firmware = $true },
        @{ Name = "zephyr.map"; Kind = "linker-map"; Firmware = $false },
        @{ Name = ".config"; Kind = "build-config"; Firmware = $false },
        @{ Name = "zephyr.dts"; Kind = "devicetree"; Firmware = $false }
    )

    foreach ($Candidate in $Candidates) {
        $ArtifactPath = Join-Path $ZephyrBuild $Candidate.Name
        if (Test-Path -LiteralPath $ArtifactPath -PathType Leaf) {
            $ManifestPath = Convert-ToManifestPath -Path $ArtifactPath
            $ArtifactArgs += @("--artifact", "$($ManifestPath):$($Candidate.Kind)")
            if ($Candidate.Firmware) {
                $FoundFirmwareImage = $true
            }
            Write-Host "including $ManifestPath as $($Candidate.Kind)"
        }
    }

    if ($ArtifactArgs.Count -eq 0) {
        throw "No Zephyr build artifacts found in $ZephyrBuild."
    }

    if (-not $FoundFirmwareImage) {
        throw "No firmware image artifact found in $ZephyrBuild; expected zephyr.elf or zephyr.bin."
    }

    if ($GenerateSbom) {
        try {
            Write-Host "initializing Zephyr SPDX metadata in $BuildDirForWest"
            Invoke-Checked -FilePath $West -Arguments @("spdx", "--init", "--build-dir", $BuildDirForWest)

            Write-Host "refreshing existing Zephyr build metadata in $BuildDirForWest"
            Invoke-Checked -FilePath $West -Arguments @("build", "-d", $BuildDirForWest, "-c")

            Write-Host "generating Zephyr SPDX/SBOM output in $BuildDirForWest"
            Invoke-Checked -FilePath $West -Arguments @("spdx", "--build-dir", $BuildDirForWest)
        }
        catch {
            throw "Zephyr SBOM generation failed. Ensure west is on PATH, the existing build directory is valid, and Zephyr Python dependencies are installed. Underlying error: $($_.Exception.Message)"
        }

        $SbomRoot = Join-Path $BuildRoot "spdx"
        $SbomFiles = Find-SbomFiles -Root $SbomRoot
        if ($SbomFiles.Count -eq 0) {
            throw "Zephyr SBOM generation completed, but no SPDX/SBOM files were found under $SbomRoot."
        }

        foreach ($SbomFile in $SbomFiles) {
            $ManifestPath = Convert-ToManifestPath -Path $SbomFile.FullName
            $ArtifactArgs += @("--artifact", "$($ManifestPath):sbom")
            $BundleIncludeArgs += @("--include-file", $ManifestPath, "sbom/$($SbomFile.Name)")
            Write-Host "including $ManifestPath as sbom"
        }
    }

    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

    $Manifest = Join-Path $OutputDir "release-manifest.json"
    $TraceReport = Join-Path $OutputDir "trace-report.json"
    $EvidenceBundle = Join-Path $OutputDir "evidence-bundle"
    $EvidenceArchive = "$EvidenceBundle.tar.gz"
    $TraceLog = "samples/logs/qemu_controller_boot.log"

    if (-not (Test-Path -LiteralPath $TraceLog -PathType Leaf)) {
        throw "QEMU trace sample not found: $TraceLog"
    }

    $ManifestArgs = @(
        "tools/generate_release_manifest.py",
        "--product", $Product,
        "--version", $Version,
        "--target", $Target,
        "--build-profile", $BuildProfile,
        "--note", "Simulator qemu_cortex_m3 firmware evidence bundle. Not a certification package."
    )
    $ManifestArgs += $ArtifactArgs
    $ManifestArgs += @("--output", $Manifest)

    Invoke-Checked -FilePath $Python -Arguments $ManifestArgs

    Invoke-Checked -FilePath $Python -Arguments @(
        "tools/generate_trace_report.py",
        "--input", $TraceLog,
        "--output", $TraceReport
    )

    $BundleArgs = @(
        "tools/build_evidence_bundle.py",
        "--manifest", $Manifest,
        "--trace-report", $TraceReport,
        "--evidence-dir", "evidence",
        "--output-dir", $EvidenceBundle
    )
    $BundleArgs += $BundleIncludeArgs

    Remove-Item -LiteralPath $EvidenceBundle -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $EvidenceArchive -Force -ErrorAction SilentlyContinue

    Invoke-Checked -FilePath $Python -Arguments $BundleArgs
}
finally {
    Pop-Location
}
