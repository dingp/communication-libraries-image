# NVSHMEM

NVSHMEM is GPU-only in this repository. The `nvshmem-gpu` target layers NVSHMEM on `nccl-gpu`, which is itself layered on `openmpi-ofi-ucx-gpu`.

Image target:

- `nvshmem-gpu`

Build features:

```text
NVSHMEM_LIBFABRIC_SUPPORT=1
NVSHMEM_PMIX_SUPPORT=1
NVSHMEM_MPI_SUPPORT=1
NVSHMEM_MPI_IS_OMPI=1
NVSHMEM_SHMEM_SUPPORT=1
NVSHMEM_USE_NCCL=1
NVSHMEM_USE_GDRCOPY=1
```

Runtime shape:

```text
NVSHMEM
  +-- PMIx for process wire-up
  +-- libfabric cxi for remote transport
  +-- NCCL for supported collectives
  +-- CUDA/GDRCopy for GPU memory paths
```

Default environment:

```bash
NVSHMEM_HOME=/opt/nvshmem
NVSHMEM_REMOTE_TRANSPORT=libfabric
NVSHMEM_LIBFABRIC_PROVIDER=cxi
NVSHMEM_DISABLE_CUDA_VMM=1
```

Test command:

```bash
scripts/run-perlmutter.sh gpu nvshmem
```
