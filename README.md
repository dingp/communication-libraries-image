# Communication Libraries Image

Container image recipes and Perlmutter run scripts for Slingshot/CXI communication libraries.

The recipes are for NERSC Perlmutter CPU and GPU nodes. GPU images default to CUDA 13.2.0. Perlmutter currently has NVIDIA driver 580.105.08; NVIDIA documents R580 as the CUDA 13.x driver family, so CUDA 13.2 is expected to work through CUDA minor-version compatibility. The CUDA version is still a build argument so it can be pinned to 13.0 if site validation requires it.

## Targets

Public-source targets in `container/Containerfile`:

| Image tag | Nodes | Contents |
| --- | --- | --- |
| `libfabric-cpu` | CPU | XPMEM userspace, Cassini/CXI headers, libcxi, libfabric with CXI/LNX/EFA |
| `libfabric-gpu` | GPU | `libfabric-cpu` plus CUDA and GDRCopy support |
| `mpich-cpu` | CPU | `libfabric-cpu` plus MPICH CH4/OFI linked to PMIx |
| `mpich-gpu` | GPU | `mpich-cpu` equivalent with CUDA-aware MPICH build |
| `openmpi-cpu` | CPU | `libfabric-cpu` plus Open MPI 5 with OFI and external PMIx |
| `openmpi-gpu` | GPU | `openmpi-cpu` equivalent with CUDA-aware Open MPI build |
| `openmpi-ofi-ucx-cpu` | CPU | `openmpi-cpu` plus UCX and OpenSHMEM enabled |
| `openmpi-ofi-ucx-gpu` | GPU | CUDA-aware Open MPI with OFI, UCX, OpenSHMEM, and external PMIx |
| `nccl-gpu` | GPU | `libfabric-gpu`, NCCL, AWS OFI NCCL plugin, and single-process NCCL tests built without MPI |
| `nvshmem-gpu` | GPU | `nccl-gpu` plus CUDA 13 NVSHMEM packages, PMIx/libfabric runtime settings, and an NVSHMEM hello test |

## Per-Target Containerfiles

The source of truth is the multi-stage `container/Containerfile`. For easier reading and CI builds, the repository also carries one buildable Containerfile per named target under `container/targets/`.

The generator is `scripts/generate-target-containerfiles.py`. It parses named `FROM ... AS ...` stages from `container/Containerfile`, follows the parent-stage dependency closure for each target, and writes a single-target file containing only the top-level build arguments and the ancestor stages needed for that target. For example, `container/targets/mpich-gpu.Containerfile` contains `gpu-base`, `libfabric-gpu`, and `mpich-gpu`, but omits unrelated OpenMPI, NCCL, and NVSHMEM stages.

Useful commands:

```bash
# List all named stages.
scripts/generate-target-containerfiles.py --list

# Regenerate every per-target file under container/targets/.
scripts/generate-target-containerfiles.py

# Regenerate one target.
scripts/generate-target-containerfiles.py --target mpich-gpu

# Check that generated files are up to date. GitHub Actions runs this.
scripts/generate-target-containerfiles.py --check
```

`scripts/build.sh` and the GitHub Actions matrix build from `container/targets/<target>.Containerfile` directly. Edit `container/Containerfile`, regenerate, and commit both the source and generated files.

## Stack Relationships

These images keep the communication stack inside the container, while the host provides the kernel drivers, Slurm launch, and device files.

The main layers are:

