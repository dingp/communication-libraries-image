#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/run-perlmutter.sh <cpu|gpu> <libfabric|mpich|openmpi|openmpi-ofi-ucx|cray-mpich|nccl|nvshmem> [image] [-- command...]

Examples:
  scripts/run-perlmutter.sh cpu mpich
  scripts/run-perlmutter.sh gpu openmpi
  scripts/run-perlmutter.sh gpu openmpi-ofi-ucx
  scripts/run-perlmutter.sh gpu nccl ghcr.io/dingp/communication-libraries-image:nccl-gpu
  scripts/run-perlmutter.sh gpu openmpi -- python3 /workspace/tests/mpi4py_hello.py

Set PODMANHPC_PMIX_HELPER=module after the generic podman-hpc --pmix helper is deployed.
USAGE
}

mode="${1:-}"
stack="${2:-}"
if [[ -z "${mode}" || -z "${stack}" ]]; then
  usage >&2
  exit 2
fi
shift 2

image="${1:-}"
if [[ -n "${image}" && "${image}" != "--" ]]; then
  shift
else
  image=""
fi
if [[ "${1:-}" == "--" ]]; then
  shift
fi

case "${mode}" in
  cpu)
    suffix=cpu
    default_nodes=2
    default_tasks_per_node=8
    mode_sbatch_extra=(--qos="${QOS:-debug}" --constraint=cpu)
    mode_srun_extra=()
    ;;
  gpu)
    suffix=gpu
    default_nodes=2
    default_tasks_per_node=4
    mode_sbatch_extra=(--gpus-per-task=1 --qos="${QOS:-debug}" --constraint=gpu)
    mode_srun_extra=(--gpus-per-task=1)
    ;;
  *)
    echo "Unsupported mode: ${mode}" >&2
    usage >&2
    exit 2
    ;;
esac

case "${stack}" in
  libfabric)
    default_target="libfabric-${suffix}"
    default_command=(fi_info -p cxi)
    ;;
  mpich)
    default_target="mpich-${suffix}"
    default_command=(python3 /workspace/tests/mpi4py_hello.py)
    ;;
  openmpi)
    default_target="openmpi-${suffix}"
    default_command=(python3 /workspace/tests/mpi4py_hello.py)
    ;;
  openmpi-ofi-ucx)
    default_target="openmpi-ofi-ucx-${suffix}"
    default_command=(python3 /workspace/tests/mpi4py_hello.py)
    ;;
  cray-mpich)
    default_target="cray-mpich-${suffix}"
    default_command=(python3 /workspace/tests/mpi4py_hello.py)
    ;;
  nccl)
    [[ "${mode}" == "gpu" ]] || { echo "NCCL is GPU-only in this repo" >&2; exit 2; }
    default_target="nccl-gpu"
    default_nodes=1
    default_tasks_per_node=1
    default_command=(/opt/nccl-tests/build/all_reduce_perf -b 8 -e 128M -f 2 -g 1)
    ;;
  nvshmem)
    [[ "${mode}" == "gpu" ]] || { echo "NVSHMEM is GPU-only in this repo" >&2; exit 2; }
    default_target="nvshmem-gpu"
    default_command=(/opt/nvshmem-tests/nvshmem_hello)
    ;;
  *)
    echo "Unsupported stack: ${stack}" >&2
    usage >&2
    exit 2
    ;;
esac

image="${image:-ghcr.io/dingp/communication-libraries-image:${default_target}}"
app_command=("$@")
if [[ ${#app_command[@]} -eq 0 ]]; then
  app_command=("${default_command[@]}")
fi

nodes="${NODES:-${default_nodes}}"
tasks_per_node="${TASKS_PER_NODE:-${default_tasks_per_node}}"
sbatch_extra=(--nodes="${nodes}" --ntasks-per-node="${tasks_per_node}" "${mode_sbatch_extra[@]}")
srun_extra=(--mpi=pmix --ntasks-per-node="${tasks_per_node}" "${mode_srun_extra[@]}")

workdir="$PWD"
account="${SLURM_ACCOUNT:-nstaff}"
job_name="comm_${stack}_${mode}"

container_args=(
  -e SLURM_*
  -e SLURMD_*
  -e PALS_*
  -e PMI_*
  -e PMIX_*
  -e PMIX_MCA_psec=native
  -e FI_PROVIDER=cxi
  -e FI_MR_CACHE_MONITOR=userfaultfd
  --ipc=host
  --network=host
  --pid=host
  --privileged
  -v /dev/shm:/dev/shm
  -v /dev/xpmem:/dev/xpmem
  -v /var/spool/slurmd:/var/spool/slurmd
  -v /run/munge:/run/munge
  -v /run/nscd:/run/nscd
  -v /etc/libibverbs.d:/etc/libibverbs.d
  -v "${workdir}:/workspace"
)

if [[ "${PODMANHPC_PMIX_HELPER:-manual}" == "module" ]]; then
  container_helper=(--pmix)
else
  container_helper=()
fi

shopt -s nullglob
for dev in /dev/cxi* /dev/ss0; do
  container_args+=(-v "${dev}:${dev}")
done

if [[ "${mode}" == "gpu" ]]; then
  container_args+=(
    -e NVIDIA_VISIBLE_DEVICES=all
    -e CUDA_VISIBLE_DEVICES
    -e LD_LIBRARY_PATH=/opt/nvshmem/lib:/opt/pmix/lib:/usr/local/lib:/usr/lib:/usr/lib64:/usr/lib64/nvidia:/usr/local/cuda/compat:/usr/local/cuda/lib64
    -e FI_CXI_DISABLE_HOST_REGISTER=1
    -e NCCL_NET="AWS Libfabric"
    -e NCCL_CROSS_NIC=1
    -e NCCL_SOCKET_IFNAME=hsn
    -e NCCL_NET_GDR_LEVEL=PHB
    -e NCCL_NCHANNELS_PER_NET_PEER=4
    -e NVSHMEM_BOOTSTRAP=PMI
    -e NVSHMEM_BOOTSTRAP_PMI=PMIX
    -e NVSHMEM_REMOTE_TRANSPORT=libfabric
    -e NVSHMEM_LIBFABRIC_PROVIDER=cxi
    -e NVSHMEM_DISABLE_CUDA_VMM=1
  )
  for dev in /dev/nvidia*; do
    container_args+=(-v "${dev}:${dev}")
  done
  # Bind the full host driver library set. CUDA 13.x images can otherwise pick
  # up the container compat JIT libraries while using the host libcuda.
  for lib in /usr/lib64/libcuda* /usr/lib64/libnvidia* /usr/lib64/nvidia/libOpenCL*; do
    container_args+=(-v "${lib}:${lib}:ro")
  done
  if [[ -x /usr/bin/nvidia-smi ]]; then
    container_args+=(-v /usr/bin/nvidia-smi:/usr/bin/nvidia-smi:ro)
  fi
fi

srun_cmd=(
  srun "${srun_extra[@]}"
  podman-hpc shared-run --rm
  "${container_helper[@]}"
  "${container_args[@]}"
  "${image}"
  "${app_command[@]}"
)
srun_cmd_str=$(printf '%q ' "${srun_cmd[@]}")

echo "Submitting ${job_name} with image ${image}"
echo "Command: ${app_command[*]}"

sbatch \
  --job-name="${job_name}" \
  --time="${TIME_LIMIT:-00:10:00}" \
  --account="${account}" \
  --output="log_%j.out" \
  "${sbatch_extra[@]}" - <<EOF
#!/bin/bash
set -euo pipefail
${srun_cmd_str}
EOF
