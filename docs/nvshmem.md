# NVSHMEM

NVSHMEM is GPU-only in this repository. The `nvshmem-gpu` target layers NVSHMEM on `nccl-gpu`, which is itself layered on `libfabric-gpu`. OpenMPI is not required by this target.

Image target:

- `nvshmem-gpu`

Build features:

```text
CUDA 13 package: libnvshmem3-cuda-13
Development package: libnvshmem3-dev-cuda-13
Static device library package: libnvshmem3-static-cuda-13
Local smoke test: /opt/nvshmem-tests/nvshmem_hello
```

This image uses the NVIDIA CUDA repository packages because the OS-agnostic source tarball is distributed through NVIDIA's authenticated download flow. The image keeps PMIx and libfabric/CXI available, and removes the packaged MPI, OpenSHMEM, UCX, and InfiniBand transport plugins so the target does not pull OpenMPI back into the runtime path.

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
NVSHMEM_BOOTSTRAP=PMI
NVSHMEM_BOOTSTRAP_PMI=PMIX
NVSHMEM_REMOTE_TRANSPORT=libfabric
NVSHMEM_LIBFABRIC_PROVIDER=cxi
NVSHMEM_DISABLE_CUDA_VMM=1
```

Test command:

```bash
scripts/run-perlmutter.sh gpu nvshmem
```

The default command is a small NVSHMEM hello binary built into the image. It is intended to verify Slurm PMIx bootstrap, GPU selection, and the libfabric/CXI transport path; application benchmarks should pass their own command.
