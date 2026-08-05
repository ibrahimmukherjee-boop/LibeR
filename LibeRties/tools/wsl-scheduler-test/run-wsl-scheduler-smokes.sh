#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

repo=${1:-/mnt/c/Users/svdijkman.DESKTOP-4OG10M4/Documents/LibeR}
test_user=${SUDO_USER:-nvidia}

R CMD INSTALL "${repo}/LibeRties"

set +u
# shellcheck disable=SC1091
source /opt/ocs/default/common/settings.sh
set -u

for _ in $(seq 1 30); do
  if qstat -f 2>/dev/null | grep -Eq '^all\.q@.*[[:space:]][A-Za-z-]+[[:space:]]*$' &&
      ! qstat -f 2>/dev/null | grep -Eq '[[:space:]](a|u|au|d|E)[A-Za-z]*$'; then
    break
  fi
  sleep 1
done
if qstat -f 2>/dev/null | grep -Eq '[[:space:]](a|u|au|d|E)[A-Za-z]*$'; then
  qstat -f >&2
  echo "OCS execution queue did not become healthy within 30 seconds." >&2
  exit 1
fi

runuser -u "${test_user}" -- env \
  SGE_ROOT="${SGE_ROOT}" SGE_CELL="${SGE_CELL}" \
  SGE_QMASTER_PORT="${SGE_QMASTER_PORT}" SGE_EXECD_PORT="${SGE_EXECD_PORT}" \
  PATH="/opt/ocs/bin/lx-amd64:${PATH}" \
  Rscript "${repo}/LibeRties/tools/wsl-scheduler-test/run-liberties-grid-engine-smoke.R"

runuser -u "${test_user}" -- \
  Rscript "${repo}/LibeRties/tools/wsl-scheduler-test/run-liberties-slurm-smoke.R"

echo "ALL_WSL_SCHEDULER_SMOKES_OK"
