# Release Checklist

Use this checklist for public alpha simulator releases. It is not a production
certification checklist.

## Preconditions

- [ ] Worktree contains only intended source changes.
- [ ] Zephyr workspace is initialized from `west.yml`.
- [ ] Development keys, build output, and release output are under ignored
      paths.
- [ ] Release notes avoid unsupported safety, cybersecurity, secure boot, or
      production OTA claims.

## Local Verification

- [ ] Host tests pass:

  ```powershell
  .\scripts\test-tools.ps1
  ```

- [ ] Zephyr simulator build passes:

  ```bash
  west build -b qemu_cortex_m3 firmware/app
  ```

- [ ] Signed image demo passes:

  ```powershell
  .\scripts\signed-image-demo.ps1
  ```

- [ ] Firmware evidence with SBOM passes:

  ```powershell
  .\scripts\firmware-evidence-demo.ps1 -GenerateSbom
  ```

- [ ] Release manifest schema validation passes:

  ```powershell
  py tools\validate_manifest.py --manifest dist\firmware-release\release-manifest.json
  ```

- [ ] Release manifest artifact verification passes:

  ```powershell
  py tools\verify_release.py --manifest dist\firmware-release\release-manifest.json --base-dir .
  ```

- [ ] Evidence bundle verification passes:

  ```powershell
  .\scripts\verify-firmware-evidence.ps1
  py tools\verify_evidence_bundle.py --bundle dist\firmware-release\evidence-bundle.tar.gz
  ```

- [ ] Update package verification passes:

  ```powershell
  .\scripts\update-package-demo.ps1
  ```

- [ ] OTA simulator demo passes:

  ```powershell
  .\scripts\ota-sim-demo.ps1
  ```

- [ ] Full simulator demo passes:

  ```powershell
  .\scripts\full-demo.ps1
  ```

## Generated Artifacts

- [ ] `dist/firmware-release/release-manifest.json` exists.
- [ ] `dist/firmware-release/trace-report.json` exists.
- [ ] `dist/firmware-release/evidence-bundle.tar.gz` exists.
- [ ] `dist/firmware-release/update-package/update-package.json` exists.
- [ ] `build-signed/zephyr/zephyr.signed.bin` exists.
- [ ] `dist/firmware-signed-release/update-package/update-package.json` exists.
- [ ] `dist/ota-sim/state.json` exists.

## GitHub Actions

- [ ] Pull request CI passes.
- [ ] Push-to-main CI passes after merge.
- [ ] CI artifact upload contains the firmware evidence bundle and update
      package outputs.

CI runs direct steps instead of `scripts/full-demo.sh` so each generated output
can be checked and uploaded explicitly.

## Tag And Release Notes

- [ ] Tag name follows the pre-1.0 format, for example `v0.1.0-alpha.1`.
- [ ] Release notes include the target: `qemu_cortex_m3`.
- [ ] Release notes list generated artifacts.
- [ ] Release notes call out simulator-first limitations.
- [ ] Release notes say development keys are not production keys.
- [ ] Release notes avoid certification claims.
- [ ] Known setup warnings are documented if they affect users.

## After Release

- [ ] Confirm generated `build/`, `build-*`, `dist/`, and `keys/` paths remain
      untracked.
- [ ] Archive or delete local development keys if they are no longer needed.
- [ ] Add follow-up issues for any release-blocking gaps found during review.
