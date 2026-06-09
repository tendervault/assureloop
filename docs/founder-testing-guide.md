# Founder testing guide

Your job as founder/tester is to break the workflow and judge whether it would convince an embedded team.

## Test 1: host tooling sanity

Run:

```bash
make test-tools
make evidence-demo
```

Pass criteria:

- tests pass,
- `dist/release-manifest.json` exists,
- `dist/trace-report.json` exists,
- `dist/evidence-bundle/index.json` exists,
- `dist/evidence-bundle.tar.gz` exists.

Founder feedback to record:

- Was the command obvious?
- Did any output look untrustworthy?
- Did the evidence bundle feel useful or fake?

## Test 2: manifest tamper detection

Run:

```bash
make manifest-demo
python3 tools/verify_release.py --manifest dist/release-manifest.json --base-dir .
echo '# tamper' >> README.md
python3 tools/verify_release.py --manifest dist/release-manifest.json --base-dir .
```

Pass criteria:

- first verify passes,
- second verify fails because the artifact hash changed.

Reset the file afterwards:

```bash
git checkout -- README.md
```

## Test 3: signature verification

Run:

```bash
make verify-demo
```

Pass criteria:

- dev keys are created under `keys/`,
- manifest signature is created,
- signature verification passes.

## Test 4: Zephyr build

Run after Zephyr is installed:

```bash
west init -l .
west update
west build -b qemu_cortex_m3 firmware/app
west build -t run
```

Pass criteria:

- build completes,
- QEMU run emits `assureloop` log lines,
- loop telemetry includes jitter numbers.

## Test notes template

```text
Date:
Host OS:
Command:
Expected:
Actual:
Error logs:
Founder judgement:
  [ ] convincing
  [ ] confusing
  [ ] broken
  [ ] not commercially useful yet
```
