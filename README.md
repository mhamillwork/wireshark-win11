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

## Windows 11 base image

The base image is `dockurr/windows:6.06`, pinned by digest in the `Dockerfile` and in `images/windows-base.txt`. It downloads and installs Windows 11 Pro on first launch.

Save the built base image into the project with:

```bash
./automation/fetch-windows-base.sh
```

That writes `images/windows-base.tar`. Load it later with `docker load -i images/windows-base.tar`. The archive is local build output and is not stored in git.

The runtime publishes `/dev/kvm`. On a host whose nested KVM cannot create vCPUs, start the same image with `KVM=N` and without `/dev/kvm`. Software emulation is much slower, and it still boots the Windows 11 installer.

A blank Windows 11 desktop, without the Wireshark first-boot scripts, is the `windows-base` service. Its viewer is on port 8016:

```bash
docker compose --profile base up --build windows-base
```

## Capture

Opening a saved capture works after the installer runs. Live capture uses Npcap. The silent install skips Npcap. Install Npcap from inside the guest when live capture is required.
