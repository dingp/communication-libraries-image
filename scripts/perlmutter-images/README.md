# Perlmutter Image Run Scripts

These are standalone `sbatch` scripts for running one published image at a time on Perlmutter. They do not call `scripts/run-perlmutter.sh` and can be copied into another project.

Submit one directly:

```bash
sbatch run-mpich-gpu.sbatch
```

Before submitting, replace `#SBATCH --account=YOUR_NERSC_ACCOUNT` with your allocation account.
The scripts require `$SCRATCH` and write Slurm stdout/stderr to `$SCRATCH/communication-libraries-image/slurm`; override `JOB_OUTPUT_DIR` to use another scratch directory.

Override the application command without editing the script:

```bash
APP_COMMAND='./my_app --input case.toml' sbatch --export=ALL run-openmpi-ofi-ucx-gpu.sbatch
```

Each script contains the `srun --mpi=pmix podman-hpc shared-run ...` command with PMIx, CXI, `/dev/shm`, XPMEM, and GPU driver mounts expanded in the file.

The MPICH and OpenMPI scripts default to the fuller repository mpi4py validation test:

```bash
python3 /workspace/tests/test_mpi4py.py
```

| Image | Script |
| --- | --- |
| `libfabric-cpu` | `run-libfabric-cpu.sbatch` |
| `libfabric-gpu` | `run-libfabric-gpu.sbatch` |
| `mpich-cpu` | `run-mpich-cpu.sbatch` |
| `mpich-gpu` | `run-mpich-gpu.sbatch` |
| `openmpi-cpu` | `run-openmpi-cpu.sbatch` |
| `openmpi-gpu` | `run-openmpi-gpu.sbatch` |
| `openmpi-ofi-ucx-cpu` | `run-openmpi-ofi-ucx-cpu.sbatch` |
| `openmpi-ofi-ucx-gpu` | `run-openmpi-ofi-ucx-gpu.sbatch` |
| `nccl-gpu` | `run-nccl-gpu.sbatch` |
| `nvshmem-gpu` | `run-nvshmem-gpu.sbatch` |
