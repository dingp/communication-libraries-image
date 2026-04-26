# OpenMPI

The OpenMPI images build OpenMPI 5 inside the container with image-provided libfabric and PMIx.
The default Perlmutter runtime path is OFI/CXI.

## Images

| Image | Node type | Notes |
| --- | --- | --- |
| `ghcr.io/dingp/communication-libraries-image:openmpi-cpu` | CPU | OpenMPI with OFI and PMIx |
| `ghcr.io/dingp/communication-libraries-image:openmpi-gpu` | GPU | CUDA-aware OpenMPI with OFI and PMIx |
| `ghcr.io/dingp/communication-libraries-image:openmpi-ofi-ucx-cpu` | CPU | OFI plus UCX, OpenSHMEM enabled |
| `ghcr.io/dingp/communication-libraries-image:openmpi-ofi-ucx-gpu` | GPU | CUDA-aware OFI plus UCX, OpenSHMEM enabled |

## Runtime

Pull and migrate:

```bash
podman-hpc pull ghcr.io/dingp/communication-libraries-image:openmpi-ofi-ucx-gpu
podman-hpc migrate ghcr.io/dingp/communication-libraries-image:openmpi-ofi-ucx-gpu
```

Submit the standalone script:

```bash
sbatch scripts/perlmutter-images/run-openmpi-ofi-ucx-gpu.sbatch
```

Override the application command:

```bash
APP_COMMAND='./my_openmpi_app input.yaml' \
  sbatch --export=ALL scripts/perlmutter-images/run-openmpi-ofi-ucx-gpu.sbatch
```

For the OFI-only image:

```bash
sbatch scripts/perlmutter-images/run-openmpi-gpu.sbatch
```

For CPU nodes:

```bash
sbatch scripts/perlmutter-images/run-openmpi-cpu.sbatch
sbatch scripts/perlmutter-images/run-openmpi-ofi-ucx-cpu.sbatch
```

## Runtime Settings

Use PMIx from Slurm:

```bash
srun --mpi=pmix
PMIX_MCA_psec=native
```

Use OFI/CXI for MPI traffic:

```bash
FI_PROVIDER=cxi
OMPI_MCA_pml=cm
OMPI_MCA_mtl=ofi
```

The `openmpi-ofi-ucx-*` images include UCX and enable OpenSHMEM, but the default MPI path remains OFI/CXI.
Use those combined images when you need OpenSHMEM or want an image that also carries UCX components.

## LINKx Status

OpenMPI deployments that use LINKx typically set:

```bash
PMIX_MCA_psec=native
FI_PROVIDER=lnx
FI_LNX_PROV_LINKS='shm+cxi:cxi0|shm+cxi:cxi1|shm+cxi:cxi2|shm+cxi:cxi3'
FI_SHM_USE_XPMEM=1
OMPI_MCA_pml=cm
OMPI_MCA_mtl=ofi
OMPI_MCA_mtl_ofi_av=table
```

That is the intended OFI layout for combining `shm` intra-node traffic with `cxi` inter-node traffic.
Container recipes often still default to the CXI-only runtime path because LINKx needs site-specific validation with the MPI, libfabric, xpmem, and container runtime stack.

For these Perlmutter containers, LINKx is not part of the default runtime path.
The tested libfabric 2.1.0 and 2.3.1 container images both list the `lnx` provider, but `fi_info` does not return usable `shm+cxi` provider entries on Perlmutter:

```bash
FI_PROVIDER=lnx \
FI_LNX_PROV_LINKS=shm+cxi:cxi0 \
FI_SHM_USE_XPMEM=0 \
fi_info -p lnx -c FI_TAGGED -t FI_EP_RDM
```

returns:

```text
fi_getinfo: -61 (No data available)
```

Use the CXI path unless you are intentionally debugging LINKx.
The benchmark script has an opt-in `RUN_LNX=1` diagnostic for that purpose.

## OB1 Shared-Memory Option

OpenMPI can also use shared memory without LINKx by switching from the `cm` PML to the `ob1` PML and composing BTLs:

```bash
PMIX_MCA_psec=native
FI_PROVIDER=cxi
OMPI_MCA_pml=ob1
OMPI_MCA_btl=self,sm,ofi
OMPI_MCA_btl_ofi_mode=1
OMPI_MCA_btl_ofi_provider_include=cxi
OMPI_MCA_smsc=xpmem,cma
```

For CUDA-buffer experiments, include `smcuda`:

```bash
OMPI_MCA_btl=self,sm,smcuda,ofi
```

This is not the default runtime path.
It can improve same-node host-buffer traffic by using OpenMPI's shared-memory BTL, but the tested OFI BTL off-node path is much slower than the default `cm`/`mtl/ofi` path.
The tested `smcuda` path was also slower than the default CXI path for CUDA buffers.
Use this only when the application is dominated by same-node host-buffer MPI traffic, or as a diagnostic for shared-memory behavior.

## mpi4py Test

The default MPICH and OpenMPI scripts run:

```bash
python3 /workspace/tests/test_mpi4py.py
```

This verifies that Python extension modules are using the MPI library inside the image and that Slurm PMIx wire-up works across ranks.

## Benchmark Results

OSU Micro-Benchmarks 7.5.2 were run on Perlmutter with CXI enabled.
For the OpenMPI results, "intra-node" means the two ranks were placed on one node.
It does not mean OpenMPI used its shared-memory BTL path.
The benchmark script sets `OMPI_MCA_pml=cm`, `OMPI_MCA_mtl=ofi`, and `FI_PROVIDER=cxi`, so both inter-node and intra-node MPI traffic use OpenMPI's OFI MTL over libfabric's CXI provider.
This is why OpenMPI intra-node bandwidth is much lower than the MPICH intra-node result, where MPICH was built with `--with-xpmem=/usr` and can use its CH4 shared-memory/XPMEM path for same-node ranks.

