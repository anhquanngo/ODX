#!/bin/bash
# Install NVIDIA cuDSS into /usr/local/cudss (Ceres GPU sparse BA).
set -euo pipefail

INSTALL_DIR="${CUDSS_ROOT:-/usr/local/cudss}"

if [ -f "${INSTALL_DIR}/include/cudss.h" ] || [ -d "${INSTALL_DIR}/lib/cmake/cudss" ]; then
  echo "cuDSS already installed at ${INSTALL_DIR}"
  exit 0
fi

CUDSS_VERSION="${CUDSS_VERSION:-0.5.0.16}"
CUDA_VER="${CUDA_VER:-12}"
ARCHIVE="libcudss-linux-x86_64-${CUDSS_VERSION}_cuda${CUDA_VER}-archive.tar.xz"
URL="https://developer.download.nvidia.com/compute/cudss/redist/libcudss/linux-x86_64/${ARCHIVE}"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

echo "Installing cuDSS ${CUDSS_VERSION} -> ${INSTALL_DIR}"

if ! command -v wget >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
  ${SUDO} apt-get update -y
  ${SUDO} apt-get install -y --no-install-recommends wget xz-utils ca-certificates
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

echo "Downloading ${URL}"
if ! wget -q "${URL}" -O "${tmpdir}/cudss.tar.xz"; then
  echo "ERROR: wget failed (exit $?) — check URL and network: ${URL}"
  exit 1
fi
tar -xf "${tmpdir}/cudss.tar.xz" -C "${tmpdir}"

srcdir=$(find "${tmpdir}" -mindepth 1 -maxdepth 1 -type d | head -1)
if [ -z "${srcdir}" ]; then
  echo "ERROR: unexpected cuDSS archive layout"
  exit 1
fi

${SUDO} mkdir -p "${INSTALL_DIR}"
${SUDO} cp -a "${srcdir}/." "${INSTALL_DIR}/"

if [ -n "${SUDO}" ]; then
  ${SUDO} tee /etc/profile.d/cudss.sh >/dev/null <<EOF
export CUDSS_ROOT=${INSTALL_DIR}
EOF
  ${SUDO} chmod 644 /etc/profile.d/cudss.sh
else
  echo "export CUDSS_ROOT=${INSTALL_DIR}" > /etc/profile.d/cudss.sh
  chmod 644 /etc/profile.d/cudss.sh
fi

echo "cuDSS installed at ${INSTALL_DIR}"
