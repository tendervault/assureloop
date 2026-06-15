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

function Resolve-WestInvocation {
    if ($West) {
        if (Test-Path -LiteralPath $West -PathType Leaf) {
            return @{
                FilePath = (Resolve-Path -LiteralPath $West).Path
                Prefix = @()
            }
        }

        try {
            return @{
                FilePath = (Get-Command $West -CommandType Application -ErrorAction Stop).Source
                Prefix = @()
            }
        }
        catch {
            if ($West -ne "west") {
                throw "west was not found at '$West'. Activate the Zephyr Python environment or pass -West. See docs/contributor-quickstart.md."
            }
        }
    }

    $PythonPath = Resolve-Tool `
        -Command $Python `
        -Message "Python was not found. Install Python or pass -Python."

    & $PythonPath -m west --version *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "west was not found. Activate the Zephyr Python environment, install west, pass -West, or use '$Python -m west'. See docs/contributor-quickstart.md."
    }

    return @{
        FilePath = $PythonPath
        Prefix = @("-m", "west")
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
    Add-DirectoryToPathIfExists -Path "C:\Program Files\CMake\bin"
    Add-DirectoryToPathIfExists -Path "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"

    Invoke-Step -Name "Host Python tests" -Script {
        & (Join-Path $PSScriptRoot "test-tools.ps1") -Python $Python
        if ($LASTEXITCODE -ne 0) {
            throw "test-tools.ps1 failed with exit code $LASTEXITCODE"
        }
    }

    $WestInvocation = Resolve-WestInvocation
    $WestFile = [string] $WestInvocation.FilePath
    $WestPrefix = [string[]] $WestInvocation.Prefix
    $WestForScripts = if ($WestPrefix.Count -eq 0) { $WestFile } else { $West }

    Invoke-Step -Name "Zephyr simulator build check" -Script {
        Invoke-Checked -FilePath $WestFile -Arguments ($WestPrefix + @(
            "build",
            "-b", $Board,
            "firmware/app"
        ))
    }

    Invoke-Step -Name "Signed image demo" -Script {
        & (Join-Path $PSScriptRoot "signed-image-demo.ps1") `
            -Python $Python `
            -West $WestForScripts `
            -Board $Board
        if ($LASTEXITCODE -ne 0) {
            throw "signed-image-demo.ps1 failed with exit code $LASTEXITCODE"
        }
    }

    Invoke-Step -Name "Firmware evidence with SBOM" -Script {
        & (Join-Path $PSScriptRoot "firmware-evidence-demo.ps1") `
            -Python $Python `
            -West $WestForScripts `
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
            -West $WestForScripts `
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
    $env:PATH = $OriginalPath
    Pop-Location
}
