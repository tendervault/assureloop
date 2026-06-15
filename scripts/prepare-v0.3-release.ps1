# SPDX-License-Identifier: Apache-2.0
#
# Prepares a local, ignored v0.3 hardware-alpha release output.
# The output contains sample/development evidence only and never copies keys/.

[CmdletBinding()]
param(
    [string] $Python = $(if ($env:PYTHON) { $env:PYTHON } else { "py" }),
    [string] $West = $(if ($env:WEST) { $env:WEST } else { "" }),
    [string] $OutputDir = $(if ($env:ASSURELOOP_V03_RELEASE_DIR) { $env:ASSURELOOP_V03_RELEASE_DIR } else { "dist/releases/v0.3-hardware-alpha" })
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

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [scriptblock] $Script
    )

    Write-Host ""
    Write-Host "==> $Name"
    & $Script
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

function Copy-Tree {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Source,

        [Parameter(Mandatory = $true)]
        [string] $Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Required release material does not exist: $Source"
    }

    Assert-PathInsideBase -Path $Destination -Base (Join-Path $RepoRoot "dist")

    $DestinationParent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $DestinationParent | Out-Null
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse
}

function Copy-FileChecked {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Source,

        [Parameter(Mandatory = $true)]
        [string] $Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Required release material does not exist: $Source"
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Assert-PathInsideBase {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Base
    )

    $FullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $BasePath = [System.IO.Path]::GetFullPath($Base).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $Prefix = $BasePath + [System.IO.Path]::DirectorySeparatorChar
    if ($FullPath -ne $BasePath -and -not $FullPath.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write release output outside ignored dist tree: $FullPath"
    }
}

function Convert-ToUnixRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Base
    )

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    $BasePath = [System.IO.Path]::GetFullPath($Base).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $Prefix = $BasePath + [System.IO.Path]::DirectorySeparatorChar
    if ($FullPath.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($Prefix.Length).Replace("\", "/")
    }
    return $FullPath.Replace("\", "/")
}

function Assert-NoPrivateMaterial {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $Forbidden = Get-ChildItem -LiteralPath $Path -Recurse -File | Where-Object {
        $_.Name -match '(?i)(private|secret|key|\.pem$|\.p8$|\.p12$)'
    }
    if ($Forbidden) {
        $List = ($Forbidden | ForEach-Object { Convert-ToUnixRelativePath -Path $_.FullName -Base $Path }) -join ", "
        throw "Release output contains private or key-like material: $List"
    }
}

function Write-Checksums {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $ChecksumPath = Join-Path $Path "SHA256SUMS.txt"
    $Files = Get-ChildItem -LiteralPath $Path -Recurse -File |
        Where-Object { $_.FullName -ne $ChecksumPath } |
        Sort-Object FullName

    $Lines = foreach ($File in $Files) {
        $Relative = Convert-ToUnixRelativePath -Path $File.FullName -Base $Path
        $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $File.FullName).Hash.ToLowerInvariant()
        "$Hash  $Relative"
    }

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($ChecksumPath, [string[]] $Lines, $Utf8NoBom)
}

