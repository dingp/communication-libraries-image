# Podman-HPC NCCL 8-Node Test With aws-ofi-nccl 1.19.0

This note records an 8-node Perlmutter `podman-hpc` run of the MPICH-backed NCCL benchmark image.
The test uses one MPI rank per GPU, four GPU ranks per node, and `all_reduce_perf -b 8 -e 4G -f 2`.

## Summary

| Component | Version or setting |
| --- | --- |
| Image | `ghcr.io/dingp/communication-libraries-image:bench-nccl-mpich-gpu` |
| Container runtime | `podman-hpc shared-run` |
| Podman backend | older backend selected by the benchmark wrapper, `/global/common/shared/das/podman-4.7.0/bin/podman` |
| MPI | MPICH inside the image, launched by Slurm PMIx |
| NCCL | `2.29.2+cuda13.2` |
| aws-ofi-nccl | `1.19.0` |
| libfabric | `2.1` |
| Test | `all_reduce_perf -b 8 -e 4G -f 2` |
| Placement | 8 GPU nodes, 4 ranks per node, 32 total ranks |
| Network | CXI provider, 4 CXI NICs found per node |
| DMA-BUF | disabled with `OFI_NCCL_DISABLE_DMABUF=1` |

The image was pulled from GHCR and migrated before submission:

```bash
podman-hpc pull ghcr.io/dingp/communication-libraries-image:bench-nccl-mpich-gpu
podman-hpc migrate ghcr.io/dingp/communication-libraries-image:bench-nccl-mpich-gpu
```

## Findings

Two 8-node `podman-hpc` runs were made. Both completed, but only the host runtime profile matched the host-side performance.

| Run | Job | Runtime profile | 4 GiB in-place time | 4 GiB in-place algbw | 4 GiB in-place busbw | Avg busbw | Result |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| podman-hpc, host profile | `52678328` | `NCCL_RUNTIME_PROFILE=host` | 120,722 us | 35.58 GB/s | 68.93 GB/s | 19.5893 GB/s | Passed |
| podman-hpc, default profile | `52678124` | `NCCL_RUNTIME_PROFILE=default` | 349,193 us | 12.30 GB/s | 23.83 GB/s | 7.75776 GB/s | Passed, slow |

The host-profile run is the useful comparison point. It selected CXI, used aws-ofi-nccl 1.19.0 with libfabric 2.1, disabled DMA-BUF registrations, and used GDRDMA:

```text
NET/OFI Initializing aws-ofi-nccl 1.19.0
NET/OFI Using Libfabric version 2.1
NET/OFI Selected provider is cxi, fabric is cxi (found 4 nics)
NET/OFI Using transport protocol SENDRECV
NET/OFI Support for DMA-BUF registrations: false
Connected all rings, use ring PXN 0 GDR 1
```

The 4 GiB row from the successful host-profile run:

```text
bytes        count       type   redop  root   time(us) algbw busbw errors time(us) algbw busbw errors
4294967296   1073741824 float  sum    -1     120675   35.59 68.96 0      120722   35.58 68.93 0
```

The run completed without validation errors:

```text
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 19.5893
# Collective test concluded: all_reduce_perf
```

The default profile also completed, but it was much slower at the large-message end:

```text
bytes        count       type   redop  root   time(us) algbw busbw errors time(us) algbw busbw errors
4294967296   1073741824 float  sum    -1     350261   12.26 23.76 0      349193   12.30 23.83 0

# Avg bus bandwidth    : 7.75776
```

The default profile explicitly maps each local rank to one CXI device through `FI_CXI_DEVICE_NAME` and exports several low-level FI/NCCL tuning variables. In this 8-node test that path completed, but the bandwidth was about one third of the host-profile path. Use `NCCL_RUNTIME_PROFILE=host` for this 8-node NCCL comparison until the default container profile is tuned further.

## Comparison

The host-profile container run closely matches the comparable 8-node host run.

| Case | Nodes | Ranks | 4 GiB in-place time | 4 GiB in-place algbw | 4 GiB in-place busbw | Avg busbw |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Host, no DMA-BUF | 8 | 32 | 120,628 us | 35.61 GB/s | 68.99 GB/s | 18.8798 GB/s |
| podman-hpc, host profile | 8 | 32 | 120,722 us | 35.58 GB/s | 68.93 GB/s | 19.5893 GB/s |
| podman-hpc, host profile | 2 | 8 | 103,702 us | 41.42 GB/s | 72.48 GB/s | 23.7324 GB/s |

At 4 GiB, the 8-node container host-profile run is effectively equal to the 8-node host run. Compared with the earlier 2-node container host-profile run, 8 nodes reduce bus bandwidth from 72.48 GB/s to 68.93 GB/s, about a 4.9% drop.

## Run Instructions

Create a scratch output directory:

```bash
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_ROOT="${SCRATCH}/communication-libraries-image/podman-hpc-nccl-runs/8node-hostprofile-${RUN_ID}"
mkdir -p "${OUT_ROOT}/slurm" "${OUT_ROOT}/results"
```

Submit from the repository root:

```bash
sbatch -A <account> -q <gpu_qos> -C gpu \
  --nodes=8 \
  --ntasks-per-node=4 \
  --gpus-per-task=1 \
  --time=00:25:00 \
  --chdir="${PWD}" \
  --output="${OUT_ROOT}/slurm/sbatch-%j.out" \
  --export=ALL,NCCL_MPI_IMPL=mpich,NCCL_RUNTIME_PROFILE=host,NCCL_DEBUG=INFO,NCCL_TEST_ARGS="-b 8 -e 4G -f 2",NODES=8,TASKS_PER_NODE=4,GPUS_PER_NODE=4,IMAGE=ghcr.io/dingp/communication-libraries-image:bench-nccl-mpich-gpu,OFI_NCCL_DISABLE_DMABUF=1,JOB_OUTPUT_DIR="${OUT_ROOT}/slurm",RESULT_DIR="${OUT_ROOT}/results" \
  benchmarks/scripts/perlmutter/run-nccl-all-reduce-gpu.sbatch
```

The result log will be written as:

```text
${OUT_ROOT}/results/nccl-mpich-gpu-all-reduce-cxi.log
```

The Slurm stdout copy will be written as:

```text
${OUT_ROOT}/slurm/nccl-all-reduce-<jobid>.out
```

## Notes

- `OFI_NCCL_DISABLE_DMABUF=1` is intentionally carried over from the host-side validation. With aws-ofi-nccl 1.19.0 and libfabric 2.1.0, the default DMA-BUF path failed in earlier tests with `NO_SPACE` completions.
- `NCCL_RUNTIME_PROFILE=host` leaves CXI provider selection to the NCCL/aws-ofi-nccl/libfabric stack inside the container. In this test it selected CXI and GDRDMA correctly.
- The `podman-hpc` wrapper in this repository still defaults to the older Podman backend for PMIx jobs because the site Podman backend has had `--userns=keep-id` issues on compute nodes.
