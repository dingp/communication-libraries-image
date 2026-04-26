# PMIx

PMIx provides process wire-up between Slurm and the MPI or SHMEM runtime. These images build OpenPMIx inside the image and rely on Slurm's PMIx support at launch.

Build location:

```text
/opt/pmix
```

Default environment:

```bash
PATH=/opt/pmix/bin:$PATH
LD_LIBRARY_PATH=/opt/pmix/lib:$LD_LIBRARY_PATH
PKG_CONFIG_PATH=/opt/pmix/lib/pkgconfig:$PKG_CONFIG_PATH
PMIX_MCA_psec=native
```

Launch model:

```text
srun --mpi=pmix
  |
  +-- Slurm/PMIx server on the host
        |
        +-- PMIx client libraries inside the container
```

The run script currently passes Slurm, PMI, PMIx, PALS, and related runtime state manually. After the generic `podman-hpc --pmix` helper is deployed, `PODMANHPC_PMIX_HELPER=module` can switch to that helper.
