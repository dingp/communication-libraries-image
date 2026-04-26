# libfabric And OFI

libfabric provides the OFI API used by MPI, NCCL plugins, and NVSHMEM to reach the Perlmutter Slingshot network.
These images build libfabric with the `cxi` provider and include Cassini/CXI headers, libcxi, and XPMEM user-space support.

## Images

| Image | Node type | Contains |
| --- | --- | --- |
| `ghcr.io/dingp/communication-libraries-image:libfabric-cpu` | CPU | libfabric with CXI/LNX/EFA, libcxi, XPMEM |
| `ghcr.io/dingp/communication-libraries-image:libfabric-gpu` | GPU | CPU contents plus CUDA and GDRCopy support |

## Runtime

Use these images when you need a low-level OFI/CXI base or want to check that the container can see the Perlmutter network devices.

Pull and migrate:

```bash
podman-hpc pull ghcr.io/dingp/communication-libraries-image:libfabric-gpu
podman-hpc migrate ghcr.io/dingp/communication-libraries-image:libfabric-gpu
```

Run the standalone smoke script:

```bash
sbatch scripts/perlmutter-images/run-libfabric-gpu.sbatch
```

The default command checks the libfabric provider list. Override it for your own OFI test:

```bash
APP_COMMAND='fi_info -p cxi' \
  sbatch --export=ALL scripts/perlmutter-images/run-libfabric-gpu.sbatch
```

## Important Environment

```bash
FI_PROVIDER=cxi
FI_MR_CACHE_MONITOR=userfaultfd
FI_CXI_DISABLE_HOST_REGISTER=1
```

`FI_PROVIDER=cxi` selects the Slingshot provider. The other variables match the settings used in the MPI, NCCL, and NVSHMEM run scripts.

## Benchmark Results

There is no standalone libfabric benchmark page in this repository.
The libfabric/CXI path is validated through the higher-level libraries that use it.

Perlmutter benchmark snapshot from 2026-04-26:

| Library using libfabric | Benchmark | Best result |
| --- | --- | --- |
| MPICH CH4/OFI | OSU `osu_bw`, CPU inter-node | 23,958.47 MB/s at 4 MiB |
| OpenMPI OFI | OSU `osu_bw`, GPU inter-node CUDA buffer | 23,987.99 MB/s at 2 MiB |
| OpenMPI OFI+UCX | OSU `osu_bw`, GPU inter-node CUDA buffer | 23,392.70 MB/s at 2 MiB |
| NCCL aws-ofi-nccl | `all_reduce_perf`, in-place bus bandwidth | 18.34 GB/s at 8 MiB |
| NVSHMEM libfabric transport | `alltoall_latency`, bus bandwidth | 3.09 GB/s at 1 MiB, 32-bit block scope |

Run the full benchmark matrix with the scripts in `benchmarks/scripts/perlmutter/`.
