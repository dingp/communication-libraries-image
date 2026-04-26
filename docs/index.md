# Documentation Index

This directory documents the communication stack pieces used by the image recipes.

| Page | Scope |
| --- | --- |
| [CXI](cxi.md) | Perlmutter Slingshot device interface and container device exposure |
| [libfabric and OFI](libfabric-ofi.md) | OFI API, libfabric implementation, and the CXI provider |
| [UCX](ucx.md) | UCX as an optional OpenMPI/OpenSHMEM transport layer |
| [PMIx](pmix.md) | Slurm process wire-up used by MPI and SHMEM runtimes |
| [MPI](mpi.md) | Shared MPI assumptions for MPICH and OpenMPI |
| [MPICH](mpich.md) | Open-source MPICH CH4/OFI images |
| [OpenMPI](openmpi.md) | OFI-only and OFI+UCX OpenMPI images |
| [NCCL](nccl.md) | GPU collective communication through AWS OFI NCCL |
| [OpenSHMEM](openshmem.md) | OpenSHMEM support in the OpenMPI OFI+UCX images |
| [NVSHMEM](nvshmem.md) | GPU SHMEM runtime built on libfabric, PMIx, NCCL, and CUDA |
| [Runtime](runtime.md) | Perlmutter run-time namespace, device, and environment requirements |
| [Podman Backend](podman-backend.md) | Local Podman backend builds and PMIx keep-id observations |
