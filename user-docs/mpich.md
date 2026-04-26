# MPICH

The MPICH images build open-source MPICH inside the container with CH4/OFI and PMIx.
They do not rely on the older podman-hpc MPICH injection module.

## Images

| Image | Node type | Default smoke test |
| --- | --- | --- |
| `ghcr.io/dingp/communication-libraries-image:mpich-cpu` | CPU | `python3 /workspace/tests/test_mpi4py.py` |
| `ghcr.io/dingp/communication-libraries-image:mpich-gpu` | GPU | `python3 /workspace/tests/test_mpi4py.py` |

## Runtime

Pull and migrate:

```bash
podman-hpc pull ghcr.io/dingp/communication-libraries-image:mpich-gpu
podman-hpc migrate ghcr.io/dingp/communication-libraries-image:mpich-gpu
```

Submit the standalone script:

```bash
sbatch scripts/perlmutter-images/run-mpich-gpu.sbatch
```

Override the application command:

```bash
APP_COMMAND='./my_mpich_app input.yaml' \
  sbatch --export=ALL scripts/perlmutter-images/run-mpich-gpu.sbatch
```

For CPU nodes, use:

```bash
sbatch scripts/perlmutter-images/run-mpich-cpu.sbatch
```

## Runtime Settings

The image is built with:

```text
--with-device=ch4:ofi
--with-libfabric=/usr
--with-pmi=pmix
--with-pmix=/opt/pmix
```

The Slurm job uses:

```bash
srun --mpi=pmix
FI_PROVIDER=cxi
PMIX_MCA_psec=native
```

The GPU image sets:

```bash
MPIR_CVAR_CH4_OFI_ENABLE_HMEM=1
```

## mpi4py Test

The default script runs the repository mpi4py validation:

```bash
python3 /workspace/tests/test_mpi4py.py
```

This test checks rank count, collectives, point-to-point communication, communicator splitting, and basic datatype behavior through the MPICH library in the image.

## Benchmark Results

OSU Micro-Benchmarks 7.5.2 were run on Perlmutter with the benchmark image `bench-mpich-gpu` and `bench-mpich-cpu`.

Summary:

| Image | Test | Placement | Buffer | Best result |
| --- | --- | --- | --- | --- |
| `bench-mpich-cpu` | `osu_bw --validation` | 2 CPU nodes | host | 23,958.47 MB/s at 4 MiB |
| `bench-mpich-cpu` | `osu_bw --validation` | 1 CPU node, 2 ranks | host | 46,371.33 MB/s at 128 KiB |
| `bench-mpich-gpu` | `osu_bw --validation` | 2 GPU nodes | host | 24,249.19 MB/s at 4 MiB |
| `bench-mpich-gpu` | `osu_bw --validation` | 1 GPU node, 2 ranks | host | 42,279.87 MB/s at 2 MiB |
| `bench-mpich-gpu` | `osu_bw --validation -d cuda` | 2 GPU nodes | CUDA | 24,217.88 MB/s at 4 MiB |
| `bench-mpich-gpu` | `osu_bw --validation -d cuda` | 1 GPU node, 2 ranks | CUDA | 36,780.40 MB/s at 256 KiB |

Run the MPICH benchmark jobs:

```bash
MPI_IMPL=mpich sbatch --export=ALL benchmarks/scripts/perlmutter/run-mpi-osu-cpu.sbatch
MPI_IMPL=mpich sbatch --export=ALL benchmarks/scripts/perlmutter/run-mpi-osu-gpu.sbatch
```

For CUDA-buffer OSU tests with MPICH, use `-d cuda`.
The older positional `D D` OSU syntax fails in the MPICH `Waitall` path on this stack.
