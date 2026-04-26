#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/perlmutter-tools/test-podman-network-curl.sh [options]

Runs reproducible login-node curl throughput tests through podman-hpc:

  1. single-curl test: serial curl downloads inside one container per network mode
  2. parallel-curl test: concurrent curl downloads inside one container per network mode

The script writes raw logs, CSV files, and a Markdown report.

Options:
  --url URL                 Download URL.
                            Default: https://cachefly.cachefly.net/100mb.test
  --image IMAGE             Container image with bash and curl.
                            Default: docker.io/library/fedora:42
  --output-dir DIR          Output directory.
                            Default: $SCRATCH/communication-libraries-image/podman-network-curl/<timestamp>
  --modes LIST              Comma-separated podman-hpc network modes.
                            Default: default,pasta,slirp4netns,host
  --single-runs N           Serial downloads per mode. Default: 3
  --parallel-count N        Concurrent downloads per parallel batch. Default: 8
  --parallel-runs N         Parallel batches per mode. Default: 1
  --connect-timeout SEC     curl --connect-timeout. Default: 15
  --max-time SEC            curl --max-time per download. Default: 180
  --no-host-baseline        Skip direct host curl baseline.
  --host-baseline           Include direct host curl baseline. Default.
  --podman-hpc CMD          podman-hpc executable. Default: podman-hpc
  -h, --help                Show this help.

Examples:
  scripts/perlmutter-tools/test-podman-network-curl.sh

  scripts/perlmutter-tools/test-podman-network-curl.sh \
    --modes default,slirp4netns,host --parallel-count 16
USAGE
}

timestamp="$(date +%Y%m%d-%H%M%S)"
default_output_dir="${SCRATCH:-$PWD}/communication-libraries-image/podman-network-curl/${timestamp}"

URL="https://cachefly.cachefly.net/100mb.test"
IMAGE="docker.io/library/fedora:42"
OUTPUT_DIR="${default_output_dir}"
MODES="default,pasta,slirp4netns,host"
SINGLE_RUNS=3
PARALLEL_COUNT=8
PARALLEL_RUNS=1
CONNECT_TIMEOUT=15
MAX_TIME=180
INCLUDE_HOST_BASELINE=1
PODMANHPC="podman-hpc"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      URL="${2:?--url requires a value}"
      shift 2
      ;;
    --image)
      IMAGE="${2:?--image requires a value}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:?--output-dir requires a value}"
      shift 2
      ;;
    --modes)
      MODES="${2:?--modes requires a value}"
      shift 2
      ;;
    --single-runs)
      SINGLE_RUNS="${2:?--single-runs requires a value}"
      shift 2
      ;;
    --parallel-count)
      PARALLEL_COUNT="${2:?--parallel-count requires a value}"
      shift 2
      ;;
    --parallel-runs)
      PARALLEL_RUNS="${2:?--parallel-runs requires a value}"
      shift 2
      ;;
    --connect-timeout)
      CONNECT_TIMEOUT="${2:?--connect-timeout requires a value}"
      shift 2
      ;;
    --max-time)
      MAX_TIME="${2:?--max-time requires a value}"
      shift 2
      ;;
    --no-host-baseline)
      INCLUDE_HOST_BASELINE=0
      shift
      ;;
    --host-baseline)
      INCLUDE_HOST_BASELINE=1
      shift
      ;;
    --podman-hpc)
      PODMANHPC="${2:?--podman-hpc requires a value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

for value_name in SINGLE_RUNS PARALLEL_COUNT PARALLEL_RUNS CONNECT_TIMEOUT MAX_TIME; do
  value="${!value_name}"
  if ! [[ "${value}" =~ ^[0-9]+$ ]] || [[ "${value}" -lt 1 ]]; then
    echo "${value_name} must be a positive integer, got: ${value}" >&2
    exit 2
  fi
done

mkdir -p "${OUTPUT_DIR}/raw"
RESULTS_CSV="${OUTPUT_DIR}/results.csv"
SUMMARY_CSV="${OUTPUT_DIR}/summary.csv"
REPORT_MD="${OUTPUT_DIR}/report.md"
METADATA_TXT="${OUTPUT_DIR}/metadata.txt"
RUNNER_DIR="${OUTPUT_DIR}/runner"
RUNNER="${RUNNER_DIR}/container-curl-runner.sh"
mkdir -p "${RUNNER_DIR}"

cleanup() {
  rm -rf "${RUNNER_DIR}"
}
trap cleanup EXIT

