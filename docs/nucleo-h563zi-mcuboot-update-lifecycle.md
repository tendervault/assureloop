# ST NUCLEO-H563ZI MCUboot Update Lifecycle

## Purpose

AL-016 investigates a local, hardware-backed MCUboot update lifecycle on the
ST NUCLEO-H563ZI. The goal is to stage a signed update image, boot it through
MCUboot, understand confirm and rollback behavior, and document downgrade and
tamper limits before adding any real OTA transport.

This is a local development investigation. It is not production OTA, not a
production secure-boot claim, and not a certification claim.

## Flash Layout

The AL-015 verified MCUboot layout for `nucleo_h563zi` is:

| Region | Address | Size | Notes |
|---|---:|---:|---|
| MCUboot bootloader | `0x08000000` | `0x10000` | Built by Zephyr sysbuild. |
| Primary slot | `0x08010000` | `0xf0000` | AssureLoop app runs from here. |
| Secondary slot | `0x08100000` | `0xf0000` | Local staged update slot. |
| Secondary image start | `0x08102000` | derived | Swap-using-offset starts after the first erase sector. |
| Storage | `0x081f0000` | `0x10000` | Reserved by the board DTS layout. |

AL-015 flashed MCUboot at `0x08000000` and a signed app at `0x08010000`.
Serial logs on COM4 showed `I: Starting bootloader`, MCUboot chainload, the
AssureLoop release line, and `loop_summary`.

## Commands

Build the lifecycle investigation artifacts without flashing:

```powershell
.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py
```

```bash
bash scripts/mcuboot-update-lifecycle-nucleo-h563zi.sh
```

The scripts build:

- `build-mcuboot-lifecycle-nucleo-h563zi-baseline`
- `build-mcuboot-lifecycle-nucleo-h563zi-update`

The baseline build uses Zephyr sysbuild with MCUboot in swap-using-offset mode.
The baseline app is version `0.1.0-dev`, has MCUboot image version `0.1.0+0`,
and requests a test upgrade from the secondary slot on boot.

The update build is an AssureLoop app version `0.1.1-dev` with MCUboot image
version `0.1.1+0`. Its signed hex is linked for the secondary slot offset. In
the tested build, `zephyr.signed.hex` covered `0x08102000` through
`0x0810d580`.

Optional hardware flashing:

```powershell
.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -Flash
```

```bash
bash scripts/mcuboot-update-lifecycle-nucleo-h563zi.sh --flash
```

For a confirm-path update, build the update app so it calls
`boot_write_img_confirmed()` on first boot:

```powershell
.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -ConfirmUpdate -Flash
```

```bash
bash scripts/mcuboot-update-lifecycle-nucleo-h563zi.sh --confirm-update --flash
```

Open serial at 115200 baud before or immediately after flashing:

```powershell
py -m serial.tools.miniterm COM4 115200
```

## Expected Logs

A successful staged test update should show MCUboot and AssureLoop markers such
as:

- `I: Starting bootloader`
- `I: Image index: 0, Swap type: test`
- `I: Starting swap using offset algorithm.`
- `I: Image 0 upgrade secondary slot -> primary slot`
- `AssureLoop controller demo booting`
- `release product=assureloop-controller-demo version=0.1.1-dev`
- `loop_summary iterations=20`

If the update app is built with `-ConfirmUpdate`, expected application logs also
include one of:

- `mcuboot_confirm status=confirmed`
- `mcuboot_confirm status=already_confirmed`

For an unconfirmed test update, the next reset should make MCUboot revert to
the previous image. Expected revert evidence includes MCUboot reporting a revert
swap type before the previous version boots.

## Confirm And Rollback Behavior

The lifecycle script supports two development behaviors:

- Default: the baseline requests a test upgrade. The update app does not
  confirm itself, so MCUboot should roll back on the next reset.
- `-ConfirmUpdate` or `--confirm-update`: the update app confirms itself on
  first boot, so MCUboot should keep it active after reset.

The baseline app's request-upgrade hook is intentionally build-time only. Normal
AssureLoop firmware builds do not request upgrades or write MCUboot trailer
state.

## Downgrade And Tamper Limits

The lifecycle MCUboot build keeps `CONFIG_MCUBOOT_DOWNGRADE_PREVENTION=y`.
The baseline image version is `0.1.0+0`; the update image version is `0.1.1+0`.
A lower-version staged image is expected to be rejected by MCUboot with a log
similar to `Image 0 in slot 1 erased due to downgrade prevention`.

Tampered update images are expected to fail MCUboot signature validation. The
current scripts do not deliberately flash a corrupted image, because this
milestone is focused on establishing the local staging path without destructive
or confusing board state.

## AL-016 Result

Status: partial, blocker documented.

Verified in AL-016:

- `.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py` builds the
  swap-using-offset MCUboot baseline.
- The baseline sysbuild config contains `SB_CONFIG_MCUBOOT_MODE_SWAP_USING_OFFSET=y`.
- The MCUboot config contains `CONFIG_BOOT_SWAP_USING_OFFSET=y` and
  `CONFIG_MCUBOOT_DOWNGRADE_PREVENTION=y`.
- The baseline app config contains
  `CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_ON_BOOT=y`.
- The secondary update app builds and produces `zephyr.signed.hex` at the
  `0x08102000` secondary-slot image start.

Not yet completed:

- A serial-captured hardware run showing the full swap, confirm, rollback, and
  downgrade/tamper rejection sequence.

Exact blocker:

- Direct local flashing can stage the secondary image, but the full rollback
  proof needs a controlled serial run and reset sequence. The default baseline
  requests an update on every boot, so an unconfirmed rollback demonstration
  must either erase/reflash the secondary slot after revert or use a dedicated
  primary test fixture that requests the upgrade only once.

Recommended next technical path:

- Add a dedicated dual-image sysbuild lifecycle fixture, mirroring Zephyr's
  `tests/boot/test_mcuboot` pattern, with a primary update-request app and a
  distinct secondary AssureLoop update image.
- Add mcumgr/SMP in a later milestone if we want a reusable transport-like path
  to upload images, mark them pending, query slot state, and avoid raw secondary
  slot flashing.

## Generated Files

The scripts create only ignored development outputs:

- `build-mcuboot-lifecycle-nucleo-h563zi-baseline/`
- `build-mcuboot-lifecycle-nucleo-h563zi-update/`
- `keys/mcuboot-dev-rsa-2048.pem`
- `keys/mcuboot-nucleo-h563zi-update-lifecycle-sysbuild.conf`
- `keys/mcuboot-nucleo-h563zi-lifecycle-baseline.conf`
- `keys/mcuboot-nucleo-h563zi-lifecycle-update.conf`

The private development key under `keys/` must not be committed or used for
production firmware.
