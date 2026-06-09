# SPDX-License-Identifier: Apache-2.0

[CmdletBinding()]
param(
    [string] $Python = $(if ($env:PYTHON) { $env:PYTHON } else { "py" }),
    [string] $Bundle = $(if ($env:FIRMWARE_EVIDENCE_BUNDLE) { $env:FIRMWARE_EVIDENCE_BUNDLE } else { "dist/firmware-release/evidence-bundle" }),
    [string] $Schema = $(if ($env:ASSURELOOP_MANIFEST_SCHEMA) { $env:ASSURELOOP_MANIFEST_SCHEMA } else { "schemas/release-manifest.schema.json" }),
    [string] $Signature = $(if ($env:ASSURELOOP_MANIFEST_SIGNATURE) { $env:ASSURELOOP_MANIFEST_SIGNATURE } else { "" }),
    [string] $PublicKey = $(if ($env:ASSURELOOP_PUBLIC_KEY) { $env:ASSURELOOP_PUBLIC_KEY } else { "" }),
    [string] $OpenSsl = $(if ($env:OPENSSL) { $env:OPENSSL } else { "openssl" })
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
    $Arguments = @(
        "tools/verify_evidence_bundle.py",
        "--bundle", $Bundle,
        "--schema", $Schema,
        "--openssl", $OpenSsl
    )

    if (($Signature -and -not $PublicKey) -or ($PublicKey -and -not $Signature)) {
        throw "-Signature and -PublicKey must be supplied together."
    }

    if ($Signature -and $PublicKey) {
        $Arguments += @("--signature", $Signature, "--public-key", $PublicKey)
    }

    Invoke-Checked -FilePath $Python -Arguments $Arguments
}
finally {
    Pop-Location
}
