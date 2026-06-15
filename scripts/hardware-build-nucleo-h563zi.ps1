# SPDX-License-Identifier: Apache-2.0

[CmdletBinding()]
param(
    [string] $Python = $(if ($env:PYTHON) { $env:PYTHON } else { "py" }),
    [string] $West = $(if ($env:WEST) { $env:WEST } else { "" }),
    [string] $Board = $(if ($env:ASSURELOOP_HARDWARE_BOARD) { $env:ASSURELOOP_HARDWARE_BOARD } else { "nucleo_h563zi" }),
    [string] $BuildDir = $(if ($env:ASSURELOOP_HARDWARE_BUILD_DIR) { $env:ASSURELOOP_HARDWARE_BUILD_DIR } else { "build-nucleo-h563zi" }),
    [switch] $Flash
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

function Assert-ToolAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Command,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    try {
        $null = Get-Command $Command -CommandType Application -ErrorAction Stop
    }
    catch {
        throw $Message
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

function Resolve-WestInvocation {
    if ($West) {
        $WestPath = Resolve-Tool `
            -Command $West `
            -Message "west was not found at '$West'. Activate the Zephyr Python environment or pass -West."
        return @{
            FilePath = $WestPath
            Prefix = @()
        }
    }

    try {
        return @{
            FilePath = (Get-Command "west" -CommandType Application -ErrorAction Stop).Source
            Prefix = @()
        }
    }
    catch {
        $PythonPath = Resolve-Tool `
            -Command $Python `
            -Message "Python was not found. Install Python or pass -Python."

        & $PythonPath -m west --version *> $null
        if ($LASTEXITCODE -ne 0) {
            throw "west was not found. Activate the Zephyr Python environment, install west, pass -West, or use '$Python -m west'."
        }

        return @{
            FilePath = $PythonPath
            Prefix = @("-m", "west")
        }
    }
}

Push-Location -LiteralPath $RepoRoot
try {
    Add-DirectoryToPathIfExists -Path "C:\Program Files\CMake\bin"
    Add-DirectoryToPathIfExists -Path "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"

    Assert-ToolAvailable `
        -Command "cmake" `
        -Message "CMake was not found. Install CMake and make sure it is on PATH before building Zephyr."
    Assert-ToolAvailable `
        -Command "ninja" `
        -Message "Ninja was not found. Install Ninja and make sure it is on PATH before building Zephyr."

    $WestInvocation = Resolve-WestInvocation
    $WestFile = [string] $WestInvocation.FilePath
    $WestPrefix = [string[]] $WestInvocation.Prefix

    Invoke-Checked -FilePath $WestFile -Arguments ($WestPrefix + @(
        "build",
        "-p", "always",
        "-b", $Board,
        "firmware/app",
        "-d", $BuildDir
    ))

    Write-Host "hardware build complete: $BuildDir"

    if ($Flash) {
        Invoke-Checked -FilePath $WestFile -Arguments ($WestPrefix + @(
            "flash",
            "-d", $BuildDir
        ))
        Write-Host "flash complete. Open the serial console with: $Python -m serial.tools.miniterm COM4 115200"
    }
    else {
        Write-Host "flash skipped. Re-run with -Flash to program a connected ST NUCLEO-H563ZI."
    }
}
finally {
    $env:PATH = $OriginalPath
    Pop-Location
}
