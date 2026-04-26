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

## Optional MakeAccessible Build

For debugging direct `podman-hpc run --userns=keep-id` failures where the OCI runtime cannot open the mounted root filesystem, the build helper can also apply a local Podman v5.8.2 patch that restores the Podman 4.7-style rootless runtime access-preparation path:

```bash
APPLY_MAKE_ACCESSIBLE_PATCH=1 \
INSTALL_ROOT=$SCRATCH/communication-libraries-image/podman-alt/podman-5.8.2-make-accessible \
  scripts/perlmutter-tools/build-podman-5.8.2.sh
```

Use the patched binary with:

```bash
export PODMANHPC_PODMAN_BIN=$SCRATCH/communication-libraries-image/podman-alt/podman-5.8.2-make-accessible/bin/podman
```

The patch calls `makeAccessible()` on the container run directory before creating the OCI container.
If Podman decides the current user is not mapped in the container user namespace, it also applies the same parent-directory execute-bit preparation to the runtime tmp directory, static directory, mounted rootfs, and volume path.
This is a diagnostic build for checking the runtime path-access hypothesis; it is not a recommendation to run arbitrary container UIDs against writable host bind mounts.

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

## Compute-Node Run Keep-Id Test

The simpler failing reproducer is a direct `podman-hpc run` on a compute node, without `srun` and without `-it`:

```bash
podman-hpc run --rm --privileged --userns=keep-id ubuntu:latest uname
```

The repository carries a batch wrapper for this exact shape:

```bash
sbatch scripts/perlmutter-tools/test-podman-keepid-run.sbatch
```

Pass allocation details on the `sbatch` command line or with your site defaults rather than editing account names into the file.
The script compares:

- site default Podman
- scratch-built Podman 5.8.2
- scratch-built Podman 5.8.2 with the optional `_CONTAINERS_FORCE_SHIFTING` patch
- an arbitrary candidate Podman backend, if `RUN_CANDIDATE=1` and `CANDIDATE_PODMAN=...` are passed

The patched backend is enabled with:

```bash
export PODMANHPC_PODMAN_BIN=$SCRATCH/communication-libraries-image/podman-alt/podman-5.8.2-force-shifting/bin/podman
export _CONTAINERS_FORCE_SHIFTING=1
```

The `makeAccessible()` backend can be tested without editing the script:

```bash
sbatch --export=ALL,RUN_SYSTEM=0,RUN_UNPATCHED=0,RUN_PATCHED=0,RUN_CANDIDATE=1,CANDIDATE_NAME=podman-5.8.2-make-accessible,CANDIDATE_PODMAN=$SCRATCH/communication-libraries-image/podman-alt/podman-5.8.2-make-accessible/bin/podman \
  scripts/perlmutter-tools/test-podman-keepid-run.sbatch
```

On 2026-04-26, this direct compute-node `podman-hpc run` test failed for all three backends with:

```text
Error: crun: open `/tmp/<uid>_hpc/storage/overlay/<layer>/merged`: Permission denied: OCI permission denied
```

A debug rerun of the patched 5.8.2 backend showed:

```text
disableShifting: false
```

That means the optional patch was active and changed the v5.8.2 overlay shifting decision, but it did not fix this `crun` failure.
For this reproducer, the failure happens after the overlay mount is created, when the OCI runtime opens the mounted root filesystem.
The result points away from the v5.8.2 `SupportsShifting(uidmap, gidmap)` contiguous-map guard as the sole cause.

A follow-up scratch build with `APPLY_MAKE_ACCESSIBLE_PATCH=1` succeeded for the same direct compute-node command:

```text
podman-hpc run --rm --privileged --userns=keep-id ubuntu:latest uname
```

The container printed `Linux` and exited with status 0.
That result points to rootfs path accessibility between Podman, conmon, and `crun` as the immediate failure mode for this reproducer.
The overlay force-shifting patch changed the shifting decision but did not fix the `crun open .../merged` failure; the access-preparation patch did.

