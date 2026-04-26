# Podman Network Curl Report

This report captures the login-node curl throughput checks used to compare Podman network modes and to compare Perlmutter's site `pasta` helper with a scratch-built newer `passt`/`pasta` helper.

## Test Setup

Date: 2026-04-26

Node: Perlmutter login node `login07.chn.perlmutter.nersc.gov`

Download URL:

```text
https://cachefly.cachefly.net/100mb.test
```

Container image:

```text
docker.io/library/fedora:42
```

Network-mode comparison command:

```bash
scripts/perlmutter-tools/test-podman-network-curl.sh
```

This covers podman-hpc default networking, explicit `--network=pasta`, explicit `--net slirp4netns`, explicit `--network=host`, and direct host `curl`.

Pasta-helper comparison command:

```bash
scripts/perlmutter-tools/test-podman-network-curl.sh \
  --modes pasta \
  --single-runs 3 \
  --parallel-count 8 \
  --parallel-runs 1 \
  --no-host-baseline
```

The single test reports the average of three serial 100 MiB downloads.
The parallel test reports aggregate throughput for one batch of eight concurrent 100 MiB downloads.

## Versions

| Component | Version |
| --- | --- |
| Site Podman | `podman version 5.3.2` |
| Scratch Podman | `podman version 5.8.2` |
| Site pasta/passt | `2024_11_27.c0fbc7e-101445` |
| Scratch pasta/passt | `2026_01_20.386b5f5` |

The scratch `passt`/`pasta` helper was selected with:

```bash
export CONTAINERS_HELPER_BINARY_DIR=$SCRATCH/communication-libraries-image/podman-alt/passt-2026_01_20.386b5f5/install/bin
```

The scratch Podman backend was selected with:

```bash
export PODMANHPC_PODMAN_BIN=$SCRATCH/communication-libraries-image/podman-alt/podman-5.8.2/bin/podman
```

## Network Mode Results

These tests used site Podman 5.3.2 and the site `pasta 2024_11_27.c0fbc7e-101445` helper unless the row says direct host curl.

### Single Curl

| Mode | Podman backend | Helper | Network option | Runs | OK | Avg speed | Avg speed |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| Default | Site Podman 5.3.2 | Site `pasta 2024_11_27` | none | 3 | 3 | 462.7 MB/s | 441.3 MiB/s |
| Pasta | Site Podman 5.3.2 | Site `pasta 2024_11_27` | `--network=pasta` | 3 | 3 | 523.4 MB/s | 499.1 MiB/s |
| Pasta | Site Podman 5.3.2 | Scratch `pasta 2026_01_20` | `--network=pasta` | 3 | 3 | 709.7 MB/s | 676.8 MiB/s |
| Pasta | Scratch Podman 5.8.2 | Site `pasta 2024_11_27` | `--network=pasta` | 3 | 3 | 488.7 MB/s | 466.1 MiB/s |
| Pasta | Scratch Podman 5.8.2 | Scratch `pasta 2026_01_20` | `--network=pasta` | 3 | 3 | 729.0 MB/s | 695.2 MiB/s |
| slirp4netns | Site Podman 5.3.2 | `/usr/bin/slirp4netns` | `--net slirp4netns` | 3 | 3 | 716.1 MB/s | 682.9 MiB/s |
| Host network | Site Podman 5.3.2 | none | `--network=host` / `--net=host` | 3 | 3 | 692.8 MB/s | 660.7 MiB/s |
| Direct host curl | none | none | none | 3 | 3 | 655.7 MB/s | 625.4 MiB/s |

### Parallel Curl

Each row used one batch of eight concurrent 100 MiB downloads.

| Mode | Network option | Bad curls | Wall time | Aggregate speed | Aggregate speed |
| --- | --- | ---: | ---: | ---: | ---: |
| Default | none | 0 | 1.087 s | 771.5 MB/s | 735.8 MiB/s |
| Pasta | `--network=pasta` | 0 | 1.022 s | 821.0 MB/s | 783.0 MiB/s |
| slirp4netns | `--net slirp4netns` | 0 | 0.974 s | 861.6 MB/s | 821.6 MiB/s |
| Host network | `--network=host` / `--net=host` | 0 | 0.362 s | 2314.9 MB/s | 2207.6 MiB/s |
| Direct host curl | none | 0 | 0.287 s | 2921.9 MB/s | 2786.5 MiB/s |

## Pasta Helper Results

| Podman backend | Pasta helper | Single avg | Parallel aggregate | Parallel wall time | Bad curls |
| --- | --- | ---: | ---: | ---: | ---: |
| Site Podman 5.3.2 | Site `pasta 2024_11_27.c0fbc7e-101445` | 472.2 MB/s | 830.5 MB/s | 1.010 s | 0 |
| Site Podman 5.3.2 | Scratch `pasta 2026_01_20.386b5f5` | 709.7 MB/s | 955.2 MB/s | 0.878 s | 0 |
| Scratch Podman 5.8.2 | Site `pasta 2024_11_27.c0fbc7e-101445` | 488.7 MB/s | 897.9 MB/s | 0.934 s | 0 |
| Scratch Podman 5.8.2 | Scratch `pasta 2026_01_20.386b5f5` | 729.0 MB/s | 934.5 MB/s | 0.898 s | 0 |

## Interpretation

The newer `pasta 2026_01_20.386b5f5` helper improved single-curl throughput for both Podman backends.

The newer helper also improved the 8-way parallel result for site Podman 5.3.2.
For scratch Podman 5.8.2, the 8-way parallel numbers were close between the site and scratch pasta helpers in this short run.

For the full network-mode comparison, `--network=host` was much faster than the rootless user-mode networking paths for the 8-way parallel curl workload.
For single-curl throughput, `--net slirp4netns` and `--network=host` were both close to direct host curl and faster than the site default.

Use `--network=host` or `--net slirp4netns` as separate comparisons when the goal is maximum download throughput rather than isolating pasta helper behavior.
