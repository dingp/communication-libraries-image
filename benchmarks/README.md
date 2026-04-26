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

## Run On Perlmutter

Each script writes Slurm stdout/stderr under `$SCRATCH/communication-libraries-image/slurm` and one log file per benchmark case under `$SCRATCH/communication-libraries-image/benchmarks/results/$SLURM_JOB_ID`.
Override `JOB_OUTPUT_DIR` or `RESULT_ROOT` if you want a different scratch location.
Before submitting, replace `#SBATCH --account=YOUR_NERSC_ACCOUNT` with your allocation account.

Run MPICH OSU `osu_bw` host-buffer tests on CPU nodes:

```bash
MPI_IMPL=mpich sbatch --export=ALL benchmarks/scripts/perlmutter/run-mpi-osu-cpu.sbatch
```

Run MPICH OSU `osu_bw` host- and device-buffer tests on GPU nodes:

```bash
MPI_IMPL=mpich sbatch --export=ALL benchmarks/scripts/perlmutter/run-mpi-osu-gpu.sbatch
```

Run OpenMPI or OpenMPI+OFI+UCX OSU benchmarks:

```bash
MPI_IMPL=openmpi sbatch --export=ALL benchmarks/scripts/perlmutter/run-mpi-osu-gpu.sbatch
MPI_IMPL=openmpi-ofi-ucx sbatch --export=ALL benchmarks/scripts/perlmutter/run-mpi-osu-gpu.sbatch
```

The OpenMPI scripts run the CSCS benchmark types: `osu_bw` inter-node and intra-node, `osu_alltoall` across two nodes, host and CUDA-buffer variants on GPU nodes, plus TCP/no-CXI comparison cases when `RUN_DEGRADED=1`.

Run NCCL `all_reduce_perf` on two GPU nodes:

```bash
sbatch benchmarks/scripts/perlmutter/run-nccl-all-reduce-gpu.sbatch
```

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
