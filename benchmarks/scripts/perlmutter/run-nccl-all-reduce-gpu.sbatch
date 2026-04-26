#!/bin/bash
#SBATCH --job-name=nccl-all-reduce
#SBATCH --account=YOUR_NERSC_ACCOUNT
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --gpus-per-task=1
#SBATCH --constraint=gpu
#SBATCH --qos=debug
#SBATCH --time=00:15:00
#SBATCH --output=/dev/null

set -euo pipefail

export PODMANHPC_PODMAN_BIN="${PODMANHPC_PODMAN_BIN:-/global/common/shared/das/podman-4.7.0/bin/podman}"
export PODMANHPC_WAIT_TIMEOUT="${PODMANHPC_WAIT_TIMEOUT:-120}"

: "${SCRATCH:?SCRATCH must point to Perlmutter scratch}"
JOB_OUTPUT_DIR="${JOB_OUTPUT_DIR:-${SCRATCH}/communication-libraries-image/slurm}"
mkdir -p "${JOB_OUTPUT_DIR}"
exec > >(tee -a "${JOB_OUTPUT_DIR}/${SLURM_JOB_NAME:-job}-${SLURM_JOB_ID:-manual}.out") 2>&1

IMAGE="${IMAGE:-ghcr.io/dingp/communication-libraries-image:bench-nccl-gpu}"
WORKDIR="${WORKDIR:-${SLURM_SUBMIT_DIR:-$PWD}}"
RESULT_ROOT="${RESULT_ROOT:-${SCRATCH}/communication-libraries-image/benchmarks/results}"
RESULT_DIR="${RESULT_DIR:-${RESULT_ROOT}/${SLURM_JOB_ID:-manual}}"
NCCL_TEST_ARGS="${NCCL_TEST_ARGS:--b 8 -e 128M -f 2}"
RUN_DEGRADED="${RUN_DEGRADED:-1}"
NODES="${NODES:-2}"
TASKS_PER_NODE="${TASKS_PER_NODE:-4}"
GPUS_PER_NODE="${GPUS_PER_NODE:-4}"
NCCL_DEBUG="${NCCL_DEBUG:-WARN}"
NCCL_DEBUG_SUBSYS="${NCCL_DEBUG_SUBSYS:-}"
FI_UNIVERSE_SIZE="${FI_UNIVERSE_SIZE:-${SLURM_NTASKS:-$((NODES * TASKS_PER_NODE))}}"
NCCL_MIN_NCHANNELS="${NCCL_MIN_NCHANNELS:-4}"
NCCL_NCHANNELS_PER_NET_PEER="${NCCL_NCHANNELS_PER_NET_PEER:-4}"
NCCL_CROSS_NIC="${NCCL_CROSS_NIC:-1}"
# The direct net-GDR path currently trips FI_ENOSPC with aws-ofi-nccl on
# Perlmutter containers. Keep this overrideable for follow-up tuning.
NCCL_NET_GDR_LEVEL="${NCCL_NET_GDR_LEVEL:-LOC}"
NCCL_GDRCOPY_ENABLE="${NCCL_GDRCOPY_ENABLE:-0}"
NCCL_PROTO="${NCCL_PROTO:-^LL128}"
CXI_DEVICE_MAP="${CXI_DEVICE_MAP:-cxi3,cxi2,cxi1,cxi0}"

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
  -e OMPI_MCA_pml=ob1
  -e OMPI_MCA_btl=self,tcp,sm
  -e FI_MR_CACHE_MONITOR=userfaultfd
  -e FI_CXI_DISABLE_HOST_REGISTER=1
  -e FI_CXI_DEFAULT_CQ_SIZE=131072
  -e FI_CXI_DEFAULT_TX_SIZE=16384
  -e FI_CXI_DEFAULT_RX_SIZE=16384
  -e FI_CXI_RX_MATCH_MODE=software
  -e FI_CXI_DISABLE_NON_INJECT_MSG_IDC=1
  -e FI_CXI_RDZV_PROTO=alt_read
  -e FI_CXI_RDZV_GET_MIN=0
  -e FI_CXI_RDZV_THRESHOLD=0
  -e FI_CXI_RDZV_EAGER_SIZE=0
  -e FI_HMEM_CUDA_USE_GDRCOPY=1
  -e FI_UNIVERSE_SIZE="${FI_UNIVERSE_SIZE}"
  -e CXI_DEVICE_MAP="${CXI_DEVICE_MAP}"
  -e NVIDIA_VISIBLE_DEVICES=all
  -e CUDA_VISIBLE_DEVICES=0,1,2,3
  -e LD_LIBRARY_PATH=/opt/pmix/lib:/usr/local/lib:/usr/lib:/usr/lib64:/usr/lib64/nvidia:/usr/local/cuda/compat:/usr/local/cuda/lib64
  -e NCCL_CROSS_NIC="${NCCL_CROSS_NIC}"
  -e NCCL_SOCKET_IFNAME=hsn
  -e NCCL_NET_GDR_LEVEL="${NCCL_NET_GDR_LEVEL}"
  -e NCCL_GDRCOPY_ENABLE="${NCCL_GDRCOPY_ENABLE}"
  -e NCCL_MIN_NCHANNELS="${NCCL_MIN_NCHANNELS}"
  -e NCCL_NCHANNELS_PER_NET_PEER="${NCCL_NCHANNELS_PER_NET_PEER}"
  -e NCCL_PROTO="${NCCL_PROTO}"
  -e NCCL_DEBUG="${NCCL_DEBUG}"
)

