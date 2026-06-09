# Hardware Target Selection

Assessed on 2026-06-09. Board availability, distributor pricing, and Zephyr
board status can change, so re-check the linked vendor and Zephyr pages before
purchase.

This document selects the first physical development board for AssureLoop's
hardware-backed secure release workflow. It is a planning milestone only. It
does not add board support, real OTA transport, production secure boot, or
certification claims.

## Recommendation

Recommended first board for AL-013: `nucleo_h563zi` / ST NUCLEO-H563ZI.

Backup board: `nrf52840dk/nrf52840` / Nordic nRF52840 DK.

The ST NUCLEO-H563ZI is the best first hardware target because it keeps the
next milestone focused on basic Zephyr logging while still leaving a credible
path to signed images, MCUboot partitions, board-targeted evidence, and local
rollback experiments. In the pinned Zephyr tree used by AssureLoop, the board
already has fixed flash partitions for `mcuboot`, `image-0`, `image-1`, and
storage. It also has an onboard ST-LINK/V3EC debugger, virtual COM port,
Ethernet, FDCAN, Arduino/ST Zio/ST morpho expansion, 2 MB flash, and 640 KB
SRAM. That is a better match for an industrial-controller-style release
assurance demo than a wireless-only board, while still being common enough for
outside developers to reproduce.

The nRF52840 DK is the backup because it has very mature Zephyr and MCUboot
ecosystem coverage, a built-in SEGGER J-Link debugger, stable serial logging,
and strong community support. It is slightly less aligned with the
industrial-controller demo story because it is primarily a wireless development
kit and has less flash headroom, but it is an excellent fallback if H563ZI
procurement or flashing friction blocks AL-013.

## Selection Criteria

The first board should:

- be maintained in upstream Zephyr,
- build a simple AssureLoop logging app with minimal board-specific changes,
- support an MCUboot-compatible flash partition layout,
- produce signed image artifacts with Zephyr/imgtool,
- allow a later local update and rollback demonstration,
- have an integrated debug probe and serial logging path,
- be available at normal development-kit cost from public channels,
- have good official documentation and community examples,
- feel like an embedded controller target rather than a Linux appliance,
- be workable from Windows PowerShell without GNU make.

## Candidate Evaluation

| Candidate category | Zephyr support maturity | MCUboot, flash, signed images | Update/rollback potential | Availability and cost | Docs and community | Industrial demo fit | Windows friendliness | Decision |
|---|---|---|---|---|---|---|---|---|
| STM32 Nucleo / Discovery class, specifically ST NUCLEO-H563ZI | Strong. Zephyr marks `nucleo_h563zi` maintained, and the pinned Zephyr tree has board sources. | Strong. The board DTS includes `mcuboot`, `image-0`, `image-1`, and storage partitions. Zephyr/imgtool signing should be usable before full bootloader verification. | Strong enough for AL-016 planning. Dual slots and storage support a later MCUboot swap/rollback investigation. | Favorable. ST describes Nucleo-144 as affordable and flexible, and the H563ZI page is active/in volume production. Re-check distributor stock before buying. | Strong official ST and Zephyr docs. STM32 ecosystem is broad. | Best. Cortex-M33, TrustZone-capable MCU, Ethernet, FDCAN, GPIO, timers, and expansion headers fit controller-style demos. | Good, with one caveat. Onboard ST-LINK/VCOM is friendly, but Zephyr's default flash runner expects STM32CubeProgrammer unless another runner is selected. | Choose first. |
| Nordic nRF52/nRF53 development board, specifically nRF52840 DK as backup | Very strong for nRF52840. nRF5340 also has strong support but adds dual-core complexity. | Strong. nRF52840 Zephyr DTS includes a partition file with `mcuboot`, `image-0`, `image-1`, and storage; the board also exposes MCUboot button/LED aliases. | Strong for simple update semantics, especially with nRF52840. nRF53 is more complex because of app/network cores. | Favorable for developer kits. Common and broadly documented; re-check current stock. | Excellent Nordic, Zephyr, and community support. | Medium. Great embedded board, but wireless/IoT oriented rather than industrial-controller oriented. | Good. Built-in SEGGER J-Link, nRF tooling, USB serial, and VS Code/nRF Connect tooling are Windows friendly. | Backup. |
| NXP i.MX RT class, specifically MIMXRT1060-EVK | Good Zephyr support, but more moving parts than needed for first hardware. | Good. The qspi/hyperflash Zephyr DTS files include MCUboot, image slots, and storage in external flash. | Good in principle. External flash gives headroom, but boot and flash setup have more failure modes. | Moderate to higher development-kit cost than simpler MCU boards. Availability is generally good, but check current distributors. | Good NXP and Zephyr docs. | Strong for high-performance controller demos: Cortex-M7, Ethernet, CAN, external flash, and many peripherals. | Medium. OpenSDA/DAPLink and MCUXpresso tooling are usable on Windows, but external flash boot configuration is more complex. | Do not choose first; revisit when AssureLoop needs a higher-performance target. |
| Do not choose yet: custom hardware or complex Linux SBC | Custom hardware has no guaranteed upstream Zephyr board support; Linux SBCs are usually not Zephyr MCU targets. | Custom boards require new DTS, partitions, flashing, and boot validation; Linux SBCs are the wrong boot/update abstraction for this milestone. | Too much undefined behavior for first hardware milestone. | Custom hardware has procurement and bring-up risk; SBCs may be cheap but do not test the MCUboot/Zephyr path we need. | Custom docs are internal only; Linux community is large but not aligned with this release-assurance path. | Poor for AL-013. Custom hardware adds board support too early; SBCs look like Linux appliances, not embedded controllers. | Poor to medium, depending on device. | Do not choose yet. |

