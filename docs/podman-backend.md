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

## Optional Force-Shifting Build

For debugging rootless overlay ownership behavior with host bind mounts, the same build helper can apply a small local patch to the vendored storage driver in Podman v5.8.2:

```bash
APPLY_FORCE_SHIFTING_PATCH=1 \
INSTALL_ROOT=$SCRATCH/communication-libraries-image/podman-alt/podman-5.8.2-force-shifting \
  scripts/perlmutter-tools/build-podman-5.8.2.sh
```

Use the patched binary with:

```bash
export PODMANHPC_PODMAN_BIN=$SCRATCH/communication-libraries-image/podman-alt/podman-5.8.2-force-shifting/bin/podman
export _CONTAINERS_FORCE_SHIFTING=1
```

The default build is unpatched.
The optional patch adds `_CONTAINERS_FORCE_SHIFTING` as an override in the overlay driver's `SupportsShifting()` check and logs the resulting `disableShifting` value at debug level.
It is intended as a diagnostic backend, not as a default runtime requirement for these images.

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

## Overlay Shifting Comparison

The force-shifting patch does not apply the same way across the tested Podman versions because the vendored storage driver changed.

| Podman version | Storage package | Overlay shifting code | Patch status |
| --- | --- | --- | --- |
| 4.7.0-dev test binary, compared with upstream v4.7.0 | `github.com/containers/storage v1.50.2` | `SupportsShifting()` has no UID/GID map arguments. If an overlay mount program is configured, it reports shifting support without checking whether the active maps are contiguous. Binary disassembly showed no call from this function to `idtools.IsContiguous`. | No `_CONTAINERS_FORCE_SHIFTING` string was present. The v5.8.2-style patch does not apply verbatim. |
| Site 5.3.2 package `podman-5.3.2-103498`, checked against the installed binary and upstream v5.3.2 | `github.com/containers/storage v1.56.1` | Same older shape: `SupportsShifting()` has no UID/GID map arguments and no contiguous-map check in this function. Binary disassembly of `/usr/bin/podman` showed this function calls `os.Getenv` and `supportsIDmappedMounts`, but not `idtools.IsContiguous`. | No `_CONTAINERS_FORCE_SHIFTING` string was present. The v5.8.2-style patch does not apply verbatim. |
| Local upstream 5.8.2 build | `go.podman.io/storage v1.62.0` | `SupportsShifting(uidmap, gidmap)` checks `idtools.IsContiguous(uidmap)` and `idtools.IsContiguous(gidmap)` when an overlay mount program is used. | No `_CONTAINERS_FORCE_SHIFTING` upstream. The optional patch in this repo applies cleanly to the vendored v5.8.2 file. |

For the local 5.8.2 backend on Perlmutter, `podman info` showed overlay storage on GPFS, non-native overlay diff, and an already configured overlay mount program.
The active ID maps used by rootless Podman had two ranges: a one-ID real user/group mapping followed by a separate subordinate range.
Those ranges are contiguous in container-ID space but not adjacent in host-ID space.

`go.podman.io/storage/pkg/idtools.IsContiguous()` checks both host-ID and container-ID continuity.
Therefore, without the optional patch, the v5.8.2 overlay mount-program path returns `false` from `SupportsShifting(uidmap, gidmap)` for this map shape, and `get()` sets `disableShifting = true`.
That is consistent with the diagnosis that a non-contiguous high GID map disables overlay shifting and sends Podman down the non-shifting ownership path.

One subtle point: `podman info` can still print `Supports shifting: true`.
In v5.8.2 that status line calls `SupportsShifting(nil, nil)`, and nil maps are trivially contiguous.
It does not prove that the actual `--userns=keep-id` mount path will keep shifting enabled for the non-contiguous maps passed later.

The same non-contiguous-map explanation does not match the checked site Podman 5.3.2 binary.
The issue may still have started with the 5.3.2 site upgrade, but the checked code path does not contain the newer v5.8.2-style contiguous-map guard that the `_CONTAINERS_FORCE_SHIFTING` patch bypasses.
For 5.3.2, the next useful debug build would log `disableShifting` in `get()` and inspect the bind-mount ownership path directly, rather than adding `_CONTAINERS_FORCE_SHIFTING` to `SupportsShifting()`.
