# MPICH

The open-source MPICH targets build MPICH inside the image against the image's libfabric and PMIx.

Image targets:

- `mpich-cpu`
- `mpich-gpu`

Configure shape:

```text
--with-device=ch4:ofi
--with-libfabric=/usr
--with-xpmem=/usr
--with-pmi=pmix
--with-pmix=/opt/pmix
--with-pm=no
```

The GPU target adds CUDA support:

```text
--with-cuda=/usr/local/cuda
MPIR_CVAR_CH4_OFI_ENABLE_HMEM=1
```

Runtime selection:

```bash
FI_PROVIDER=cxi
PMIX_MCA_psec=native
```

Test command:

```bash
scripts/run-perlmutter.sh cpu mpich
scripts/run-perlmutter.sh gpu mpich
```
