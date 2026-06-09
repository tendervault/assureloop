# SPDX-License-Identifier: Apache-2.0

[CmdletBinding()]
param(
    [string] $OpenSsl = $(if ($env:OPENSSL) { $env:OPENSSL } else { "openssl" }),
    [string] $KeysDir = $(if ($env:ASSURELOOP_KEYS_DIR) { $env:ASSURELOOP_KEYS_DIR } else { "keys" })
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

    $KeysRoot = if ([System.IO.Path]::IsPathRooted($KeysDir)) {
        [System.IO.Path]::GetFullPath($KeysDir)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $KeysDir))
    }

    New-Item -ItemType Directory -Force -Path $KeysRoot | Out-Null

    $PrivateKey = Join-Path $KeysRoot "dev-rsa-private.pem"
    $PublicKey = Join-Path $KeysRoot "dev-rsa-public.pem"

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
}
finally {
    $env:PATH = $OriginalPath
    Pop-Location
}
