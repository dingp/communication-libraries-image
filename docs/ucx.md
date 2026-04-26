# UCX

UCX is built for the `openmpi-ofi-ucx-*` targets. It is not the default Slingshot MPI path in these images; default MPI traffic is still steered through OpenMPI's OFI MTL and libfabric `cxi`.

Image targets:

- `openmpi-ofi-ucx-cpu`
- `openmpi-ofi-ucx-gpu`

CPU UCX build:

```text
--prefix=/usr
--enable-mt
--enable-devel-headers
```

GPU UCX build:

```text
--prefix=/usr
--with-cuda=/usr/local/cuda
--with-gdrcopy=/usr/local
--enable-mt
--enable-devel-headers
```

OpenMPI then sees UCX components such as:

```text
pml: ucx
osc: ucx
spml: ucx
```

The image keeps these components available for OpenSHMEM and portability tests. For Perlmutter MPI runs, use:

```bash
OMPI_MCA_pml=cm
OMPI_MCA_mtl=ofi
FI_PROVIDER=cxi
```
