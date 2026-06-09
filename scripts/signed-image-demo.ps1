# SPDX-License-Identifier: Apache-2.0

[CmdletBinding()]
param(
    [string] $Python = $(if ($env:PYTHON) { $env:PYTHON } else { "py" }),
    [string] $West = $(if ($env:WEST) { $env:WEST } else { "west" }),
    [string] $Imgtool = $(if ($env:IMGTOOL) { $env:IMGTOOL } else { "imgtool" }),
    [string] $BuildDir = $(if ($env:SIGNED_BUILD_DIR) { $env:SIGNED_BUILD_DIR } else { "build-signed" }),
    [string] $OutputDir = $(if ($env:SIGNED_FIRMWARE_RELEASE_DIR) { $env:SIGNED_FIRMWARE_RELEASE_DIR } else { "dist/firmware-signed-release" }),
    [string] $KeysDir = $(if ($env:ASSURELOOP_KEYS_DIR) { $env:ASSURELOOP_KEYS_DIR } else { "keys" }),
    [string] $KeyFile = $(if ($env:ASSURELOOP_MCUBOOT_KEY) { $env:ASSURELOOP_MCUBOOT_KEY } else { "" }),
    [string] $Board = $(if ($env:ASSURELOOP_SIGNED_IMAGE_BOARD) { $env:ASSURELOOP_SIGNED_IMAGE_BOARD } else { "qemu_cortex_m3" }),
    [string] $Overlay = $(if ($env:ASSURELOOP_SIGNED_IMAGE_OVERLAY) { $env:ASSURELOOP_SIGNED_IMAGE_OVERLAY } else { "firmware/app/overlays/qemu_cortex_m3_mcuboot.overlay" })
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

function Resolve-Tool {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Command,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if (Test-Path -LiteralPath $Command -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Command).Path
    }

    try {
        return (Get-Command $Command -CommandType Application -ErrorAction Stop).Source
    }
    catch {
        throw $Message
    }
}

function Resolve-Imgtool {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Command
    )

    if (Test-Path -LiteralPath $Command -PathType Leaf) {
        return @{
            FilePath = (Resolve-Path -LiteralPath $Command).Path
            UsePython = $false
        }
    }

    try {
        return @{
            FilePath = (Get-Command $Command -CommandType Application -ErrorAction Stop).Source
            UsePython = $false
        }
    }
    catch {
        $SiblingFallback = Join-Path $RepoRoot "../bootloader/mcuboot/scripts/imgtool.py"
        if (Test-Path -LiteralPath $SiblingFallback -PathType Leaf) {
            return @{
                FilePath = (Resolve-Path -LiteralPath $SiblingFallback).Path
                UsePython = $true
            }
        }

        if ($env:ZEPHYR_BASE) {
            $WorkspaceRoot = Split-Path -Parent $env:ZEPHYR_BASE
            $Fallback = Join-Path $WorkspaceRoot "bootloader/mcuboot/scripts/imgtool.py"
            if (Test-Path -LiteralPath $Fallback -PathType Leaf) {
                return @{
                    FilePath = (Resolve-Path -LiteralPath $Fallback).Path
                    UsePython = $true
                }
            }
        }

        throw "MCUboot imgtool was not found. Install imgtool, activate the Zephyr Python environment, or set IMGTOOL to imgtool.py."
    }
}

function Invoke-Imgtool {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Tool,

        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    if ($Tool.UsePython) {
        $CommandArguments = @($Tool.FilePath) + $Arguments
        Invoke-Checked -FilePath $Python -Arguments $CommandArguments
    }
    else {
        Invoke-Checked -FilePath $Tool.FilePath -Arguments $Arguments
    }
}

