#!/bin/bash
set -euo pipefail

PASST_VERSION="${PASST_VERSION:-2026_01_20.386b5f5}"
PASST_SHA256="${PASST_SHA256:-b378b36cc6d17988fd8efdc9e432495afc96787c3ee231aee55bc7e50c4edf6d}"

: "${SCRATCH:?SCRATCH must point to Perlmutter scratch}"

INSTALL_ROOT="${INSTALL_ROOT:-${SCRATCH}/communication-libraries-image/podman-alt/passt-${PASST_VERSION}}"
SRC_DIR="${SRC_DIR:-${INSTALL_ROOT}/passt-${PASST_VERSION}}"
TARBALL="${INSTALL_ROOT}/passt-${PASST_VERSION}.tar.gz"
PASST_URL="${PASST_URL:-https://passt.top/passt/snapshot/passt-${PASST_VERSION}.tar.gz}"

mkdir -p "${INSTALL_ROOT}"

if [[ ! -s "${TARBALL}" ]]; then
  echo "Downloading ${PASST_URL}"
  curl -L --fail --retry 3 "${PASST_URL}" -o "${TARBALL}"
fi

if [[ -n "${PASST_SHA256}" ]]; then
  echo "${PASST_SHA256}  ${TARBALL}" | sha256sum -c -
fi

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "Extracting passt ${PASST_VERSION} under ${INSTALL_ROOT}"
  tar -C "${INSTALL_ROOT}" -xzf "${TARBALL}"
fi

echo "Building and installing passt ${PASST_VERSION}"
make -C "${SRC_DIR}" "VERSION=${PASST_VERSION}" "prefix=${INSTALL_ROOT}/install" install

echo
"${INSTALL_ROOT}/install/bin/pasta" --version | sed -n '1p'
"${INSTALL_ROOT}/install/bin/passt" --version | sed -n '1p'
echo
echo "Installed passt/pasta at:"
echo "  ${INSTALL_ROOT}/install/bin"
echo
echo "Use with local Podman/podman-hpc by exporting:"
echo "  export CONTAINERS_HELPER_BINARY_DIR=${INSTALL_ROOT}/install/bin"
echo "  export PODMANHPC_PODMAN_BIN=\$SCRATCH/communication-libraries-image/podman-alt/podman-5.8.2/bin/podman"
