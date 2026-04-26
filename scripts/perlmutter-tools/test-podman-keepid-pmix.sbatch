#!/bin/bash
#SBATCH --job-name=podman-keepid-pmix
#SBATCH --account=YOUR_NERSC_ACCOUNT
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --constraint=cpu
#SBATCH --qos=debug
#SBATCH --time=00:20:00
#SBATCH --output=/dev/null

set -euo pipefail

: "${SCRATCH:?SCRATCH must point to Perlmutter scratch}"
RESULT_DIR="${RESULT_DIR:-${SCRATCH}/communication-libraries-image/podman-keepid-tests/${SLURM_JOB_ID:-manual}}"
mkdir -p "${RESULT_DIR}"
exec > >(tee -a "${RESULT_DIR}/slurm.out") 2>&1

IMAGE="${IMAGE:-ghcr.io/dingp/communication-libraries-image:openmpi-ofi-ucx-cpu}"
WORKDIR="${WORKDIR:-${SLURM_SUBMIT_DIR:-$PWD}}"
OLD_PODMAN="${OLD_PODMAN:-/global/common/shared/das/podman-4.7.0/bin/podman}"
NEW_PODMAN="${NEW_PODMAN:-${SCRATCH}/communication-libraries-image/podman-alt/podman-5.8.2/bin/podman}"
CASE_TIMEOUT="${CASE_TIMEOUT:-90}"

export PODMANHPC_WAIT_TIMEOUT="${PODMANHPC_WAIT_TIMEOUT:-120}"

CXI_MOUNTS=()
OPTIONAL_MOUNTS=()

for dev in /dev/cxi* /dev/ss0; do
  [[ -e "${dev}" ]] && CXI_MOUNTS+=(-v "${dev}:${dev}")
done

for path in /dev/xpmem /var/spool/slurmd /run/munge /run/nscd /etc/libibverbs.d; do
  [[ -e "${path}" ]] && OPTIONAL_MOUNTS+=(-v "${path}:${path}")
done

COMMON_ENV=(
  -e 'SLURM_*'
  -e 'SLURMD_*'
  -e 'PALS_*'
  -e 'PMI_*'
  -e 'PMIX_*'
  -e PMIX_MCA_psec=native
  -e FI_PROVIDER=cxi
  -e FI_MR_CACHE_MONITOR=userfaultfd
  -e OMPI_MCA_pml=cm
  -e OMPI_MCA_mtl=ofi
)

podman_version() {
  local podman_bin="$1"

  if [[ "${podman_bin}" == "system" ]]; then
    /usr/bin/podman --version
  else
    "${podman_bin}" --version
  fi
}

run_case() {
  local name="$1"
  local podman_bin="$2"
  local userns_mode="$3"
  local outfile="${RESULT_DIR}/${name}.log"
  local status
  local userns_args=()

  if [[ "${podman_bin}" == "system" ]]; then
    unset PODMANHPC_PODMAN_BIN
  else
    export PODMANHPC_PODMAN_BIN="${podman_bin}"
  fi

  if [[ "${userns_mode}" == "keep-id" ]]; then
    userns_args=(--userns=keep-id)
  fi

  set +e
  {
    echo "===== BEGIN ${name} podman_bin=${podman_bin} userns=${userns_mode} ====="
    podman_version "${podman_bin}"
    echo "PODMANHPC_PODMAN_BIN=${PODMANHPC_PODMAN_BIN:-system}"
    timeout "${CASE_TIMEOUT}" srun -N 2 \
      -n 2 \
      --ntasks-per-node=1 \
      --mpi=pmix \
      podman-hpc shared-run --rm \
      "${userns_args[@]}" \
      "${COMMON_ENV[@]}" \
      --ipc=host \
      --network=host \
      --pid=host \
      --privileged \
      -v /dev/shm:/dev/shm \
      -v "${WORKDIR}:/workspace" \
      "${OPTIONAL_MOUNTS[@]}" \
      "${CXI_MOUNTS[@]}" \
      "${IMAGE}" \
      bash -lc "python3 /workspace/tests/test_mpi4py.py"
    status=$?
    echo "===== END ${name} status=${status} ====="
    exit "${status}"
  } 2>&1 | tee "${outfile}"
  status=${PIPESTATUS[0]}
  set -e

  echo "${name} ${status}" >> "${RESULT_DIR}/summary.txt"
  return 0
}

echo "RESULT_DIR=${RESULT_DIR}"
echo "IMAGE=${IMAGE}"
echo "WORKDIR=${WORKDIR}"
echo "OLD_PODMAN=${OLD_PODMAN}"
echo "NEW_PODMAN=${NEW_PODMAN}"
echo "CASE_TIMEOUT=${CASE_TIMEOUT}"

run_case old-4.7.0-keepid "${OLD_PODMAN}" keep-id
run_case scratch-5.8.2-keepid "${NEW_PODMAN}" keep-id
run_case system-keepid system keep-id
run_case system-no-keepid system none

echo "===== SUMMARY ====="
cat "${RESULT_DIR}/summary.txt"