cat > "${RESULTS_CSV}" <<'CSV'
kind,mode,run,worker,http_code,size_bytes,time_total_s,speed_Bps,curl_exit
CSV

cat > "${SUMMARY_CSV}" <<'CSV'
kind,mode,run,parallel_count,total_bytes,wall_s,aggregate_Bps,bad_count
CSV

cat > "${RUNNER}" <<'RUNNER'
#!/usr/bin/env bash
set -u

kind="${1:?kind is required}"
mode="${2:?mode is required}"
url="${3:?url is required}"
single_runs="${4:?single_runs is required}"
parallel_count="${5:?parallel_count is required}"
parallel_runs="${6:?parallel_runs is required}"
connect_timeout="${7:?connect_timeout is required}"
max_time="${8:?max_time is required}"

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp}"
}
trap cleanup EXIT

run_curl() {
  local run="$1"
  local worker="$2"
  local out="${tmp}/${kind}.${run}.${worker}.out"
  local err="${tmp}/${kind}.${run}.${worker}.err"
  local rc=0
  local http_code="000"
  local size_bytes="0"
  local time_total="0"
  local speed_bps="0"

  curl --http1.1 \
    --connect-timeout "${connect_timeout}" \
    --max-time "${max_time}" \
    -L -o /dev/null -sS \
    -w "%{http_code} %{size_download} %{time_total} %{speed_download}" \
    "${url}" > "${out}" 2> "${err}" || rc=$?

  if [[ -s "${out}" ]]; then
    read -r http_code size_bytes time_total speed_bps < "${out}" || true
  fi

  if [[ -s "${err}" ]]; then
    sed "s/^/STDERR,${kind},${mode},${run},${worker},/" "${err}" >&2
  fi

  printf 'RESULT,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "${kind}" "${mode}" "${run}" "${worker}" \
    "${http_code}" "${size_bytes}" "${time_total}" "${speed_bps}" "${rc}"
}

run_single() {
  local run

  for run in $(seq 1 "${single_runs}"); do
    run_curl "${run}" 1
  done
}

run_parallel() {
  local run
  local worker
  local start_ns
  local end_ns
  local wall_ns
  local result_file
  local bytes
  local bad

  for run in $(seq 1 "${parallel_runs}"); do
    start_ns="$(date +%s%N)"
    for worker in $(seq 1 "${parallel_count}"); do
      result_file="${tmp}/result.${run}.${worker}.csv"
      run_curl "${run}" "${worker}" > "${result_file}" &
    done
    wait
    end_ns="$(date +%s%N)"
    wall_ns=$((end_ns - start_ns))

    for worker in $(seq 1 "${parallel_count}"); do
      cat "${tmp}/result.${run}.${worker}.csv"
    done

    bytes="$(awk -F, '$1 == "RESULT" {sum += $7} END {printf "%.0f", sum + 0}' "${tmp}"/result."${run}".*.csv)"
    bad="$(awk -F, '$1 == "RESULT" && ($6 != 200 || $10 != 0) {bad++} END {print bad + 0}' "${tmp}"/result."${run}".*.csv)"
    awk -v kind="${kind}" -v mode="${mode}" -v run="${run}" \
      -v count="${parallel_count}" -v bytes="${bytes}" -v bad="${bad}" -v ns="${wall_ns}" \
      'BEGIN {
        wall = ns / 1000000000
        aggregate = wall > 0 ? bytes / wall : 0
        printf "SUMMARY,%s,%s,%s,%s,%.0f,%.6f,%.0f,%s\n", kind, mode, run, count, bytes, wall, aggregate, bad
      }'
  done
}

case "${kind}" in
  single)
    run_single
    ;;
  parallel)
    run_parallel
    ;;
  *)
    echo "Unsupported kind: ${kind}" >&2
    exit 2
    ;;
esac
RUNNER
chmod +x "${RUNNER}"

append_output() {
  local log_file="$1"

  awk -F, '$1 == "RESULT" {print $2 "," $3 "," $4 "," $5 "," $6 "," $7 "," $8 "," $9 "," $10}' "${log_file}" >> "${RESULTS_CSV}"
  awk -F, '$1 == "SUMMARY" {print $2 "," $3 "," $4 "," $5 "," $6 "," $7 "," $8 "," $9}' "${log_file}" >> "${SUMMARY_CSV}"
}

