# SPDX-License-Identifier: Apache-2.0

[CmdletBinding()]
param(
    [string] $Python = $(if ($env:PYTHON) { $env:PYTHON } else { "py" }),
    [string] $Dist = $(if ($env:DIST) { $env:DIST } else { "dist" })
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
    New-Item -ItemType Directory -Force -Path $Dist | Out-Null

    $Manifest = Join-Path $Dist "release-manifest.json"
    $TraceReport = Join-Path $Dist "trace-report.json"
    $EvidenceBundle = Join-Path $Dist "evidence-bundle"

    Invoke-Checked -FilePath $Python -Arguments @(
        "tools/generate_release_manifest.py",
        "--product", "assureloop-controller-demo",
        "--version", "0.1.0-dev",
        "--target", "host-demo",
        "--artifact", "README.md:doc",
        "--output", $Manifest
    )

    Invoke-Checked -FilePath $Python -Arguments @(
        "tools/generate_trace_report.py",
        "--input", "samples/logs/controller_boot.log",
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
