#!/bin/bash
#SBATCH --job-name=nccl-all-reduce
#SBATCH --account=YOUR_NERSC_ACCOUNT
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --gpus-per-task=1
#SBATCH --constraint=gpu
#SBATCH --qos=debug
#SBATCH --time=00:15:00
#SBATCH --output=nccl-all-reduce-%j.out

set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/dingp/communication-libraries-image:bench-nccl-gpu}"
WORKDIR="${WORKDIR:-${SLURM_SUBMIT_DIR:-$PWD}}"
RESULT_DIR="${RESULT_DIR:-${WORKDIR}/benchmarks/results/${SLURM_JOB_ID:-manual}}"
NCCL_TEST_ARGS="${NCCL_TEST_ARGS:--b 8 -e 128M -f 2}"
RUN_DEGRADED="${RUN_DEGRADED:-1}"

mkdir -p "${RESULT_DIR}"

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
  -e OMPI_MCA_pml=cm
  -e OMPI_MCA_mtl=ofi
  -e FI_MR_CACHE_MONITOR=userfaultfd
  -e FI_CXI_DISABLE_HOST_REGISTER=1
  -e NVIDIA_VISIBLE_DEVICES=all
  -e CUDA_VISIBLE_DEVICES
  -e LD_LIBRARY_PATH=/opt/pmix/lib:/usr/local/lib:/usr/lib:/usr/lib64:/usr/lib64/nvidia:/usr/local/cuda/compat:/usr/local/cuda/lib64
  -e NCCL_CROSS_NIC=1
  -e NCCL_SOCKET_IFNAME=hsn
  -e NCCL_NET_GDR_LEVEL=PHB
  -e NCCL_NCHANNELS_PER_NET_PEER=4
  -e NCCL_DEBUG=WARN
)

run_case() {
  local name="$1"
  local provider="$2"
  local outfile="${RESULT_DIR}/${name}.log"
  local provider_env=()
  local cxi_mounts=()
  local status

  if [[ "${provider}" == "cxi" ]]; then
    provider_env=(-e FI_PROVIDER=cxi -e NCCL_NET="AWS Libfabric")
    cxi_mounts=("${CXI_MOUNTS[@]}")
  else
    provider_env=(-e FI_PROVIDER=tcp -e NCCL_NET=Socket)
    cxi_mounts=()
  fi

  set +e
  {
    echo "===== BEGIN BENCHMARK name=${name} suite=nccl impl=nccl mode=gpu provider=${provider} nodes=2 ntasks=8 tasks_per_node=4 command=/opt/nccl-tests/build/all_reduce_perf ${NCCL_TEST_ARGS} ====="
    srun -N 2 \
      --ntasks-per-node=4 \
      --gpus-per-task=1 \
      --mpi=pmix \
      podman-hpc shared-run --rm \
      "${PMIX_HELPER_ARGS[@]}" \
      "${COMMON_ENV[@]}" \
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
      bash -lc "/opt/nccl-tests/build/all_reduce_perf ${NCCL_TEST_ARGS}"
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

run_case "nccl-gpu-all-reduce-cxi" cxi

if [[ "${RUN_DEGRADED}" == "1" ]]; then
  run_case "nccl-gpu-all-reduce-socket" tcp
fi
