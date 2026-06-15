# SPDX-License-Identifier: Apache-2.0
#
# Usage: .\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 [-FlashBaseline] [-FlashUpdate] [-ConfirmUpdate|-NoConfirmUpdate] [-TamperUpdate|-DowngradeUpdate] [-EraseBeforeFlash]
# Builds a local MCUboot update-lifecycle investigation for ST NUCLEO-H563ZI.

[CmdletBinding()]
param(
    [string] $Python = $(if ($env:PYTHON) { $env:PYTHON } else { "py" }),
    [string] $West = $(if ($env:WEST) { $env:WEST } else { "west" }),
    [string] $Imgtool = $(if ($env:IMGTOOL) { $env:IMGTOOL } else { "imgtool" }),
    [string] $BaselineBuildDir = $(if ($env:MCUBOOT_NUCLEO_H563ZI_BASELINE_BUILD_DIR) { $env:MCUBOOT_NUCLEO_H563ZI_BASELINE_BUILD_DIR } else { "build-mcuboot-lifecycle-nucleo-h563zi-baseline" }),
    [string] $UpdateBuildDir = $(if ($env:MCUBOOT_NUCLEO_H563ZI_UPDATE_BUILD_DIR) { $env:MCUBOOT_NUCLEO_H563ZI_UPDATE_BUILD_DIR } else { "build-mcuboot-lifecycle-nucleo-h563zi-update" }),
    [string] $KeysDir = $(if ($env:ASSURELOOP_KEYS_DIR) { $env:ASSURELOOP_KEYS_DIR } else { "keys" }),
    [string] $KeyFile = $(if ($env:ASSURELOOP_MCUBOOT_KEY) { $env:ASSURELOOP_MCUBOOT_KEY } else { "" }),
    [string] $ZephyrSdk = $(if ($env:ZEPHYR_SDK_INSTALL_DIR) { $env:ZEPHYR_SDK_INSTALL_DIR } elseif (Test-Path -LiteralPath "D:\zephyr-sdk" -PathType Container) { "D:\zephyr-sdk" } else { "" }),
    [string] $SerialPort = $(if ($env:ASSURELOOP_NUCLEO_SERIAL_PORT) { $env:ASSURELOOP_NUCLEO_SERIAL_PORT } else { "COM4" }),
    [int] $Baud = $(if ($env:ASSURELOOP_NUCLEO_BAUD) { [int] $env:ASSURELOOP_NUCLEO_BAUD } else { 115200 }),
    [string] $BaselineVersion = "0.1.0-dev",
    [string] $UpdateVersion = "0.1.1-dev",
    [string] $BaselineImageVersion = "0.1.0+0",
    [string] $UpdateImageVersion = "0.1.1+0",
    [switch] $ConfirmUpdate,
    [switch] $NoConfirmUpdate,
    [switch] $PermanentUpgrade,
    [switch] $TamperUpdate,
    [switch] $DowngradeUpdate,
    [switch] $EraseBeforeFlash,
    [switch] $FlashBaseline,
    [switch] $FlashUpdate,
    [switch] $Flash
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$OriginalSdk = $env:ZEPHYR_SDK_INSTALL_DIR
$OriginalToolchain = $env:ZEPHYR_TOOLCHAIN_VARIANT
$OriginalPath = $env:PATH
$ShouldFlashBaseline = [bool]($Flash -or $FlashBaseline)
$ShouldFlashUpdate = [bool]($Flash -or $FlashUpdate)

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
            UsePython = $Command.EndsWith(".py")
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

function ConvertTo-CMakePath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    return ([System.IO.Path]::GetFullPath($Path)).Replace("\", "/")
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Content
    )

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content + [Environment]::NewLine, $Utf8NoBom)
}

