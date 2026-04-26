#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  benchmarks/scripts/build.sh <target|all> [target...]

Examples:
  benchmarks/scripts/build.sh bench-openmpi-ofi-ucx-gpu
  BASE_IMAGE_REPO=localhost/communication-libraries-image benchmarks/scripts/build.sh all

Environment:
  CONTAINER_BUILDER  Container builder command. Default: podman-hpc
  IMAGE_REPO         Repository for benchmark image tags. Default: localhost/communication-libraries-image
  BASE_IMAGE_REPO    Repository containing the base images. Default: ghcr.io/dingp/communication-libraries-image
  OSU_VERSION        OSU Micro-Benchmarks version. Default: 7.5.2
USAGE
}

targets=("$@")
if [[ ${#targets[@]} -eq 0 || "${targets[0]}" == "-h" || "${targets[0]}" == "--help" ]]; then
  usage
  [[ ${#targets[@]} -eq 0 ]] && exit 2 || exit 0
fi

all_targets=(
  bench-mpich-cpu
  bench-mpich-gpu
  bench-openmpi-cpu
  bench-openmpi-gpu
  bench-openmpi-ofi-ucx-cpu
  bench-openmpi-ofi-ucx-gpu
  bench-nccl-gpu
  bench-nvshmem-gpu
)

if [[ " ${targets[*]} " == *" all "* ]]; then
  targets=("${all_targets[@]}")
fi

runtime="${CONTAINER_BUILDER:-podman-hpc}"
repo="${IMAGE_REPO:-localhost/communication-libraries-image}"
base_repo="${BASE_IMAGE_REPO:-ghcr.io/dingp/communication-libraries-image}"
osu_version="${OSU_VERSION:-7.5.2}"

for target in "${targets[@]}"; do
  case " ${all_targets[*]} " in
    *" ${target} "*) ;;
    *)
      echo "Unknown benchmark target: ${target}" >&2
      usage >&2
      exit 2
      ;;
  esac

  tag="${repo}:${target}"
  echo "Building ${tag} from benchmarks/container/Containerfile"
  "${runtime}" build \
    --build-arg "BASE_IMAGE_REPO=${base_repo}" \
    --build-arg "OSU_VERSION=${osu_version}" \
    --target "${target}" \
    -f benchmarks/container/Containerfile \
    -t "${tag}" \
    .
done
