# NCCL

NCCL is GPU-only in this repository. The `nccl-gpu` target layers NCCL and the AWS OFI NCCL plugin directly on `libfabric-gpu`. It does not install OpenMPI, MPICH, or UCX.

Image target:

- `nccl-gpu`

Stack:

```text
NCCL collectives
  |
  +-- AWS OFI NCCL plugin
        |
        +-- libfabric OFI
              |
              +-- cxi provider
                    |
                    +-- Slingshot/Cassini
```

Build choices:

```text
Base image: libfabric-gpu
NCCL package: 2.29.7-1+cuda13.2 by default
AWS OFI NCCL plugin: 1.19.0
nccl-tests: MPI=0, NVCC_GENCODE="-gencode=arch=compute_80,code=sm_80"
MPI runtime: not included
```

aws-ofi-nccl 1.19.0 release notes list NCCL 2.27.3-1, 2.28.7-1, and 2.29.7-1 as tested versions. The image pins the CUDA 13.2 build of 2.29.7 by default and exposes `NCCL_PACKAGE_VERSION` as a build argument for validation runs.

The bundled `nccl-tests` binaries are single-process GPU smoke tests. Distributed NCCL tests should be supplied by applications or Slurm wrapper scripts that own the rank count, GPU binding, and node layout.

Default environment:

```bash
NCCL_NET="AWS Libfabric"
NCCL_CROSS_NIC=1
NCCL_SOCKET_IFNAME=hsn
NCCL_NET_GDR_LEVEL=PHB
NCCL_NCHANNELS_PER_NET_PEER=4
FI_PROVIDER=cxi
FI_CXI_DISABLE_HOST_REGISTER=1
FI_MR_CACHE_MONITOR=userfaultfd
```

Test command:

```bash
scripts/run-perlmutter.sh gpu nccl
```

The default NCCL run script allocation is one node and one task. For distributed tests, pass a custom command and set `NODES` and `TASKS_PER_NODE` explicitly.
