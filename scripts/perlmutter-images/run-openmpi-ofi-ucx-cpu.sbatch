#!/bin/bash
#SBATCH --job-name=openmpi-ofi-ucx-cpu
#SBATCH --account=YOUR_NERSC_ACCOUNT
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=8
#SBATCH --constraint=cpu
#SBATCH --qos=debug
#SBATCH --time=00:10:00
#SBATCH --output=/dev/null

set -euo pipefail

: "${SCRATCH:?SCRATCH must point to Perlmutter scratch}"
JOB_OUTPUT_DIR="${JOB_OUTPUT_DIR:-${SCRATCH}/communication-libraries-image/slurm}"
mkdir -p "${JOB_OUTPUT_DIR}"
exec > >(tee -a "${JOB_OUTPUT_DIR}/${SLURM_JOB_NAME:-job}-${SLURM_JOB_ID:-manual}.out") 2>&1

IMAGE="${IMAGE:-ghcr.io/dingp/communication-libraries-image:openmpi-ofi-ucx-cpu}"
APP_COMMAND="${APP_COMMAND:-python3 /workspace/tests/test_mpi4py.py}"
WORKDIR="${WORKDIR:-${SLURM_SUBMIT_DIR:-$PWD}}"
TASKS_PER_NODE="${TASKS_PER_NODE:-${SLURM_NTASKS_PER_NODE:-8}}"
TASKS_PER_NODE="${TASKS_PER_NODE%%(*}"

CXI_MOUNTS=()
OPTIONAL_MOUNTS=()
PMIX_HELPER_ARGS=()

for dev in /dev/cxi* /dev/ss0; do
  [[ -e "${dev}" ]] && CXI_MOUNTS+=(-v "${dev}:${dev}")
done

for path in /dev/xpmem /var/spool/slurmd /run/munge /run/nscd /etc/libibverbs.d; do
  [[ -e "${path}" ]] && OPTIONAL_MOUNTS+=(-v "${path}:${path}")
done

if [[ "${PODMANHPC_PMIX_HELPER:-manual}" == "module" ]]; then
  PMIX_HELPER_ARGS=(--pmix)
fi

echo "IMAGE=${IMAGE}"
echo "APP_COMMAND=${APP_COMMAND}"

srun --mpi=pmix \
  --ntasks-per-node="${TASKS_PER_NODE}" \
  podman-hpc shared-run --rm \
  "${PMIX_HELPER_ARGS[@]}" \
  -e 'SLURM_*' \
  -e 'SLURMD_*' \
  -e 'PALS_*' \
  -e 'PMI_*' \
  -e 'PMIX_*' \
  -e PMIX_MCA_psec=native \
  -e FI_PROVIDER=cxi \
  -e FI_MR_CACHE_MONITOR=userfaultfd \
  --ipc=host \
  --network=host \
  --pid=host \
  --privileged \
  -v /dev/shm:/dev/shm \
  -v "${WORKDIR}:/workspace" \
  "${OPTIONAL_MOUNTS[@]}" \
  "${CXI_MOUNTS[@]}" \
  "${IMAGE}" \
  bash -lc "${APP_COMMAND}"