A focused `ob1`/BTL experiment was also run with `bench-openmpi-ofi-ucx-*` images.
The host-buffer same-node cases improved, but off-node `ob1`/OFI bandwidth was much lower than the default `cm`/OFI path, and CUDA-buffer `smcuda` did not improve the same-node result.

| Node type | Runtime path | Placement | Buffer | Best result |
| --- | --- | --- | --- | --- |
| CPU | `cm` + `mtl/ofi` + `cxi` | 1 CPU node, 2 ranks | host | 23,336.66 MB/s at 4 MiB |
| CPU | `ob1` + `self,sm,ofi` | 1 CPU node, 2 ranks | host | 47,035.04 MB/s at 128 KiB |
| CPU | `ob1` + `self,sm,ofi` | 2 CPU nodes, 2 ranks | host | 3,733.96 MB/s at 512 KiB |
| GPU | `cm` + `mtl/ofi` + `cxi` | 1 GPU node, 2 ranks | host | 24,048.03 MB/s at 4 MiB |
| GPU | `ob1` + `self,sm,ofi` | 1 GPU node, 2 ranks | host | 40,628.51 MB/s at 2 MiB |
| GPU | `ob1` + `self,sm,ofi` | 2 GPU nodes, 2 ranks | host | 4,106.17 MB/s at 1 MiB |
| GPU | `cm` + `mtl/ofi` + `cxi` | 1 GPU node, 2 ranks | CUDA | 24,238.85 MB/s at 4 MiB |
| GPU | `ob1` + `self,sm,smcuda,ofi` | 1 GPU node, 2 ranks | CUDA | 10,344.34 MB/s at 4 MiB |
| GPU | `ob1` + `self,sm,smcuda,ofi` | 2 GPU nodes, 2 ranks | CUDA | 3,987.26 MB/s at 1 MiB |

The detailed snapshot is in [`benchmarks/reports/perlmutter-openmpi-ob1-btl-20260426.md`](../benchmarks/reports/perlmutter-openmpi-ob1-btl-20260426.md).

CPU results:

| Image | Test | Placement | Best result |
| --- | --- | --- | --- |
| `bench-openmpi-cpu` | `osu_bw --validation` | 2 CPU nodes | 23,957.45 MB/s at 4 MiB |
| `bench-openmpi-cpu` | `osu_bw --validation` | 1 CPU node, 2 ranks | 20,626.52 MB/s at 2 MiB |
| `bench-openmpi-cpu` | `osu_alltoall --validation` | 2 CPU nodes, 8 ranks | 8.99 us at 2 B |
| `bench-openmpi-ofi-ucx-cpu` | `osu_bw --validation` | 2 CPU nodes | 23,959.66 MB/s at 4 MiB |
| `bench-openmpi-ofi-ucx-cpu` | `osu_bw --validation` | 1 CPU node, 2 ranks | 19,570.71 MB/s at 2 MiB |
| `bench-openmpi-ofi-ucx-cpu` | `osu_alltoall --validation` | 2 CPU nodes, 8 ranks | 8.88 us at 4 B |

GPU results:

| Image | Test | Placement | Buffer | Best result |
| --- | --- | --- | --- | --- |
| `bench-openmpi-gpu` | `osu_bw --validation` | 2 GPU nodes | host | 24,147.06 MB/s at 4 MiB |
| `bench-openmpi-gpu` | `osu_bw --validation` | 1 GPU node, 2 ranks | host | 23,501.83 MB/s at 4 MiB |
| `bench-openmpi-gpu` | `osu_bw --validation -d cuda` | 2 GPU nodes | CUDA | 23,987.99 MB/s at 2 MiB |
| `bench-openmpi-gpu` | `osu_bw --validation -d cuda` | 1 GPU node, 2 ranks | CUDA | 23,698.49 MB/s at 4 MiB |
| `bench-openmpi-gpu` | `osu_alltoall --validation` | 2 GPU nodes, 8 ranks | host | 32.17 us at 2 B |
| `bench-openmpi-gpu` | `osu_alltoall --validation -d cuda` | 2 GPU nodes, 8 ranks | CUDA | 47.87 us at 256 B |
| `bench-openmpi-ofi-ucx-gpu` | `osu_bw --validation` | 2 GPU nodes | host | 24,256.57 MB/s at 4 MiB |
| `bench-openmpi-ofi-ucx-gpu` | `osu_bw --validation` | 1 GPU node, 2 ranks | host | 24,228.05 MB/s at 4 MiB |
| `bench-openmpi-ofi-ucx-gpu` | `osu_bw --validation -d cuda` | 2 GPU nodes | CUDA | 23,392.70 MB/s at 2 MiB |
| `bench-openmpi-ofi-ucx-gpu` | `osu_bw --validation -d cuda` | 1 GPU node, 2 ranks | CUDA | 23,713.81 MB/s at 4 MiB |
| `bench-openmpi-ofi-ucx-gpu` | `osu_alltoall --validation` | 2 GPU nodes, 8 ranks | host | 32.55 us at 32 B |
| `bench-openmpi-ofi-ucx-gpu` | `osu_alltoall --validation -d cuda` | 2 GPU nodes, 8 ranks | CUDA | 48.34 us at 256 B |

Run the OpenMPI benchmark jobs:

```bash
MPI_IMPL=openmpi sbatch --export=ALL benchmarks/scripts/perlmutter/run-mpi-osu-gpu.sbatch
MPI_IMPL=openmpi-ofi-ucx sbatch --export=ALL benchmarks/scripts/perlmutter/run-mpi-osu-gpu.sbatch
```
