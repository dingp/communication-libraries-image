# Podman Network Curl Report

This report captures the login-node curl throughput checks used to compare Perlmutter's site `pasta` helper with a scratch-built newer `passt`/`pasta` helper.

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

Test command:

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

## Results

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

Use `--network=host` or `--net slirp4netns` as separate comparisons when the goal is maximum download throughput rather than isolating pasta helper behavior.
