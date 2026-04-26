# OpenMPI OB1 BTL Experiment

Generated: 2026-04-26

This focused OSU Micro-Benchmarks 7.5.2 run tested whether OpenMPI can use shared memory for same-node traffic without the libfabric LINKx provider.
The tested images were:

- `ghcr.io/dingp/communication-libraries-image:bench-openmpi-ofi-ucx-cpu`
- `ghcr.io/dingp/communication-libraries-image:bench-openmpi-ofi-ucx-gpu`

The default comparison path was:

```bash
PMIX_MCA_psec=native
FI_PROVIDER=cxi
OMPI_MCA_pml=cm
OMPI_MCA_mtl=ofi
```

The host-buffer shared-memory test path was:

```bash
PMIX_MCA_psec=native
FI_PROVIDER=cxi
OMPI_MCA_pml=ob1
OMPI_MCA_btl=self,sm,ofi
OMPI_MCA_btl_ofi_mode=1
OMPI_MCA_btl_ofi_provider_include=cxi
OMPI_MCA_smsc=xpmem,cma
```

The CUDA-buffer shared-memory test added `smcuda`:

```bash
OMPI_MCA_btl=self,sm,smcuda,ofi
```

## Summary

The `ob1`/BTL path is useful as a same-node host-buffer diagnostic and may help host-buffer-heavy workloads.
It should not replace the default OpenMPI runtime for general jobs because the tested off-node OFI BTL path is much slower than `cm`/`mtl/ofi`.
For CUDA buffers, the tested `smcuda` path was slower than the default CXI path.

## Results

| Node type | Case | Placement | Buffer | Best bandwidth |
| --- | --- | --- | --- | --- |
| CPU | `cm` + `mtl/ofi` + `cxi` | 1 CPU node, 2 ranks | host | 23,336.66 MB/s at 4 MiB |
| CPU | `ob1` + `self,sm,ofi` | 1 CPU node, 2 ranks | host | 47,035.04 MB/s at 128 KiB |
| CPU | `ob1` + `self,sm,ofi` | 2 CPU nodes, 2 ranks | host | 3,733.96 MB/s at 512 KiB |
| CPU | `ob1` + `self,sm,tcp` | 1 CPU node, 2 ranks | host | 46,898.01 MB/s at 128 KiB |
| GPU | `cm` + `mtl/ofi` + `cxi` | 1 GPU node, 2 ranks | host | 24,048.03 MB/s at 4 MiB |
| GPU | `ob1` + `self,sm,ofi` | 1 GPU node, 2 ranks | host | 40,628.51 MB/s at 2 MiB |
| GPU | `ob1` + `self,sm,ofi` | 2 GPU nodes, 2 ranks | host | 4,106.17 MB/s at 1 MiB |
| GPU | `cm` + `mtl/ofi` + `cxi` | 1 GPU node, 2 ranks | CUDA | 24,238.85 MB/s at 4 MiB |
| GPU | `ob1` + `self,sm,smcuda,ofi` | 1 GPU node, 2 ranks | CUDA | 10,344.34 MB/s at 4 MiB |
| GPU | `ob1` + `self,sm,smcuda,ofi` | 2 GPU nodes, 2 ranks | CUDA | 3,987.26 MB/s at 1 MiB |

## Interpretation

For host buffers, `ob1,self,sm,ofi` confirms that OpenMPI can use the `sm` BTL for same-node traffic in these containers.
The CPU same-node result was about 2.0x the default CXI-only path in this run.
The GPU-node host-buffer same-node result was about 1.7x the default CXI-only path.

For off-node traffic, `ob1` with the OFI BTL over CXI reached only about 4 GB/s in these two-node point-to-point tests.
That is far below the roughly 24 GB/s normally measured with `cm`/`mtl/ofi`.

For CUDA buffers, `ob1,self,sm,smcuda,ofi` did not help: same-node bandwidth was about 10.3 GB/s, compared with about 24.2 GB/s for `cm`/`mtl/ofi` over CXI.

The default OpenMPI path should therefore remain `cm`/`mtl/ofi` with `FI_PROVIDER=cxi`.
Use `ob1`/BTL only for targeted same-node host-buffer tests or workloads where the off-node path is not performance-critical.
