# Wireshark 4.6.9 on Windows 11

Windows 11 Docker environment that builds a Wireshark 4.6.9 x64 installer and launches Wireshark on a Windows 11 desktop.

Three images are defined in the `Dockerfile`:

| Image | Target | Role |
| --- | --- | --- |
| `wireshark-win11/windows-base:11` | `windows-base` | Windows 11 Pro base image |
| `wireshark-win11/wireshark-build:4.6.9` | `build` | Compiles Wireshark and packages the NSIS installer |
| `wireshark-win11/wireshark-runtime:4.6.9` | `runtime` | Windows 11 desktop that installs and launches Wireshark |

The host needs Linux, Docker, and KVM (`/dev/kvm`). The Windows 11 guest is installed automatically the first time the runtime starts. The desktop is on port 8006 and RDP is on port 3389 (`Docker` / `admin`).

## Build the Windows installer

```bash
./automation/build-windows-installer.sh
```

The script builds the build image and runs it. Wireshark `v4.6.9` is cross-compiled with the MinGW-w64 steps from the Wireshark Developer’s Guide (`tools/mingw-rpm-setup.sh`, `mingw64-cmake`, `ninja wireshark_nsis_prep`, `ninja wireshark_nsis`). The installer is written to `dist/`:

```text
dist/wireshark-4.6.9-Win11Docker-x64.exe
dist/SHA256SUMS
```

## Launch Windows 11 and Wireshark

```bash
docker compose up --build wireshark-runtime
```

Open `http://127.0.0.1:8006`. At the end of Windows setup, and again at logon, the guest silent-installs `dist/Wireshark-*-x64.exe` from the shared drive and starts Wireshark. The same shared drive is `Z:` and the Desktop `Shared` folder.

The desktop also has **Build Wireshark Installer**. That runs `automation/build-windows-installer.ps1` inside the guest with the Wireshark 4.6.9 Windows CI toolchain: Visual Studio 2022 Build Tools, the Windows 11 SDK (10.0.22621), Qt 6.8.3 (`win64_msvc2022_64`), CMake, NSIS 3, and `msbuild` of `wireshark_nsis_prep` then `wireshark_nsis`. Give the guest more memory before using that path (`RAM_SIZE=8G` or higher in `docker-compose.yml`). The disk is 120 GB so the toolchain and the build tree fit.

## Isolated network

The Windows base image and the Wireshark runtime image are stored in the repository. They share layers, so both fit in one 228 MB archive, `images/windows-base/windows-images.tar`, split into pieces under 50 MB:

```text
images/windows-base/windows-images.tar.00
images/windows-base/windows-images.tar.01
...
```

`dockurr/windows:6.06` is inside that base image. Load the archive, then start the runtime without pulling:

```bash
./automation/load-images.sh
docker compose up --no-build wireshark-runtime
```

Rebuilding the runtime from that archive, without pulling `dockurr/windows`, uses the loaded base image:

```bash
docker compose build --build-arg WINDOWS_BASE_IMAGE=wireshark-win11/windows-base:11 wireshark-runtime
```

The Wireshark build image is not in the repository. The built image is 5.11 GB, and the MinGW toolchain layer alone is 3.21 GB. That is too large for this GitHub repository. Build it on a connected machine with `./automation/build-windows-installer.sh`, then copy `dist/wireshark-4.6.9-Win11Docker-x64.exe` onto the isolated host. The runtime installs that file from the shared `dist/` folder. The Fedora toolchain image still downloads packages while it is built, and the compile still downloads Lua and Npcap, so that step stays on a connected machine.

The Windows 11 installation ISO is not in the Docker image. On a connected network the runtime downloads it on first launch. On an isolated network, put the ISO in the project directory and add this mount to `wireshark-runtime` in `docker-compose.yml`:

```yaml
- ./win11x64.iso:/custom.iso
```

`./automation/fetch-windows-base.sh` rebuilds the vendored archive after the base image changes.

The runtime publishes `/dev/kvm`. On a host whose nested KVM cannot create vCPUs, start the same image with `KVM=N` and without `/dev/kvm`. Software emulation is much slower, and it still boots the Windows 11 installer.

A blank Windows 11 desktop, without the Wireshark first-boot scripts, is the `windows-base` service. Its viewer is on port 8016:

```bash
docker compose --profile base up --build windows-base
```

## Capture

Opening a saved capture works after the installer runs. Live capture uses Npcap. The silent install skips Npcap. Install Npcap from inside the guest when live capture is required.
