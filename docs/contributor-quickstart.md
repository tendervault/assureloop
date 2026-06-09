# Contributor Quickstart

This guide helps outside contributors run the current simulator-first AssureLoop
workflow. It is intentionally focused on local development and review.

## Windows Setup

Install common Zephyr host tools:

```powershell
winget install Kitware.CMake Ninja-build.Ninja oss-winget.gperf Python.Python.3.12 Git.Git oss-winget.dtc wget 7zip.7zip
```

Close and reopen PowerShell so new tools are on `PATH`, then create a Zephyr
workspace above the AssureLoop checkout:

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
```

Run host tests without GNU make:

```powershell
.\scripts\test-tools.ps1
```

Run the full simulator demo:

```powershell
.\scripts\full-demo.ps1
```

## Bash/Linux Setup

Install common host tools using your package manager. On Ubuntu, this is a
typical starting point:

```bash
sudo apt-get update
sudo apt-get install --no-install-recommends \
  git cmake ninja-build gperf ccache dfu-util device-tree-compiler \
  wget xz-utils file make gcc gcc-multilib g++-multilib python3 python3-venv \
  python3-pip python3-setuptools python3-wheel
```

Create the Zephyr workspace:

```bash
mkdir -p ~/assureloop-zephyr
cd ~/assureloop-zephyr
git clone https://github.com/tendervault/assureloop.git assureloop

python3 -m venv .venv
. .venv/bin/activate

pip install west
west init -l assureloop
west update
west zephyr-export
python -m pip install $(west packages pip)

cd zephyr
west sdk install -t arm-zephyr-eabi

cd ../assureloop
west build -b qemu_cortex_m3 firmware/app
```

Run the full simulator demo:

```bash
bash scripts/full-demo.sh
```

## Common Commands

Host tests:

```powershell
.\scripts\test-tools.ps1
```

```bash
python3 -m unittest discover -s tests -v
```

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

Signed image demo:

```powershell
.\scripts\signed-image-demo.ps1
```

```bash
bash scripts/signed-image-demo.sh
```

Evidence verification:

```powershell
.\scripts\verify-firmware-evidence.ps1
```

```bash
bash scripts/verify-firmware-evidence.sh
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
```

```bash
bash scripts/ota-sim-demo.sh
```

## Generated Folders To Avoid Committing

These paths are generated and ignored:

```text
build/
build-*/
dist/
keys/
zephyr/
modules/
bootloader/
.west/
tools/zephyr-sdk-*/
*.sig
*.tar.gz
```

Private development keys must stay under ignored paths such as `keys/`.

## Troubleshooting

### OpenSSL

`verify-demo.ps1` and signed manifest workflows need OpenSSL. If the script
reports `OpenSSL was not found`, install OpenSSL, add it to `PATH`, or pass an
explicit path:

```powershell
.\scripts\firmware-evidence-demo.ps1 -Sign -OpenSsl 'C:\Program Files\Git\usr\bin\openssl.exe'
```

### west

If `west was not found`, activate the Zephyr Python virtual environment or pass
the `-West` parameter on PowerShell scripts:

```powershell
.\scripts\full-demo.ps1 -West west
```

### Zephyr SDK

If CMake reports that no Zephyr toolchain is available, install the Zephyr SDK
for `arm-zephyr-eabi` and make sure your environment can find it:

```powershell
cd $Env:USERPROFILE\assureloop-zephyr\zephyr
west sdk install -t arm-zephyr-eabi
```

### DTC

If Zephyr reports `Could NOT find Dtc`, install the device tree compiler and
restart the shell. On Windows, `oss-winget.dtc` is the expected package in the
setup command above. Some local builds may warn about DTC discovery while still
using generated devicetree output; treat persistent DTC failures as setup
issues.

### QEMU

If `west build -t run` cannot find QEMU, confirm the Zephyr SDK was installed
and exported in the active workspace. The simulator run target is interactive;
use `Ctrl+A`, then `X`, to exit QEMU.

### MCUboot imgtool

If the signed image demo cannot find `imgtool`, activate the Zephyr Python
environment or set `IMGTOOL` to the MCUboot `imgtool.py` path. The scripts also
look for MCUboot as a sibling of the AssureLoop repository in the west
workspace.
