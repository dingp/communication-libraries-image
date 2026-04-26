# OpenSHMEM

OpenSHMEM support is enabled in the `openmpi-ofi-ucx-*` targets. The OFI-only OpenMPI targets intentionally keep OpenSHMEM disabled.

OpenMPI OFI+UCX build:

```text
--with-ofi=/usr
--with-ucx=/usr
--enable-oshmem
```

Resulting OpenSHMEM components include UCX-backed paths:

```text
OpenSHMEM API
  |
  +-- OpenMPI OSHMEM
        |
        +-- spml: ucx
        +-- atomic: ucx
        +-- sshmem: ucx
```

This is why the combined OpenMPI targets include UCX: OpenSHMEM needs a usable SPML path, and the UCX components provide it.

MPI traffic remains independent from this choice when the runtime sets:

```bash
OMPI_MCA_pml=cm
OMPI_MCA_mtl=ofi
FI_PROVIDER=cxi
```