if [[ -n "${NCCL_DEBUG_SUBSYS}" ]]; then
  COMMON_ENV+=(-e NCCL_DEBUG_SUBSYS="${NCCL_DEBUG_SUBSYS}")
fi

if [[ -n "${OFI_NCCL_PROTOCOL:-}" ]]; then
  COMMON_ENV+=(-e OFI_NCCL_PROTOCOL="${OFI_NCCL_PROTOCOL}")
fi

if [[ -n "${FI_CXI_DEVICE_NAME_OVERRIDE:-}" ]]; then
  FI_CXI_DEVICE_NAME="${FI_CXI_DEVICE_NAME_OVERRIDE}"
  COMMON_ENV+=(-e FI_CXI_DEVICE_NAME="${FI_CXI_DEVICE_NAME}")
fi

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
    echo "===== BEGIN BENCHMARK name=${name} suite=nccl impl=nccl mode=gpu provider=${provider} nodes=${NODES} ntasks=$((NODES * TASKS_PER_NODE)) tasks_per_node=${TASKS_PER_NODE} command=/opt/nccl-tests/build/all_reduce_perf ${NCCL_TEST_ARGS} ====="
    srun -N "${NODES}" \
      --ntasks-per-node="${TASKS_PER_NODE}" \
      --gpus-per-node="${GPUS_PER_NODE}" \
      --gpu-bind=none \
      --mpi=pmix \
      podman-hpc shared-run --rm --userns=keep-id \
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
      bash -lc 'if [[ "${FI_PROVIDER:-}" == "cxi" && -z "${FI_CXI_DEVICE_NAME:-}" ]]; then local_rank="${SLURM_LOCALID:-0}"; IFS=, read -r -a cxi_devices <<< "${CXI_DEVICE_MAP:-cxi3,cxi2,cxi1,cxi0}"; if (( local_rank < ${#cxi_devices[@]} )); then export FI_CXI_DEVICE_NAME="${cxi_devices[$local_rank]}"; else export FI_CXI_DEVICE_NAME="cxi${local_rank}"; fi; fi; echo "rank=${SLURM_PROCID:-?} local_rank=${SLURM_LOCALID:-?} CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-} FI_CXI_DEVICE_NAME=${FI_CXI_DEVICE_NAME:-} CXI_DEVICE_MAP=${CXI_DEVICE_MAP:-}"; /opt/nccl-tests/build/all_reduce_perf "$@"' bash ${NCCL_TEST_ARGS}
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
echo "CXI_DEVICE_MAP=${CXI_DEVICE_MAP}"
echo "NCCL_NET_GDR_LEVEL=${NCCL_NET_GDR_LEVEL}"
echo "NCCL_GDRCOPY_ENABLE=${NCCL_GDRCOPY_ENABLE}"

run_case "nccl-gpu-all-reduce-cxi" cxi

if [[ "${RUN_DEGRADED}" == "1" ]]; then
  run_case "nccl-gpu-all-reduce-socket" tcp
fi
