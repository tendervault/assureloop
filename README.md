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

## Quick start: Zephyr firmware build

Install Zephyr dependencies using the official Zephyr getting-started flow, then initialize this repo as a west workspace:

```bash
west init -l .
west update
west zephyr-export
west build -b qemu_cortex_m3 firmware/app
west build -t run
```

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
