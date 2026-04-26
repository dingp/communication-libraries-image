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
RUN_DEFAULT_USER="${RUN_DEFAULT_USER:-1}"
RUN_ROOT_USER="${RUN_ROOT_USER:-1}"
RUN_KEEP_GROUPS="${RUN_KEEP_GROUPS:-1}"
GROUP_WRITE_TEST_DIR="${GROUP_WRITE_TEST_DIR:-}"
RUN_GROUP_WRITE_TEST="${RUN_GROUP_WRITE_TEST:-1}"

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
group_write_script='set -eu
echo "inside id:"
id
: "${TARGET_NAME:?TARGET_NAME is required}"
printf "group-write test by %s\n" "$(id)" > "/work/${TARGET_NAME}"
stat -c "inside %n uid=%u gid=%g user=%U group=%G mode=%a" "/work/${TARGET_NAME}"'

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
  local keep_groups="$4"
  local dir="${HOST_TEST_ROOT}/${name}"
  local extra_args=()
  local status

  if [[ "${keep_groups}" == "1" ]]; then
    extra_args+=(--group-add keep-groups)
  fi

  rm -rf "${dir}"
  mkdir -p "${dir}"
  chmod "${mode}" "${dir}"

  echo
  echo "===== BEGIN CASE ${name} user_arg=${user_arg:-default} keep_groups=${keep_groups} host_dir=${dir} mode=${mode} ====="
  stat -c "host-before %n uid=%u gid=%g user=%U group=%G mode=%a" "${dir}"

  set +e
  if [[ -n "${user_arg}" ]]; then
    timeout "${CASE_TIMEOUT}" "${podman_base[@]}" "${extra_args[@]}" --user "${user_arg}" --volume "${dir}:/work:rw" "${IMAGE}" sh -lc "${inside_script}"
  else
    timeout "${CASE_TIMEOUT}" "${podman_base[@]}" "${extra_args[@]}" --volume "${dir}:/work:rw" "${IMAGE}" sh -lc "${inside_script}"
  fi
  status=$?
  set -e

  echo "container status=${status}"
  host_stat "${dir}"
  echo "===== END CASE ${name} status=${status} ====="
}

run_group_write_case() {
  local name="$1"
  local keep_groups="$2"
  local expected="$3"
  local target_name="podman-keepgroups-${SLURM_JOB_ID:-manual}-${name}.txt"
  local target_path="${GROUP_WRITE_TEST_DIR%/}/${target_name}"
  local extra_args=()
  local status

  if [[ "${keep_groups}" == "1" ]]; then
    extra_args+=(--group-add keep-groups)
  fi

  echo
  echo "===== BEGIN GROUP-WRITE CASE ${name} keep_groups=${keep_groups} dir=${GROUP_WRITE_TEST_DIR} expected=${expected} ====="
  stat -c "group-dir %n uid=%u gid=%g user=%U group=%G mode=%a" "${GROUP_WRITE_TEST_DIR}"
  rm -f "${target_path}" 2>/dev/null || true

  set +e
  timeout "${CASE_TIMEOUT}" "${podman_base[@]}" "${extra_args[@]}" \
    --env "TARGET_NAME=${target_name}" \
    --volume "${GROUP_WRITE_TEST_DIR}:/work:rw" \
    "${IMAGE}" sh -lc "${group_write_script}"
  status=$?
  set -e

  echo "container status=${status}"
  stat -c "host-created %n uid=%u gid=%g user=%U group=%G mode=%a" "${target_path}" 2>&1 || true
  rm -f "${target_path}" 2>/dev/null || true

  if [[ "${expected}" == "success" && "${status}" -ne 0 ]]; then
    echo "ERROR: expected success but container exited ${status}"
    return 1
  fi
  if [[ "${expected}" == "failure" && "${status}" -eq 0 ]]; then
    echo "ERROR: expected failure but container succeeded"
    return 1
  fi

  echo "===== END GROUP-WRITE CASE ${name} status=${status} ====="
}

run_group_write_tests_if_configured() {
  if [[ "${RUN_GROUP_WRITE_TEST}" != "1" || -z "${GROUP_WRITE_TEST_DIR}" ]]; then
    echo
    echo "Skipping group-write test; set GROUP_WRITE_TEST_DIR to a host directory writable only through a supplemental group."
    return 0
  fi

  if [[ ! -d "${GROUP_WRITE_TEST_DIR}" ]]; then
    echo "Skipping group-write test; not a directory: ${GROUP_WRITE_TEST_DIR}"
    return 0
  fi

  if [[ ! -w "${GROUP_WRITE_TEST_DIR}" ]]; then
    echo "Skipping group-write test; host user cannot write to: ${GROUP_WRITE_TEST_DIR}"
    return 0
  fi

  if [[ "$(stat -c %u "${GROUP_WRITE_TEST_DIR}")" == "$(id -u)" ]]; then
    echo "Skipping group-write test; directory is owned by this user, so it does not prove supplemental-group access."
    return 0
  fi

  run_group_write_case no-keep-groups 0 failure
  run_group_write_case keep-groups 1 success
}

echo "HOST=$(hostname -f)"
echo "HOST_ID=$(id)"
echo "HOST_GROUPS=$(id -G)"
echo "IMAGE=${IMAGE}"
echo "PODMAN_BIN=${PODMAN_BIN:-system}"
echo "PODMANHPC_PODMAN_BIN=${PODMANHPC_PODMAN_BIN:-}"
echo "HOST_TEST_ROOT=${HOST_TEST_ROOT}"
echo "CASE_TIMEOUT=${CASE_TIMEOUT}"
echo "PODMANHPC_LOG_LEVEL=${PODMANHPC_LOG_LEVEL}"
echo "RUN_DEFAULT_USER=${RUN_DEFAULT_USER}"
echo "RUN_ROOT_USER=${RUN_ROOT_USER}"
echo "RUN_KEEP_GROUPS=${RUN_KEEP_GROUPS}"
echo "RUN_GROUP_WRITE_TEST=${RUN_GROUP_WRITE_TEST}"
echo "GROUP_WRITE_TEST_DIR=${GROUP_WRITE_TEST_DIR}"

if [[ "${RUN_DEFAULT_USER}" == "1" ]]; then
  run_case default-user "" 0775 0
fi

if [[ "${RUN_KEEP_GROUPS}" == "1" ]]; then
  run_case default-user-keep-groups "" 0775 1
fi

if [[ "${RUN_ROOT_USER}" == "1" ]]; then
  run_case root-user "0:0" 0777 0
fi

run_group_write_tests_if_configured
