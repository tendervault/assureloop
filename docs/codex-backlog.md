# Codex backlog

## Issue AL-001: verify Zephyr app builds on qemu_cortex_m3

Role: senior engineer.

Goal: make `west build -b qemu_cortex_m3 firmware/app` pass on a clean workspace.

Tasks:

- Run the Zephyr build.
- Fix any CMake/Kconfig/board-name issues.
- Keep the app minimal.
- Update `README.md` if commands change.

Acceptance criteria:

- clean build passes,
- `west build -t run` emits boot identity and loop jitter logs,
- no unsupported hardware assumptions.

## Issue AL-002: wire firmware artifacts into release manifest

Goal: make `scripts/make_release_bundle.sh qemu_cortex_m3` produce a manifest referencing built firmware artifacts.

Acceptance criteria:

- release directory includes firmware artifacts when present,
- manifest verification passes,
- missing optional artifacts produce clear warnings, not silent success.

## Issue AL-003: add SPDX SBOM workflow

Goal: use Zephyr `west spdx` to generate SBOM documents and include them in the manifest/evidence bundle.

Acceptance criteria:

- `dist/sbom/*.spdx` files are captured,
- manifest records SBOM files,
- CI uploads SBOM artifacts,
- docs explain limitations.

## Issue AL-004: add MCUboot sysbuild for one supported board

Goal: create a signed-image path with MCUboot for one board.

Candidate: STM32H7-class Nucleo board, unless founder chooses a different available board.

Acceptance criteria:

- sysbuild builds bootloader + app,
- signed image is produced,
- docs explain keys and non-production limitations,
- tamper/downgrade tests are documented.

## Issue AL-005: OTA package simulator

Goal: create a host-side simulator for update package acceptance/rejection.

Acceptance criteria:

- valid signed package accepted,
- unsigned package rejected,
- modified artifact rejected,
- rollback state machine documented.

## Issue AL-006: evidence quality pass

Goal: make the evidence bundle look useful to a product security/compliance lead.

Acceptance criteria:

- requirements are specific and testable,
- each requirement maps to a test or explicit gap,
- security checklist separates implemented/planned/not-applicable,
- bundle has an index and reviewer notes.
