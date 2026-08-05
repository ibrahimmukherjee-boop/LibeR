#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /mounted/windows/runtime/directory" >&2
  exit 1
fi

runtime=$1
repo=/mnt/c/Users/svdijkman.DESKTOP-4OG10M4/Documents/LibeR
mkdir -p "${runtime}"
rm -f "${runtime}/grid.token" "${runtime}/slurm.token" "${runtime}/stop"

set +u
# shellcheck disable=SC1091
source /opt/ocs/default/common/settings.sh
set -u

Rscript --vanilla "${repo}/LibeRties/tools/wsl-scheduler-test/run-ssh-tunnel-test-server.R" \
  grid_engine /tmp/liberties-ssh-grid 8000 "${runtime}/grid.token" \
  >"${runtime}/grid-api.log" 2>&1 &
grid_pid=$!
Rscript --vanilla "${repo}/LibeRties/tools/wsl-scheduler-test/run-ssh-tunnel-test-server.R" \
  slurm /tmp/liberties-ssh-slurm 8001 "${runtime}/slurm.token" \
  >"${runtime}/slurm-api.log" 2>&1 &
slurm_pid=$!

cleanup() {
  kill "${grid_pid}" "${slurm_pid}" 2>/dev/null || true
  wait "${grid_pid}" "${slurm_pid}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

for _ in $(seq 1 120); do
  if [[ -s "${runtime}/grid.token" && -s "${runtime}/slurm.token" ]] &&
      curl -fsS http://127.0.0.1:8000/v1/health >/dev/null &&
      curl -fsS http://127.0.0.1:8001/v1/health >/dev/null; then
    echo "SSH_TUNNEL_TEST_APIS_READY"
    break
  fi
  if ! kill -0 "${grid_pid}" 2>/dev/null || ! kill -0 "${slurm_pid}" 2>/dev/null; then
    cat "${runtime}/grid-api.log" >&2 || true
    cat "${runtime}/slurm-api.log" >&2 || true
    exit 1
  fi
  sleep 0.25
done
if ! curl -fsS http://127.0.0.1:8000/v1/health >/dev/null ||
    ! curl -fsS http://127.0.0.1:8001/v1/health >/dev/null; then
  echo "Timed out waiting for SSH tunnel test APIs." >&2
  exit 1
fi

while [[ ! -f "${runtime}/stop" ]]; do sleep 0.25; done
echo "SSH_TUNNEL_TEST_APIS_STOPPING"
