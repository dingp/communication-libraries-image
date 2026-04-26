#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/build.sh [--build-arg NAME=VALUE] <target|all> [target...]

Examples:
  scripts/build.sh mpich-cpu
  scripts/build.sh --build-arg CUDA_VERSION=13.0.0 openmpi-gpu
  scripts/build.sh all
USAGE
}

build_args=()
targets=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-arg)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      build_args+=(--build-arg "$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      targets+=("$1")
      shift
      ;;
  esac
done

if [[ ${#targets[@]} -eq 0 ]]; then
  usage >&2
  exit 2
fi

all_targets=(
  libfabric-cpu
  libfabric-gpu
  mpich-cpu
  mpich-gpu
  openmpi-cpu
  openmpi-gpu
  openmpi-ofi-ucx-cpu
  openmpi-ofi-ucx-gpu
  nccl-gpu
  nvshmem-gpu
)

if [[ " ${targets[*]} " == *" all "* ]]; then
  targets=("${all_targets[@]}")
fi

runtime="${CONTAINER_BUILDER:-podman-hpc}"
repo="${IMAGE_REPO:-localhost/communication-libraries-image}"

for target in "${targets[@]}"; do
  tag="${repo}:${target}"
  containerfile="container/targets/${target}.Containerfile"
  if [[ ! -f "${containerfile}" ]]; then
    echo "Missing ${containerfile}; run scripts/generate-target-containerfiles.py" >&2
    exit 1
  fi

  echo "Building ${tag} from ${containerfile}"
  "${runtime}" build \
    "${build_args[@]}" \
    -f "${containerfile}" \
    -t "${tag}" \
    .
done