| Layer | What it provides | Main techniques used |
| --- | --- | --- |
| CXI | Userspace access to the HPE Slingshot Cassini NIC. | Host kernel device files such as `/dev/cxi*`, libcxi ioctls, NIC command queues, completion queues, memory registration, and hardware offload. |
| OFI | A provider-neutral network API used by MPI, NCCL plugins, and PGAS libraries. | The libfabric API exposes endpoints, address vectors, completion queues, scalable endpoints, tagged messaging, RMA, atomics, and provider selection through `FI_PROVIDER=cxi`. |
| libfabric | The implementation of OFI and the container entry point to the CXI provider. | Provider plugins, memory registration cache, XPMEM-assisted intra-node paths, and optional CUDA/GDRCopy memory support in GPU images. |
| UCX | A communication framework used by OpenMPI components and OpenSHMEM. | Transport selection, active messages, RMA, tagged operations, shared memory transports, CUDA memory hooks, and optional GPUDirect-style paths. |
| PMIx | Process-management wire-up between Slurm and ranks inside the container. | Slurm hosts the PMIx server, the image carries the OpenPMIx client, and ranks exchange job metadata, endpoints, namespaces, and local topology. |
| MPI | The application-facing distributed-memory programming model. | Point-to-point messages, collectives, communicators, derived datatypes, one-sided RMA, and launcher integration through PMIx. |
| MPICH | MPI implementation used for CH4/OFI examples. | The CH4 device uses the OFI netmod, which maps MPI operations onto libfabric endpoints and the `cxi` provider. |
| OpenMPI | MPI and OpenSHMEM implementation used for the combined examples. | Modular components select the runtime path: `pml/cm` plus `mtl/ofi` for MPI over OFI/CXI, and UCX components for optional MPI paths and OSHMEM. |
| NCCL | GPU collective communication library. | CUDA kernels, topology-aware rings/trees, GPU buffers, and the AWS OFI NCCL plugin for Slingshot through libfabric/CXI. |
| OpenSHMEM | Partitioned global address space model for symmetric-memory communication. | Processing elements, symmetric heaps, puts/gets, atomics, barriers, and OpenMPI OSHMEM SPML components, with UCX in the combined images. |
| NVSHMEM | GPU-resident SHMEM programming model. | Symmetric GPU memory, device-side puts/gets/atomics, CUDA streams, PMIx bootstrap, libfabric/CXI transport, and NCCL-assisted collectives where applicable. |

MPI over Slingshot uses OFI/libfabric and the CXI provider:

```text
MPI application
  |
  +-- MPICH CH4/OFI
  |     |
  |     +-- OFI API
  |           |
  |           +-- libfabric cxi provider
  |                 |
  |                 +-- libcxi + host /dev/cxi*
  |                       |
  |                       +-- Slingshot/Cassini NIC
  |
  +-- OpenMPI default on Perlmutter
        |
        +-- PML cm -> MTL ofi
              |
              +-- OFI API -> libfabric cxi -> libcxi -> /dev/cxi*
```

PMIx is the process wire-up path from Slurm into the container:

```text
srun --mpi=pmix
  |
  +-- Slurm PMIx server on host
        |
        +-- OpenPMIx client in image
              |
              +-- MPI ranks or SHMEM PEs
```

The combined OpenMPI targets include both OFI and UCX:

```text
openmpi-ofi-ucx-*
  |
  +-- MPI default path:
  |     PML cm -> MTL ofi -> libfabric -> cxi
  |
  +-- Optional MPI/one-sided path:
  |     PML ucx / OSC ucx -> UCX transports
  |
  +-- OpenSHMEM path:
        OSHMEM -> SPML ucx -> UCX transports
```

GPU collectives and GPU SHMEM layer on the same network substrate:

```text
NCCL
  |
  +-- AWS OFI NCCL plugin -> libfabric/OFI -> cxi

NVSHMEM
  |
  +-- PMIx for wire-up
  +-- libfabric/OFI/cxi for remote transport
  +-- NCCL for supported collectives
  +-- CUDA/GDRCopy for GPU memory paths
```

The NCCL image is intentionally not an MPI image. It builds `nccl-tests` with `MPI=0`, which makes the bundled tests useful for single-process GPU smoke tests. Multi-rank NCCL validation should be driven by application launchers or Slurm wrapper scripts that explicitly choose the rank layout, GPU binding, and cross-node topology.

The NVSHMEM image also avoids an OpenMPI base. It uses NVIDIA's CUDA 13 NVSHMEM packages, sets PMIx as the Slurm bootstrap path, keeps libfabric/CXI as the remote transport, and removes packaged MPI/OpenSHMEM/UCX/IB plugins that are not part of the Perlmutter Slingshot path.

UCX is present in the combined OpenMPI images for OpenSHMEM and portability testing. The default Perlmutter MPI path still selects OFI/CXI with:

