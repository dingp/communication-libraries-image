# Runtime

Use `podman-hpc shared-run` under `srun`.
Do not use `podman-hpc --mpi`, `podman-hpc --cuda-mpi`, or the old podman-hpc MPICH module for these images.
MPI, libfabric, NCCL, and NVSHMEM are built into the image.

## Required Slurm Shape

MPI and SHMEM jobs use PMIx from Slurm:

```bash
srun --mpi=pmix podman-hpc shared-run --rm ...
```

The container command needs the Slurm and PMIx environment:

```bash
-e 'SLURM_*' \
-e 'SLURMD_*' \
-e 'PALS_*' \
-e 'PMI_*' \
-e 'PMIX_*' \
-e PMIX_MCA_psec=native
```

## Required Device And Namespace Shape

The standalone scripts in `scripts/perlmutter-images/` expand the device lists on the compute node and pass the needed runtime options:

```bash
--ipc=host \
--network=host \
--pid=host \
--privileged \
-v /dev/shm:/dev/shm \
-v /dev/cxi0:/dev/cxi0 \
-v /dev/cxi1:/dev/cxi1 \
-v /dev/cxi2:/dev/cxi2 \
-v /dev/cxi3:/dev/cxi3
```

GPU scripts also pass:

```bash
-v /dev/nvidia0:/dev/nvidia0 \
-v /dev/nvidia1:/dev/nvidia1 \
-v /dev/nvidia2:/dev/nvidia2 \
-v /dev/nvidia3:/dev/nvidia3 \
-v /dev/nvidiactl:/dev/nvidiactl \
-v /dev/nvidia-uvm:/dev/nvidia-uvm
```

and bind the host NVIDIA driver libraries from `/usr/lib64`.
That keeps the container CUDA user-space stack matched to the Perlmutter driver at runtime.

## Common Environment

All Slingshot communication paths use the CXI provider:

```bash
FI_PROVIDER=cxi
PMIX_MCA_psec=native
```

OpenMPI uses OFI by default:

```bash
OMPI_MCA_pml=cm
OMPI_MCA_mtl=ofi
```

GPU images also set or pass CUDA and GPU-communication settings such as:

```bash
NVIDIA_VISIBLE_DEVICES=all
FI_MR_CACHE_MONITOR=userfaultfd
FI_CXI_DISABLE_HOST_REGISTER=1
```

## Image Availability

Pull and migrate each image before a multi-node job:

```bash
podman-hpc pull ghcr.io/dingp/communication-libraries-image:openmpi-ofi-ucx-gpu
podman-hpc migrate ghcr.io/dingp/communication-libraries-image:openmpi-ofi-ucx-gpu
```

If the image was built locally, migrate the local tag:

```bash
podman-hpc migrate localhost/communication-libraries-image:openmpi-ofi-ucx-gpu
```

## Minimal Slurm Pattern

Each user-facing page points to a standalone script. The common submission pattern is:

```bash
APP_COMMAND='./my_app input.yaml' \
  sbatch --export=ALL scripts/perlmutter-images/run-openmpi-ofi-ucx-gpu.sbatch
```

The script sets the image, PMIx environment, CXI/GPU mounts, and `podman-hpc shared-run` command.
