# ST NUCLEO-H563ZI MCUboot Update Lifecycle

## Purpose

AL-017 closes the hardware lifecycle trust gaps left after AL-016B. This
MCUboot update lifecycle document records the controlled local validation for
the ST NUCLEO-H563ZI: staged update, confirm, rollback, tampered-update
rejection, and downgrade-update rejection.

This is a direct-flash hardware validation path. It is not production OTA, not
a network transport, not a production secure-boot claim, and not a
certification claim.

## Flash Layout

The verified MCUboot layout for `nucleo_h563zi` is:

| Region | Address | Size | Notes |
|---|---:|---:|---|
| MCUboot bootloader | `0x08000000` | `0x10000` | Built by Zephyr sysbuild. |
| Primary slot | `0x08010000` | `0xf0000` | AssureLoop app runs from here. |
| Secondary slot | `0x08100000` | `0xf0000` | Local staged update slot. |
| Secondary image start | `0x08102000` | derived | Swap-using-offset starts after the first erase sector. |
| Storage | `0x081f0000` | `0x10000` | Used for a small one-shot request marker. |

The scripts use COM4 at 115200 baud for manual serial capture.

## Controlled Fixture

The lifecycle fixture builds distinguishable images:

- Baseline image: serial marker `lifecycle_role=baseline`.
- Normal update image: `0.1.1+0`, `lifecycle_role=update-rollback` or
  `lifecycle_role=update-confirm`.
- Tampered update image: a copy of `zephyr.signed.hex` with one payload byte
  changed and the Intel HEX checksum recomputed. This keeps the file flashable
  while invalidating the MCUboot signature/hash check. The build role is
  `lifecycle_role=update-tampered`, but a successful rejection means that app
  role never boots.
- Downgrade update image: a `0.1.0+0` secondary image staged against a
  `0.1.1+0` primary image. The build role is
  `lifecycle_role=update-downgrade`, but a successful rejection means that app
  role never boots.

The baseline checks that the secondary slot contains a readable MCUboot image
header before it requests an upgrade. It then writes a 16-byte one-shot marker
to the first sector of the storage partition before rebooting. If the board
rolls back or rejects the staged update, the baseline sees
`mcuboot_update_request_once marker=present` and does not repeatedly request
the same staged image.

## Commands

Build the lifecycle investigation artifacts without flashing:

```powershell
.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py
```

```bash
PYTHON=py bash scripts/mcuboot-update-lifecycle-nucleo-h563zi.sh
```

Flash only MCUboot plus the baseline app:

```powershell
.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -FlashBaseline
```

Flash the staged update first, then MCUboot plus the baseline app:

```powershell
.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -NoConfirmUpdate -Flash
```

Build and flash the confirm-path update:

```powershell
.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -ConfirmUpdate -EraseBeforeFlash -Flash
```

Build and flash a tampered secondary update:

```powershell
.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -TamperUpdate -EraseBeforeFlash -Flash
```

Build and flash a lower-version secondary update:

```powershell
.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -DowngradeUpdate -EraseBeforeFlash -Flash
```

Bash equivalents:

```bash
PYTHON=py bash scripts/mcuboot-update-lifecycle-nucleo-h563zi.sh --no-confirm-update --flash
PYTHON=py bash scripts/mcuboot-update-lifecycle-nucleo-h563zi.sh --confirm-update --erase-before-flash --flash
PYTHON=py bash scripts/mcuboot-update-lifecycle-nucleo-h563zi.sh --tamper-update --erase-before-flash --flash
PYTHON=py bash scripts/mcuboot-update-lifecycle-nucleo-h563zi.sh --downgrade-update --erase-before-flash --flash
```

Open serial at 115200 baud before or immediately after flashing:

```powershell
py -m serial.tools.miniterm COM4 115200
```

## Controlled Test Matrix

| Test | Command | Hardware result |
|---|---|---|
| Build-only investigation | `.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py` | Baseline and update builds pass; update signed hex starts at `0x08102000`; no board state changes. |
| Staged rollback path | `.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -NoConfirmUpdate -Flash` | MCUboot reports test swap; update logs `lifecycle_role=update-rollback`; after reset, MCUboot reverts and baseline logs `marker=present`. Captured in `samples/logs/nucleo_h563zi_mcuboot_update_rollback.log`. |
| Confirm path | `.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -ConfirmUpdate -EraseBeforeFlash -Flash` | Update logs `mcuboot_confirm status=confirmed`; after reset, MCUboot reports `image_ok=0x1` and the update logs `already_confirmed`. Captured in `samples/logs/nucleo_h563zi_mcuboot_update_confirm.log`. |
| Tamper path | `.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -TamperUpdate -EraseBeforeFlash -Flash` | MCUboot reports `Image in the secondary slot is not valid!` and keeps booting the baseline. Captured in `samples/logs/nucleo_h563zi_mcuboot_tamper_reject.log`. |
| Downgrade path | `.\scripts\mcuboot-update-lifecycle-nucleo-h563zi.ps1 -Python py -DowngradeUpdate -EraseBeforeFlash -Flash` | MCUboot reports `Image 0 in slot 1 erased due to downgrade prevention` and keeps booting the primary image. Captured in `samples/logs/nucleo_h563zi_mcuboot_downgrade_reject.log`. |

