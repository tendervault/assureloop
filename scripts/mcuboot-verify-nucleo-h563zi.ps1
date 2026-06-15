# SPDX-License-Identifier: Apache-2.0
#
# Usage: .\scripts\mcuboot-verify-nucleo-h563zi.ps1 [-Flash]
# Expected signed application artifacts include zephyr.signed.bin and zephyr.signed.hex.

[CmdletBinding()]
param(
    [string] $Python = $(if ($env:PYTHON) { $env:PYTHON } else { "py" }),
    [string] $West = $(if ($env:WEST) { $env:WEST } else { "west" }),
    [string] $Imgtool = $(if ($env:IMGTOOL) { $env:IMGTOOL } else { "imgtool" }),
    [string] $BuildDir = $(if ($env:MCUBOOT_NUCLEO_H563ZI_BUILD_DIR) { $env:MCUBOOT_NUCLEO_H563ZI_BUILD_DIR } else { "build-mcuboot-nucleo-h563zi" }),
    [string] $KeysDir = $(if ($env:ASSURELOOP_KEYS_DIR) { $env:ASSURELOOP_KEYS_DIR } else { "keys" }),
    [string] $KeyFile = $(if ($env:ASSURELOOP_MCUBOOT_KEY) { $env:ASSURELOOP_MCUBOOT_KEY } else { "" }),
    [string] $ZephyrSdk = $(if ($env:ZEPHYR_SDK_INSTALL_DIR) { $env:ZEPHYR_SDK_INSTALL_DIR } elseif (Test-Path -LiteralPath "D:\zephyr-sdk" -PathType Container) { "D:\zephyr-sdk" } else { "" }),
    [string] $SerialPort = $(if ($env:ASSURELOOP_NUCLEO_SERIAL_PORT) { $env:ASSURELOOP_NUCLEO_SERIAL_PORT } else { "COM4" }),
    [int] $Baud = $(if ($env:ASSURELOOP_NUCLEO_BAUD) { [int] $env:ASSURELOOP_NUCLEO_BAUD } else { 115200 }),
    [switch] $Flash
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$OriginalSdk = $env:ZEPHYR_SDK_INSTALL_DIR
$OriginalToolchain = $env:ZEPHYR_TOOLCHAIN_VARIANT
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

function Add-PythonUserScriptsToPath {
    $UserBase = & $Python -c "import site; print(site.USER_BASE)" 2>$null
    if ($LASTEXITCODE -eq 0 -and $UserBase) {
        Add-DirectoryToPathIfExists -Path (Join-Path $UserBase "Scripts")
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
                throw "west was not found at '$West'. Activate the Zephyr Python environment or pass -West."
            }
        }
    }

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

function Resolve-Imgtool {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Command
    )

    if (Test-Path -LiteralPath $Command -PathType Leaf) {
        return @{
            FilePath = (Resolve-Path -LiteralPath $Command).Path
            UsePython = $false
        }
    }

    try {
        return @{
            FilePath = (Get-Command $Command -CommandType Application -ErrorAction Stop).Source
            UsePython = $false
        }
    }
    catch {
        $SiblingFallback = Join-Path $RepoRoot "../bootloader/mcuboot/scripts/imgtool.py"
        if (Test-Path -LiteralPath $SiblingFallback -PathType Leaf) {
            return @{
                FilePath = (Resolve-Path -LiteralPath $SiblingFallback).Path
                UsePython = $true
            }
        }

        if ($env:ZEPHYR_BASE) {
            $WorkspaceRoot = Split-Path -Parent $env:ZEPHYR_BASE
            $Fallback = Join-Path $WorkspaceRoot "bootloader/mcuboot/scripts/imgtool.py"
            if (Test-Path -LiteralPath $Fallback -PathType Leaf) {
                return @{
                    FilePath = (Resolve-Path -LiteralPath $Fallback).Path
                    UsePython = $true
                }
            }
        }

        throw "MCUboot imgtool was not found. Install imgtool, activate the Zephyr Python environment, or set IMGTOOL to imgtool.py."
    }
}

function Invoke-Imgtool {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Tool,

        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    if ($Tool.UsePython) {
        Invoke-Checked -FilePath $Python -Arguments (@($Tool.FilePath) + $Arguments)
    }
    else {
        Invoke-Checked -FilePath $Tool.FilePath -Arguments $Arguments
    }
}

function Add-Stm32CubeProgrammerToPathIfExists {
    Add-DirectoryToPathIfExists -Path "C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin"
    Add-DirectoryToPathIfExists -Path "C:\Program Files (x86)\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin"
}

function Assert-Stm32CubeProgrammerAvailable {
    try {
        $null = Get-Command "STM32_Programmer_CLI" -CommandType Application -ErrorAction Stop
    }
    catch {
        throw "STM32CubeProgrammer CLI was not found. Install STM32CubeProgrammer v2.22.0 or add its bin directory to PATH before flashing."
    }
}

