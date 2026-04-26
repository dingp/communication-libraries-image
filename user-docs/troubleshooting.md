# Troubleshooting

## The Job Cannot See CXI Devices

Inside a compute-node allocation, check:

```bash
ls /dev/cxi*
```

The `podman-hpc shared-run` command must bind those devices into the container.
The standalone scripts do this automatically.

## MPI Or NVSHMEM PMIx Bootstrap Fails

Use Slurm PMIx:

```bash
srun --mpi=pmix ...
```

Make sure the container receives:

```bash
-e 'PMI_*'
-e 'PMIX_*'
-e PMIX_MCA_psec=native
```

If testing a site podman-hpc PMIx helper, set:

```bash
PODMANHPC_PMIX_HELPER=module
```

The repository scripts otherwise pass the PMIx environment explicitly.

## Multi-node Jobs Start Slowly

Pull and migrate the image before submitting:

```bash
podman-hpc pull ghcr.io/dingp/communication-libraries-image:openmpi-gpu
podman-hpc migrate ghcr.io/dingp/communication-libraries-image:openmpi-gpu
```

This makes the image available in the form expected by compute nodes.

## NCCL Reports That AWS Libfabric Is Not Found

Use:

```bash
NCCL_NET="AWS Libfabric"
```

Do not use:

```bash
NCCL_NET_PLUGIN=ofi
```

Run with `NCCL_DEBUG=INFO` to confirm that NCCL selected the AWS Libfabric network.

## NCCL Fails In Direct GPU-memory Transport

The benchmark script defaults to:

```bash
NCCL_NET_GDR_LEVEL=LOC
NCCL_GDRCOPY_ENABLE=0
```

This avoids a currently observed `FI_ENOSPC` failure in the direct net-GDR path.
Override those variables only when intentionally testing that path.

## MPICH CUDA-buffer OSU Fails With Positional D D

Use:

```bash
./pt2pt/osu_bw --validation -d cuda
```

Avoid the older positional OSU syntax:

```bash
./pt2pt/osu_bw --validation D D
```

The `-d cuda` form is what the Perlmutter benchmark script uses for MPICH CUDA-buffer tests.
