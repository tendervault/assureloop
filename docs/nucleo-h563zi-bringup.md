# ST NUCLEO-H563ZI Bring-Up

AL-013 records the first successful physical-board bring-up for AssureLoop. It
keeps the project simulator-first while proving that the existing controller
demo also builds, flashes, and logs correctly on one selected development
board.

This is a development-board validation path. It is not OTA support, not a cloud
update service, not production secure boot, and not a certification claim.

## Hardware

Required hardware:

- ST NUCLEO-H563ZI development board.
- USB-C data cable connected to the top ST-LINK USB-C port.
- Windows development machine.

Use the top ST-LINK USB-C port for flashing and serial logging. The user USB-C
connector is not the validated AL-013 connection path.

Validated board details from manual flash output:

- Board: NUCLEO-H563ZI.
- Device: STM32H56x/573.
- CPU: Cortex-M33.
- Voltage: 3.28V.
- Programmed image: `zephyr.hex` at `0x08000000`.
- Application start: successful.

## Windows Tooling

Validated project path:

```powershell
cd D:\assureloop
```

Prerequisites:

- Python launcher `py`.
- west installed in the active Zephyr Python environment.
- CMake on `PATH`.
- Ninja on `PATH`.
- 7-Zip available for Zephyr SDK archive extraction when bootstrapping.
- `pyserial` for `serial.tools.miniterm`.
- `jsonschema` for AssureLoop host-side validation tools.
- Zephyr SDK installed. Example path: `D:\zephyr-sdk`.
- STM32CubeProgrammer installed and on `PATH` or discoverable by Zephyr.

Validated STM32CubeProgrammer version:

```text
STM32CubeProgrammer v2.22.0
```

Useful environment examples:

```powershell
$env:ZEPHYR_SDK_INSTALL_DIR = 'D:\zephyr-sdk'
$env:ZEPHYR_TOOLCHAIN_VARIANT = 'zephyr'
```

Activate the same Zephyr workspace and Python environment used for simulator
builds before running the hardware commands.

## Build

Zephyr board target:

```text
nucleo_h563zi
```

Validated build command:

```powershell
py -m west build -p always -b nucleo_h563zi firmware/app -d build-nucleo-h563zi
```

PowerShell helper:

```powershell
.\scripts\hardware-build-nucleo-h563zi.ps1
```

Bash helper:

```bash
bash scripts/hardware-build-nucleo-h563zi.sh
```

Both helper scripts build `firmware/app` for `nucleo_h563zi` into
`build-nucleo-h563zi`. They do not flash unless explicitly requested.

## Flash

Validated flash command:

```powershell
py -m west flash -d build-nucleo-h563zi
```

PowerShell helper with flashing enabled:

```powershell
.\scripts\hardware-build-nucleo-h563zi.ps1 -Flash
```

Bash helper with flashing enabled:

```bash
bash scripts/hardware-build-nucleo-h563zi.sh --flash
```

Expected flash markers include:

- `Board       : NUCLEO-H563ZI`
- `Device name : STM32H56x/573`
- `CPU        : Cortex-M33`
- `Voltage    : 3.28V`
- `Download verified successfully`
- `Application is running, Please Hold on...`

Exact STM32CubeProgrammer wording can vary slightly by version.

## Serial Console

Validated Windows serial port:

```text
COM4
```

Validated serial command:

```powershell
py -m serial.tools.miniterm COM4 115200
```

Serial automation is intentionally not part of AL-013. Keep the console manual
until the serial port naming and reset behavior are reliable across developer
machines.

Expected boot log markers:

```text
AssureLoop controller demo booting
release product=assureloop-controller-demo version=0.1.0-dev profile=dev git_sha=unknown
loop_config period_ms=100 iterations=20
loop iteration=1
loop iteration=20
loop_summary iterations=20 min_jitter_ns=100000 max_jitter_ns=100000 avg_abs_jitter_ns=100000
AssureLoop controller demo complete
```

The validated manual run emitted `loop iteration=1` through
`loop iteration=20`.

## Successful AL-013 Validation

Manual validation completed with:

```powershell
py -m west build -p always -b nucleo_h563zi firmware/app -d build-nucleo-h563zi
py -m west flash -d build-nucleo-h563zi
py -m serial.tools.miniterm COM4 115200
```

The board was connected through the top ST-LINK USB-C port. Flashing used
STM32CubeProgrammer v2.22.0 and programmed `zephyr.hex` at `0x08000000`.
The application started successfully, and COM4 serial logs included the
AssureLoop boot marker, release identity, loop configuration, twenty loop
iterations, loop summary, and completion marker.

## Troubleshooting

Missing west:

- Activate the Zephyr Python environment for the workspace.
- Try `py -m west --version`.
- Install west into the active environment with `py -m pip install west`.
- Pass an explicit tool path with `.\scripts\hardware-build-nucleo-h563zi.ps1 -West west`.

Missing CMake:

- Install CMake and add it to `PATH`.
- Confirm with `cmake --version`.
- Restart the terminal after installer changes.

Missing Ninja:

- Install Ninja and add it to `PATH`.
- Confirm with `ninja --version`.
- If Ninja came from a Python environment, activate that environment first.

Missing `jsonschema`:

- Install it in the Python environment used by AssureLoop tools:
  `py -m pip install jsonschema`.
- This affects host-side manifest validation, not the Zephyr compile itself.

Zephyr SDK not found:

- Confirm the SDK exists at the expected path, for example `D:\zephyr-sdk`.
- Set `$env:ZEPHYR_SDK_INSTALL_DIR = 'D:\zephyr-sdk'`.
- Set `$env:ZEPHYR_TOOLCHAIN_VARIANT = 'zephyr'` when needed.
- Re-run `west zephyr-export` if the workspace was recently created.

7-Zip extraction issues:

- Install 7-Zip and confirm `7z` is on `PATH`.
- Re-run SDK extraction from a short path without spaces if archive extraction
  fails.
- Delete only the incomplete SDK extraction directory before retrying.

STM32CubeProgrammer not found:

- Install STM32CubeProgrammer and include its `bin` directory on `PATH`.
- Confirm `STM32_Programmer_CLI --version` works.
- Reconnect the board through the top ST-LINK USB-C port.
- Update ST-LINK firmware if STM32CubeProgrammer detects the probe but flashing
  fails.

Serial port issues:

- Check Windows Device Manager for the current ST-LINK virtual COM port.
- COM4 was the validated AL-013 port, but another machine may assign a
  different COM number.
- Close other terminal programs before opening miniterm.
- Use `115200` baud.
- Press reset on the board after opening miniterm if the boot log has already
  scrolled by.
