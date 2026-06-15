# SPDX-License-Identifier: Apache-2.0
#
# Usage: .\scripts\signed-image-demo-nucleo-h563zi.ps1 [-Flash]
# The board-specific flow always forwards -GenerateSbom to signed-image-demo.ps1.

[CmdletBinding()]
param(
    [string] $Python = $(if ($env:PYTHON) { $env:PYTHON } else { "py" }),
    [string] $West = $(if ($env:WEST) { $env:WEST } else { "west" }),
    [string] $Imgtool = $(if ($env:IMGTOOL) { $env:IMGTOOL } else { "imgtool" }),
    [string] $BuildDir = $(if ($env:SIGNED_NUCLEO_H563ZI_BUILD_DIR) { $env:SIGNED_NUCLEO_H563ZI_BUILD_DIR } else { "build-signed-nucleo-h563zi" }),
    [string] $OutputDir = $(if ($env:SIGNED_NUCLEO_H563ZI_RELEASE_DIR) { $env:SIGNED_NUCLEO_H563ZI_RELEASE_DIR } else { "dist/firmware-nucleo-h563zi-release" }),
    [string] $KeysDir = $(if ($env:ASSURELOOP_KEYS_DIR) { $env:ASSURELOOP_KEYS_DIR } else { "keys" }),
    [string] $KeyFile = $(if ($env:ASSURELOOP_MCUBOOT_KEY) { $env:ASSURELOOP_MCUBOOT_KEY } else { "" }),
    [string] $ZephyrSdk = $(if ($env:ZEPHYR_SDK_INSTALL_DIR) { $env:ZEPHYR_SDK_INSTALL_DIR } elseif (Test-Path -LiteralPath "D:\zephyr-sdk" -PathType Container) { "D:\zephyr-sdk" } else { "" }),
    [string] $TraceLog = $(if ($env:ASSURELOOP_NUCLEO_TRACE_LOG) { $env:ASSURELOOP_NUCLEO_TRACE_LOG } else { "samples/logs/nucleo_h563zi_boot.log" }),
    [switch] $Flash
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$OriginalSdk = $env:ZEPHYR_SDK_INSTALL_DIR
$OriginalToolchain = $env:ZEPHYR_TOOLCHAIN_VARIANT
$OriginalPath = $env:PATH

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

function Add-DirectoryToPathIfExists {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (Test-Path -LiteralPath $Path -PathType Container) {
        $env:PATH = "$Path;$env:PATH"
    }
}

function Add-PythonUserScriptsToPath {
    $UserBase = & $Python -c "import site; print(site.USER_BASE)" 2>$null
    if ($LASTEXITCODE -eq 0 -and $UserBase) {
        Add-DirectoryToPathIfExists -Path (Join-Path $UserBase "Scripts")
    }
}

function Assert-ToolAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Command,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    try {
        $null = Get-Command $Command -CommandType Application -ErrorAction Stop
    }
    catch {
        throw $Message
    }
}

Push-Location -LiteralPath $RepoRoot
try {
    Add-PythonUserScriptsToPath
    Add-DirectoryToPathIfExists -Path "C:\Program Files\CMake\bin"
    Add-DirectoryToPathIfExists -Path "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"

    Assert-ToolAvailable `
        -Command "cmake" `
        -Message "CMake was not found. Install CMake and make sure it is on PATH before building Zephyr."
    Assert-ToolAvailable `
        -Command "ninja" `
        -Message "Ninja was not found. Install Ninja and make sure it is on PATH before building Zephyr."

    if (-not $ZephyrSdk) {
        throw "Zephyr SDK was not found. Set ZEPHYR_SDK_INSTALL_DIR, for example D:\zephyr-sdk."
    }
    if (-not (Test-Path -LiteralPath $ZephyrSdk -PathType Container)) {
        throw "Zephyr SDK path does not exist: $ZephyrSdk"
    }
    $env:ZEPHYR_SDK_INSTALL_DIR = (Resolve-Path -LiteralPath $ZephyrSdk).Path
    if (-not $env:ZEPHYR_TOOLCHAIN_VARIANT) {
        $env:ZEPHYR_TOOLCHAIN_VARIANT = "zephyr"
    }

    $CommonParams = @{
        Python = $Python
        West = $West
        Imgtool = $Imgtool
        BuildDir = $BuildDir
        OutputDir = $OutputDir
        KeysDir = $KeysDir
        Board = "nucleo_h563zi"
        Target = "nucleo_h563zi"
        Overlay = ""
        TraceLog = $TraceLog
        EvidenceNote = "ST NUCLEO-H563ZI board-specific signed image evidence bundle. Development keys only; not production secure boot or certification."
        GenerateSbom = $true
    }

    if ($KeyFile) {
        $CommonParams.KeyFile = $KeyFile
    }
    if ($Flash) {
        $CommonParams.Flash = $true
    }

    & (Join-Path $PSScriptRoot "signed-image-demo.ps1") @CommonParams
    if ($LASTEXITCODE -ne 0) {
        throw "signed-image-demo.ps1 failed with exit code $LASTEXITCODE"
    }

    $EvidenceBundle = Join-Path $OutputDir "evidence-bundle"
    $UpdatePackage = Join-Path $OutputDir "update-package"

    Invoke-Checked -FilePath $Python -Arguments @(
        "tools/verify_evidence_bundle.py",
        "--bundle", $EvidenceBundle
    )

    Invoke-Checked -FilePath $Python -Arguments @(
        "tools/verify_update_package.py",
        "--package", $UpdatePackage,
        "--target", "nucleo_h563zi"
    )

    Write-Host "NUCLEO-H563ZI signed evidence release: $OutputDir"
    Write-Host "Evidence bundle: $EvidenceBundle"
    Write-Host "Update package: $UpdatePackage"
}
finally {
    $env:PATH = $OriginalPath
    $env:ZEPHYR_SDK_INSTALL_DIR = $OriginalSdk
    $env:ZEPHYR_TOOLCHAIN_VARIANT = $OriginalToolchain
    Pop-Location
}