function New-TamperedIntelHex {
    param(
        [Parameter(Mandatory = $true)]
        [string] $InputPath,

        [Parameter(Mandatory = $true)]
        [string] $OutputPath,

        [uint32] $MinimumAddress = 0x08102400
    )

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $Lines = [System.IO.File]::ReadAllLines($InputPath)
    $ExtendedAddress = [uint32] 0
    $Tampered = $false
    $OutputLines = foreach ($Line in $Lines) {
        if ($Line.Length -lt 11 -or -not $Line.StartsWith(":")) {
            $Line
            continue
        }

        $ByteCount = [Convert]::ToInt32($Line.Substring(1, 2), 16)
        $Address = [Convert]::ToInt32($Line.Substring(3, 4), 16)
        $RecordType = [Convert]::ToInt32($Line.Substring(7, 2), 16)
        $Data = $Line.Substring(9, $ByteCount * 2)

        if ($RecordType -eq 4 -and $ByteCount -eq 2) {
            $ExtendedAddress = [uint32] ([Convert]::ToInt32($Data, 16) -shl 16)
            $Line
            continue
        }

        if (-not $Tampered -and $RecordType -eq 0 -and $ByteCount -gt 0) {
            $AbsoluteAddress = $ExtendedAddress + [uint32] $Address
            if ($AbsoluteAddress -ge $MinimumAddress) {
                $Bytes = [byte[]]::new($ByteCount)
                for ($Index = 0; $Index -lt $ByteCount; $Index++) {
                    $Bytes[$Index] = [Convert]::ToByte($Data.Substring($Index * 2, 2), 16)
                }

                $Bytes[0] = [byte] ($Bytes[0] -bxor 0x01)
                $ChecksumSum = $ByteCount + (($Address -shr 8) -band 0xff) + ($Address -band 0xff) + $RecordType
                foreach ($Byte in $Bytes) {
                    $ChecksumSum += $Byte
                }
                $Checksum = (-$ChecksumSum) -band 0xff
                $DataHex = ($Bytes | ForEach-Object { $_.ToString("X2") }) -join ""
                $Tampered = $true
                ":{0:X2}{1:X4}{2:X2}{3}{4:X2}" -f $ByteCount, $Address, $RecordType, $DataHex, $Checksum
                continue
            }
        }

        $Line
    }

    if (-not $Tampered) {
        throw "Could not find an Intel HEX data record at or after 0x{0:X8} to tamper in $InputPath." -f $MinimumAddress
    }

    [System.IO.File]::WriteAllLines($OutputPath, $OutputLines, $Utf8NoBom)
}

