#!/bin/bash
#SBATCH --job-name=mpi-osu-gpu
#SBATCH --account=YOUR_NERSC_ACCOUNT
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --gpus-per-task=1
#SBATCH --constraint=gpu
#SBATCH --qos=debug
#SBATCH --time=00:20:00
#SBATCH --output=/dev/null

set -euo pipefail

: "${SCRATCH:?SCRATCH must point to Perlmutter scratch}"
JOB_OUTPUT_DIR="${JOB_OUTPUT_DIR:-${SCRATCH}/communication-libraries-image/slurm}"
mkdir -p "${JOB_OUTPUT_DIR}"
exec > >(tee -a "${JOB_OUTPUT_DIR}/${SLURM_JOB_NAME:-job}-${SLURM_JOB_ID:-manual}.out") 2>&1

MPI_IMPL="${MPI_IMPL:-openmpi-ofi-ucx}" # mpich, openmpi, or openmpi-ofi-ucx
IMAGE="${IMAGE:-ghcr.io/dingp/communication-libraries-image:bench-${MPI_IMPL}-gpu}"
WORKDIR="${WORKDIR:-${SLURM_SUBMIT_DIR:-$PWD}}"
RESULT_ROOT="${RESULT_ROOT:-${SCRATCH}/communication-libraries-image/benchmarks/results}"
RESULT_DIR="${RESULT_DIR:-${RESULT_ROOT}/${SLURM_JOB_ID:-manual}}"
RUN_DEGRADED="${RUN_DEGRADED:-1}"

mkdir -p "${RESULT_DIR}"

case "${MPI_IMPL}" in
  mpich|openmpi|openmpi-ofi-ucx) ;;
  *)
    echo "Unsupported MPI_IMPL=${MPI_IMPL}; expected mpich, openmpi, or openmpi-ofi-ucx" >&2
    exit 2
    ;;
esac

CXI_MOUNTS=()
GPU_MOUNTS=()
NVIDIA_LIBRARY_MOUNTS=()
OPTIONAL_MOUNTS=()
PMIX_HELPER_ARGS=()

for dev in /dev/cxi* /dev/ss0; do
  [[ -e "${dev}" ]] && CXI_MOUNTS+=(-v "${dev}:${dev}")
done

for dev in /dev/nvidia*; do
  [[ -e "${dev}" ]] && GPU_MOUNTS+=(-v "${dev}:${dev}")
done

for lib in /usr/lib64/libcuda* /usr/lib64/libnvidia* /usr/lib64/nvidia/libOpenCL*; do
  [[ -e "${lib}" ]] && NVIDIA_LIBRARY_MOUNTS+=(-v "${lib}:${lib}:ro")
done

if [[ -x /usr/bin/nvidia-smi ]]; then
  NVIDIA_LIBRARY_MOUNTS+=(-v /usr/bin/nvidia-smi:/usr/bin/nvidia-smi:ro)
fi

for path in /dev/xpmem /var/spool/slurmd /run/munge /run/nscd /etc/libibverbs.d; do
  [[ -e "${path}" ]] && OPTIONAL_MOUNTS+=(-v "${path}:${path}")
done

if [[ "${PODMANHPC_PMIX_HELPER:-manual}" == "module" ]]; then
  PMIX_HELPER_ARGS=(--pmix)
fi

COMMON_ENV=(
  -e 'SLURM_*'
  -e 'SLURMD_*'
  -e 'PALS_*'
  -e 'PMI_*'
  -e 'PMIX_*'
  -e PMIX_MCA_psec=native
  -e FI_MR_CACHE_MONITOR=userfaultfd
  -e NVIDIA_VISIBLE_DEVICES=all
  -e CUDA_VISIBLE_DEVICES
  -e LD_LIBRARY_PATH=/opt/nvshmem/lib:/opt/pmix/lib:/usr/local/lib:/usr/lib:/usr/lib64:/usr/lib64/nvidia:/usr/local/cuda/compat:/usr/local/cuda/lib64
)

MPI_ENV=()
if [[ "${MPI_IMPL}" == "mpich" ]]; then
  MPI_ENV=(-e MPIR_CVAR_CH4_OFI_ENABLE_HMEM=1)
