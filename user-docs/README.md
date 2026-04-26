# Perlmutter Container Communication Libraries

These pages are for NERSC users who want to run communication-library containers on Perlmutter with `podman-hpc`.
They cover the published images from this repository, not module or uenv workflows.

The model is:

```text
Slurm srun --mpi=pmix
  |
  +-- podman-hpc shared-run
        |
        +-- application in container
              |
              +-- MPI, NCCL, or NVSHMEM from the image
                    |
                    +-- libfabric/OFI cxi provider
                          |
                          +-- host /dev/cxi* and Slingshot
```

The image contains the communication libraries. The host provides Slurm, the kernel drivers, GPU driver libraries, `/dev/cxi*`, `/dev/nvidia*`, `/dev/xpmem`, and the Slingshot fabric.

## Pick An Image

| Use case | Image tag | User page |
| --- | --- | --- |
| Low-level libfabric/OFI/CXI smoke tests | `libfabric-cpu`, `libfabric-gpu` | [libfabric](libfabric.md) |
| MPI application built for MPICH | `mpich-cpu`, `mpich-gpu` | [MPICH](mpich.md) |
| MPI application built for OpenMPI | `openmpi-cpu`, `openmpi-gpu` | [OpenMPI](openmpi.md) |
| OpenMPI plus UCX and OpenSHMEM | `openmpi-ofi-ucx-cpu`, `openmpi-ofi-ucx-gpu` | [OpenMPI](openmpi.md) |
| Single-process NCCL smoke tests or NCCL runtime base | `nccl-gpu` | [NCCL](nccl.md) |
| NVSHMEM applications | `nvshmem-gpu` | [NVSHMEM](nvshmem.md) |

## First Run

Pull and migrate the image from a Perlmutter login node before running on compute nodes:

```bash
podman-hpc pull ghcr.io/dingp/communication-libraries-image:mpich-gpu
podman-hpc migrate ghcr.io/dingp/communication-libraries-image:mpich-gpu
```

Use the same image reference in the Slurm script:

```bash
sbatch scripts/perlmutter-images/run-mpich-gpu.sbatch
```

Before submitting any script, replace:

```bash
#SBATCH --account=YOUR_NERSC_ACCOUNT
```

with your allocation account. The scripts write Slurm output under:

```bash
$SCRATCH/communication-libraries-image/slurm
```

## Pages

| Page | Contents |
| --- | --- |
| [Runtime](runtime.md) | Common `podman-hpc shared-run`, PMIx, CXI, GPU, and scratch requirements |
| [libfabric](libfabric.md) | OFI/CXI base images and low-level validation |
| [MPICH](mpich.md) | MPICH CH4/OFI images, mpi4py smoke tests, and OSU results |
| [OpenMPI](openmpi.md) | OpenMPI OFI and OFI+UCX images, OpenSHMEM notes, and OSU results |
| [NCCL](nccl.md) | NCCL plus aws-ofi-nccl usage and all-reduce results |
| [NVSHMEM](nvshmem.md) | NVSHMEM PMIx/libfabric usage and all-to-all latency results |
| [Troubleshooting](troubleshooting.md) | Common Perlmutter container communication failures |