```bash
OMPI_MCA_pml=cm
OMPI_MCA_mtl=ofi
FI_PROVIDER=cxi
PMIX_MCA_psec=native
```

## Documentation

Dedicated notes are in `docs/`:

| Topic | Page |
| --- | --- |
| CXI | [`docs/cxi.md`](docs/cxi.md) |
| libfabric and OFI | [`docs/libfabric-ofi.md`](docs/libfabric-ofi.md) |
| UCX | [`docs/ucx.md`](docs/ucx.md) |
| PMIx | [`docs/pmix.md`](docs/pmix.md) |
| MPI | [`docs/mpi.md`](docs/mpi.md) |
| MPICH | [`docs/mpich.md`](docs/mpich.md) |
| OpenMPI | [`docs/openmpi.md`](docs/openmpi.md) |
| NCCL | [`docs/nccl.md`](docs/nccl.md) |
| OpenSHMEM | [`docs/openshmem.md`](docs/openshmem.md) |
| NVSHMEM | [`docs/nvshmem.md`](docs/nvshmem.md) |
| Perlmutter runtime | [`docs/runtime.md`](docs/runtime.md) |

## Local Builds

Build one target:

```bash
scripts/build.sh mpich-cpu
scripts/build.sh openmpi-gpu
scripts/build.sh openmpi-ofi-ucx-gpu
```

Build all public-source targets:

```bash
scripts/build.sh all
```

Override CUDA:

```bash
scripts/build.sh --build-arg CUDA_VERSION=13.0.0 mpich-gpu
```

## Perlmutter Runs

These examples do not use podman-hpc `--mpi` or `--cuda-mpi`. MPI, libfabric, CXI, and GPU communication libraries are in the image. Slurm provides launch and PMIx wire-up, and `podman-hpc shared-run` starts one container per node.

The directory `scripts/perlmutter-images/` contains standalone `sbatch` scripts, one per published image. Each file contains the flattened `srun ... podman-hpc shared-run` command and can be copied into an application repository. Use `scripts/run-perlmutter.sh` for day-to-day repo testing; use the standalone scripts when documenting or adapting a single image for an end-user workflow.

For MPICH and OpenMPI images, the default smoke test is:

```bash
python3 /workspace/tests/test_mpi4py.py
```

### Standalone Scripts

Each script has default `#SBATCH` settings, a default image tag, and a simple smoke-test command. Copy the script for the image you use, edit the `#SBATCH` lines and `APP_COMMAND`, then submit it with `sbatch`.

| Image tag | Script | Submit example |
| --- | --- |
| `libfabric-cpu` | `scripts/perlmutter-images/run-libfabric-cpu.sbatch` | `sbatch scripts/perlmutter-images/run-libfabric-cpu.sbatch` |
| `libfabric-gpu` | `scripts/perlmutter-images/run-libfabric-gpu.sbatch` | `sbatch scripts/perlmutter-images/run-libfabric-gpu.sbatch` |
| `mpich-cpu` | `scripts/perlmutter-images/run-mpich-cpu.sbatch` | `sbatch scripts/perlmutter-images/run-mpich-cpu.sbatch` |
| `mpich-gpu` | `scripts/perlmutter-images/run-mpich-gpu.sbatch` | `sbatch scripts/perlmutter-images/run-mpich-gpu.sbatch` |
| `openmpi-cpu` | `scripts/perlmutter-images/run-openmpi-cpu.sbatch` | `sbatch scripts/perlmutter-images/run-openmpi-cpu.sbatch` |
| `openmpi-gpu` | `scripts/perlmutter-images/run-openmpi-gpu.sbatch` | `sbatch scripts/perlmutter-images/run-openmpi-gpu.sbatch` |
| `openmpi-ofi-ucx-cpu` | `scripts/perlmutter-images/run-openmpi-ofi-ucx-cpu.sbatch` | `sbatch scripts/perlmutter-images/run-openmpi-ofi-ucx-cpu.sbatch` |
| `openmpi-ofi-ucx-gpu` | `scripts/perlmutter-images/run-openmpi-ofi-ucx-gpu.sbatch` | `sbatch scripts/perlmutter-images/run-openmpi-ofi-ucx-gpu.sbatch` |
| `nccl-gpu` | `scripts/perlmutter-images/run-nccl-gpu.sbatch` | `sbatch scripts/perlmutter-images/run-nccl-gpu.sbatch` |
| `nvshmem-gpu` | `scripts/perlmutter-images/run-nvshmem-gpu.sbatch` | `sbatch scripts/perlmutter-images/run-nvshmem-gpu.sbatch` |