Push-Location -LiteralPath $RepoRoot
try {
    Add-DirectoryToPathIfExists -Path "C:\Program Files\CMake\bin"
    Add-DirectoryToPathIfExists -Path "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"

    Invoke-Step -Name "Host Python tests" -Script {
        & (Join-Path $PSScriptRoot "test-tools.ps1") -Python $Python
        if ($LASTEXITCODE -ne 0) {
            throw "test-tools.ps1 failed with exit code $LASTEXITCODE"
        }
    }

    Invoke-Step -Name "Full simulator demo" -Script {
        & (Join-Path $PSScriptRoot "full-demo.ps1") -Python $Python -West $West
        if ($LASTEXITCODE -ne 0) {
            throw "full-demo.ps1 failed with exit code $LASTEXITCODE"
        }
    }

    Invoke-Step -Name "NUCLEO-H563ZI hardware build" -Script {
        & (Join-Path $PSScriptRoot "hardware-build-nucleo-h563zi.ps1") -Python $Python -West $West
        if ($LASTEXITCODE -ne 0) {
            throw "hardware-build-nucleo-h563zi.ps1 failed with exit code $LASTEXITCODE"
        }
    }

    Invoke-Step -Name "NUCLEO-H563ZI signed image evidence" -Script {
        & (Join-Path $PSScriptRoot "signed-image-demo-nucleo-h563zi.ps1") -Python $Python -West $West
        if ($LASTEXITCODE -ne 0) {
            throw "signed-image-demo-nucleo-h563zi.ps1 failed with exit code $LASTEXITCODE"
        }
    }

    Invoke-Step -Name "NUCLEO-H563ZI MCUboot verification build" -Script {
        & (Join-Path $PSScriptRoot "mcuboot-verify-nucleo-h563zi.ps1") -Python $Python -West $West
        if ($LASTEXITCODE -ne 0) {
            throw "mcuboot-verify-nucleo-h563zi.ps1 failed with exit code $LASTEXITCODE"
        }
    }

    Invoke-Step -Name "NUCLEO-H563ZI lifecycle build" -Script {
        & (Join-Path $PSScriptRoot "mcuboot-update-lifecycle-nucleo-h563zi.ps1") -Python $Python -West $West
        if ($LASTEXITCODE -ne 0) {
            throw "mcuboot-update-lifecycle-nucleo-h563zi.ps1 failed with exit code $LASTEXITCODE"
        }
    }

    Invoke-Step -Name "Assemble release output" -Script {
        $ReleaseRoot = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
            [System.IO.Path]::GetFullPath($OutputDir)
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputDir))
        }
        Assert-PathInsideBase -Path $ReleaseRoot -Base (Join-Path $RepoRoot "dist")

        if (Test-Path -LiteralPath $ReleaseRoot) {
            Remove-Item -LiteralPath $ReleaseRoot -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $ReleaseRoot | Out-Null

        Copy-FileChecked -Source "docs/releases/v0.3-hardware-alpha.md" -Destination (Join-Path $ReleaseRoot "release-notes.md")
        Copy-FileChecked -Source "docs/v0.3-hardware-alpha-release.md" -Destination (Join-Path $ReleaseRoot "release-readiness.md")

        $LogsRoot = Join-Path $ReleaseRoot "sample-logs"
        foreach ($Log in @(
            "samples/logs/qemu_controller_boot.log",
            "samples/logs/nucleo_h563zi_boot.log",
            "samples/logs/nucleo_h563zi_mcuboot_update_confirm.log",
            "samples/logs/nucleo_h563zi_mcuboot_update_rollback.log",
            "samples/logs/nucleo_h563zi_mcuboot_tamper_reject.log",
            "samples/logs/nucleo_h563zi_mcuboot_downgrade_reject.log"
        )) {
            Copy-FileChecked -Source $Log -Destination (Join-Path $LogsRoot ([System.IO.Path]::GetFileName($Log)))
        }

        $SampleRoot = Join-Path $ReleaseRoot "sample-dev-artifacts"
        Copy-Tree -Source "dist/firmware-nucleo-h563zi-release/evidence-bundle" -Destination (Join-Path $SampleRoot "evidence-bundle")
        Copy-FileChecked -Source "dist/firmware-nucleo-h563zi-release/evidence-bundle.tar.gz" -Destination (Join-Path $SampleRoot "evidence-bundle.tar.gz")
        Copy-Tree -Source "dist/firmware-nucleo-h563zi-release/update-package" -Destination (Join-Path $SampleRoot "update-package")

        $VerificationPath = Join-Path $ReleaseRoot "verification-summary.txt"
        $EvidenceResult = & $Python @(
            "tools/verify_evidence_bundle.py",
            "--bundle", "dist/firmware-nucleo-h563zi-release/evidence-bundle"
        ) 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Evidence bundle verification failed while preparing release output: $EvidenceResult"
        }
        $UpdateResult = & $Python @(
            "tools/verify_update_package.py",
            "--package", "dist/firmware-nucleo-h563zi-release/update-package",
            "--target", "nucleo_h563zi"
        ) 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Update package verification failed while preparing release output: $UpdateResult"
        }

        $VerificationLines = @(
            "AssureLoop v0.3 hardware-alpha local release verification",
            "",
            "This output contains sample/development artifacts only.",
            "Private keys are intentionally excluded.",
            "",
            "Evidence bundle verification:",
            $EvidenceResult,
            "",
            "Update package verification:",
            $UpdateResult
        )
        $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllLines($VerificationPath, [string[]] $VerificationLines, $Utf8NoBom)

        Assert-NoPrivateMaterial -Path $ReleaseRoot
        Write-Checksums -Path $ReleaseRoot

        Write-Host "v0.3 hardware-alpha release output: $ReleaseRoot"
        Write-Host "checksums: $(Join-Path $ReleaseRoot 'SHA256SUMS.txt')"
    }
}
finally {
    $env:PATH = $OriginalPath
    Pop-Location
}
