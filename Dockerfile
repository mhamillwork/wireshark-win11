# syntax=docker/dockerfile:1
#
# Three targets:
#   windows-base      Windows 11 Pro base image
#   build             toolchain image that cross-compiles the Wireshark NSIS installer
#   runtime           Windows 11 image that installs and launches Wireshark

ARG WINDOWS_BASE_REF=dockurr/windows:6.06@sha256:16fd7c39a3e48bb946d29c59dc6015942e5b900a1fa5d7e5552053bfc48ee2ea
ARG FEDORA_REF=fedora:43
ARG WIRESHARK_REF=v4.6.9
ARG WINDOWS_BASE_IMAGE=windows-base

# Windows 11 Pro base. The guest is installed on first launch (VERSION=11).
FROM ${WINDOWS_BASE_REF} AS windows-base

ENV VERSION="11" \
    LANGUAGE="English" \
    REGION="en-US" \
    KEYBOARD="en-US" \
    DISK_SIZE="64G"

LABEL org.opencontainers.image.title="Windows 11 base" \
      org.opencontainers.image.description="Windows 11 Pro base image used by the Wireshark runtime." \
      org.opencontainers.image.version="11"

# Build image. Fedora is the toolchain Wireshark documents for producing a
# Windows NSIS installer with MinGW-w64. Launching the image runs that build.
FROM ${FEDORA_REF} AS build

ARG WIRESHARK_REF
RUN dnf -y install ca-certificates git \
    && dnf clean all

RUN git clone --depth 1 --branch "${WIRESHARK_REF}" \
      https://gitlab.com/wireshark/wireshark.git /src/wireshark \
    && git -C /src/wireshark describe --tags --exact-match

WORKDIR /src/wireshark

# Package list is Wireshark's own tools/mingw-rpm-setup.sh at this tag.
# python3 is required by the CMake build and is not in that list.
RUN ./tools/mingw-rpm-setup.sh --install-all -y \
    && dnf -y install python3 perl pkgconf-pkg-config \
    && dnf clean all \
    && command -v mingw64-cmake \
    && command -v makensis \
    && command -v ninja

COPY automation/build-windows-installer.sh /usr/local/bin/build-windows-installer.sh
RUN chmod 0755 /usr/local/bin/build-windows-installer.sh

ENV INSIDE_WIRESHARK_BUILD_IMAGE=1 \
    WIRESHARK_REF="${WIRESHARK_REF}" \
    WIRESHARK_VERSION_EXTRA="-Win11Docker" \
    JOBS=2 \
    CCACHE_DIR=/var/cache/ccache \
    CCACHE_MAXSIZE=8G

VOLUME ["/out", "/src/wireshark/build", "/var/cache/ccache"]
ENTRYPOINT ["/usr/local/bin/build-windows-installer.sh"]

# Runtime image. Same Windows 11 base, with first-boot automation that
# silent-installs the installer produced by the build image and starts Wireshark.
# WINDOWS_BASE_IMAGE defaults to the stage above. On an isolated network, load
# the vendored archive and pass wireshark-win11/windows-base:11 so this build
# does not pull dockurr/windows.
ARG WINDOWS_BASE_IMAGE
FROM ${WINDOWS_BASE_IMAGE} AS runtime

COPY oem/runtime/ /oem/
COPY automation/build-windows-installer.ps1 /oem/build-windows-installer.ps1

ENV VERSION="11" \
    RAM_SIZE="4G" \
    CPU_CORES="2" \
    DISK_SIZE="120G" \
    USERNAME="Docker" \
    PASSWORD="admin" \
    LANGUAGE="English" \
    REGION="en-US" \
    KEYBOARD="en-US"

LABEL org.opencontainers.image.title="Wireshark Windows 11 runtime" \
      org.opencontainers.image.description="Windows 11 Pro desktop that installs and launches Wireshark 4.6.9." \
      org.opencontainers.image.version="4.6.9"