Push-Location -LiteralPath $RepoRoot
try {
    $WestPath = Resolve-Tool -Command $West -Message "west was not found. Activate the Zephyr Python environment or pass -West."
    $ImgtoolCommand = Resolve-Imgtool -Command $Imgtool

    $KeysRoot = if ([System.IO.Path]::IsPathRooted($KeysDir)) {
        [System.IO.Path]::GetFullPath($KeysDir)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $KeysDir))
    }
    New-Item -ItemType Directory -Force -Path $KeysRoot | Out-Null

    $SigningKey = if ($KeyFile) {
        if ([System.IO.Path]::IsPathRooted($KeyFile)) {
            [System.IO.Path]::GetFullPath($KeyFile)
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $KeyFile))
        }
    }
    else {
        Join-Path $KeysRoot "mcuboot-dev-rsa-2048.pem"
    }

    if (-not (Test-Path -LiteralPath $SigningKey -PathType Leaf)) {
        Invoke-Imgtool -Tool $ImgtoolCommand -Arguments @(
            "keygen",
            "-k", $SigningKey,
            "-t", "rsa-2048"
        )
        Write-Host "created $SigningKey"
        Write-Host "development MCUboot key only; do not use for production"
    }

    $OverlayPath = if ([System.IO.Path]::IsPathRooted($Overlay)) {
        [System.IO.Path]::GetFullPath($Overlay)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Overlay))
    }

    if (-not (Test-Path -LiteralPath $OverlayPath -PathType Leaf)) {
        throw "signed-image overlay not found: $OverlayPath"
    }

    $KeyForCMake = $SigningKey.Replace("\", "/")
    $OverlayForCMake = $OverlayPath.Replace("\", "/")
    $KeyArgument = '-DCONFIG_MCUBOOT_SIGNATURE_KEY_FILE:STRING="' + $KeyForCMake + '"'
    $OverlayArgument = "-DEXTRA_DTC_OVERLAY_FILE=$OverlayForCMake"

    Invoke-Checked -FilePath $WestPath -Arguments @(
        "build",
        "-p", "always",
        "-b", $Board,
        "firmware/app",
        "-d", $BuildDir,
        "--",
        "-DCONFIG_BOOTLOADER_MCUBOOT=y",
        "-DCONFIG_BUILD_OUTPUT_BIN=y",
        $KeyArgument,
        $OverlayArgument
    )

    $BuildRoot = if ([System.IO.Path]::IsPathRooted($BuildDir)) {
        [System.IO.Path]::GetFullPath($BuildDir)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $BuildDir))
    }
    $ZephyrBuild = Join-Path $BuildRoot "zephyr"
    $SignedArtifacts = @(
        @(
            (Join-Path $ZephyrBuild "zephyr.signed.bin"),
            (Join-Path $ZephyrBuild "zephyr.signed.hex"),
            (Join-Path $ZephyrBuild "zephyr.signed.confirmed.bin"),
            (Join-Path $ZephyrBuild "zephyr.signed.confirmed.hex")
        ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    )

    if ($SignedArtifacts.Count -eq 0) {
        throw "No signed image artifacts were produced under $ZephyrBuild."
    }

    foreach ($Artifact in $SignedArtifacts) {
        Write-Host "signed image artifact: $Artifact"
    }

    $SignedBin = Join-Path $ZephyrBuild "zephyr.signed.bin"
    if (Test-Path -LiteralPath $SignedBin -PathType Leaf) {
        Invoke-Imgtool -Tool $ImgtoolCommand -Arguments @(
            "verify",
            "-k", $SigningKey,
            $SignedBin
        )
    }

    & (Join-Path $PSScriptRoot "firmware-evidence-demo.ps1") `
        -Python $Python `
        -West $WestPath `
        -BuildDir $BuildDir `
        -OutputDir $OutputDir
    if ($LASTEXITCODE -ne 0) {
        throw "firmware-evidence-demo.ps1 failed with exit code $LASTEXITCODE"
    }

    $Manifest = Join-Path $OutputDir "release-manifest.json"
    $EvidenceBundle = Join-Path $OutputDir "evidence-bundle"
    $UpdatePackage = Join-Path $OutputDir "update-package"

    Invoke-Checked -FilePath $Python -Arguments @(
        "tools/create_update_package.py",
        "--manifest", $Manifest,
        "--evidence-bundle", $EvidenceBundle,
        "--output-dir", $UpdatePackage
    )

    Invoke-Checked -FilePath $Python -Arguments @(
        "tools/verify_update_package.py",
        "--package", $UpdatePackage,
        "--target", $Board
    )
}
finally {
    Pop-Location
}
