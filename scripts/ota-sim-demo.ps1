# SPDX-License-Identifier: Apache-2.0

[CmdletBinding()]
param(
    [string] $Python = $(if ($env:PYTHON) { $env:PYTHON } else { "py" }),
    [string] $SignedBuildDir = $(if ($env:SIGNED_BUILD_DIR) { $env:SIGNED_BUILD_DIR } else { "build-signed" }),
    [string] $SignedReleaseDir = $(if ($env:SIGNED_FIRMWARE_RELEASE_DIR) { $env:SIGNED_FIRMWARE_RELEASE_DIR } else { "dist/firmware-signed-release" }),
    [string] $State = $(if ($env:OTA_SIM_STATE) { $env:OTA_SIM_STATE } else { "dist/ota-sim/state.json" }),
    [string] $Target = $(if ($env:ASSURELOOP_TARGET) { $env:ASSURELOOP_TARGET } else { "qemu_cortex_m3" }),
    [string] $InitialVersion = $(if ($env:ASSURELOOP_INSTALLED_VERSION) { $env:ASSURELOOP_INSTALLED_VERSION } else { "0.0.0" }),
    [switch] $KeepState
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

function Get-FullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

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

function Test-SignedUpdatePackage {
    param(
        [Parameter(Mandatory = $true)]
        [string] $PackageDir
    )

    $PackageJson = Join-Path $PackageDir "update-package.json"
    if (-not (Test-Path -LiteralPath $PackageJson -PathType Leaf)) {
        return $false
    }

    try {
        $Package = Get-Content -Raw -LiteralPath $PackageJson | ConvertFrom-Json
    }
    catch {
        return $false
    }

    $Payload = $Package.payload
    if ($null -eq $Payload) {
        return $false
    }

    if ($Payload.kind -ne "firmware-signed-image") {
        return $false
    }

    if (-not $Payload.path) {
        return $false
    }

    $PayloadPath = Join-Path $PackageDir $Payload.path
    return (Test-Path -LiteralPath $PayloadPath -PathType Leaf)
}

function Remove-GeneratedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [switch] $Recurse
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    $GeneratedRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot "dist/ota-sim"))
    $GeneratedRootPrefix = $GeneratedRoot.TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar
    if (
        ($FullPath -ne $GeneratedRoot) -and
        (-not $FullPath.StartsWith($GeneratedRootPrefix, [System.StringComparison]::OrdinalIgnoreCase))
    ) {
        throw "refusing to remove path outside dist/ota-sim: $FullPath"
    }

    if ($Recurse) {
        Remove-Item -LiteralPath $FullPath -Recurse -Force
    }
    else {
        Remove-Item -LiteralPath $FullPath -Force
    }
}

Push-Location -LiteralPath $RepoRoot
try {
    $PackageDir = Join-Path (Get-FullPath -Path $SignedReleaseDir) "update-package"
    $SignedImage = Join-Path (Join-Path (Get-FullPath -Path $SignedBuildDir) "zephyr") "zephyr.signed.bin"

    if (-not ((Test-Path -LiteralPath $SignedImage -PathType Leaf) -and (Test-SignedUpdatePackage -PackageDir $PackageDir))) {
        & (Join-Path $PSScriptRoot "signed-image-demo.ps1") -Python $Python
        if ($LASTEXITCODE -ne 0) {
            throw "signed-image-demo.ps1 failed with exit code $LASTEXITCODE"
        }
    }

    $StatePath = Get-FullPath -Path $State
    $StateDir = Split-Path -Parent $StatePath
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

    if (-not $KeepState) {
        Remove-GeneratedPath -Path $StatePath
    }

    Invoke-Checked -FilePath $Python -Arguments @(
        "tools/simulate_ota.py",
        "--action", "stage",
        "--package", $PackageDir,
        "--state", $StatePath,
        "--target", $Target,
        "--installed-version", $InitialVersion
    )

    Invoke-Checked -FilePath $Python -Arguments @(
        "tools/simulate_ota.py",
        "--action", "install",
        "--state", $StatePath,
        "--target", $Target
    )

    Invoke-Checked -FilePath $Python -Arguments @(
        "tools/simulate_ota.py",
        "--action", "confirm",
        "--state", $StatePath
    )

    & $Python @(
        "tools/simulate_ota.py",
        "--action", "stage",
        "--package", $PackageDir,
        "--state", $StatePath,
        "--target", $Target,
        "--installed-version", "999.0.0"
    )
    if ($LASTEXITCODE -eq 0) {
        throw "downgrade rejection demo unexpectedly passed"
    }
    Write-Host "downgrade rejection demo passed"
    $global:LASTEXITCODE = 0

    $TamperedPackageDir = Join-Path $StateDir "tampered-update-package"
    Remove-GeneratedPath -Path $TamperedPackageDir -Recurse
    Copy-Item -LiteralPath $PackageDir -Destination $TamperedPackageDir -Recurse

    $TamperedJson = Join-Path $TamperedPackageDir "update-package.json"
    $TamperedPackage = Get-Content -Raw -LiteralPath $TamperedJson | ConvertFrom-Json
    $TamperedPayload = Join-Path $TamperedPackageDir $TamperedPackage.payload.path
    Set-Content -LiteralPath $TamperedPayload -Value "tampered" -NoNewline

    & $Python @(
        "tools/simulate_ota.py",
        "--action", "stage",
        "--package", $TamperedPackageDir,
        "--state", $StatePath,
        "--target", $Target
    )
    if ($LASTEXITCODE -eq 0) {
        throw "tamper rejection demo unexpectedly passed"
    }
    Write-Host "tamper rejection demo passed"
    $global:LASTEXITCODE = 0

    Invoke-Checked -FilePath $Python -Arguments @(
        "tools/simulate_ota.py",
        "status",
        "--state", $StatePath
    )
}
finally {
    Pop-Location
}
