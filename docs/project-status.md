# Project Status

## Current Summary

AssureLoop is open-source release assurance tooling for Zephyr-based embedded
firmware. The current alpha workflow can build a simulator firmware demo,
generate release evidence, verify artifacts, package a simulator update, and
exercise a local OTA lifecycle state machine. The project also has a static
public landing page for `assureloop.dev` that links developers to the GitHub
repository, v0.3 hardware-alpha release, docs, and sample artifacts.

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
- Produces ST NUCLEO-H563ZI board-specific signed image evidence and update
  packages for development verification.
- Verifies ST NUCLEO-H563ZI MCUboot bootloader execution and signed application
  chainload using local development keys.
- Builds ST NUCLEO-H563ZI MCUboot update-lifecycle investigation artifacts,
  including a swap-using-offset baseline, a secondary-slot signed update image,
  distinguishable baseline/update serial roles, and a one-shot request marker.
- Verifies ST NUCLEO-H563ZI hardware negative-update behavior for tampered
  secondary images and lower-version secondary images.
- Prepares local v0.3 hardware-alpha release output under ignored `dist/`
  paths with release notes, sample logs, sample development evidence, update
  package output, verification summaries, and checksums.
- Publishes a static public landing page from `site/` for `assureloop.dev`
  through GitHub Pages, with explicit non-production limitations.
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

The first physical validation target is ST NUCLEO-H563ZI. AL-013 manually
validated build, flash, and COM4 serial logging for that board, but broad
hardware support and hardware-backed update/rollback remain future work.
AL-014 adds board-specific signed image evidence and package verification for
that target using local development keys. AL-015 verifies MCUboot bootloader
execution on the physical board and confirms the AssureLoop signed application
boots after MCUboot. AL-016 adds the board-specific update-lifecycle build and
staging path. AL-016B adds a controlled dual-image fixture with a secondary-slot
validity check and one-shot baseline request marker. Physical NUCLEO-H563ZI
serial evidence proves staged swap, confirmed update persistence, unconfirmed
rollback, tampered-update rejection, and downgrade-update rejection for the
local direct-flash lifecycle path.

## Not Production-Ready Yet

AssureLoop is not production-ready. In particular, it is not:

- a new RTOS,
- a production secure boot implementation,
- a production OTA transport,
- a cloud update service,
- broad hardware board support,
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
| AL-013 | Done | ST NUCLEO-H563ZI manually builds, flashes, starts successfully, and emits the expected COM4 controller logs. |
| AL-014 | Done | ST NUCLEO-H563ZI signed-image evidence produces SBOM-backed manifests, evidence bundles, and update packages with development keys. |
| AL-015 | Done | ST NUCLEO-H563ZI boots through MCUboot with a locally signed development image; serial logs show MCUboot chainload and AssureLoop `loop_summary`. |
| AL-016 | Partial | ST NUCLEO-H563ZI update-lifecycle artifacts build: swap-using-offset MCUboot baseline, secondary-slot signed update image at `0x08102000`, and documented confirm/rollback blockers. |
| AL-016B | Done | Controlled NUCLEO-H563ZI MCUboot lifecycle fixture distinguishes baseline/update images, validates the staged secondary image before requesting upgrade, proves staged swap, confirm persistence, and unconfirmed rollback with real serial evidence, and prevents repeated baseline requests with a storage-partition one-shot marker. |
| AL-017 | Done | Hardware negative-update validation proves MCUboot rejects a tampered secondary image and a lower-version secondary image on ST NUCLEO-H563ZI; v0.3 hardware-alpha release readiness is documented. |
| AL-018 | Done | v0.3 hardware-alpha release notes and local release preparation scripts assemble safe sample/dev release materials, verification summaries, and checksums under ignored `dist/releases/v0.3-hardware-alpha/`. |
| AL-019 | Done | Public static landing page for `assureloop.dev` documents AssureLoop's release-assurance scope, v0.3 hardware-alpha proof points, supported ST NUCLEO-H563ZI board, resource links, domain setup, and non-production limitations. |

## Next Planned Milestones

- Decide whether mcumgr/SMP should become the next local update transport
  milestone after v0.3 hardware-alpha release preparation.
- Keep the public site aligned with future alpha release notes and hardware
  evidence without adding backend services or analytics.
- Improve evidence quality and reviewer-facing evidence bundle content.
- Define a production signing threat model and key custody policy before any
  production signing claims.
- Add real OTA transport only after local package acceptance and rollback
  behavior are well specified.

## Definition Of Done For Alpha Work

A change is complete when it has working code or clearly marked documentation,
a test or manual verification path, updated docs when behavior changes, and no
unsupported certification or production security claims.
