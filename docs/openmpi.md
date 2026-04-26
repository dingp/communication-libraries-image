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