net_args_for_mode() {
  local mode="$1"

  case "${mode}" in
    default)
      ;;
    pasta)
      printf '%s\n' "--network=pasta"
      ;;
    slirp4netns)
      printf '%s\n' "--net" "slirp4netns"
      ;;
    host)
      printf '%s\n' "--network=host"
      ;;
    *)
      echo "Unsupported mode: ${mode}" >&2
      exit 2
      ;;
  esac
}

run_container_test() {
  local kind="$1"
  local mode="$2"
  local log_file="${OUTPUT_DIR}/raw/${kind}-${mode}.log"
  local net_args=()
  local arg

  while IFS= read -r arg; do
    [[ -n "${arg}" ]] && net_args+=("${arg}")
  done < <(net_args_for_mode "${mode}")

  echo "Running ${kind} test for mode=${mode}"
  "${PODMANHPC}" run --rm \
    "${net_args[@]}" \
    -v "${RUNNER}:/tmp/container-curl-runner.sh:ro" \
    "${IMAGE}" \
    bash /tmp/container-curl-runner.sh \
      "${kind}" "${mode}" "${URL}" "${SINGLE_RUNS}" "${PARALLEL_COUNT}" \
      "${PARALLEL_RUNS}" "${CONNECT_TIMEOUT}" "${MAX_TIME}" \
    > >(tee "${log_file}") \
    2> >(tee "${log_file%.log}.stderr" >&2)

  append_output "${log_file}"
}

run_host_baseline() {
  local kind="$1"
  local mode="host-curl"
  local log_file="${OUTPUT_DIR}/raw/${kind}-${mode}.log"

  echo "Running ${kind} direct host curl baseline"
  bash "${RUNNER}" \
    "${kind}" "${mode}" "${URL}" "${SINGLE_RUNS}" "${PARALLEL_COUNT}" \
    "${PARALLEL_RUNS}" "${CONNECT_TIMEOUT}" "${MAX_TIME}" \
    > >(tee "${log_file}") \
    2> >(tee "${log_file%.log}.stderr" >&2)

  append_output "${log_file}"
}

collect_metadata() {
  {
    echo "date=$(date -Is)"
    echo "host=$(hostname -f 2>/dev/null || hostname)"
    echo "url=${URL}"
    echo "image=${IMAGE}"
    echo "modes=${MODES}"
    echo "single_runs=${SINGLE_RUNS}"
    echo "parallel_count=${PARALLEL_COUNT}"
    echo "parallel_runs=${PARALLEL_RUNS}"
    echo "connect_timeout=${CONNECT_TIMEOUT}"
    echo "max_time=${MAX_TIME}"
    echo "podman_hpc=${PODMANHPC}"
    if command -v "${PODMANHPC}" >/dev/null 2>&1; then
      echo "podman_hpc_version=$("${PODMANHPC}" --version 2>/dev/null || true)"
    fi
    if command -v podman >/dev/null 2>&1; then
      echo "podman_version=$(podman --version 2>/dev/null || true)"
      echo "podman_rootless_network_cmd=$(podman info --format '{{.Host.RootlessNetworkCmd}}' 2>/dev/null || true)"
      echo "podman_network_backend=$(podman info --format '{{.Host.NetworkBackend}}' 2>/dev/null || true)"
      echo "podman_pasta=$(podman info --format '{{.Host.Pasta.Executable}}' 2>/dev/null || true)"
      echo "podman_slirp4netns=$(podman info --format '{{.Host.Slirp4NetNS.Executable}}' 2>/dev/null || true)"
    fi
  } > "${METADATA_TXT}"
}

