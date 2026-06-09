# SPDX-License-Identifier: Apache-2.0

[CmdletBinding()]
param(
    [string] $Python = $(if ($env:PYTHON) { $env:PYTHON } else { "py" }),
    [string] $BuildDir = $(if ($env:BUILD_DIR) { $env:BUILD_DIR } else { "build" }),
    [string] $OutputDir = $(if ($env:FIRMWARE_RELEASE_DIR) { $env:FIRMWARE_RELEASE_DIR } else { "dist/firmware-release" }),
    [string] $Product = $(if ($env:ASSURELOOP_PRODUCT) { $env:ASSURELOOP_PRODUCT } else { "assureloop-controller-demo" }),
    [string] $Version = $(if ($env:ASSURELOOP_VERSION) { $env:ASSURELOOP_VERSION } else { "0.1.0-dev" }),
    [string] $Target = $(if ($env:ASSURELOOP_TARGET) { $env:ASSURELOOP_TARGET } else { "qemu_cortex_m3" }),
    [string] $BuildProfile = $(if ($env:ASSURELOOP_BUILD_PROFILE) { $env:ASSURELOOP_BUILD_PROFILE } else { "dev" })
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

Push-Location -LiteralPath $RepoRoot
try {
    $BuildRoot = if ([System.IO.Path]::IsPathRooted($BuildDir)) {
        [System.IO.Path]::GetFullPath($BuildDir)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $BuildDir))
    }

    $ZephyrBuild = Join-Path $BuildRoot "zephyr"
    if (-not (Test-Path -LiteralPath $ZephyrBuild -PathType Container)) {
        throw "Zephyr build directory not found: $ZephyrBuild. Run 'west build -b qemu_cortex_m3 firmware/app' first."
    }

    $ArtifactArgs = @()
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

    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

    $Manifest = Join-Path $OutputDir "release-manifest.json"
    $TraceReport = Join-Path $OutputDir "trace-report.json"
    $EvidenceBundle = Join-Path $OutputDir "evidence-bundle"
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

    Invoke-Checked -FilePath $Python -Arguments @(
        "tools/build_evidence_bundle.py",
        "--manifest", $Manifest,
        "--trace-report", $TraceReport,
        "--evidence-dir", "evidence",
        "--output-dir", $EvidenceBundle
    )
}
finally {
    Pop-Location
}