Push-Location -LiteralPath $RepoRoot
try {
    if ($ConfirmUpdate -and $NoConfirmUpdate) {
        throw "Use either -ConfirmUpdate or -NoConfirmUpdate, not both."
    }
    if ($TamperUpdate -and $DowngradeUpdate) {
        throw "Use either -TamperUpdate or -DowngradeUpdate, not both."
    }
    if (($TamperUpdate -or $DowngradeUpdate) -and $ConfirmUpdate) {
        throw "Negative update validation uses a non-confirming update image. Omit -ConfirmUpdate."
    }
    if ($DowngradeUpdate) {
        if (-not $PSBoundParameters.ContainsKey("BaselineVersion")) {
            $BaselineVersion = "0.1.1-dev"
        }
        if (-not $PSBoundParameters.ContainsKey("BaselineImageVersion")) {
            $BaselineImageVersion = "0.1.1+0"
        }
        if (-not $PSBoundParameters.ContainsKey("UpdateVersion")) {
            $UpdateVersion = "0.1.0-dev"
        }
        if (-not $PSBoundParameters.ContainsKey("UpdateImageVersion")) {
            $UpdateImageVersion = "0.1.0+0"
        }
    }

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

    if ($ShouldFlashBaseline -or $ShouldFlashUpdate) {
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

    $KeyForCMake = ConvertTo-CMakePath -Path $SigningKey
    $ImgtoolForCMake = ConvertTo-CMakePath -Path ([string] $ImgtoolCommand.FilePath)
    $BaselineRole = "baseline"
    $UpdateRole = if ($DowngradeUpdate) {
        "update-downgrade"
    }
    elseif ($TamperUpdate) {
        "update-tampered"
    }
    elseif ($ConfirmUpdate) {
        "update-confirm"
    }
    else {
        "update-rollback"
    }

    $SysbuildConf = Join-Path $KeysRoot "mcuboot-nucleo-h563zi-update-lifecycle-sysbuild.conf"
    Write-Utf8NoBom -Path $SysbuildConf -Content (@(
        "# SPDX-License-Identifier: Apache-2.0",
        "# Generated by scripts/mcuboot-update-lifecycle-nucleo-h563zi.ps1; ignored development config.",
        ('SB_CONFIG_BOOT_SIGNATURE_KEY_FILE="{0}"' -f $KeyForCMake),
        "SB_CONFIG_MCUBOOT_MODE_OVERWRITE_ONLY=n",
        "SB_CONFIG_MCUBOOT_MODE_SWAP_USING_OFFSET=y"
    ) -join [Environment]::NewLine)

    $BaselineAppConf = Join-Path $KeysRoot "mcuboot-nucleo-h563zi-lifecycle-baseline.conf"
    $BaselineAppLines = @(
        "# SPDX-License-Identifier: Apache-2.0",
        "# Generated baseline app config for local MCUboot update lifecycle investigation.",
        "CONFIG_FLASH=y",
        "CONFIG_FLASH_PAGE_LAYOUT=y",
        "CONFIG_FLASH_MAP=y",
        "CONFIG_STREAM_FLASH=y",
        "CONFIG_IMG_MANAGER=y",
        "CONFIG_MCUBOOT_IMG_MANAGER=y",
        "CONFIG_REBOOT=y",
        "CONFIG_BUILD_OUTPUT_BIN=y",
        "CONFIG_BUILD_OUTPUT_HEX=y",
        ('CONFIG_ASSURELOOP_LIFECYCLE_ROLE="{0}"' -f $BaselineRole),
        "CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_ON_BOOT=y",
        "CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_ONCE=y",
        ('CONFIG_MCUBOOT_IMGTOOL_SIGN_VERSION="{0}"' -f $BaselineImageVersion)
    )
    if ($PermanentUpgrade) {
        $BaselineAppLines += "CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_PERMANENT=y"
    }
    Write-Utf8NoBom -Path $BaselineAppConf -Content ($BaselineAppLines -join [Environment]::NewLine)

    $UpdateAppConf = Join-Path $KeysRoot "mcuboot-nucleo-h563zi-lifecycle-update.conf"
    $UpdateAppLines = @(
        "# SPDX-License-Identifier: Apache-2.0",
        "# Generated update app config for local MCUboot update lifecycle investigation.",
        "CONFIG_BOOTLOADER_MCUBOOT=y",
        "CONFIG_FLASH=y",
        "CONFIG_FLASH_PAGE_LAYOUT=y",
        "CONFIG_FLASH_MAP=y",
        "CONFIG_STREAM_FLASH=y",
        "CONFIG_IMG_MANAGER=y",
        "CONFIG_MCUBOOT_IMG_MANAGER=y",
        "CONFIG_BUILD_OUTPUT_BIN=y",
        "CONFIG_BUILD_OUTPUT_HEX=y",
        "CONFIG_MCUBOOT_BOOTLOADER_MODE_OVERWRITE_ONLY=n",
        "CONFIG_MCUBOOT_BOOTLOADER_MODE_SWAP_USING_OFFSET=y",
        "CONFIG_MCUBOOT_BOOTLOADER_NO_DOWNGRADE=y",
        ('CONFIG_ASSURELOOP_LIFECYCLE_ROLE="{0}"' -f $UpdateRole),
        "CONFIG_ASSURELOOP_NUCLEO_H563ZI_SECONDARY_SLOT_UPDATE_IMAGE=y",
        ('CONFIG_MCUBOOT_SIGNATURE_KEY_FILE="{0}"' -f $KeyForCMake),
        ('CONFIG_MCUBOOT_IMGTOOL_SIGN_VERSION="{0}"' -f $UpdateImageVersion)
    )
    if ($ConfirmUpdate) {
        $UpdateAppLines += "CONFIG_ASSURELOOP_MCUBOOT_CONFIRM_ON_BOOT=y"
    }
    Write-Utf8NoBom -Path $UpdateAppConf -Content ($UpdateAppLines -join [Environment]::NewLine)

    $SysbuildConfForCMake = ConvertTo-CMakePath -Path $SysbuildConf
    $BaselineAppConfForCMake = ConvertTo-CMakePath -Path $BaselineAppConf
    $UpdateAppConfForCMake = ConvertTo-CMakePath -Path $UpdateAppConf

    Invoke-Checked -FilePath $WestFile -Arguments ($WestPrefix + @(
        "build",
        "-p", "always",
        "-b", "nucleo_h563zi",
        "firmware/app",
        "-d", $BaselineBuildDir,
        "--sysbuild",
        "--",
        "-DFILE_SUFFIX=nucleo_h563zi",
        "-DIMGTOOL:FILEPATH=$ImgtoolForCMake",
        "-DSB_EXTRA_CONF_FILE=$SysbuildConfForCMake",
        "-DEXTRA_CONF_FILE=$BaselineAppConfForCMake",
        "-DASSURELOOP_VERSION=$BaselineVersion"
    ))

    Invoke-Checked -FilePath $WestFile -Arguments ($WestPrefix + @(
        "build",
        "-p", "always",
        "-b", "nucleo_h563zi",
        "firmware/app",
        "-d", $UpdateBuildDir,
        "--",
        "-DIMGTOOL:FILEPATH=$ImgtoolForCMake",
        "-DEXTRA_CONF_FILE=$UpdateAppConfForCMake",
        "-DASSURELOOP_VERSION=$UpdateVersion"
    ))

    $BaselineRoot = if ([System.IO.Path]::IsPathRooted($BaselineBuildDir)) {
        [System.IO.Path]::GetFullPath($BaselineBuildDir)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $BaselineBuildDir))
    }
    $UpdateRoot = if ([System.IO.Path]::IsPathRooted($UpdateBuildDir)) {
        [System.IO.Path]::GetFullPath($UpdateBuildDir)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $UpdateBuildDir))
    }

    $BootloaderArtifacts = @(
        Join-Path $BaselineRoot "mcuboot/zephyr/zephyr.elf"
        Join-Path $BaselineRoot "mcuboot/zephyr/zephyr.hex"
        Join-Path $BaselineRoot "mcuboot/zephyr/zephyr.map"
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }

    $BaselineArtifacts = @(
        Get-ChildItem -Path (Join-Path $BaselineRoot "app/zephyr") -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^zephyr(\.signed)?\.(bin|hex|elf|map)$' } |
            ForEach-Object { $_.FullName }
    )

    $UpdateArtifacts = @(
        Get-ChildItem -Path (Join-Path $UpdateRoot "zephyr") -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^zephyr(\.signed)?\.(bin|hex|elf|map)$' } |
            ForEach-Object { $_.FullName }
    )

    $UpdateSignedHex = Join-Path $UpdateRoot "zephyr/zephyr.signed.hex"
    $FlashUpdateHex = $UpdateSignedHex
    $TamperedUpdateHex = $null

    if ($BootloaderArtifacts.Count -eq 0) {
        throw "No MCUboot bootloader artifacts were produced under $BaselineRoot."
    }
    if (-not (Test-Path -LiteralPath $UpdateSignedHex -PathType Leaf)) {
        throw "No secondary-slot signed update hex was produced at $UpdateSignedHex."
    }
    if ($TamperUpdate) {
        $TamperedUpdateHex = Join-Path $UpdateRoot "zephyr/zephyr.signed.tampered.hex"
        New-TamperedIntelHex -InputPath $UpdateSignedHex -OutputPath $TamperedUpdateHex
        $FlashUpdateHex = $TamperedUpdateHex
        $UpdateArtifacts += $TamperedUpdateHex
    }

    Write-Host "MCUboot mode: swap using offset"
    Write-Host "bootloader address: 0x08000000"
    Write-Host "primary slot address: 0x08010000"
    Write-Host "secondary slot address: 0x08100000"
    Write-Host "secondary update image start: 0x08102000"
    Write-Host "baseline release version: $BaselineVersion image version: $BaselineImageVersion"
    Write-Host "update release version: $UpdateVersion image version: $UpdateImageVersion"
    Write-Host "baseline lifecycle role: $BaselineRole"
    Write-Host "update lifecycle role: $UpdateRole"
    Write-Host "baseline upgrade request mode: $(if ($PermanentUpgrade) { 'permanent' } else { 'test' })"
    Write-Host "baseline upgrade request guard: one-shot storage marker"
    Write-Host "update auto-confirm: $(if ($ConfirmUpdate) { 'enabled' } else { 'disabled' })"
    Write-Host "negative update mode: $(if ($TamperUpdate) { 'tamper' } elseif ($DowngradeUpdate) { 'downgrade' } else { 'none' })"

    foreach ($Artifact in $BootloaderArtifacts) {
        Write-Host "MCUboot bootloader artifact: $Artifact"
    }
    foreach ($Artifact in $BaselineArtifacts) {
        Write-Host "baseline artifact: $Artifact"
    }
    foreach ($Artifact in $UpdateArtifacts) {
        Write-Host "secondary-slot update artifact: $Artifact"
    }

    if ($ShouldFlashBaseline -or $ShouldFlashUpdate) {
        if ($EraseBeforeFlash) {
            Invoke-Checked -FilePath "STM32_Programmer_CLI" -Arguments @(
                "-c", "port=SWD", "mode=UR", "reset=HWrst",
                "-e", "all"
            )
            Write-Host "device mass erase completed before lifecycle flash."
        }

        if ($ShouldFlashUpdate) {
            Invoke-Checked -FilePath "STM32_Programmer_CLI" -Arguments @(
                "-c", "port=SWD", "mode=UR", "reset=HWrst",
                "-d", $FlashUpdateHex,
                "-v",
                "-rst"
            )
            Write-Host "secondary update image flashed from $FlashUpdateHex"
        }

        if ($ShouldFlashBaseline) {
            Invoke-Checked -FilePath $WestFile -Arguments ($WestPrefix + @(
                "flash",
                "-d", $BaselineBuildDir
            ))
            Write-Host "baseline bootloader and primary app flashed."
        }

        if ($ShouldFlashBaseline -and $ShouldFlashUpdate) {
            Write-Host "the staged update was programmed before baseline flash so the baseline's first boot can request it once."
        }
        Write-Host "Capture serial logs with: $Python -m serial.tools.miniterm $SerialPort $Baud"
        if ($TamperUpdate) {
            Write-Host "Expected tamper logs include MCUboot validation rejection for the secondary image and baseline version=$BaselineVersion continuing to boot."
        }
        elseif ($DowngradeUpdate) {
            Write-Host "Expected downgrade logs include MCUboot downgrade prevention for secondary version=$UpdateImageVersion and baseline version=$BaselineVersion continuing to boot."
        }
        else {
            Write-Host "Expected lifecycle logs include lifecycle_role=$BaselineRole, mcuboot_update_request_once marker=written, MCUboot swap output, release version=$UpdateVersion, lifecycle_role=$UpdateRole, and loop_summary."
        }
    }
    else {
        Write-Host "flash skipped. Re-run with -FlashBaseline, -FlashUpdate, or -Flash to program a connected ST NUCLEO-H563ZI."
        Write-Host "With -Flash, the script flashes the secondary update image before the baseline image."
        if ($TamperUpdate) {
            Write-Host "tampered secondary update image: $TamperedUpdateHex"
        }
        Write-Host "Capture serial logs with: $Python -m serial.tools.miniterm $SerialPort $Baud"
    }
}
finally {
    $env:PATH = $OriginalPath
    $env:ZEPHYR_SDK_INSTALL_DIR = $OriginalSdk
    $env:ZEPHYR_TOOLCHAIN_VARIANT = $OriginalToolchain
    Pop-Location
}
