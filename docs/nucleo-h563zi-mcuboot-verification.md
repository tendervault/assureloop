# ST NUCLEO-H563ZI MCUboot Verification

## Purpose

AL-015 verifies that the ST NUCLEO-H563ZI can boot the AssureLoop controller
demo through MCUboot using a locally signed development image.

This is development boot verification only. It is not real OTA transport, not a
production signing-key custody model, not production secure boot certification,
and not a safety or cybersecurity certification claim.

## Prerequisites

- ST NUCLEO-H563ZI connected through the top ST-LINK USB-C port.
- Windows serial port observed as `COM4`.
- Zephyr SDK installed, for example `D:\zephyr-sdk`.
- `west`, CMake, Ninja, Python, pyserial, and MCUboot `imgtool.py`.
- STM32CubeProgrammer installed. The validated setup used
  STM32CubeProgrammer v2.22.0.

The scripts create or reuse the local development image-signing key under
ignored `keys/` paths. Do not use this key for production releases.

## Commands

Build only:

```powershell
.\scripts\mcuboot-verify-nucleo-h563zi.ps1 -Python py
```

Build and flash:

```powershell
.\scripts\mcuboot-verify-nucleo-h563zi.ps1 -Python py -Flash
```

Bash:

```bash
bash scripts/mcuboot-verify-nucleo-h563zi.sh
bash scripts/mcuboot-verify-nucleo-h563zi.sh --flash
```

The build uses:

```text
west build -p always -b nucleo_h563zi firmware/app -d build-mcuboot-nucleo-h563zi --sysbuild
```

with the `nucleo_h563zi` sysbuild file suffix, MCUboot enabled by
`firmware/app/sysbuild.conf`, and board-specific MCUboot image fragments under
`firmware/app/sysbuild/`.

## Build Artifacts

Expected MCUboot bootloader artifacts:

```text
build-mcuboot-nucleo-h563zi/mcuboot/zephyr/zephyr.elf
build-mcuboot-nucleo-h563zi/mcuboot/zephyr/zephyr.hex
build-mcuboot-nucleo-h563zi/mcuboot/zephyr/zephyr.map
```

Expected signed application artifacts:

```text
build-mcuboot-nucleo-h563zi/app/zephyr/zephyr.signed.bin
build-mcuboot-nucleo-h563zi/app/zephyr/zephyr.signed.hex
```

The verified build also generated `build-mcuboot-nucleo-h563zi/domains.yaml`.

## Flash Layout

The NUCLEO-H563ZI upstream Zephyr board DTS already provides an MCUboot-style
flash layout. AssureLoop uses that board layout instead of adding a custom board
partition map.

| Region | Address | Size | Purpose |
|---|---:|---:|---|
| `boot_partition` | `0x08000000` | 64 KiB | MCUboot bootloader |
| `slot0_partition` | `0x08010000` | 960 KiB | Primary signed application image |
| `slot1_partition` | `0x08100000` | 960 KiB | Secondary image slot for future update work |
| `storage_partition` | `0x081F0000` | 64 KiB | Storage partition reserved by board DTS |

The AL-015 flash run programmed:

```text
build-mcuboot-nucleo-h563zi/mcuboot/zephyr/zephyr.hex at 0x08000000
build-mcuboot-nucleo-h563zi/app/zephyr/zephyr.signed.hex at 0x08010000
```

## Serial Validation

Open the serial console after flashing:

```powershell
py -m serial.tools.miniterm COM4 115200
```

Expected MCUboot markers:

```text
*** Booting MCUboot
I: Starting bootloader
I: Image index: 0, Swap type: none
I: Bootloader chainload address offset: 0x10000
I: Image version: v0.0.0
I: Jumping to the first image slot
```

Expected AssureLoop app markers:

```text
AssureLoop controller demo booting
release product=assureloop-controller-demo version=0.1.0-dev profile=dev git_sha=unknown
loop_config period_ms=100 iterations=20
loop iteration=20
loop_summary iterations=20
AssureLoop controller demo complete
```

## Verified Result

The AL-015 hardware flash and serial capture succeeded on the connected
ST NUCLEO-H563ZI:

- `west build --sysbuild` produced MCUboot bootloader artifacts and signed
  application artifacts.
- MCUboot fit in the 64 KiB `boot_partition` with
  `CONFIG_BOOT_VALIDATE_SLOT0=y`.
- `west flash` used STM32CubeProgrammer v2.22.0 and programmed the bootloader
  and signed application at the expected addresses.
- Serial logs on `COM4` showed MCUboot starting, chainloading from offset
  `0x10000`, and then the AssureLoop application emitting the release log and
  `loop_summary`.

## Troubleshooting

- `west was not found`: activate the Zephyr Python environment, install west, or
  pass `-Python py` so the script can use `py -m west`.
- `Zephyr SDK was not found`: set `ZEPHYR_SDK_INSTALL_DIR`, for example
  `D:\zephyr-sdk`.
- `CMake was not found` or `Ninja was not found`: install the tools and add them
  to `PATH`. The PowerShell script also checks the common Windows install paths.
- `MCUboot imgtool was not found`: make sure the Zephyr workspace has the
  MCUboot module or set `IMGTOOL` to `bootloader/mcuboot/scripts/imgtool.py`.
- `STM32CubeProgrammer CLI was not found`: install STM32CubeProgrammer or add
  its `bin` directory to `PATH` before using `-Flash` or `--flash`.
- No serial output: confirm the top ST-LINK USB-C connection, check Device
  Manager for the active COM port, and rerun `py -m serial.tools.miniterm COM4
  115200` with the observed port.
- Kconfig warnings about the generated key config: remove the ignored
  `keys/mcuboot-nucleo-h563zi-sysbuild.conf` file and rerun the script. The
  PowerShell script writes this file as UTF-8 without BOM for Kconfig.

## Limitations

- The signing key is a local development key under ignored `keys/`.
- The verified path proves bootloader execution and signed-image chainload on
  one NUCLEO-H563ZI board.
- It does not demonstrate real OTA transport, field update policy, hardware
  rollback behavior, production anti-rollback fuses, or production secure boot
  certification.
- AL-016 is the planned next hardware milestone for local update/rollback
  behavior if practical.
