# Release process

## Release stages

1. Build firmware.
2. Generate SBOM.
3. Generate release manifest.
4. Generate trace report from test run.
5. Build evidence bundle.
6. Sign manifest.
7. Verify manifest and artifact hashes.
8. Publish release artifacts.

## Development release command

```bash
make evidence-demo
make verify-demo
```

## Firmware release command target

Once Zephyr build integration is verified:

```bash
west build -b qemu_cortex_m3 firmware/app
west spdx --init -d build
west build -d build -b qemu_cortex_m3 firmware/app
west spdx -d build
mkdir -p dist/firmware dist/sbom
cp build/zephyr/zephyr.{bin,elf,hex} dist/firmware/ 2>/dev/null || true
cp build/spdx/* dist/sbom/ 2>/dev/null || true
python3 tools/generate_release_manifest.py \
  --product assureloop-controller-demo \
  --version 0.1.0-dev \
  --target qemu_cortex_m3 \
  --artifact dist/firmware/zephyr.bin:firmware \
  --artifact dist/firmware/zephyr.elf:debug \
  --sbom-dir dist/sbom \
  --output dist/release-manifest.json
```

## Versioning

Before the first stable release, use:

```text
0.1.0-dev
0.1.0-alpha.1
0.1.0-alpha.2
```

Do not use `1.0` until a design partner can build, run, update, and verify an AssureLoop release from documentation alone.

## Signing policy

Development keys may be generated locally with:

```bash
./scripts/create_dev_keys.sh
```

Development keys must never be reused for production. Production signing policy is a separate milestone.
