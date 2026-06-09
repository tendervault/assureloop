# SPDX-License-Identifier: Apache-2.0

[CmdletBinding()]
param(
    [string] $Python = $(if ($env:PYTHON) { $env:PYTHON } else { "py" }),
    [string] $West = $(if ($env:WEST) { $env:WEST } else { "west" }),
    [string] $Board = $(if ($env:ASSURELOOP_TARGET) { $env:ASSURELOOP_TARGET } else { "qemu_cortex_m3" })
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

Push-Location -LiteralPath $RepoRoot
try {
    Invoke-Step -Name "Host Python tests" -Script {
        & (Join-Path $PSScriptRoot "test-tools.ps1") -Python $Python
        if ($LASTEXITCODE -ne 0) {
            throw "test-tools.ps1 failed with exit code $LASTEXITCODE"
        }
    }

    $WestPath = Resolve-Tool `
        -Command $West `
        -Message "west was not found. Activate the Zephyr Python environment or pass -West. See docs/contributor-quickstart.md."

    Invoke-Step -Name "Zephyr simulator build check" -Script {
        Invoke-Checked -FilePath $WestPath -Arguments @(
            "build",
            "-b", $Board,
            "firmware/app"
        )
    }

    Invoke-Step -Name "Signed image demo" -Script {
        & (Join-Path $PSScriptRoot "signed-image-demo.ps1") `
            -Python $Python `
            -West $WestPath `
            -Board $Board
        if ($LASTEXITCODE -ne 0) {
            throw "signed-image-demo.ps1 failed with exit code $LASTEXITCODE"
        }
    }

    Invoke-Step -Name "Firmware evidence with SBOM" -Script {
        & (Join-Path $PSScriptRoot "firmware-evidence-demo.ps1") `
            -Python $Python `
            -West $WestPath `
            -GenerateSbom
        if ($LASTEXITCODE -ne 0) {
            throw "firmware-evidence-demo.ps1 failed with exit code $LASTEXITCODE"
        }
    }

    Invoke-Step -Name "Evidence verification" -Script {
        & (Join-Path $PSScriptRoot "verify-firmware-evidence.ps1") -Python $Python
        if ($LASTEXITCODE -ne 0) {
            throw "verify-firmware-evidence.ps1 failed with exit code $LASTEXITCODE"
        }
    }

    Invoke-Step -Name "Update package demo" -Script {
        & (Join-Path $PSScriptRoot "update-package-demo.ps1") `
            -Python $Python `
            -West $WestPath `
            -Target $Board
        if ($LASTEXITCODE -ne 0) {
            throw "update-package-demo.ps1 failed with exit code $LASTEXITCODE"
        }
    }

    Invoke-Step -Name "OTA simulator demo" -Script {
        & (Join-Path $PSScriptRoot "ota-sim-demo.ps1") `
            -Python $Python `
            -Target $Board
        if ($LASTEXITCODE -ne 0) {
            throw "ota-sim-demo.ps1 failed with exit code $LASTEXITCODE"
        }
    }

    Write-Host ""
    Write-Host "Full simulator demo completed."
}
finally {
    Pop-Location
}
