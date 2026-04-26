# Benchmarks

This directory contains Perlmutter benchmark image recipes, Slurm job scripts, and a result parser modeled on the CSCS communication-library documentation.

The benchmark image stages use the main repository images as base images and add only benchmark suites. MPI benchmark images build OSU Micro-Benchmarks 7.5.2 by default.

| Benchmark image tag | Base image | Added benchmark suite |
| --- | --- | --- |
| `bench-mpich-cpu` | `mpich-cpu` | OSU Micro-Benchmarks |
| `bench-mpich-gpu` | `mpich-gpu` | OSU Micro-Benchmarks with CUDA buffers |
| `bench-openmpi-cpu` | `openmpi-cpu` | OSU Micro-Benchmarks |
| `bench-openmpi-gpu` | `openmpi-gpu` | OSU Micro-Benchmarks with CUDA buffers |
| `bench-openmpi-ofi-ucx-cpu` | `openmpi-ofi-ucx-cpu` | OSU Micro-Benchmarks |
| `bench-openmpi-ofi-ucx-gpu` | `openmpi-ofi-ucx-gpu` | OSU Micro-Benchmarks with CUDA buffers |
| `bench-nccl-gpu` | `openmpi-ofi-ucx-gpu` | MPI-enabled `nccl-tests` for distributed `all_reduce_perf` |
| `bench-nvshmem-gpu` | `nvshmem-gpu` | Packaged NVSHMEM performance tests |

The production `nccl-gpu` image remains MPI-free. The benchmark-only `bench-nccl-gpu` target includes OpenMPI because the CSCS-style distributed `all_reduce_perf` test uses MPI for rank wire-up.

## Build

Build one benchmark image locally:

```bash
benchmarks/scripts/build.sh bench-openmpi-ofi-ucx-gpu
```

Build all benchmark images:

```bash
benchmarks/scripts/build.sh all
```

Use local base images instead of the published GHCR images:

```bash
BASE_IMAGE_REPO=localhost/communication-libraries-image benchmarks/scripts/build.sh all
```

Override the OSU Micro-Benchmarks version when needed:

```bash
OSU_VERSION=7.5.2 benchmarks/scripts/build.sh bench-openmpi-gpu
```

Override the NCCL package when validating a different CUDA 13.2 NCCL build:

```bash
NCCL_PACKAGE_VERSION=2.30.4-1+cuda13.2 benchmarks/scripts/build.sh bench-nccl-gpu
```

## Run On Perlmutter

Each script writes Slurm stdout/stderr under `$SCRATCH/communication-libraries-image/slurm` and one log file per benchmark case under `$SCRATCH/communication-libraries-image/benchmarks/results/$SLURM_JOB_ID`.
Override `JOB_OUTPUT_DIR` or `RESULT_ROOT` if you want a different scratch location.
Before submitting, replace `#SBATCH --account=YOUR_NERSC_ACCOUNT` with your allocation account.

The benchmark jobs launch with `srun --mpi=pmix` and `podman-hpc shared-run`.
Until the site `podman-hpc` stack handles `--userns=keep-id` reliably with PMIx, these scripts default to the older Podman backend:

```bash
PODMANHPC_PODMAN_BIN=/global/common/shared/das/podman-4.7.0/bin/podman
```

Set `PODMANHPC_PODMAN_BIN` before `sbatch` if you need to test a different backend.

Run MPICH OSU `osu_bw` host-buffer tests on CPU nodes:

```bash
MPI_IMPL=mpich sbatch --export=ALL benchmarks/scripts/perlmutter/run-mpi-osu-cpu.sbatch
```

Run MPICH OSU `osu_bw` host-buffer tests on GPU nodes:

```bash
MPI_IMPL=mpich sbatch --export=ALL benchmarks/scripts/perlmutter/run-mpi-osu-gpu.sbatch
```

The MPICH GPU script skips CUDA-buffer OSU cases by default because the current containerized MPICH path fails the OSU CUDA-buffer `Waitall` case on Perlmutter. Set `RUN_CUDA_BUFFER=1` when explicitly testing that path.

Run OpenMPI or OpenMPI+OFI+UCX OSU benchmarks:

```bash
MPI_IMPL=openmpi sbatch --export=ALL benchmarks/scripts/perlmutter/run-mpi-osu-gpu.sbatch
MPI_IMPL=openmpi-ofi-ucx sbatch --export=ALL benchmarks/scripts/perlmutter/run-mpi-osu-gpu.sbatch
```

The OpenMPI scripts run the CSCS benchmark types: `osu_bw` inter-node and intra-node, `osu_alltoall` across two nodes, and host plus CUDA-buffer variants on GPU nodes. TCP/no-CXI comparison cases are optional with `RUN_DEGRADED=1`; they are treated as diagnostic comparisons and do not fail the batch job if they fail.

Run NCCL `all_reduce_perf` on two GPU nodes:

```bash
sbatch benchmarks/scripts/perlmutter/run-nccl-all-reduce-gpu.sbatch
```

The NCCL benchmark script launches four ranks per GPU node by default and maps local ranks to the four Perlmutter CXI devices by PCI locality:

```text
local_rank:  0     1     2     3
GPU:         0     1     2     3
CXI:         cxi3  cxi2  cxi1  cxi0
```

The default can be changed with `CXI_DEVICE_MAP`. The script also defaults `NCCL_NET_GDR_LEVEL=LOC` and `NCCL_GDRCOPY_ENABLE=0` because the direct net-GDR path currently returns `FI_ENOSPC` in this containerized Perlmutter setup. This was reproduced with NCCL 2.29.7-1+cuda13.2 and 2.30.4-1+cuda13.2 when using aws-ofi-nccl 1.19.0. Set `NCCL_NET_GDR_LEVEL=PHB NCCL_GDRCOPY_ENABLE=1` before `sbatch` when testing direct GPU-memory transport. Set `RUN_DEGRADED=1` to add the optional socket comparison; it is treated as diagnostic and does not fail the batch job if it fails.

Run NVSHMEM device all-to-all latency on two GPU nodes:

```bash
sbatch benchmarks/scripts/perlmutter/run-nvshmem-alltoall-latency-gpu.sbatch
```

Override an image tag when testing a local build:

```bash
IMAGE=localhost/communication-libraries-image:bench-openmpi-ofi-ucx-gpu \
  MPI_IMPL=openmpi-ofi-ucx \
  sbatch --export=ALL benchmarks/scripts/perlmutter/run-mpi-osu-gpu.sbatch
```

## Process Results

Generate a Markdown report from a result directory:

```bash
benchmarks/scripts/process-results.py "$SCRATCH/communication-libraries-image/benchmarks/results/<jobid>" \
  -o "$SCRATCH/communication-libraries-image/benchmarks/results/<jobid>/report.md"
```

The parser recognizes:

| Suite | Parsed output |
| --- | --- |
| OSU | `osu_bw` bandwidth tables and `osu_alltoall` latency tables |
| NCCL | `all_reduce_perf` out-of-place and in-place bandwidth tables |
| NVSHMEM | `alltoall_latency` device latency and bandwidth tables |
