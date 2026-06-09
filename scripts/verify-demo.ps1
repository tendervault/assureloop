# SPDX-License-Identifier: Apache-2.0

[CmdletBinding()]
param(
    [string] $Python = $(if ($env:PYTHON) { $env:PYTHON } else { "py" }),
    [string] $OpenSsl = $(if ($env:OPENSSL) { $env:OPENSSL } else { "openssl" }),
    [string] $Dist = $(if ($env:DIST) { $env:DIST } else { "dist" })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
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

Push-Location -LiteralPath $RepoRoot
try {
    $OpenSslPath = Resolve-OpenSsl -Command $OpenSsl
    $OpenSslDir = Split-Path -Parent $OpenSslPath
    $env:PATH = "$OpenSslDir;$OriginalPath"

    New-Item -ItemType Directory -Force -Path $Dist | Out-Null
    New-Item -ItemType Directory -Force -Path "keys" | Out-Null

    $Manifest = Join-Path $Dist "release-manifest.json"
    $Signature = "$Manifest.sig"
    $PrivateKey = Join-Path "keys" "dev-rsa-private.pem"
    $PublicKey = Join-Path "keys" "dev-rsa-public.pem"

    Invoke-Checked -FilePath $Python -Arguments @(
        "tools/generate_release_manifest.py",
        "--product", "assureloop-controller-demo",
        "--version", "0.1.0-dev",
        "--target", "host-demo",
        "--artifact", "README.md:doc",
        "--output", $Manifest
    )

    Invoke-Checked -FilePath $Python -Arguments @(
        "tools/validate_manifest.py",
        "--manifest", $Manifest
    )

    if (-not (Test-Path -LiteralPath $PrivateKey -PathType Leaf)) {
        Invoke-Checked -FilePath $OpenSslPath -Arguments @(
            "genpkey",
            "-algorithm", "RSA",
            "-pkeyopt", "rsa_keygen_bits:3072",
            "-out", $PrivateKey
        )
    }

    Invoke-Checked -FilePath $OpenSslPath -Arguments @(
        "rsa",
        "-in", $PrivateKey,
        "-pubout",
        "-out", $PublicKey
    )

    Write-Host "created $PrivateKey and $PublicKey"
    Write-Host "development keys only; do not use for production"

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
}
finally {
    $env:PATH = $OriginalPath
    Pop-Location
}
