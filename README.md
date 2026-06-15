# AssureLoop

[![CI](https://github.com/tendervault/assureloop/actions/workflows/ci.yml/badge.svg)](https://github.com/tendervault/assureloop/actions/workflows/ci.yml)

AssureLoop is open-source release assurance tooling for Zephyr-based embedded
firmware. It helps developers build a simulator firmware image, generate an
SBOM, create a release manifest, sign and verify evidence, package an update,
and exercise a local OTA lifecycle simulator before moving to physical hardware.

## What AssureLoop Is / Is Not

AssureLoop is:

- release assurance tooling for embedded firmware,
- a Zephyr-first simulator workflow,
- a way to produce and verify manifests, SBOMs, evidence bundles, signed image
  artifacts, update packages, and OTA simulator state,
- an alpha project for founder/testing and early design-partner feedback.

AssureLoop is not:

- a new RTOS,
- a production bootloader,
- a production OTA transport,
- a cloud update service,
- broad physical hardware board support,
- a production signing-key custody model,
- a safety or cybersecurity certification claim.

Current simulator target: `qemu_cortex_m3`.

## Run The Full Simulator Demo

The full demo requires a working Zephyr/west environment. Setup instructions are
in [docs/contributor-quickstart.md](docs/contributor-quickstart.md).

Windows PowerShell:

```powershell
.\scripts\full-demo.ps1
```

Bash:

```bash
bash scripts/full-demo.sh
```

The full demo runs host tests, checks the Zephyr simulator build, creates and
verifies a signed image, generates firmware evidence with SBOM, verifies the
evidence bundle, creates and verifies an update package, and runs the OTA
simulator.

Generated output stays under ignored paths such as `build/`, `build-*`,
`dist/`, and `keys/`.

## Quick Start Without Zephyr

Host-side tests and the README-based evidence demo do not require Zephyr or GNU
make on Windows:

```powershell
.\scripts\test-tools.ps1
.\scripts\evidence-demo.ps1
.\scripts\verify-demo.ps1
```

Use a specific Python interpreter when needed:

```powershell
.\scripts\test-tools.ps1 -Python python
```

Bash:

```bash
python3 -m unittest discover -s tests -v
make evidence-demo
make verify-demo
```

## Common Simulator Commands

Firmware build:

```bash
west build -b qemu_cortex_m3 firmware/app
```

Firmware run:

```bash
west build -t run
```

Firmware evidence with SBOM:

```powershell
.\scripts\firmware-evidence-demo.ps1 -GenerateSbom
```

```bash
bash scripts/firmware-evidence-demo.sh --generate-sbom
```

Evidence verification:

```powershell
.\scripts\verify-firmware-evidence.ps1
```

```bash
bash scripts/verify-firmware-evidence.sh
```

Signed image demo:

```powershell
.\scripts\signed-image-demo.ps1
```

```bash
bash scripts/signed-image-demo.sh
```

Update package demo:

```powershell
.\scripts\update-package-demo.ps1
```

```bash
bash scripts/update-package-demo.sh
```

OTA simulator demo:

```powershell
.\scripts\ota-sim-demo.ps1
py tools\simulate_ota.py status --state dist\ota-sim\state.json
```

```bash
bash scripts/ota-sim-demo.sh
python3 tools/simulate_ota.py status --state dist/ota-sim/state.json
```

Clean generated output on Windows:

```powershell
.\scripts\clean.ps1
```

## Documentation

- [Project status](docs/project-status.md)
- [Release assurance flow](docs/release-assurance-flow.md)
- [Hardware target selection](docs/hardware-target-selection.md)
- [ST NUCLEO-H563ZI bring-up](docs/nucleo-h563zi-bringup.md)
- [ST NUCLEO-H563ZI signed evidence](docs/nucleo-h563zi-signed-evidence.md)
- [ST NUCLEO-H563ZI MCUboot verification](docs/nucleo-h563zi-mcuboot-verification.md)
- [ST NUCLEO-H563ZI MCUboot update lifecycle](docs/nucleo-h563zi-mcuboot-update-lifecycle.md)
- [v0.3 hardware-alpha release readiness](docs/v0.3-hardware-alpha-release.md)
- [v0.3 hardware-alpha release notes](docs/releases/v0.3-hardware-alpha.md)
- [Contributor quickstart](docs/contributor-quickstart.md)
- [Release checklist](docs/release-checklist.md)
- [Architecture](docs/architecture.md)
- [Threat model](docs/threat-model.md)
- [Release process](docs/release-process.md)
- [Roadmap](docs/roadmap.md)

## CI Validation

GitHub Actions runs host tests, sets up Zephyr from `west.yml`, builds
`qemu_cortex_m3`, generates firmware evidence with SBOM, validates and verifies
the release manifest, verifies the evidence bundle, creates and verifies update
packages, builds the signed simulator image, and runs the OTA simulator.

CI uses direct steps instead of `scripts/full-demo.sh` so generated outputs can
be checked and uploaded as artifacts explicitly. CI does not use private signing
keys and does not commit generated `build/`, `dist/`, or `keys/` output.

## Repository Layout

```text
firmware/app/              Zephyr controller demo application
tools/                     Release, evidence, verification, package, and OTA simulator tooling
scripts/                   Windows PowerShell and Bash developer helpers
evidence/                  Starter requirements, tests, and security checklist evidence
schemas/                   Release manifest JSON Schema
samples/logs/              Sample controller/QEMU logs for trace reports
docs/                      Project status, architecture, quickstart, and release docs
tests/                     Host-side unit tests
.github/workflows/         CI workflow
west.yml                   Zephyr workspace manifest pinned to Zephyr v4.4.0
```

## Contributing

Use small, reviewable changes. Do not add physical board support, real OTA
transport, cloud services, or production certification/security claims unless a
specific issue scopes that work. See [CONTRIBUTING.md](CONTRIBUTING.md) and
[AGENTS.md](AGENTS.md).

## License

Apache-2.0. See [LICENSE](LICENSE).
