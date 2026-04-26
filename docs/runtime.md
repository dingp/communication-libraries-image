# Runtime Notes

The run scripts assume:

- The image contains libfabric with the CXI provider.
- The image contains its MPI implementation.
- Slurm launches ranks with `--mpi=pmix`.
- podman-hpc `shared-run` is used as the container runtime, not as the MPI provider.

Until a generic `podman-hpc --pmix` helper is deployed, `scripts/run-perlmutter.sh` passes the required Slurm, PMIx, CXI, and GPU devices explicitly.

The multi-node launch path mirrors the existing Perlmutter MPI test wrapper: host IPC/network/PID namespaces are shared, `/dev/shm` and `/dev/xpmem` are bind-mounted, and all visible `/dev/cxi*` devices are passed through. GPU runs additionally pass `/dev/nvidia*` and the host NVIDIA driver libraries.

Keep the GPU driver-library bind broad. Binding only `libcuda` can leave the container to load CUDA compat JIT libraries from the image while using the host driver, which is not the intended Perlmutter path. The run script binds the host driver companion libraries such as `libnvidia-ptxjitcompiler` and `libnvidia-nvvm` through the `/usr/lib64/libnvidia*` glob.

For Open MPI, the default runtime variables match the CSCS communication guidance:

```bash
PMIX_MCA_psec=native
FI_PROVIDER=cxi
OMPI_MCA_pml=cm
OMPI_MCA_mtl=ofi
```

The `openmpi-ofi-ucx-*` targets build Open MPI with both libfabric/OFI and UCX, and enable OpenSHMEM. Runtime MPI is still steered to OFI/CXI with `pml=cm` and `mtl=ofi`; UCX is present for OpenSHMEM/NVSHMEM-related support and for portability tests that explicitly select UCX.

For MPICH, the images are configured with:

```bash
--with-device=ch4:ofi
--with-libfabric=/usr
--with-pmi=pmix
--with-pmix=/opt/pmix
--with-pm=no
```

For NCCL, the image includes `aws-ofi-nccl` and defaults to:

```bash
NCCL_NET="AWS Libfabric"
FI_PROVIDER=cxi
FI_CXI_DISABLE_HOST_REGISTER=1
FI_MR_CACHE_MONITOR=userfaultfd
```
