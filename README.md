# AssureLoop

AssureLoop is an open-source secure release assurance platform for embedded controllers.

The project starts with a narrow, practical wedge: a Zephyr-based controller reference application plus tooling for reproducible releases, SBOM capture, release manifests, evidence bundles, and testable control-loop telemetry.

AssureLoop is **not** a new RTOS. It is an OS-adjacent platform that makes existing embedded stacks easier to ship, audit, update, and maintain.

## Project status

`v0.1-dev`: repository scaffold, firmware demo skeleton, release/evidence tooling, and CI skeleton.

Production readiness: **not yet**. The initial repo is meant for founder-led testing, Codex implementation work, and early design partner demos.

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

To generate an SPDX SBOM after a Zephyr build:

```bash
west spdx --init -d build
west build -d build -b qemu_cortex_m3 firmware/app
west spdx -d build
```

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
├── release-manifest.json.sig
├── trace-report.json
└── evidence-bundle/
```

## Initial development roles

- Founder / tester: define customer pain, run the workflows, break the demos, report what feels confusing or unconvincing.
- Senior architect: keep scope narrow, protect the security/compliance model, define interfaces and acceptance criteria.
- Senior engineer / Codex: implement the next issues in `docs/codex-backlog.md` and keep commits small and reviewable.

## License

Apache-2.0. See `LICENSE`.
