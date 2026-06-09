# AssureLoop

[![CI](https://github.com/tendervault/assureloop/actions/workflows/ci.yml/badge.svg)](https://github.com/tendervault/assureloop/actions/workflows/ci.yml)

AssureLoop is an open-source secure release assurance platform for embedded controllers.

The project starts with a narrow, practical wedge: a Zephyr-based controller reference application plus tooling for reproducible releases, SBOM capture, release manifests, evidence bundles, and testable control-loop telemetry.

AssureLoop is **not** a new RTOS. It is an OS-adjacent platform that makes existing embedded stacks easier to ship, audit, update, and maintain.

## Project status

`v0.1-dev`: repository scaffold, firmware demo skeleton, release/evidence tooling, and CI skeleton.

Production readiness: **not yet**. The initial repo is meant for founder-led testing, Codex implementation work, and early design partner demos.

## CI validation

GitHub Actions runs on every pull request and every push to `main`. The CI
workflow checks:

- host-side Python tooling tests with `python -m unittest discover -s tests -v`
- Zephyr setup from this repository's `west.yml`
- simulator firmware build with `west build -p always -b qemu_cortex_m3 firmware/app`
- unsigned firmware evidence generation with Zephyr SPDX SBOM output
- release manifest schema validation with `python tools/validate_manifest.py --manifest dist/firmware-release/release-manifest.json`
- release manifest verification with `python tools/verify_release.py --manifest dist/firmware-release/release-manifest.json --base-dir .`
- end-to-end evidence bundle verification with `scripts/verify-firmware-evidence.sh`
- upload of the generated firmware evidence bundle as a GitHub Actions artifact

CI does not use private signing keys and does not commit generated `build/` or
`dist/` outputs.

## What this repo contains

```text
.
├── firmware/app/              Zephyr controller demo application
├── tools/                     Release manifest, signing, verification, trace, evidence tooling
├── evidence/                  Starter requirements, test matrix, and security checklist
├── docs/                      Architecture, threat model, roadmap, release process
├── scripts/                   Developer helper scripts
├── tests/                     Host-side tests for AssureLoop tooling
├── .github/workflows/         Initial CI workflows
└── west.yml                   Zephyr workspace manifest pinned to Zephyr v4.4.0
```

## First principles

1. Use Zephyr first; do not build a kernel.
2. Keep the core open and auditable.
3. Support one controller-class target path before broad board support.
4. Treat secure boot, signed updates, SBOMs, manifests, test evidence, and vulnerability response as first-class product features.
5. Make every release explainable: what was built, from which source, with which config, tested how, and signed by whom.

## Quick start: host-side tooling only

This path works without a Zephyr SDK or hardware.

```bash
python3 -m unittest discover -s tests -v
mkdir -p dist
python3 tools/generate_release_manifest.py \
  --product assureloop-controller-demo \
  --version 0.1.0-dev \
  --target host-demo \
  --artifact README.md:doc \
  --output dist/release-manifest.json
python3 tools/validate_manifest.py --manifest dist/release-manifest.json
python3 tools/verify_release.py --manifest dist/release-manifest.json --base-dir .
python3 tools/generate_trace_report.py \
  --input samples/logs/controller_boot.log \
  --output dist/trace-report.json
python3 tools/build_evidence_bundle.py \
  --manifest dist/release-manifest.json \
  --trace-report dist/trace-report.json \
  --evidence-dir evidence \
  --output-dir dist/evidence-bundle
```

## Windows PowerShell developer commands

Windows host-side validation does not require GNU make. From PowerShell, run:

```powershell
.\scripts\test-tools.ps1
.\scripts\evidence-demo.ps1
.\scripts\verify-demo.ps1
.\scripts\clean.ps1
```

The scripts use the Windows Python launcher (`py`) by default. To use another interpreter, pass `-Python`, for example:

```powershell
.\scripts\test-tools.ps1 -Python python
```

`.\scripts\evidence-demo.ps1` writes the demo manifest, trace report, evidence bundle directory, and `dist/evidence-bundle.tar.gz`. `.\scripts\verify-demo.ps1` also requires OpenSSL because it creates development keys and verifies a manifest signature; pass `-OpenSsl C:\path\to\openssl.exe` if OpenSSL is not on `PATH`.

## Quick start: Zephyr firmware build

AssureLoop is a west manifest repository. Keep the west top directory above the
AssureLoop checkout so Zephyr modules are installed as siblings of this repo,
not inside AssureLoop's own `tools/` directory.

### Windows PowerShell Zephyr setup

These steps follow the official Zephyr getting-started and SDK installation
flow, with the AssureLoop manifest pinned to Zephyr v4.4.0 and Zephyr SDK
1.0.1.

```powershell
winget install Kitware.CMake Ninja-build.Ninja oss-winget.gperf Python.Python.3.12 Git.Git oss-winget.dtc wget 7zip.7zip
```

Close and reopen PowerShell so the new tools are on `PATH`, then create the
workspace:

```powershell
mkdir $Env:USERPROFILE\assureloop-zephyr
cd $Env:USERPROFILE\assureloop-zephyr
git clone https://github.com/tendervault/assureloop.git assureloop

py -3.12 -m venv .venv
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\.venv\Scripts\Activate.ps1

pip install west
west init -l assureloop
west update
west zephyr-export
python -m pip install @((west packages pip) -split ' ')

cd zephyr
west sdk install -t arm-zephyr-eabi

cd ..\assureloop
west build -b qemu_cortex_m3 firmware/app
west build -t run
```

The QEMU run target is interactive. Use `Ctrl+A`, then `X`, to exit after the
demo prints `loop_summary`.

Expected runtime output includes:

```text
AssureLoop controller demo booting
release product=assureloop-controller-demo version=0.1.0-dev profile=dev git_sha=unknown
loop_config period_ms=100 iterations=20
loop iteration=1 ...
loop_summary iterations=20 ...
```

Reference docs:

- [Zephyr Getting Started Guide](https://docs.zephyrproject.org/latest/develop/getting_started/)
- [Zephyr SDK installation](https://docs.zephyrproject.org/latest/develop/toolchains/zephyr_sdk.html)

## Firmware evidence demo

After a successful simulator build:

```powershell
west build -b qemu_cortex_m3 firmware/app
.\scripts\firmware-evidence-demo.ps1
```

On Linux/macOS, use the Bash helper instead:

```bash
west build -b qemu_cortex_m3 firmware/app
bash scripts/firmware-evidence-demo.sh
```

This default firmware evidence demo does not generate an SBOM. It packages
available Zephyr build outputs from `build/zephyr`, including `zephyr.elf`,
`zephyr.bin`, `zephyr.map`, `.config`, and `zephyr.dts` when present. It uses
`samples/logs/qemu_controller_boot.log` as the QEMU trace sample and writes:

```text
dist/firmware-release/
├── release-manifest.json
├── trace-report.json
├── evidence-bundle/
└── evidence-bundle.tar.gz
```

The manifest records SHA256 hashes for the collected firmware build artifacts.
This is simulator evidence for development review, not a certification package.

To include Zephyr SPDX SBOM output in the same release evidence:

```powershell
west build -b qemu_cortex_m3 firmware/app
.\scripts\firmware-evidence-demo.ps1 -GenerateSbom
```

On Linux/macOS:

```bash
bash scripts/firmware-evidence-demo.sh --generate-sbom
```

With `-GenerateSbom`, the script runs `west spdx --build-dir build` against the
existing build directory. Zephyr writes generated SPDX files under:

```text
build/spdx/
├── app.spdx
├── zephyr.spdx
├── build.spdx
└── modules-deps.spdx
```

Those files are added to `release-manifest.json` as `sbom` artifacts and copied
into `dist/firmware-release/evidence-bundle/sbom/`.

To include Zephyr SPDX SBOM output and sign the release manifest with a local
development key:

```powershell
west build -b qemu_cortex_m3 firmware/app
.\scripts\firmware-evidence-demo.ps1 -GenerateSbom -Sign -OpenSsl 'C:\Program Files\Git\usr\bin\openssl.exe'
```

With `-Sign`, the script creates or reuses local development RSA keys under the
ignored `keys/` directory, signs `dist/firmware-release/release-manifest.json`,
writes `dist/firmware-release/release-manifest.sig`, and verifies the signature
before completing. The public development key is copied into the evidence bundle
under `signing/dev-rsa-public.pem`; the private key stays under `keys/` and must
not be committed. This development signature only detects manifest changes after
signing with that local key. It is not a production identity, secure key custody
model, OTA update signature, MCUboot integration, or certification claim.

To verify a signed firmware release manually:

```powershell
py tools\verify_release.py --manifest dist\firmware-release\release-manifest.json --base-dir . --signature dist\firmware-release\release-manifest.sig --public-key keys\dev-rsa-public.pem
```

Troubleshooting `west spdx`:

- Run `west build -b qemu_cortex_m3 firmware/app` first.
- Make sure `west`, CMake, Ninja, Zephyr Python packages, and Zephyr SDK 1.0.1
  are available in the active PowerShell environment.
- If `west spdx` reports a missing CMake API reply directory, rerun
  `.\scripts\firmware-evidence-demo.ps1 -GenerateSbom`; the script initializes
  SPDX metadata and refreshes the existing build before generating SPDX output.
- If signing fails with `OpenSSL was not found`, install OpenSSL, add it to
  `PATH`, or pass `-OpenSsl` with the full path to `openssl.exe`. Git for
  Windows commonly provides OpenSSL at
  `C:\Program Files\Git\usr\bin\openssl.exe`.
- Generated SBOM, build, and release output stays under ignored `build/` and
  `dist/` directories. Development private keys stay under ignored `keys/`.

To generate an SPDX SBOM manually after a Zephyr build:

```bash
west spdx --init -d build
west build -d build -b qemu_cortex_m3 firmware/app
west spdx -d build
```

## Release Manifest Schema

Release manifests are validated against
`schemas/release-manifest.schema.json`. That schema is part of AssureLoop's
evidence contract: it documents the fields downstream tools can rely on, such
as `product`, `version`, `target`, `generated_at`, artifact `path`, artifact
`kind`, and artifact `sha256`.

Validate a manifest from Windows PowerShell:

```powershell
py tools\validate_manifest.py --manifest dist\firmware-release\release-manifest.json
```

Validate a manifest from Bash:

```bash
python3 tools/validate_manifest.py --manifest dist/firmware-release/release-manifest.json
```

The validation step checks the manifest shape only. Use
`tools/verify_release.py` as well to verify referenced artifact hashes and an
optional manifest signature.

## Verify an Evidence Bundle

Use the evidence bundle verifier to check a generated bundle as a complete
release artifact. It accepts either the unpacked `evidence-bundle` directory or
the `evidence-bundle.tar.gz` archive.

Windows PowerShell:

```powershell
.\scripts\verify-firmware-evidence.ps1
py tools\verify_evidence_bundle.py --bundle dist\firmware-release\evidence-bundle.tar.gz
```

Bash:

```bash
bash scripts/verify-firmware-evidence.sh
python3 tools/verify_evidence_bundle.py --bundle dist/firmware-release/evidence-bundle.tar.gz
```

Signed bundle verification:

```powershell
.\scripts\verify-firmware-evidence.ps1 `
  -Bundle dist\firmware-release\evidence-bundle `
  -Signature dist\firmware-release\evidence-bundle\release-manifest.sig `
  -PublicKey dist\firmware-release\evidence-bundle\signing\dev-rsa-public.pem `
  -OpenSsl 'C:\Program Files\Git\usr\bin\openssl.exe'
```

The verifier checks that `release-manifest.json` exists and passes the schema,
all manifest artifacts are present and match their SHA256 hashes, `trace-report.json`
exists, starter evidence files are present, SBOM files are included when the
manifest lists SBOM artifacts, and optional manifest signature verification
passes when a signature and public key are supplied.

## Release workflow target

A useful AssureLoop release should eventually produce:

```text
dist/
├── firmware/
│   ├── zephyr.bin
│   ├── zephyr.hex
│   └── zephyr.elf
├── sbom/
│   ├── app.spdx
│   ├── zephyr.spdx
│   ├── build.spdx
│   └── modules-deps.spdx
├── release-manifest.json
├── release-manifest.sig
├── trace-report.json
└── evidence-bundle/
```

## Initial development roles

- Founder / tester: define customer pain, run the workflows, break the demos, report what feels confusing or unconvincing.
- Senior architect: keep scope narrow, protect the security/compliance model, define interfaces and acceptance criteria.
- Senior engineer / Codex: implement the next issues in `docs/codex-backlog.md` and keep commits small and reviewable.

## License

Apache-2.0. See `LICENSE`.
