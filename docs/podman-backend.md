# Podman Backend

`podman-hpc` wraps a Podman binary.
For these images, MPI and SHMEM jobs use `podman-hpc shared-run` under `srun --mpi=pmix`.

The Podman binary can be changed without changing the image:

```bash
export PODMANHPC_PODMAN_BIN=$SCRATCH/communication-libraries-image/podman-alt/podman-5.8.2/bin/podman
```

## Local Podman 5.8.2 Build

The script below builds Podman v5.8.2 under `$SCRATCH` and prints the `PODMANHPC_PODMAN_BIN` line to use it:

```bash
scripts/perlmutter-tools/build-podman-5.8.2.sh
```

Default install location:

```text
$SCRATCH/communication-libraries-image/podman-alt/podman-5.8.2/bin/podman
```

The script downloads Go 1.26.2, verifies its checksum, clones the Podman v5.8.2 tag, and builds the local Podman binary.
It reuses the site `conmon`, `crun`, `netavark`, and related runtime helpers.

The default build tags are:

```text
containers_image_openpgp exclude_graphdriver_btrfs exclude_graphdriver_devicemapper systemd
```

If `libseccomp` development files are available, the script also adds the `seccomp` build tag.

## PMIx Keep-Id Test

The comparison script below runs a two-node `mpi4py` test through `podman-hpc shared-run`:

```bash
sbatch scripts/perlmutter-tools/test-podman-keepid-pmix.sbatch
```

It compares:

- site default Podman
- the older Podman 4.7.0 test binary, if present
- the scratch-built Podman 5.8.2 binary

The test uses:

```bash
srun --mpi=pmix podman-hpc shared-run --rm --userns=keep-id ...
```

## 2026-04-26 Observation

On Perlmutter, the site Podman was:

```text
podman version 5.3.2
```

The older comparison binary was:

```text
podman version 4.7.0-dev
```

The local scratch build was:

```text
podman version 5.8.2
```

A two-node CPU `mpi4py` test with `podman-hpc shared-run --userns=keep-id` completed successfully with both Podman 4.7.0-dev and the scratch-built Podman 5.8.2.
The same timeout-protected rerun also completed once with site Podman 5.3.2 and `--userns=keep-id`, while the site-Podman no-`keep-id` control timed out.

This means the focused reproducer did not show a deterministic `--userns=keep-id` failure in site Podman 5.3.2.
It did confirm that Podman 5.8.2 works with `podman-hpc shared-run`, Slurm PMIx, and `--userns=keep-id` in this two-node MPI test.
