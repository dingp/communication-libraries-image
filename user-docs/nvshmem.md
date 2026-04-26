# NVSHMEM

NVSHMEM is GPU-only in this repository.
The `nvshmem-gpu` image layers NVIDIA's CUDA 13 NVSHMEM packages on the NCCL/libfabric/CXI base and uses PMIx for Slurm bootstrap.
It does not require OpenMPI in the runtime image.

## Image

| Image | Node type | Default smoke test |
| --- | --- | --- |
| `ghcr.io/dingp/communication-libraries-image:nvshmem-gpu` | GPU | `/opt/nvshmem-tests/nvshmem_hello` |

## Runtime

Pull and migrate:

```bash
podman-hpc pull ghcr.io/dingp/communication-libraries-image:nvshmem-gpu
podman-hpc migrate ghcr.io/dingp/communication-libraries-image:nvshmem-gpu
```

Submit the standalone script:

```bash
sbatch scripts/perlmutter-images/run-nvshmem-gpu.sbatch
```

Override the command:

```bash
APP_COMMAND='/opt/nvshmem/bin/perftest/device/coll/alltoall_latency' \
  sbatch --export=ALL scripts/perlmutter-images/run-nvshmem-gpu.sbatch
```

## Runtime Settings

Use PMIx from Slurm:

```bash
srun --mpi=pmix
PMIX_MCA_psec=native
```

Use the libfabric transport:

```bash
NVSHMEM_BOOTSTRAP=PMI
NVSHMEM_BOOTSTRAP_PMI=PMIX
NVSHMEM_REMOTE_TRANSPORT=libfabric
NVSHMEM_LIBFABRIC_PROVIDER=cxi
NVSHMEM_DISABLE_CUDA_VMM=1
FI_PROVIDER=cxi
```

`NVSHMEM_DISABLE_CUDA_VMM=1` is required for this libfabric transport path.

## Benchmark Results

Perlmutter benchmark snapshot from 2026-04-26:

| Image | Test | Placement | Best result |
| --- | --- | --- | --- |
| `bench-nvshmem-gpu` | `alltoall_latency` | 2 GPU nodes, 8 ranks | 3.09 GB/s bus bandwidth at 1 MiB, 32-bit block scope |

Run the NVSHMEM benchmark:

```bash
sbatch benchmarks/scripts/perlmutter/run-nvshmem-alltoall-latency-gpu.sbatch
```

The benchmark script uses the same PMIx and libfabric environment as the standalone NVSHMEM run script.
