# SPDX-License-Identifier: Apache-2.0

[CmdletBinding()]
param(
    [string] $Python = $(if ($env:PYTHON) { $env:PYTHON } else { "py" }),
    [string] $West = $(if ($env:WEST) { $env:WEST } else { "west" }),
    [string] $OpenSsl = $(if ($env:OPENSSL) { $env:OPENSSL } else { "openssl" }),
    [string] $KeysDir = $(if ($env:ASSURELOOP_KEYS_DIR) { $env:ASSURELOOP_KEYS_DIR } else { "keys" }),
    [string] $BuildDir = $(if ($env:BUILD_DIR) { $env:BUILD_DIR } else { "build" }),
    [string] $OutputDir = $(if ($env:FIRMWARE_RELEASE_DIR) { $env:FIRMWARE_RELEASE_DIR } else { "dist/firmware-release" }),
    [string] $Product = $(if ($env:ASSURELOOP_PRODUCT) { $env:ASSURELOOP_PRODUCT } else { "assureloop-controller-demo" }),
    [string] $Version = $(if ($env:ASSURELOOP_VERSION) { $env:ASSURELOOP_VERSION } else { "0.1.0-dev" }),
    [string] $Target = $(if ($env:ASSURELOOP_TARGET) { $env:ASSURELOOP_TARGET } else { "qemu_cortex_m3" }),
    [string] $BuildProfile = $(if ($env:ASSURELOOP_BUILD_PROFILE) { $env:ASSURELOOP_BUILD_PROFILE } else { "dev" }),
    [switch] $GenerateSbom,
    [switch] $Sign
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$OriginalPath = $env:PATH
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

function Resolve-OpenSsl {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Command
    )

    if (Test-Path -LiteralPath $Command -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Command).Path
    }

    try {
        return (Get-Command $Command -CommandType Application -ErrorAction Stop).Source
    }
    catch {
        throw "OpenSSL was not found. Install OpenSSL, add it to PATH, or pass -OpenSsl with the full path to openssl.exe."
    }
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
    $OpenSslPath = $null
    if ($Sign) {
        $OpenSslPath = Resolve-OpenSsl -Command $OpenSsl
        $OpenSslDir = Split-Path -Parent $OpenSslPath
        $env:PATH = "$OpenSslDir;$OriginalPath"
    }

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
        @{ Name = "zephyr.signed.bin"; Kind = "firmware-signed-image"; Firmware = $true },
        @{ Name = "zephyr.signed.hex"; Kind = "firmware-signed-image"; Firmware = $true },
        @{ Name = "zephyr.signed.confirmed.bin"; Kind = "firmware-signed-image"; Firmware = $true },
        @{ Name = "zephyr.signed.confirmed.hex"; Kind = "firmware-signed-image"; Firmware = $true },
        @{ Name = "zephyr.elf"; Kind = "firmware-elf"; Firmware = $true },
        @{ Name = "zephyr.bin"; Kind = "firmware-bin"; Firmware = $true },
        @{ Name = "zephyr.map"; Kind = "firmware-map"; Firmware = $false },
        @{ Name = ".config"; Kind = "firmware-config"; Firmware = $false },
        @{ Name = "zephyr.dts"; Kind = "firmware-devicetree"; Firmware = $false }
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
            Write-Host "including $ManifestPath as sbom"
        }
    }

    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

    $Manifest = Join-Path $OutputDir "release-manifest.json"
    $Signature = Join-Path $OutputDir "release-manifest.sig"
    $TraceReport = Join-Path $OutputDir "trace-report.json"
    $EvidenceBundle = Join-Path $OutputDir "evidence-bundle"
    $EvidenceArchive = "$EvidenceBundle.tar.gz"
    $TraceLog = "samples/logs/qemu_controller_boot.log"

    if (-not (Test-Path -LiteralPath $TraceLog -PathType Leaf)) {
        throw "QEMU trace sample not found: $TraceLog"
    }

    if (-not $Sign) {
        Remove-Item -LiteralPath $Signature -Force -ErrorAction SilentlyContinue
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
        "tools/validate_manifest.py",
        "--manifest", $Manifest
    )

    if ($Sign) {
        $PrivateKey = Join-Path $KeysDir "dev-rsa-private.pem"
        $PublicKey = Join-Path $KeysDir "dev-rsa-public.pem"
        $KeyScript = Join-Path $PSScriptRoot "create_dev_keys.ps1"

        & $KeyScript -OpenSsl $OpenSslPath -KeysDir $KeysDir

        Invoke-Checked -FilePath $Python -Arguments @(
            "tools/sign_release.py",
            "--manifest", $Manifest,
            "--private-key", $PrivateKey,
            "--signature", $Signature,
            "--openssl", $OpenSslPath
        )

        Invoke-Checked -FilePath $Python -Arguments @(
            "tools/verify_release.py",
            "--manifest", $Manifest,
            "--base-dir", ".",
            "--signature", $Signature,
            "--public-key", $PublicKey,
            "--openssl", $OpenSslPath
        )

        $BundleIncludeArgs += @("--include-file", $Signature, "release-manifest.sig")
        $BundleIncludeArgs += @("--include-file", $PublicKey, "signing/dev-rsa-public.pem")
    }

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
    $env:PATH = $OriginalPath
    Pop-Location
}