else
  MPI_ENV=(-e OMPI_MCA_pml=cm -e OMPI_MCA_mtl=ofi)
fi

run_case() {
  local name="$1"
  local nodes="$2"
  local ntasks="$3"
  local tasks_per_node="$4"
  local provider="$5"
  local command="$6"
  local outfile="${RESULT_DIR}/${name}.log"
  local provider_env=()
  local cxi_mounts=()
  local status

  if [[ "${provider}" == "cxi" ]]; then
    provider_env=(-e FI_PROVIDER=cxi)
    cxi_mounts=("${CXI_MOUNTS[@]}")
  else
    provider_env=(-e FI_PROVIDER=tcp)
    cxi_mounts=()
  fi

  set +e
  {
    echo "===== BEGIN BENCHMARK name=${name} suite=osu impl=${MPI_IMPL} mode=gpu provider=${provider} nodes=${nodes} ntasks=${ntasks} tasks_per_node=${tasks_per_node} command=${command} ====="
    srun -N "${nodes}" \
      -n "${ntasks}" \
      --ntasks-per-node="${tasks_per_node}" \
      --gpus-per-task=1 \
      --mpi=pmix \
      podman-hpc shared-run --rm \
      "${PMIX_HELPER_ARGS[@]}" \
      "${COMMON_ENV[@]}" \
      "${MPI_ENV[@]}" \
      "${provider_env[@]}" \
      --ipc=host \
      --network=host \
      --pid=host \
      --privileged \
      -v /dev/shm:/dev/shm \
      -v "${WORKDIR}:/workspace" \
      "${OPTIONAL_MOUNTS[@]}" \
      "${cxi_mounts[@]}" \
      "${GPU_MOUNTS[@]}" \
      "${NVIDIA_LIBRARY_MOUNTS[@]}" \
      "${IMAGE}" \
      bash -lc "cd /usr/local/libexec/osu-micro-benchmarks/mpi && ${command}"
    status=$?
    echo "===== END BENCHMARK name=${name} status=${status} ====="
    exit "${status}"
  } 2>&1 | tee "${outfile}"
  status=${PIPESTATUS[0]}
  set -e
  return "${status}"
}

echo "IMAGE=${IMAGE}"
echo "RESULT_DIR=${RESULT_DIR}"

run_case "${MPI_IMPL}-gpu-osu-bw-intra-host" 1 2 2 cxi "./pt2pt/osu_bw --validation"
run_case "${MPI_IMPL}-gpu-osu-bw-inter-host" 2 2 1 cxi "./pt2pt/osu_bw --validation"
run_case "${MPI_IMPL}-gpu-osu-bw-intra-device" 1 2 2 cxi "./pt2pt/osu_bw --validation D D"
run_case "${MPI_IMPL}-gpu-osu-bw-inter-device" 2 2 1 cxi "./pt2pt/osu_bw --validation D D"

if [[ "${MPI_IMPL}" == openmpi* ]]; then
  if [[ "${RUN_DEGRADED}" == "1" ]]; then
    run_case "${MPI_IMPL}-gpu-osu-bw-inter-host-tcp" 2 2 1 tcp "./pt2pt/osu_bw --validation"
    run_case "${MPI_IMPL}-gpu-osu-bw-inter-device-tcp" 2 2 1 tcp "./pt2pt/osu_bw --validation D D"
  fi

  run_case "${MPI_IMPL}-gpu-osu-alltoall-host" 2 8 4 cxi "./collective/osu_alltoall --validation"
  run_case "${MPI_IMPL}-gpu-osu-alltoall-device" 2 8 4 cxi "./collective/osu_alltoall --validation -d cuda"

  if [[ "${RUN_DEGRADED}" == "1" ]]; then
    run_case "${MPI_IMPL}-gpu-osu-alltoall-host-tcp" 2 8 4 tcp "./collective/osu_alltoall --validation"
    run_case "${MPI_IMPL}-gpu-osu-alltoall-device-tcp" 2 8 4 tcp "./collective/osu_alltoall --validation -d cuda"
  fi
fi
