#!/bin/bash
#SBATCH --job-name=podman-keepid-bind
#SBATCH --account=YOUR_NERSC_ACCOUNT
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --constraint=cpu
#SBATCH --qos=debug
#SBATCH --time=00:10:00
#SBATCH --output=/dev/null

set -euo pipefail

: "${SCRATCH:?SCRATCH must point to Perlmutter scratch}"
JOB_OUTPUT_DIR="${JOB_OUTPUT_DIR:-${SCRATCH}/communication-libraries-image/podman-keepid-bindmount}"
mkdir -p "${JOB_OUTPUT_DIR}"
exec > >(tee -a "${JOB_OUTPUT_DIR}/${SLURM_JOB_NAME:-job}-${SLURM_JOB_ID:-manual}.out") 2>&1

IMAGE="${IMAGE:-ubuntu:latest}"
CASE_TIMEOUT="${CASE_TIMEOUT:-120}"
PODMAN_BIN="${PODMAN_BIN:-}"
PODMANHPC_LOG_LEVEL="${PODMANHPC_LOG_LEVEL:-fatal}"
HOST_TEST_ROOT="${HOST_TEST_ROOT:-${JOB_OUTPUT_DIR}/host-volume-${SLURM_JOB_ID:-manual}}"

if [[ -n "${PODMAN_BIN}" ]]; then
  export PODMANHPC_PODMAN_BIN="${PODMAN_BIN}"
fi

podman_base=(podman-hpc --log-level "${PODMANHPC_LOG_LEVEL}" run --rm --privileged --userns=keep-id)
inside_script='set -eu
echo "inside id:"
id
umask 002
printf "created by %s\n" "$(id)" > /work/created.txt
mkdir -p /work/nested
printf "nested by %s\n" "$(id)" > /work/nested/file.txt
stat -c "inside %n uid=%u gid=%g user=%U group=%G mode=%a" /work /work/created.txt /work/nested /work/nested/file.txt'

host_stat() {
  local dir="$1"

  echo "host ownership under ${dir}:"
  stat -c "host %n uid=%u gid=%g user=%U group=%G mode=%a" \
    "${dir}" \
    "${dir}/created.txt" \
    "${dir}/nested" \
    "${dir}/nested/file.txt" 2>&1 || true
}

run_case() {
  local name="$1"
  local user_arg="$2"
  local mode="$3"
  local dir="${HOST_TEST_ROOT}/${name}"
  local status

  rm -rf "${dir}"
  mkdir -p "${dir}"
  chmod "${mode}" "${dir}"

  echo
  echo "===== BEGIN CASE ${name} user_arg=${user_arg:-default} host_dir=${dir} mode=${mode} ====="
  stat -c "host-before %n uid=%u gid=%g user=%U group=%G mode=%a" "${dir}"

  set +e
  if [[ -n "${user_arg}" ]]; then
    timeout "${CASE_TIMEOUT}" "${podman_base[@]}" --user "${user_arg}" --volume "${dir}:/work:rw" "${IMAGE}" sh -lc "${inside_script}"
  else
    timeout "${CASE_TIMEOUT}" "${podman_base[@]}" --volume "${dir}:/work:rw" "${IMAGE}" sh -lc "${inside_script}"
  fi
  status=$?
  set -e

  echo "container status=${status}"
  host_stat "${dir}"
  echo "===== END CASE ${name} status=${status} ====="
}

echo "HOST=$(hostname -f)"
echo "IMAGE=${IMAGE}"
echo "PODMAN_BIN=${PODMAN_BIN:-system}"
echo "PODMANHPC_PODMAN_BIN=${PODMANHPC_PODMAN_BIN:-}"
echo "HOST_TEST_ROOT=${HOST_TEST_ROOT}"
echo "CASE_TIMEOUT=${CASE_TIMEOUT}"
echo "PODMANHPC_LOG_LEVEL=${PODMANHPC_LOG_LEVEL}"

run_case default-user "" 0775
run_case root-user "0:0" 0777
