# ST NUCLEO-H563ZI Signed Evidence

AL-014 extends the AssureLoop release assurance workflow from simulator-only
signed images to a board-specific ST NUCLEO-H563ZI signed application image,
SBOM, release manifest, evidence bundle, and update package.

This workflow uses local development image-signing keys only. It does not add
real OTA transport, does not install or verify a production MCUboot bootloader,
does not provide production secure boot, and is not a certification claim.

## Purpose

The NUCLEO-H563ZI signed evidence flow proves that AssureLoop can package a
physical-board target with the same evidence contract used by the simulator:

- Zephyr build artifacts from `build-signed-nucleo-h563zi`.
- MCUboot/imgtool signed image artifacts where Zephyr produces them.
- Zephyr SPDX/SBOM output.
- A release manifest with SHA256 hashes.
- A trace report generated from the NUCLEO boot log sample.
- An evidence bundle directory and `.tar.gz` archive.
- An update package that prefers the signed image payload.

Board target:

```text
nucleo_h563zi
```

## Windows Command

Use the same Zephyr workspace used for AL-013. If needed, set the SDK path:

```powershell
$env:ZEPHYR_SDK_INSTALL_DIR = 'D:\zephyr-sdk'
$env:ZEPHYR_TOOLCHAIN_VARIANT = 'zephyr'
```

Build the signed board release, generate SBOM/evidence, and verify the package:

```powershell
.\scripts\signed-image-demo-nucleo-h563zi.ps1 -Python py
```

Optional flash path:

```powershell
.\scripts\signed-image-demo-nucleo-h563zi.ps1 -Python py -Flash
```

The optional flash step programs the signed application image. AL-015 will
cover MCUboot bootloader verification on the physical board, so this command is
not a production secure-boot validation.

## Bash Command

```bash
bash scripts/signed-image-demo-nucleo-h563zi.sh
```

Optional flash path:

```bash
bash scripts/signed-image-demo-nucleo-h563zi.sh --flash
```

## Output Files

Primary output directory:

```text
dist/firmware-nucleo-h563zi-release/
```

Expected outputs:

- `release-manifest.json`
- `trace-report.json`
- `evidence-bundle/`
- `evidence-bundle.tar.gz`
- `update-package/update-package.json`
- copied SBOM files under the bundle and update package when generated

Expected build artifacts, when produced by Zephyr:

- `build-signed-nucleo-h563zi/zephyr/zephyr.elf`
- `build-signed-nucleo-h563zi/zephyr/zephyr.hex`
- `build-signed-nucleo-h563zi/zephyr/zephyr.bin`
- `build-signed-nucleo-h563zi/zephyr/zephyr.signed.bin`
- `build-signed-nucleo-h563zi/zephyr/zephyr.signed.hex`
- `build-signed-nucleo-h563zi/zephyr/zephyr.map`
- `build-signed-nucleo-h563zi/zephyr/.config`
- `build-signed-nucleo-h563zi/zephyr/zephyr.dts`
- `build-signed-nucleo-h563zi/spdx/*.spdx`

The release manifest records these artifacts with SHA256 hashes. Signed image
artifacts use the `firmware-signed-image` kind so update-package creation can
prefer the signed board image as payload.

## Development Keys

The script creates or reuses:

```text
keys/mcuboot-dev-rsa-2048.pem
```

This path is ignored by git. Treat the key as a disposable development key. Do
not reuse it for production releases, do not commit it, and do not treat this
workflow as production key custody.

## Verification

Evidence bundle verification:

```powershell
py tools\verify_evidence_bundle.py --bundle dist\firmware-nucleo-h563zi-release\evidence-bundle
```

```bash
python3 tools/verify_evidence_bundle.py --bundle dist/firmware-nucleo-h563zi-release/evidence-bundle
```

Update package verification:

```powershell
py tools\verify_update_package.py --package dist\firmware-nucleo-h563zi-release\update-package --target nucleo_h563zi
```

```bash
python3 tools/verify_update_package.py --package dist/firmware-nucleo-h563zi-release/update-package --target nucleo_h563zi
```

The verifier checks manifest schema validity, artifact existence and SHA256
hashes, evidence bundle contents, SBOM files when listed, payload hash, and
target matching.

## Trace Source

The board-specific trace report is generated from:

```text
samples/logs/nucleo_h563zi_boot.log
```

That sample records the AL-013 boot markers observed on COM4: boot banner,
release identity, loop configuration, loop iterations 1 through 20, loop
summary, and completion.

## Limitations

- This is board-specific evidence generation, not broad board support.
- The signed image is created with a local development key.
- The optional flash path does not prove MCUboot bootloader behavior.
- No real OTA transport is included.
- No cloud service is included.
- No production secure boot or safety/cybersecurity certification is claimed.
