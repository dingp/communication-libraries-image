# libfabric and OFI

OFI is the API used by MPI, NCCL plugins, and SHMEM runtimes to reach high-speed networks. libfabric is the implementation used here, and the `cxi` provider is the Slingshot path on Perlmutter.

Image targets:

- `libfabric-cpu`
- `libfabric-gpu`

Build features:

```text
libfabric
  +-- cxi provider for Slingshot/Cassini
  +-- lnx provider
  +-- efa provider
  +-- xpmem support
  +-- CUDA and GDRCopy support in GPU images
```

The GPU target enables CUDA-aware libfabric support and GDRCopy:

```text
--with-cuda=/usr/local/cuda
--enable-cuda-dlopen
--enable-gdrcopy-dlopen
```

Default runtime selection:

```bash
FI_PROVIDER=cxi
FI_MR_CACHE_MONITOR=userfaultfd
```

The images intentionally contain libfabric and CXI userspace libraries so they do not depend on the older `podman-hpc --mpi` MPICH module path.