Push-Location -LiteralPath $RepoRoot
try {
    Add-PythonUserScriptsToPath
    Add-DirectoryToPathIfExists -Path "C:\Program Files\CMake\bin"
    Add-DirectoryToPathIfExists -Path "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"
    Add-Stm32CubeProgrammerToPathIfExists

    Assert-ToolAvailable `
        -Command "cmake" `
        -Message "CMake was not found. Install CMake and make sure it is on PATH before building Zephyr."
    Assert-ToolAvailable `
        -Command "ninja" `
        -Message "Ninja was not found. Install Ninja and make sure it is on PATH before building Zephyr."

    if (-not $ZephyrSdk) {
        throw "Zephyr SDK was not found. Set ZEPHYR_SDK_INSTALL_DIR, for example D:\zephyr-sdk."
    }
    if (-not (Test-Path -LiteralPath $ZephyrSdk -PathType Container)) {
        throw "Zephyr SDK path does not exist: $ZephyrSdk"
    }
    $env:ZEPHYR_SDK_INSTALL_DIR = (Resolve-Path -LiteralPath $ZephyrSdk).Path
    if (-not $env:ZEPHYR_TOOLCHAIN_VARIANT) {
        $env:ZEPHYR_TOOLCHAIN_VARIANT = "zephyr"
    }

    if ($Flash) {
        Assert-Stm32CubeProgrammerAvailable
    }

    $WestInvocation = Resolve-WestInvocation
    $WestFile = [string] $WestInvocation.FilePath
    $WestPrefix = [string[]] $WestInvocation.Prefix
    $ImgtoolCommand = Resolve-Imgtool -Command $Imgtool

    $KeysRoot = if ([System.IO.Path]::IsPathRooted($KeysDir)) {
        [System.IO.Path]::GetFullPath($KeysDir)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $KeysDir))
    }
    New-Item -ItemType Directory -Force -Path $KeysRoot | Out-Null

    $SigningKey = if ($KeyFile) {
        if ([System.IO.Path]::IsPathRooted($KeyFile)) {
            [System.IO.Path]::GetFullPath($KeyFile)
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $KeyFile))
        }
    }
    else {
        Join-Path $KeysRoot "mcuboot-dev-rsa-2048.pem"
    }

    if (-not (Test-Path -LiteralPath $SigningKey -PathType Leaf)) {
        Invoke-Imgtool -Tool $ImgtoolCommand -Arguments @(
            "keygen",
            "-k", $SigningKey,
            "-t", "rsa-2048"
        )
        Write-Host "created $SigningKey"
        Write-Host "development MCUboot key only; do not use for production"
    }

    $ImgtoolForCMake = ([string] $ImgtoolCommand.FilePath).Replace("\", "/")
    $KeyForCMake = $SigningKey.Replace("\", "/")
    $SysbuildKeyConf = Join-Path $KeysRoot "mcuboot-nucleo-h563zi-sysbuild.conf"
    $SysbuildKeyConfContent = @(
        "# SPDX-License-Identifier: Apache-2.0",
        "# Generated by scripts/mcuboot-verify-nucleo-h563zi.ps1; ignored development config.",
        ('SB_CONFIG_BOOT_SIGNATURE_KEY_FILE="{0}"' -f $KeyForCMake)
    ) -join [Environment]::NewLine
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($SysbuildKeyConf, $SysbuildKeyConfContent + [Environment]::NewLine, $Utf8NoBom)
    $SysbuildKeyConfForCMake = $SysbuildKeyConf.Replace("\", "/")

    Invoke-Checked -FilePath $WestFile -Arguments ($WestPrefix + @(
        "build",
        "-p", "always",
        "-b", "nucleo_h563zi",
        "firmware/app",
        "-d", $BuildDir,
        "--sysbuild",
        "--",
        "-DFILE_SUFFIX=nucleo_h563zi",
        "-DIMGTOOL:FILEPATH=$ImgtoolForCMake",
        "-DSB_EXTRA_CONF_FILE=$SysbuildKeyConfForCMake"
    ))

    $BuildRoot = if ([System.IO.Path]::IsPathRooted($BuildDir)) {
        [System.IO.Path]::GetFullPath($BuildDir)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $BuildDir))
    }

    $BootloaderArtifacts = @(
        Join-Path $BuildRoot "mcuboot/zephyr/zephyr.elf"
        Join-Path $BuildRoot "mcuboot/zephyr/zephyr.hex"
        Join-Path $BuildRoot "mcuboot/zephyr/zephyr.map"
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }

    $SignedArtifacts = @(
        Get-ChildItem -Path $BuildRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^zephyr\.signed(\.confirmed)?\.(bin|hex)$' } |
            ForEach-Object { $_.FullName }
    )

    $MergedArtifacts = @(
        Join-Path $BuildRoot "merged.hex"
        Join-Path $BuildRoot "merged.bin"
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }

    if ($BootloaderArtifacts.Count -eq 0) {
        throw "No MCUboot bootloader artifacts were produced under $BuildRoot."
    }
    if ($SignedArtifacts.Count -eq 0) {
        throw "No signed application image artifacts were produced under $BuildRoot."
    }

    foreach ($Artifact in $BootloaderArtifacts) {
        Write-Host "MCUboot bootloader artifact: $Artifact"
    }
    foreach ($Artifact in $SignedArtifacts) {
        Write-Host "signed application artifact: $Artifact"
    }
    foreach ($Artifact in $MergedArtifacts) {
        Write-Host "merged flash artifact: $Artifact"
    }

    if ($Flash) {
        Invoke-Checked -FilePath $WestFile -Arguments ($WestPrefix + @(
            "flash",
            "-d", $BuildDir
        ))
        Write-Host "flash complete. Capture serial logs with: $Python -m serial.tools.miniterm $SerialPort $Baud"
        Write-Host "Expected logs include MCUboot boot output, AssureLoop controller demo booting, release product/version, and loop_summary."
    }
    else {
        Write-Host "flash skipped. Re-run with -Flash to program a connected ST NUCLEO-H563ZI."
        Write-Host "After flashing, capture serial logs with: $Python -m serial.tools.miniterm $SerialPort $Baud"
    }
}
finally {
    $env:PATH = $OriginalPath
    $env:ZEPHYR_SDK_INSTALL_DIR = $OriginalSdk
    $env:ZEPHYR_TOOLCHAIN_VARIANT = $OriginalToolchain
    Pop-Location
}
