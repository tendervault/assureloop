# ST NUCLEO-H563ZI MCUboot Update Lifecycle

## Purpose

AL-016B turns the AL-016 MCUboot update lifecycle groundwork into a controlled
hardware validation sequence for the ST NUCLEO-H563ZI. The goal is to prove, or
cleanly block, local staged-update behavior: baseline boot, signed
secondary-slot image staging, MCUboot swap, update confirmation, rollback after
an unconfirmed test update, and downgrade or tamper limitations.

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
| Storage | `0x081f0000` | `0x10000` | Used by AL-016B for a small one-shot request marker. |

AL-015 flashed MCUboot at `0x08000000` and a signed app at `0x08010000`.
Serial logs on COM4 showed `I: Starting bootloader`, MCUboot chainload, the
AssureLoop release line, and `loop_summary`.

## Controlled Fixture

The AL-016B fixture builds two distinguishable images:

- Baseline image: release version `0.1.0-dev`, MCUboot image version
  `0.1.0+0`, and serial marker `lifecycle_role=baseline`.
- Update image: release version `0.1.1-dev`, MCUboot image version
  `0.1.1+0`, and serial marker `lifecycle_role=update-rollback` or
  `lifecycle_role=update-confirm`.

The baseline checks that the secondary slot contains a readable MCUboot image
header before it requests an upgrade. It then writes a 16-byte one-shot marker
to the first sector of the storage partition before rebooting. If the board
rolls back to the baseline image, the baseline sees
`mcuboot_update_request_once marker=present` and does not repeatedly request
the same staged update.

The one-shot marker is development-only state. Re-running the same staged test
from a board that already contains the marker requires erasing the storage
partition or reflashing a clean board image as part of the next controlled
hardware pass.

## Commands

Build the lifecycle investigation artifacts without flashing:

```powershell
.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py
```

```bash
PYTHON=py bash scripts/mcuboot-update-lifecycle-nucleo-h563zi.sh
```

The scripts build:

- `build-mcuboot-lifecycle-nucleo-h563zi-baseline`
- `build-mcuboot-lifecycle-nucleo-h563zi-update`

The update `zephyr.signed.hex` is linked for the secondary slot offset. In the
tested build, it starts at `0x08102000`.

Flash only MCUboot plus the baseline app:

```powershell
.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -FlashBaseline
```

Flash only the secondary-slot update image:

```powershell
.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -FlashUpdate
```

Flash the staged update first, then MCUboot plus the baseline app:

```powershell
.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -NoConfirmUpdate -Flash
```

Build and flash the confirm-path update:

```powershell
.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -ConfirmUpdate -Flash
```

Bash equivalents:

```bash
PYTHON=py bash scripts/mcuboot-update-lifecycle-nucleo-h563zi.sh --flash-baseline
PYTHON=py bash scripts/mcuboot-update-lifecycle-nucleo-h563zi.sh --flash-update
PYTHON=py bash scripts/mcuboot-update-lifecycle-nucleo-h563zi.sh --no-confirm-update --flash
PYTHON=py bash scripts/mcuboot-update-lifecycle-nucleo-h563zi.sh --confirm-update --flash
```

For repeatable hardware validation after a prior lifecycle run, erase the
device first so the storage-partition one-shot marker is cleared:

```powershell
STM32_Programmer_CLI -c port=SWD mode=UR reset=HWrst -e all
```

Open serial at 115200 baud before or immediately after flashing:

```powershell
py -m serial.tools.miniterm COM4 115200
```

## Controlled Test Matrix

| Test | Command | Expected evidence |
|---|---|---|
| Build-only investigation | `.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py` | Baseline and update builds pass; update signed hex starts at `0x08102000`; no board state changes. |
| Baseline boot without staged update | `.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -FlashBaseline` | `lifecycle_role=baseline`, `mcuboot_update_request status=secondary_invalid`, release version `0.1.0-dev`, and `loop_summary`. |
| Staged rollback path | `.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -NoConfirmUpdate -Flash` | Baseline stages the secondary image once; MCUboot reports test swap; update logs version `0.1.1-dev` and `lifecycle_role=update-rollback`; after reset, MCUboot reverts and baseline logs `marker=present` without re-requesting. Captured in `samples/logs/nucleo_h563zi_mcuboot_update_rollback.log`. |
| Confirm path | `STM32_Programmer_CLI -c port=SWD mode=UR reset=HWrst -e all`, then `.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -ConfirmUpdate -Flash` | Update logs `lifecycle_role=update-confirm` and `mcuboot_confirm status=confirmed`; after reset, MCUboot reports `image_ok=0x1` and the update logs `mcuboot_confirm status=already_confirmed`. Captured in `samples/logs/nucleo_h563zi_mcuboot_update_confirm.log`. |
| Downgrade path | Build a lower `-UpdateImageVersion` than the installed image and stage it. | MCUboot downgrade prevention should reject the lower-version secondary image. This is not yet serial-proven for AL-016B. |
| Tamper path | Deliberately corrupt the staged signed update image before flashing. | MCUboot signature validation should reject the update. This is not yet scripted to avoid confusing persistent board state. |