## Bind-Mount Ownership Test

The repository carries a second compute-node wrapper that writes files into a host bind mount under `--userns=keep-id` and records both inside-container and host-side ownership:

```bash
sbatch scripts/perlmutter-tools/test-podman-keepid-bindmount.sbatch
```

Pass a candidate backend on the `sbatch` command line rather than editing local paths into the file:

```bash
sbatch --export=ALL,PODMAN_BIN=$SCRATCH/communication-libraries-image/podman-alt/podman-5.8.2-make-accessible/bin/podman \
  scripts/perlmutter-tools/test-podman-keepid-bindmount.sbatch
```

With the `makeAccessible()` Podman 5.8.2 build, the default `keep-id` user case succeeded and files created under the host bind mount were owned by the same host user and group as the submitting user.

The explicit root case also ran:

```text
podman-hpc run --rm --privileged --userns=keep-id --user 0:0 -v <host-dir>:/work:rw ubuntu:latest ...
```

Inside the container, the new files appeared as `root:root`.
On the host, those same files were owned by a high subordinate UID/GID with no local user or group name.
That confirms a real bind-mount ownership hazard: avoid using `--user 0:0` or arbitrary container UID/GID values with writable host bind mounts under `--userns=keep-id` unless the resulting host ownership is understood and acceptable.
For normal end-user workflows that use the default `keep-id` user, the bind-mount write test preserved the submitting user's host UID/GID.

## Supplemental Groups For Bind Mounts

Some Perlmutter project directories are writable because the user is a member of a supplemental host group, not because the path is owned by the user's primary GID.
Under `--userns=keep-id`, a container process may keep only the primary UID/GID unless the OCI runtime is told to preserve the original supplemental groups.

Podman already exposes the needed crun feature:

```bash
podman-hpc run --rm --privileged --userns=keep-id --group-add keep-groups \
  -v <group-writable-host-dir>:/work:rw ubuntu:latest ...
```

`--group-add keep-groups` sets Podman's `run.oci.keep_original_groups` annotation.
It is intentionally different from adding a numeric group ID to the OCI spec: the host supplemental groups are kept by the runtime, while unmapped group IDs may still appear inside the container as the overflow group, often `65534` or `nogroup`.
That display is expected and does not mean the kernel permission check failed.

The bind-mount diagnostic can test this directly:

```bash
sbatch --export=ALL,PODMAN_BIN=$SCRATCH/communication-libraries-image/podman-alt/podman-5.8.2-make-accessible/bin/podman,GROUP_WRITE_TEST_DIR=<host-dir-writable-only-through-a-supplemental-group> \
  scripts/perlmutter-tools/test-podman-keepid-bindmount.sbatch
```

On 2026-04-26, using the `makeAccessible()` Podman 5.8.2 build on a Perlmutter CPU node:

| Case | Result |
| --- | --- |
| `--userns=keep-id` without `--group-add keep-groups` | Writing to a group-gated CFS directory failed with `Permission denied`. |
| `--userns=keep-id --group-add keep-groups` | The same write succeeded. |

In that test, `id` inside the container showed the additional group as `65534(nogroup)` because the host supplemental GID was not mapped into the container user namespace.
The created file still appeared on the host with the expected project-group ownership due to the host directory's setgid bit.

The proposed implementation for Perlmutter wrappers is therefore:

- Keep the `makeAccessible()` style path-access fix for the direct `podman-hpc run --userns=keep-id` rootfs-open failure.
- Add an opt-in `--group-add keep-groups` path for `--userns=keep-id` jobs that bind mount group-protected host directories.
- Do not translate all host supplemental groups into explicit OCI `additionalGids`; high and non-contiguous site group IDs are exactly where ID-map and ownership behavior becomes fragile.
- Keep it opt-in or clearly documented because `keep-groups` is crun-specific and is exclusive with other `--group-add` values.

## Login-Node Network Curl Test

