# NCCL

NCCL is GPU-only in this repository.
The `nccl-gpu` image contains NCCL, libfabric/CXI, and the AWS OFI NCCL plugin.
It does not include OpenMPI or MPICH.

## Image

| Image | Node type | Notes |
| --- | --- | --- |
| `ghcr.io/dingp/communication-libraries-image:nccl-gpu` | GPU | NCCL, aws-ofi-nccl, libfabric/CXI, single-process `nccl-tests` built without MPI |

## Runtime

Pull and migrate:

```bash
podman-hpc pull ghcr.io/dingp/communication-libraries-image:nccl-gpu
podman-hpc migrate ghcr.io/dingp/communication-libraries-image:nccl-gpu
```

Run the single-process smoke test:

```bash
sbatch scripts/perlmutter-images/run-nccl-gpu.sbatch
```

Override the NCCL command:

```bash
APP_COMMAND='/opt/nccl-tests/build/all_reduce_perf -b 8 -e 128M -f 2 -g 1' \
  sbatch --export=ALL scripts/perlmutter-images/run-nccl-gpu.sbatch
```

The pure `nccl-gpu` image builds `nccl-tests` with `MPI=0`.
Use application launchers or the benchmark-only image for distributed NCCL tests.

## Runtime Settings

Use the AWS OFI NCCL plugin:

```bash
NCCL_NET="AWS Libfabric"
FI_PROVIDER=cxi
NCCL_SOCKET_IFNAME=hsn
NCCL_CROSS_NIC=1
NCCL_NCHANNELS_PER_NET_PEER=4
```

Perlmutter GPU nodes have four GPUs and four CXI devices.
The benchmark script maps local ranks to CXI devices by PCI locality:

```text
local rank: 0     1     2     3
GPU:        0     1     2     3
CXI:        cxi3  cxi2  cxi1  cxi0
```

The benchmark script currently defaults to:

```bash
NCCL_NET_GDR_LEVEL=LOC
NCCL_GDRCOPY_ENABLE=0
```

This avoids a direct net-GDR path that has returned `FI_ENOSPC` in the current containerized Perlmutter setup.
Override those variables when testing direct GPU-memory transport.

## Benchmark Results

The distributed NCCL benchmark uses a benchmark-only image, `bench-nccl-gpu`, because `all_reduce_perf` uses MPI for rank wire-up in that mode.
The production `nccl-gpu` image remains MPI-free.
The alternate benchmark image `bench-nccl-mpich-gpu` uses `mpich-gpu` as its base and builds MPI-enabled `nccl-tests` with MPICH. It is intended for PHB plus GDRCopy experiments and defaults to `NCCL_NET_GDR_LEVEL=PHB` and `NCCL_GDRCOPY_ENABLE=1`.

Perlmutter benchmark snapshot from 2026-04-26:

| Image | Test | Placement | Best result |
| --- | --- | --- | --- |
| `bench-nccl-gpu` | `all_reduce_perf -b 8 -e 128M -f 2` | 2 GPU nodes, 8 ranks | 18.34 GB/s in-place bus bandwidth at 8 MiB |

Run the NCCL benchmark:

```bash
sbatch benchmarks/scripts/perlmutter/run-nccl-all-reduce-gpu.sbatch
```

Run the MPICH-backed PHB/GDRCopy variant:

```bash
NCCL_MPI_IMPL=mpich sbatch --export=ALL benchmarks/scripts/perlmutter/run-nccl-all-reduce-gpu.sbatch
```

Useful overrides:

```bash
NCCL_DEBUG=INFO sbatch --export=ALL benchmarks/scripts/perlmutter/run-nccl-all-reduce-gpu.sbatch
CXI_DEVICE_MAP=cxi3,cxi2,cxi1,cxi0 sbatch --export=ALL benchmarks/scripts/perlmutter/run-nccl-all-reduce-gpu.sbatch
```

Do not set `NCCL_NET_PLUGIN=ofi` for these images.
Use `NCCL_NET="AWS Libfabric"`.
