#!/bin/bash
#SBATCH --job-name=podman-keepid-run
#SBATCH --account=YOUR_NERSC_ACCOUNT
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --constraint=cpu
#SBATCH --qos=debug
#SBATCH --time=00:10:00
#SBATCH --output=/dev/null

set -euo pipefail

: "${SCRATCH:?SCRATCH must point to Perlmutter scratch}"
JOB_OUTPUT_DIR="${JOB_OUTPUT_DIR:-${SCRATCH}/communication-libraries-image/podman-keepid-run}"
mkdir -p "${JOB_OUTPUT_DIR}"
exec > >(tee -a "${JOB_OUTPUT_DIR}/${SLURM_JOB_NAME:-job}-${SLURM_JOB_ID:-manual}.out") 2>&1

IMAGE="${IMAGE:-ubuntu:latest}"
CASE_COMMAND="${CASE_COMMAND:-uname}"
CASE_TIMEOUT="${CASE_TIMEOUT:-90}"
NEW_PODMAN="${NEW_PODMAN:-${SCRATCH}/communication-libraries-image/podman-alt/podman-5.8.2/bin/podman}"
PATCHED_PODMAN="${PATCHED_PODMAN:-${SCRATCH}/communication-libraries-image/podman-alt/podman-5.8.2-force-shifting/bin/podman}"
CANDIDATE_PODMAN="${CANDIDATE_PODMAN:-}"
CANDIDATE_NAME="${CANDIDATE_NAME:-podman-candidate}"
CANDIDATE_FORCE_SHIFTING="${CANDIDATE_FORCE_SHIFTING:-0}"
PODMANHPC_LOG_LEVEL="${PODMANHPC_LOG_LEVEL:-fatal}"
RUN_SYSTEM="${RUN_SYSTEM:-1}"
RUN_UNPATCHED="${RUN_UNPATCHED:-1}"
RUN_PATCHED="${RUN_PATCHED:-1}"
RUN_CANDIDATE="${RUN_CANDIDATE:-0}"

run_case() {
  local name="$1"
  local podman_bin="$2"
  local force_shifting="$3"
  local status

  echo
  echo "===== BEGIN CASE ${name} backend=${podman_bin} force_shifting=${force_shifting} command=${CASE_COMMAND} ====="

  if [[ "${podman_bin}" == "system" ]]; then
    unset PODMANHPC_PODMAN_BIN
  else
    export PODMANHPC_PODMAN_BIN="${podman_bin}"
  fi

  if [[ "${force_shifting}" == "1" ]]; then
    export _CONTAINERS_FORCE_SHIFTING=1
  else
    unset _CONTAINERS_FORCE_SHIFTING
  fi

  set +e
  timeout "${CASE_TIMEOUT}" podman-hpc --log-level "${PODMANHPC_LOG_LEVEL}" run --rm --privileged --userns=keep-id "${IMAGE}" ${CASE_COMMAND}
  status=$?
  set -e

  echo "===== END CASE ${name} status=${status} ====="
}

echo "HOST=$(hostname -f)"
echo "IMAGE=${IMAGE}"
echo "CASE_COMMAND=${CASE_COMMAND}"
echo "NEW_PODMAN=${NEW_PODMAN}"
echo "PATCHED_PODMAN=${PATCHED_PODMAN}"
echo "CANDIDATE_PODMAN=${CANDIDATE_PODMAN}"
echo "CANDIDATE_NAME=${CANDIDATE_NAME}"
echo "CANDIDATE_FORCE_SHIFTING=${CANDIDATE_FORCE_SHIFTING}"
echo "CASE_TIMEOUT=${CASE_TIMEOUT}"
echo "PODMANHPC_LOG_LEVEL=${PODMANHPC_LOG_LEVEL}"
echo "RUN_SYSTEM=${RUN_SYSTEM}"
echo "RUN_UNPATCHED=${RUN_UNPATCHED}"
echo "RUN_PATCHED=${RUN_PATCHED}"
echo "RUN_CANDIDATE=${RUN_CANDIDATE}"

if [[ "${RUN_SYSTEM}" == "1" ]]; then
  run_case system system 0
fi

if [[ "${RUN_UNPATCHED}" == "1" ]]; then
  if [[ -x "${NEW_PODMAN}" ]]; then
    run_case podman-5.8.2 "${NEW_PODMAN}" 0
  else
    echo "Skipping unpatched 5.8.2; not executable: ${NEW_PODMAN}"
  fi
fi

if [[ "${RUN_PATCHED}" == "1" ]]; then
  if [[ -x "${PATCHED_PODMAN}" ]]; then
    run_case podman-5.8.2-force-shifting "${PATCHED_PODMAN}" 1
  else
    echo "Skipping patched 5.8.2; not executable: ${PATCHED_PODMAN}"
  fi
fi

if [[ "${RUN_CANDIDATE}" == "1" ]]; then
  if [[ -x "${CANDIDATE_PODMAN}" ]]; then
    run_case "${CANDIDATE_NAME}" "${CANDIDATE_PODMAN}" "${CANDIDATE_FORCE_SHIFTING}"
  else
    echo "Skipping candidate; not executable: ${CANDIDATE_PODMAN}"
  fi
fi
