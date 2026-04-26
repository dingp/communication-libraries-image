# MPI

The MPI images contain the MPI implementation inside the image. They do not rely on host MPICH injection from `podman-hpc --mpi`.

Common assumptions:

```text
application
  |
  +-- MPI ABI from image
        |
        +-- PMIx client from image
        +-- OFI/libfabric from image
              |
              +-- cxi provider
                    |
                    +-- host /dev/cxi*
```

MPI implementations:

- [MPICH](mpich.md) uses CH4/OFI.
- [OpenMPI](openmpi.md) uses OFI by default and has an optional OFI+UCX build.

Run-time launch still comes from Slurm:

```bash
srun --mpi=pmix podman-hpc shared-run ...
```

The container runtime must expose CXI and Slurm runtime state. See [Runtime](runtime.md).
