# SPDX-License-Identifier: Apache-2.0

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$TrimChars = [char[]] @(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)
$RepoFull = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd($TrimChars)
$DistFull = [System.IO.Path]::GetFullPath((Join-Path $RepoFull "dist")).TrimEnd($TrimChars)
$ExpectedDist = [System.IO.Path]::Combine($RepoFull, "dist")

if (-not [string]::Equals($DistFull, $ExpectedDist, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "refusing to remove unexpected path: $DistFull"
}

if (Test-Path -LiteralPath $DistFull) {
    if ($PSCmdlet.ShouldProcess($DistFull, "Remove generated dist output")) {
        Remove-Item -LiteralPath $DistFull -Recurse -Force
        Write-Host "removed $DistFull"
    }
}
else {
    Write-Host "nothing to clean: $DistFull"
}
