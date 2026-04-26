#!/bin/bash
#SBATCH --job-name=nvshmem-alltoall
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

: "${SCRATCH:?SCRATCH must point to Perlmutter scratch}"
JOB_OUTPUT_DIR="${JOB_OUTPUT_DIR:-${SCRATCH}/communication-libraries-image/slurm}"
mkdir -p "${JOB_OUTPUT_DIR}"
exec > >(tee -a "${JOB_OUTPUT_DIR}/${SLURM_JOB_NAME:-job}-${SLURM_JOB_ID:-manual}.out") 2>&1

IMAGE="${IMAGE:-ghcr.io/dingp/communication-libraries-image:bench-nvshmem-gpu}"
WORKDIR="${WORKDIR:-${SLURM_SUBMIT_DIR:-$PWD}}"
RESULT_ROOT="${RESULT_ROOT:-${SCRATCH}/communication-libraries-image/benchmarks/results}"
RESULT_DIR="${RESULT_DIR:-${RESULT_ROOT}/${SLURM_JOB_ID:-manual}}"
NVSHMEM_TEST="${NVSHMEM_TEST:-/opt/nvshmem/bin/perftest/device/coll/alltoall_latency}"

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

outfile="${RESULT_DIR}/nvshmem-gpu-alltoall-latency.log"

echo "IMAGE=${IMAGE}"
echo "RESULT_DIR=${RESULT_DIR}"

set +e
{
  echo "===== BEGIN BENCHMARK name=nvshmem-gpu-alltoall-latency suite=nvshmem impl=nvshmem mode=gpu provider=cxi nodes=2 ntasks=8 tasks_per_node=4 command=${NVSHMEM_TEST} ====="
  srun -N 2 \
    --ntasks-per-node=4 \
    --gpus-per-task=1 \
    --mpi=pmix \
    podman-hpc shared-run --rm --userns=keep-id \
    "${PMIX_HELPER_ARGS[@]}" \
    -e 'SLURM_*' \
    -e 'SLURMD_*' \
    -e 'PALS_*' \
    -e 'PMI_*' \
    -e 'PMIX_*' \
    -e PMIX_MCA_psec=native \
    -e FI_PROVIDER=cxi \
    -e FI_MR_CACHE_MONITOR=userfaultfd \
    -e FI_CXI_DISABLE_HOST_REGISTER=1 \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e CUDA_VISIBLE_DEVICES \
    -e LD_LIBRARY_PATH=/opt/nvshmem/lib:/opt/pmix/lib:/usr/local/lib:/usr/lib:/usr/lib64:/usr/lib64/nvidia:/usr/local/cuda/compat:/usr/local/cuda/lib64 \
    -e NCCL_NET="AWS Libfabric" \
    -e NCCL_CROSS_NIC=1 \
    -e NCCL_SOCKET_IFNAME=hsn \
    -e NCCL_NET_GDR_LEVEL=PHB \
    -e NCCL_NCHANNELS_PER_NET_PEER=4 \
    -e NVSHMEM_BOOTSTRAP=PMI \
    -e NVSHMEM_BOOTSTRAP_PMI=PMIX \
    -e NVSHMEM_REMOTE_TRANSPORT=libfabric \
    -e NVSHMEM_LIBFABRIC_PROVIDER=cxi \
    -e NVSHMEM_DISABLE_CUDA_VMM=1 \
    --ipc=host \
    --network=host \
    --pid=host \
    --privileged \
    -v /dev/shm:/dev/shm \
    -v "${WORKDIR}:/workspace" \
    "${OPTIONAL_MOUNTS[@]}" \
    "${CXI_MOUNTS[@]}" \
    "${GPU_MOUNTS[@]}" \
    "${NVIDIA_LIBRARY_MOUNTS[@]}" \
    "${IMAGE}" \
    bash -lc "${NVSHMEM_TEST}"
  status=$?
  echo "===== END BENCHMARK name=nvshmem-gpu-alltoall-latency status=${status} ====="
  exit "${status}"
} 2>&1 | tee "${outfile}"
status=${PIPESTATUS[0]}
set -e
exit "${status}"
