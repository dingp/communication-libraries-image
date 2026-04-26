#!/bin/bash
set -euo pipefail

PODMAN_VERSION="${PODMAN_VERSION:-5.8.2}"
GO_VERSION="${GO_VERSION:-1.26.2}"
GO_SHA256="${GO_SHA256:-990e6b4bbba816dc3ee129eaeaf4b42f17c2800b88a2166c265ac1a200262282}"

: "${SCRATCH:?SCRATCH must point to Perlmutter scratch}"

INSTALL_ROOT="${INSTALL_ROOT:-${SCRATCH}/communication-libraries-image/podman-alt/podman-${PODMAN_VERSION}}"
SRC_DIR="${SRC_DIR:-${INSTALL_ROOT}/src}"
GO_ROOT="${INSTALL_ROOT}/go"
GO_TARBALL="${INSTALL_ROOT}/go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
PODMAN_REPO="${PODMAN_REPO:-https://github.com/containers/podman.git}"

PODMAN_BUILDTAGS="${PODMAN_BUILDTAGS:-containers_image_openpgp exclude_graphdriver_btrfs exclude_graphdriver_devicemapper systemd}"
if pkg-config --exists libseccomp 2>/dev/null; then
  PODMAN_BUILDTAGS="${PODMAN_BUILDTAGS} seccomp"
else
  echo "libseccomp development files were not found; building Podman without the seccomp build tag."
fi

mkdir -p "${INSTALL_ROOT}/bin" "${INSTALL_ROOT}/gocache" "${INSTALL_ROOT}/gopath"

if [[ ! -s "${GO_TARBALL}" ]]; then
  echo "Downloading ${GO_URL}"
  curl -L --fail --retry 3 "${GO_URL}" -o "${GO_TARBALL}"
fi

echo "${GO_SHA256}  ${GO_TARBALL}" | sha256sum -c -

if [[ ! -x "${GO_ROOT}/bin/go" ]]; then
  echo "Extracting Go ${GO_VERSION} under ${INSTALL_ROOT}"
  tar -C "${INSTALL_ROOT}" -xzf "${GO_TARBALL}"
fi

if [[ ! -d "${SRC_DIR}/.git" ]]; then
  echo "Cloning Podman v${PODMAN_VERSION}"
  git clone --depth 1 --branch "v${PODMAN_VERSION}" "${PODMAN_REPO}" "${SRC_DIR}"
else
  echo "Updating Podman source tree to v${PODMAN_VERSION}"
  if ! git -C "${SRC_DIR}" rev-parse -q --verify "refs/tags/v${PODMAN_VERSION}" >/dev/null; then
    git -C "${SRC_DIR}" fetch --depth 1 origin "refs/tags/v${PODMAN_VERSION}:refs/tags/v${PODMAN_VERSION}"
  fi
  git -C "${SRC_DIR}" checkout -f "v${PODMAN_VERSION}"
fi

export PATH="${GO_ROOT}/bin:${PATH}"
export GOCACHE="${INSTALL_ROOT}/gocache"
export GOPATH="${INSTALL_ROOT}/gopath"

echo "Building Podman v${PODMAN_VERSION}"
echo "Go: $("${GO_ROOT}/bin/go" version)"
echo "Build tags: ${PODMAN_BUILDTAGS}"
make -C "${SRC_DIR}" "BUILDTAGS=${PODMAN_BUILDTAGS}" bin/podman

install -m 0755 "${SRC_DIR}/bin/podman" "${INSTALL_ROOT}/bin/podman"

echo
"${INSTALL_ROOT}/bin/podman" --version
echo
echo "Installed local Podman at:"
echo "  ${INSTALL_ROOT}/bin/podman"
echo
echo "Use it with podman-hpc by exporting:"
echo "  export PODMANHPC_PODMAN_BIN=${INSTALL_ROOT}/bin/podman"