Perlmutter's site Podman default rootless network command may differ across maintenance windows.
The repository includes a login-node curl benchmark for checking the current default against explicit network modes:

```bash
scripts/perlmutter-tools/test-podman-network-curl.sh
```

The script runs both serial single-curl downloads and concurrent curl batches through:

- podman-hpc default networking
- explicit `--network=pasta`
- explicit `--net slirp4netns`
- explicit `--network=host`
- direct host `curl`, unless `--no-host-baseline` is passed

It writes raw logs, `results.csv`, `summary.csv`, and `report.md` under `$SCRATCH/communication-libraries-image/podman-network-curl/<timestamp>` by default.

## Overlay Shifting Comparison

The force-shifting patch does not apply the same way across the tested Podman versions because the vendored storage driver changed.

| Podman version | Storage package | Overlay shifting code | Patch status |
| --- | --- | --- | --- |
| 4.7.0-dev test binary, compared with upstream v4.7.0 | `github.com/containers/storage v1.50.2` | The overlay driver's `SupportsShifting()` has no UID/GID map arguments. The map-contiguity gate is one layer higher in `store.canUseShifting(uidmap, gidmap)`, which checks `idtools.IsContiguous()` before allowing mount-time shifting. | No `_CONTAINERS_FORCE_SHIFTING` string was present. The v5.8.2-style overlay-driver patch does not apply verbatim; an older-storage patch would need to target `store.canUseShifting()`. |
| Site 5.3.2 package `podman-5.3.2-103498`, checked against the installed binary and upstream v5.3.2 | `github.com/containers/storage v1.56.1` | Same older shape: `SupportsShifting()` has no UID/GID map arguments, while `store.canUseShifting(uidmap, gidmap)` performs the contiguity check. Binary disassembly of `/usr/bin/podman` showed no map-aware `SupportsShifting()` implementation. | No `_CONTAINERS_FORCE_SHIFTING` string was present. The v5.8.2-style overlay-driver patch does not apply verbatim. |
| Local upstream 5.8.2 build | `go.podman.io/storage v1.62.0` | `SupportsShifting(uidmap, gidmap)` checks `idtools.IsContiguous(uidmap)` and `idtools.IsContiguous(gidmap)` when an overlay mount program is used; `store.canUseShifting()` delegates to that driver method. | No `_CONTAINERS_FORCE_SHIFTING` upstream. The optional patch in this repo applies cleanly to the vendored v5.8.2 overlay driver. |

For the local 5.8.2 backend on Perlmutter, `podman info` showed overlay storage on GPFS, non-native overlay diff, and an already configured overlay mount program.
The active ID maps used by rootless Podman had two ranges: a one-ID real user/group mapping followed by a separate subordinate range.
Those ranges are contiguous in container-ID space but not adjacent in host-ID space.

`go.podman.io/storage/pkg/idtools.IsContiguous()` checks both host-ID and container-ID continuity.
Therefore, without the optional patch, the v5.8.2 overlay mount-program path returns `false` from `SupportsShifting(uidmap, gidmap)` for this map shape, and `get()` sets `disableShifting = true`.
That is consistent with the diagnosis that a non-contiguous high GID map disables overlay shifting and sends Podman down the non-shifting ownership path.

One subtle point: `podman info` can still print `Supports shifting: true`.
In v5.8.2 that status line calls `SupportsShifting(nil, nil)`, and nil maps are trivially contiguous.
It does not prove that the actual `--userns=keep-id` mount path will keep shifting enabled for the non-contiguous maps passed later.

For 4.7.0 and 5.3.2, the same map-contiguity logic exists in `store.canUseShifting()` rather than the overlay driver's `SupportsShifting()` method.
That means the non-contiguous-map behavior is not unique to 5.8.2.
For the direct compute-node `crun open .../merged` failure, the successful `makeAccessible()` build is the stronger signal: the immediate issue is path accessibility to the mounted rootfs, while overlay shifting is a separate ownership and performance concern.