## Expected Logs

Baseline boot without a valid staged update should include:

- `I: Starting bootloader`
- `AssureLoop controller demo booting`
- `release product=assureloop-controller-demo version=0.1.0-dev`
- `lifecycle_role=baseline`
- `mcuboot_update_request status=secondary_invalid`
- `loop_summary iterations=20`

Staged update boot should include:

- `lifecycle_role=baseline`
- `mcuboot_update_request secondary_version=0.1.1+0`
- `mcuboot_update_request mode=test rc=0`
- `mcuboot_update_request_once marker=written`
- `mcuboot_update_request rebooting`
- `I: Image index: 0, Swap type: test`
- `I: Starting swap using offset algorithm.`
- `I: Image 0 upgrade secondary slot -> primary slot`
- `release product=assureloop-controller-demo version=0.1.1-dev`
- `lifecycle_role=update-rollback`
- `loop_summary iterations=20`

Confirmed update boot should additionally include:

- `lifecycle_role=update-confirm`
- `mcuboot_confirm status=confirmed`

Rollback evidence should include MCUboot reporting a revert swap on the next
reset, then the baseline release line and:

- `lifecycle_role=baseline`
- `mcuboot_update_request_once marker=present`
- `mcuboot_update_request status=already_requested`

## What Has Been Proven

Verified in AL-016B build/investigation runs:

- The baseline sysbuild uses MCUboot swap-using-offset mode.
- The baseline app logs `lifecycle_role=baseline`.
- The baseline app validates the secondary image header before requesting an
  update.
- The baseline app records a one-shot marker in `storage_partition` to avoid
  repeatedly requesting the same staged image after rollback.
- The update app logs `lifecycle_role=update-rollback` by default.
- The `-ConfirmUpdate` path builds an update app that calls
  `boot_write_img_confirmed()`.
- The secondary update image builds as `zephyr.signed.hex` for `0x08102000`.

Verified on physical ST NUCLEO-H563ZI hardware with serial capture:

- A directly programmed secondary-slot image is detected by MCUboot as a test
  update.
- MCUboot performs a swap-using-offset update from the secondary slot.
- The `0.1.1-dev` update image boots and logs `lifecycle_role=update-rollback`
  when it is not configured to confirm itself.
- An unconfirmed update reverts on the next reset, and the `0.1.0-dev`
  baseline boots again.
- The baseline sees `mcuboot_update_request_once marker=present` after rollback
  and avoids repeatedly requesting the same staged image.
- The `0.1.1-dev` confirm-path update logs `mcuboot_confirm status=confirmed`.
- After reset, MCUboot reports the primary image as confirmed with
  `image_ok=0x1`, and the update app logs
  `mcuboot_confirm status=already_confirmed`.

These behaviors are still not proven by captured hardware serial logs in this
repository:

- Downgrade rejection.
- Tamper rejection.

The committed sample logs are cleaned extracts from real hardware captures:

- `samples/logs/nucleo_h563zi_mcuboot_update_confirm.log`
- `samples/logs/nucleo_h563zi_mcuboot_update_rollback.log`

## Known Limitations And Blockers

- Serial capture is still manual. The recommended capture command is
  `py -m serial.tools.miniterm COM4 115200`.
- The one-shot marker uses the storage partition and persists across resets.
  A repeated validation run may need a storage partition erase step or a
  full-device erase before flashing the next staged test.
- The baseline's first post-flash app logs can be missed when serial capture
  starts during reset or flashing. The rollback capture still proves the marker
  was present because the reverted baseline logs `marker=present` and
  `already_requested`.
- The current scripts do not intentionally stage a corrupted image. That should
  be added as a separate controlled test to avoid confusing persistent board
  state.
- Downgrade validation needs a controlled prior installed version and a lower
  staged image version. The build knobs exist, but the hardware rejection log is
  not captured yet.
- mcumgr/SMP is not required for this direct-flash investigation. It remains a
  likely later milestone for a cleaner upload, pending, and slot-query workflow.

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