## Why H563ZI Is Best For AL-013

AL-013 should prove a narrow thing: AssureLoop can boot on one real Zephyr board
and emit the same style of release/logging evidence that the simulator emits.
The H563ZI minimizes unrelated work:

- no custom board definition is needed at the start,
- serial logging can use the onboard virtual COM port,
- flashing can use documented Zephyr runners,
- the existing fixed partitions make later MCUboot work plausible,
- the controller-style peripherals support credible future demos,
- the board has enough flash for bootloader, primary image, secondary image,
  and storage without immediately optimizing the application.

The first AL-013 build should stay simple:

```bash
west build -b nucleo_h563zi firmware/app
```

Expected AL-013 scope is only build, flash, serial log capture, and evidence
metadata update for the selected board target. MCUboot bootloader execution,
signed-image evidence, and rollback remain later milestones.

## Board-Readiness Checklist

- [ ] Zephyr sample builds for `nucleo_h563zi`, starting with
      `samples/hello_world` or `samples/basic/blinky`.
- [ ] AssureLoop firmware app builds for `nucleo_h563zi`.
- [ ] Basic serial logging works over the onboard virtual COM port.
- [ ] Manual flashing path is documented for STM32CubeProgrammer and one backup
      runner if practical.
- [ ] Signed image build works for the board application image.
- [ ] MCUboot bootloader build works for the board.
- [ ] Flash partitions are confirmed from generated devicetree and map output.
- [ ] Evidence bundle includes the physical board target and artifact hashes.
- [ ] Update package can select the board signed image as payload.
- [ ] Rollback plan is documented before attempting a real board rollback demo.
- [ ] Limitations are documented: local development keys only, no production
      secure boot claim, no OTA transport claim, no certification claim.

## Future Milestone Plan

- AL-013: bring up ST NUCLEO-H563ZI with basic Zephyr logging.
- AL-014: generate signed image evidence for ST NUCLEO-H563ZI.
- AL-015: verify MCUboot boot behavior on ST NUCLEO-H563ZI.
- AL-016: demonstrate local update and rollback behavior on ST NUCLEO-H563ZI
  if practical.

## Sources

- Zephyr NUCLEO-H563ZI board documentation:
  https://docs.zephyrproject.org/latest/boards/st/nucleo_h563zi/doc/index.html
- ST NUCLEO-H563ZI product page:
  https://www.st.com/en/evaluation-tools/nucleo-h563zi.html
- Zephyr nRF52840 DK board documentation:
  https://docs.zephyrproject.org/latest/boards/nordic/nrf52840dk/doc/index.html
- Nordic nRF52840 DK product page:
  https://www.nordicsemi.com/Products/Development-hardware/nRF52840-DK
- Zephyr nRF5340 DK board documentation:
  https://docs.zephyrproject.org/latest/boards/nordic/nrf5340dk/doc/index.html
- Zephyr MIMXRT1060-EVK board documentation:
  https://docs.zephyrproject.org/latest/boards/nxp/mimxrt1060_evk/doc/index.html
- NXP MIMXRT1060-EVK product documentation:
  https://www.nxp.com/design/design-center/development-boards-and-designs/MIMXRT1060-EVKB
