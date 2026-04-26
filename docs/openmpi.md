# OpenMPI

OpenMPI targets are built inside the image against image-provided libfabric and PMIx.

Image targets:

- `openmpi-cpu`
- `openmpi-gpu`
- `openmpi-ofi-ucx-cpu`
- `openmpi-ofi-ucx-gpu`

The OFI-only targets build OpenMPI with:

```text
--with-ofi=/usr
--with-pmix=/opt/pmix
--without-ucx
--disable-oshmem
```

The OFI+UCX targets build OpenMPI with:

```text
--with-ofi=/usr
--with-ucx=/usr
--with-pmix=/opt/pmix
--enable-oshmem
```

The GPU variants add:

```text
--with-cuda=/usr/local/cuda
--with-cuda-libdir=/usr/local/cuda/targets/x86_64-linux/lib/stubs
```

Default Perlmutter MPI runtime:

```bash
OMPI_MCA_pml=cm
OMPI_MCA_mtl=ofi
FI_PROVIDER=cxi
PMIX_MCA_psec=native
```

That keeps Slingshot MPI traffic on OFI/CXI even when UCX is present in the image. UCX remains available for explicit UCX tests and OpenSHMEM components.

CSCS documents LINKx for uenv OpenMPI with `FI_PROVIDER=lnx`, `FI_LNX_PROV_LINKS=shm+cxi:cxi0|...`, `FI_SHM_USE_XPMEM=1`, and `OMPI_MCA_mtl_ofi_av=table`.
That is intended to route intra-node traffic through `shm` and inter-node traffic through `cxi`.
Their container OpenMPI section still uses the CXI provider environment and states that LINKx instructions are not currently provided for manually built container images.

On Perlmutter with these containers, libfabric 2.1.0 and a local libfabric 2.3.1 test image both list `lnx` in `fi_info -l`, but `fi_info -p lnx -c FI_TAGGED -t FI_EP_RDM` with `FI_LNX_PROV_LINKS=shm+cxi:cxi0` returns `fi_getinfo: -61`.
Keep `FI_PROVIDER=cxi` as the default container path; use `RUN_LNX=1` in the CPU OSU benchmark script only as an experimental diagnostic.