## Expected Logs

Staged update boot should include:

- `I: Image index: 0, Swap type: test`
- `I: Starting swap using offset algorithm.`
- `release product=assureloop-controller-demo version=0.1.1-dev`
- `lifecycle_role=update-rollback`
- `loop_summary iterations=20`

Confirmed update boot should additionally include:

- `lifecycle_role=update-confirm`
- `mcuboot_confirm status=confirmed`
- after reset, `image_ok=0x1`
- after reset, `mcuboot_confirm status=already_confirmed`

Rollback evidence should include:

- `I: Image index: 0, Swap type: revert`
- `lifecycle_role=baseline`
- `mcuboot_update_request_once marker=present`
- `mcuboot_update_request status=already_requested`

Tamper rejection should include:

- `I: Image index: 0, Swap type: test`
- `E: Image in the secondary slot is not valid!`
- baseline `loop_summary`

Downgrade rejection should include:

- `I: Image index: 0, Swap type: test`
- `I: Image 0 in slot 1 erased due to downgrade prevention`
- `I: Image version: v0.1.1`
- baseline `loop_summary`

## Hardware-Proven

Verified on physical ST NUCLEO-H563ZI hardware with serial capture:

- MCUboot boots and chainloads a signed AssureLoop primary image.
- A directly programmed secondary-slot image is detected as a test update.
- MCUboot performs a swap-using-offset update from the secondary slot.
- An unconfirmed update reverts on the next reset.
- A confirmed update remains active after reset.
- A tampered secondary image is rejected by MCUboot validation.
- A lower-version secondary image is rejected by MCUboot downgrade prevention.
- The one-shot marker prevents repeated baseline requests after rejection or
  rollback.

Committed sample logs are cleaned extracts from real hardware captures:

- `samples/logs/nucleo_h563zi_mcuboot_update_confirm.log`
- `samples/logs/nucleo_h563zi_mcuboot_update_rollback.log`
- `samples/logs/nucleo_h563zi_mcuboot_tamper_reject.log`
- `samples/logs/nucleo_h563zi_mcuboot_downgrade_reject.log`

## Simulator-Only Or Future Work

These items are still not hardware-proven release features:

- Real network OTA transport.
- mcumgr/SMP upload and slot-query workflow.
- Production signing-key custody.
- Hardware-backed rollback counters or anti-rollback fuses.
- Broad board support beyond ST NUCLEO-H563ZI.
- Safety or cybersecurity certification evidence.

Simulator/package tests continue to cover update package tamper, downgrade, and
target mismatch checks independently from the direct-flash hardware path.

## Recovery

To return the board to a clean known state after a lifecycle test:

```powershell
STM32_Programmer_CLI -c port=SWD mode=UR reset=HWrst -e all
.\scripts\mcuboot-verify-nucleo-h563zi.ps1 -Python py -Flash
```

To run the normal non-MCUboot board demo again:

```powershell
.\scripts\hardware-build-nucleo-h563zi.ps1 -Python py -Flash
```

If serial output stops:

- Confirm the board is connected through the top ST-LINK USB-C port.
- Reopen COM4 at 115200 baud.
- Make sure no other terminal owns COM4.
- Mass erase and reflash a known-good image if MCUboot reports no bootable
  image.

## Known Limitations

- Serial capture is still manual.
- The one-shot marker uses the storage partition and persists across resets.
  Repeated validation runs should use `-EraseBeforeFlash`.
- The downgrade test proves MCUboot image-version downgrade prevention. The
  sysbuild primary image logs the default app release string
  `version=0.1.0-dev` even when its MCUboot image header is `v0.1.1`; the
  bootloader rejection is based on the MCUboot image header, not that app log.
- The tamper test mutates one signed image byte. It proves MCUboot rejects that
  corrupted secondary image, not every possible corruption pattern.
- Development keys under `keys/` are ignored local keys and must not be used
  for production firmware.
