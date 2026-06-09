# SPDX-License-Identifier: Apache-2.0

[CmdletBinding()]
param(
    [string] $Python = $(if ($env:PYTHON) { $env:PYTHON } else { "py" }),
    [string] $West = $(if ($env:WEST) { $env:WEST } else { "west" }),
    [string] $BuildDir = $(if ($env:BUILD_DIR) { $env:BUILD_DIR } else { "build" }),
    [string] $OutputDir = $(if ($env:UPDATE_PACKAGE_DIR) { $env:UPDATE_PACKAGE_DIR } else { "dist/firmware-release/update-package" }),
    [string] $FirmwareReleaseDir = $(if ($env:FIRMWARE_RELEASE_DIR) { $env:FIRMWARE_RELEASE_DIR } else { "dist/firmware-release" }),
    [string] $Target = $(if ($env:ASSURELOOP_TARGET) { $env:ASSURELOOP_TARGET } else { "qemu_cortex_m3" })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

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

    & (Join-Path $PSScriptRoot "firmware-evidence-demo.ps1") `
        -Python $Python `
        -West $West `
        -BuildDir $BuildDir `
        -OutputDir $FirmwareReleaseDir `
        -GenerateSbom
    if ($LASTEXITCODE -ne 0) {
        throw "firmware-evidence-demo.ps1 failed with exit code $LASTEXITCODE"
    }

    $Manifest = Join-Path $FirmwareReleaseDir "release-manifest.json"
    $EvidenceBundle = Join-Path $FirmwareReleaseDir "evidence-bundle"

    Invoke-Checked -FilePath $Python -Arguments @(
        "tools/create_update_package.py",
        "--manifest", $Manifest,
        "--evidence-bundle", $EvidenceBundle,
        "--output-dir", $OutputDir
    )

    Invoke-Checked -FilePath $Python -Arguments @(
        "tools/verify_update_package.py",
        "--package", $OutputDir,
        "--target", $Target
    )

    & $Python @(
        "tools/verify_update_package.py",
        "--package", $OutputDir,
        "--installed-version", "999.0.0"
    )
    if ($LASTEXITCODE -eq 0) {
        throw "downgrade rejection demo unexpectedly passed"
    }

    Write-Host "downgrade rejection demo passed"
    $global:LASTEXITCODE = 0
}
finally {
    Pop-Location
}