Override the application command without editing the script:

```bash
APP_COMMAND='./my_app --input input.toml' sbatch --export=ALL scripts/perlmutter-images/run-openmpi-ofi-ucx-gpu.sbatch
```

The repository wrapper commands are shorter and use the same runtime shape:

```bash
scripts/run-perlmutter.sh cpu mpich
scripts/run-perlmutter.sh gpu openmpi
scripts/run-perlmutter.sh gpu openmpi-ofi-ucx
scripts/run-perlmutter.sh gpu nccl
scripts/run-perlmutter.sh gpu nvshmem
```

The default `gpu nccl` run uses one node and one task because the bundled `nccl-tests` binary is built without MPI. Set `NODES`, `TASKS_PER_NODE`, and pass a custom command when using an application-level or Slurm-managed distributed NCCL test.

The run script currently passes the PMIx and CXI runtime environment explicitly. Once NERSC/podman-hpc#152 is deployed, set `PODMANHPC_PMIX_HELPER=module` to use the `podman-hpc --pmix` helper instead of the manual PMIx plumbing:

```bash
PODMANHPC_PMIX_HELPER=module scripts/run-perlmutter.sh gpu openmpi
```

For GPU runs, bind the complete host NVIDIA driver library set, not only `libcuda`. The script binds `/usr/lib64/libcuda*`, `/usr/lib64/libnvidia*`, and `/usr/bin/nvidia-smi`; this keeps the driver JIT and NVML libraries matched to the Perlmutter 580.105.08 host driver while the image carries the CUDA 13.2 user-space toolkit.

## Benchmarks

CSCS-style benchmark support is under `benchmarks/`. It includes benchmark image stages based on this repo's images, Perlmutter `sbatch` scripts, and a parser that converts OSU, NCCL, and NVSHMEM logs into a Markdown report.

```bash
benchmarks/scripts/build.sh bench-openmpi-ofi-ucx-gpu
MPI_IMPL=openmpi-ofi-ucx sbatch --export=ALL benchmarks/scripts/perlmutter/run-mpi-osu-gpu.sbatch
benchmarks/scripts/process-results.py benchmarks/results/<jobid> -o benchmarks/results/<jobid>/report.md
```

See [`benchmarks/README.md`](benchmarks/README.md) for the benchmark matrix.

## Published Images

GitHub Actions builds and pushes public-source targets to GHCR:

```text
ghcr.io/dingp/communication-libraries-image:libfabric-cpu
ghcr.io/dingp/communication-libraries-image:libfabric-gpu
ghcr.io/dingp/communication-libraries-image:mpich-cpu
ghcr.io/dingp/communication-libraries-image:mpich-gpu
ghcr.io/dingp/communication-libraries-image:openmpi-cpu
ghcr.io/dingp/communication-libraries-image:openmpi-gpu
ghcr.io/dingp/communication-libraries-image:openmpi-ofi-ucx-cpu
ghcr.io/dingp/communication-libraries-image:openmpi-ofi-ucx-gpu
ghcr.io/dingp/communication-libraries-image:nccl-gpu
ghcr.io/dingp/communication-libraries-image:nvshmem-gpu
ghcr.io/dingp/communication-libraries-image:bench-mpich-cpu
ghcr.io/dingp/communication-libraries-image:bench-mpich-gpu
ghcr.io/dingp/communication-libraries-image:bench-openmpi-cpu
ghcr.io/dingp/communication-libraries-image:bench-openmpi-gpu
ghcr.io/dingp/communication-libraries-image:bench-openmpi-ofi-ucx-cpu
ghcr.io/dingp/communication-libraries-image:bench-openmpi-ofi-ucx-gpu
ghcr.io/dingp/communication-libraries-image:bench-nccl-gpu
ghcr.io/dingp/communication-libraries-image:bench-nvshmem-gpu
```
