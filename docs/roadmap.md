# Roadmap

## Milestone 0: open-source skeleton

Status: started.

Acceptance criteria:

- public-ready repository structure,
- Apache-2.0 license,
- contribution/security docs,
- host-side tests,
- release manifest generation,
- trace report generation,
- evidence bundle generation,
- Zephyr app skeleton.

## Milestone 1: buildable controller demo

Acceptance criteria:

- `west build -b qemu_cortex_m3 firmware/app` passes,
- `west build -t run` emits structured AssureLoop logs,
- CI runs host tests and Zephyr build,
- release manifest includes firmware artifacts,
- founder can test without hardware.

## Milestone 2: SBOM and provenance

Acceptance criteria:

- `west spdx` runs in CI,
- generated SPDX files are copied into `dist/sbom`,
- manifest references SBOM files,
- build metadata includes Zephyr revision and toolchain hints,
- evidence bundle includes SBOM and manifest.

## Milestone 3: secure boot path

Acceptance criteria:

- MCUboot sysbuild configuration works on the chosen reference board,
- signed image boots,
- tampered image fails in a documented test,
- rollback/downgrade behavior is documented.

## Milestone 4: OTA simulator

Acceptance criteria:

- local OTA package format defined,
- signed package accepted by simulator,
- unsigned or modified package rejected,
- failed update rollback behavior simulated,
- logs produce trace evidence.

## Milestone 5: first real board

Candidate boards:

- STM32H7-class Nucleo board,
- i.MX RT-class EVK,
- another industrial-controller-relevant Cortex-M board with good Zephyr support.

Acceptance criteria:

- one board selected,
- board-specific build and flash instructions documented,
- loop timing measured on hardware,
- release/evidence workflow unchanged from QEMU path.
