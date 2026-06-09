# Project Status

## Current Summary

AssureLoop is open-source release assurance tooling for Zephyr-based embedded
firmware. The current alpha workflow can build a simulator firmware demo,
generate release evidence, verify artifacts, package a simulator update, and
exercise a local OTA lifecycle state machine.

The project is simulator-first. The reference firmware target is
`qemu_cortex_m3`, and the current signed-image path creates an
MCUboot-compatible signed application image for development verification.

## What AssureLoop Currently Does

- Builds a small Zephyr controller demo for `qemu_cortex_m3`.
- Emits structured boot, release, loop configuration, loop iteration, and loop
  summary logs.
- Generates release manifests with artifact SHA256 hashes.
- Validates release manifests against a JSON Schema.
- Generates trace reports from controller log samples.
- Builds evidence bundles as directories and `.tar.gz` archives.
- Verifies evidence bundles end to end.
- Generates Zephyr SPDX SBOM output with `west spdx`.
- Signs and verifies release manifests with local development keys.
- Produces MCUboot-compatible signed image artifacts where Zephyr supports them.
- Packages simulator update payloads and verifies downgrade, target, and tamper
  checks.
- Simulates local OTA lifecycle states: staged, installed, confirmed, rollback,
  rejected downgrade, rejected tamper, and rejected target mismatch.
- Documents the first recommended physical board target and board-readiness
  plan without adding hardware support yet.
- Runs host tests, Zephyr build, evidence generation, package verification, and
  OTA simulator checks in GitHub Actions.

## Simulator-First Scope

These pieces are intentionally simulator-first:

- `qemu_cortex_m3` firmware build and run path.
- Zephyr SPDX/SBOM capture from the simulator build directory.
- MCUboot/imgtool application image signing using a local development key.
- Update package verification using local files.
- OTA lifecycle simulation using `dist/ota-sim/state.json`.

The simulator path is meant to prove release mechanics before physical board
support is added.

## Not Production-Ready Yet

AssureLoop is not production-ready. In particular, it is not:

- a new RTOS,
- a production secure boot implementation,
- a production OTA transport,
- a cloud update service,
- a hardware board port,
- a safety certification package,
- a cybersecurity certification claim,
- a production signing-key custody model.

Development private keys are generated locally under ignored `keys/` paths and
must not be reused for production releases.

## Completed Milestones

| Milestone | Status | Summary |
|---|---:|---|
| AL-000 | Done | Repository scaffold, host-side release manifest, trace report, evidence bundle, signing, verification, and starter docs. |
| AL-001 | Done | Zephyr controller demo builds and runs on `qemu_cortex_m3` with structured runtime logs. |
| AL-002 | Done | Firmware evidence demo packages real Zephyr build artifacts into a release manifest and evidence bundle. |
| AL-003 | Done | Optional Zephyr SPDX/SBOM generation is included in firmware evidence bundles. |
| AL-004 | Done | Firmware release manifests can be signed and verified with local development keys. |
| AL-005 | Done | GitHub Actions validates host tools, Zephyr qemu build, firmware evidence, and package generation. |
| AL-006 | Done | Release manifests have a JSON Schema and validation tool. |
| AL-007 | Done | Evidence bundles can be verified as complete release artifacts. |
| AL-008 | Done | Simulator-first update packages are created and verified with payload safety checks. |
| AL-009 | Done | MCUboot-compatible signed image workflow produces and verifies signed simulator image artifacts. |
| AL-010 | Done | Local OTA simulator models stage, install, confirm, rollback, and rejection states. |
| AL-011 | Done | Public alpha docs, full-demo wrappers, contributor quickstart, release checklist, and issue templates make the project easier to evaluate. |
| AL-012 | Done | First hardware target selection recommends ST NUCLEO-H563ZI, names nRF52840 DK as backup, and defines board-readiness milestones. |

## Next Planned Milestones

- AL-013: bring up ST NUCLEO-H563ZI with basic Zephyr logging.
- AL-014: generate signed image evidence for ST NUCLEO-H563ZI.
- AL-015: verify MCUboot boot behavior on ST NUCLEO-H563ZI.
- AL-016: demonstrate local update and rollback behavior on ST NUCLEO-H563ZI
  if practical.
- Improve evidence quality and reviewer-facing evidence bundle content.
- Define a production signing threat model and key custody policy before any
  production signing claims.
- Add real OTA transport only after local package acceptance and rollback
  behavior are well specified.

## Definition Of Done For Alpha Work

A change is complete when it has working code or clearly marked documentation,
a test or manual verification path, updated docs when behavior changes, and no
unsupported certification or production security claims.