generate_report() {
  python3 - "${RESULTS_CSV}" "${SUMMARY_CSV}" "${METADATA_TXT}" "${REPORT_MD}" <<'PY'
import csv
import datetime as dt
import math
import sys
from collections import defaultdict
from pathlib import Path

results_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
metadata_path = Path(sys.argv[3])
report_path = Path(sys.argv[4])

metadata = {}
for line in metadata_path.read_text().splitlines():
    if "=" in line:
        key, value = line.split("=", 1)
        metadata[key] = value

def fnum(value, default=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default

with results_path.open(newline="") as fh:
    results = list(csv.DictReader(fh))

with summary_path.open(newline="") as fh:
    summaries = list(csv.DictReader(fh))

single_by_mode = defaultdict(list)
parallel_curls_by_mode = defaultdict(list)
for row in results:
    if row["kind"] == "single":
        single_by_mode[row["mode"]].append(row)
    elif row["kind"] == "parallel":
        parallel_curls_by_mode[row["mode"]].append(row)

parallel_by_mode = defaultdict(list)
for row in summaries:
    if row["kind"] == "parallel":
        parallel_by_mode[row["mode"]].append(row)

def avg(values):
    values = list(values)
    return sum(values) / len(values) if values else math.nan

def mbps(bytes_per_second):
    return bytes_per_second / 1_000_000

def mibps(bytes_per_second):
    return bytes_per_second / 1_048_576

def ok_count(rows):
    return sum(1 for r in rows if r["http_code"] == "200" and r["curl_exit"] == "0")

lines = []
lines.append("# Podman Network Curl Benchmark")
lines.append("")
lines.append(f"Generated: {dt.datetime.now().astimezone().isoformat(timespec='seconds')}")
lines.append("")
lines.append("## Configuration")
lines.append("")
lines.append("| Key | Value |")
lines.append("| --- | --- |")
for key in [
    "date",
    "host",
    "url",
    "image",
    "modes",
    "single_runs",
    "parallel_count",
    "parallel_runs",
    "connect_timeout",
    "max_time",
    "podman_hpc",
    "podman_hpc_version",
    "podman_version",
    "podman_rootless_network_cmd",
    "podman_network_backend",
    "podman_pasta",
    "podman_slirp4netns",
]:
    if key in metadata and metadata[key]:
        lines.append(f"| `{key}` | `{metadata[key]}` |")

lines.append("")
lines.append("## Single Curl")
lines.append("")
lines.append("| Mode | Runs | OK | Avg time (s) | Avg speed (MB/s) | Avg speed (MiB/s) | Min speed (MB/s) | Max speed (MB/s) |")
lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
for mode in sorted(single_by_mode):
    rows = single_by_mode[mode]
    speeds = [fnum(r["speed_Bps"]) for r in rows]
    times = [fnum(r["time_total_s"]) for r in rows]
    lines.append(
        f"| `{mode}` | {len(rows)} | {ok_count(rows)} | "
        f"{avg(times):.3f} | {mbps(avg(speeds)):.1f} | {mibps(avg(speeds)):.1f} | "
        f"{mbps(min(speeds)):.1f} | {mbps(max(speeds)):.1f} |"
    )

lines.append("")
lines.append("## Parallel Curl")
lines.append("")
lines.append("| Mode | Batches | Parallel count | Bad curls | Avg wall (s) | Avg aggregate (MB/s) | Avg aggregate (MiB/s) |")
lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
for mode in sorted(parallel_by_mode):
    rows = parallel_by_mode[mode]
    aggregate = [fnum(r["aggregate_Bps"]) for r in rows]
    walls = [fnum(r["wall_s"]) for r in rows]
    bad = sum(int(fnum(r["bad_count"])) for r in rows)
    counts = sorted({r["parallel_count"] for r in rows})
    count_text = ",".join(counts)
    lines.append(
        f"| `{mode}` | {len(rows)} | {count_text} | {bad} | "
        f"{avg(walls):.3f} | {mbps(avg(aggregate)):.1f} | {mibps(avg(aggregate)):.1f} |"
    )

lines.append("")
lines.append("## Raw Files")
lines.append("")
lines.append(f"- Results CSV: `{results_path.name}`")
lines.append(f"- Summary CSV: `{summary_path.name}`")
lines.append("- Per-mode logs: `raw/`")
lines.append("")
lines.append("Notes:")
lines.append("")
lines.append("- `default` uses podman-hpc without an explicit network option.")
lines.append("- `pasta`, `slirp4netns`, and `host` use explicit Podman network options.")
lines.append("- `host-curl` is the direct login-node curl baseline when enabled.")
lines.append("- Aggregate parallel throughput is total downloaded bytes divided by the measured wall time inside the container or host runner.")

report_path.write_text("\n".join(lines) + "\n")
PY
}

collect_metadata

IFS=',' read -r -a mode_array <<< "${MODES}"
for mode in "${mode_array[@]}"; do
  mode="${mode//[[:space:]]/}"
  [[ -z "${mode}" ]] && continue
  run_container_test single "${mode}"
  run_container_test parallel "${mode}"
done

if [[ "${INCLUDE_HOST_BASELINE}" == "1" ]]; then
  run_host_baseline single
  run_host_baseline parallel
fi

generate_report

echo
echo "Wrote:"
echo "  ${RESULTS_CSV}"
echo "  ${SUMMARY_CSV}"
echo "  ${REPORT_MD}"
