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
  AWS_OFI_NCCL_VERSION  AWS OFI NCCL plugin version. Default: 1.19.0
  NCCL_PACKAGE_VERSION  NCCL Debian package version. Default: 2.29.7-1+cuda13.2
  NCCL_SOURCE_BRANCH    NCCL source tag for the MPICH NCCL benchmark image. Default: v2.29.2-1
  NCCL_MPICH_AWS_OFI_NCCL_VERSION  AWS OFI NCCL plugin version for the MPICH NCCL benchmark image. Default: 1.6.0
  NCCL_TESTS_VERSION    nccl-tests version. Default: 2.17.1
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
  bench-nccl-mpich-gpu
  bench-nvshmem-gpu
)

if [[ " ${targets[*]} " == *" all "* ]]; then
  targets=("${all_targets[@]}")
fi

runtime="${CONTAINER_BUILDER:-podman-hpc}"
repo="${IMAGE_REPO:-localhost/communication-libraries-image}"
base_repo="${BASE_IMAGE_REPO:-ghcr.io/dingp/communication-libraries-image}"
osu_version="${OSU_VERSION:-7.5.2}"
aws_ofi_nccl_version="${AWS_OFI_NCCL_VERSION:-1.19.0}"
nccl_package_version="${NCCL_PACKAGE_VERSION:-2.29.7-1+cuda13.2}"
nccl_source_branch="${NCCL_SOURCE_BRANCH:-v2.29.2-1}"
nccl_mpich_aws_ofi_nccl_version="${NCCL_MPICH_AWS_OFI_NCCL_VERSION:-1.6.0}"
nccl_tests_version="${NCCL_TESTS_VERSION:-2.17.1}"

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
    --build-arg "AWS_OFI_NCCL_VERSION=${aws_ofi_nccl_version}" \
    --build-arg "NCCL_PACKAGE_VERSION=${nccl_package_version}" \
    --build-arg "NCCL_SOURCE_BRANCH=${nccl_source_branch}" \
    --build-arg "NCCL_MPICH_AWS_OFI_NCCL_VERSION=${nccl_mpich_aws_ofi_nccl_version}" \
    --build-arg "NCCL_TESTS_VERSION=${nccl_tests_version}" \
    --target "${target}" \
    -f benchmarks/container/Containerfile \
    -t "${tag}" \
    .
done
