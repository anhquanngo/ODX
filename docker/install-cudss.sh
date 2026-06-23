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
ARCHIVE="cudss-linux-x86_64-${CUDSS_VERSION}_cuda${CUDA_VER}-archive.tar.xz"
URL="https://developer.download.nvidia.com/compute/cudss/redist/cudss/linux-x86_64/${ARCHIVE}"

echo "Installing cuDSS ${CUDSS_VERSION} -> ${INSTALL_DIR}"
apt-get update -y
apt-get install -y --no-install-recommends wget xz-utils ca-certificates

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

wget -q "${URL}" -O "${tmpdir}/cudss.tar.xz"
tar -xf "${tmpdir}/cudss.tar.xz" -C "${tmpdir}"

mkdir -p "${INSTALL_DIR}"
# NVIDIA redist archive: single top-level directory (name varies by version).
srcdir=$(find "${tmpdir}" -mindepth 1 -maxdepth 1 -type d | head -1)
if [ -z "${srcdir}" ]; then
  echo "ERROR: unexpected cuDSS archive layout"
  exit 1
fi
cp -a "${srcdir}/." "${INSTALL_DIR}/"

echo "export CUDSS_ROOT=${INSTALL_DIR}" > /etc/profile.d/cudss.sh
chmod 644 /etc/profile.d/cudss.sh
echo "cuDSS installed at ${INSTALL_DIR}"
