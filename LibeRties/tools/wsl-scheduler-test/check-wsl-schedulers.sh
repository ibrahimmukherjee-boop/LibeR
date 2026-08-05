#!/usr/bin/env bash
set -euo pipefail

for service in liberties-wsl-hostname munge slurmctld slurmd ocs-qmaster ocs-execd; do
  systemctl is-active --quiet "${service}.service"
  echo "${service}=active"
done

node=$(hostname -s)
address=$(getent ahostsv4 "${node}" | awk 'NR == 1 { print $1 }')
if [[ -z "${address}" || "${address}" == 127.* ]]; then
  echo "${node} resolves to invalid scheduler address ${address:-missing}." >&2
  exit 1
fi
echo "hostname=${node} address=${address}"

for command in qsub qstat qacct qdel; do
  resolved=$(command -v "${command}")
  [[ "${resolved}" == "/usr/local/bin/${command}" ]]
  echo "${command}=${resolved}"
done

set +u
# shellcheck disable=SC1091
source /opt/ocs/default/common/settings.sh
set -u
for _ in $(seq 1 30); do
  if ! qstat -f 2>/dev/null | grep -Eq '[[:space:]](a|u|au|d|E)[A-Za-z]*$'; then
    break
  fi
  sleep 1
done
qstat -f
if qstat -f 2>/dev/null | grep -Eq '[[:space:]](a|u|au|d|E)[A-Za-z]*$'; then
  echo "OCS queue is not available after restart." >&2
  exit 1
fi

sinfo --noheader --format='%P %a %D %t %N'
sinfo --noheader --format='%t' | grep -Eq '^(idle|mix|alloc)$'
Rscript --vanilla -e '
  suppressPackageStartupMessages(library(LibeRties))
  grid <- ls_grid_engine_executor()
  slurm <- ls_slurm_executor()
  stopifnot(nzchar(grid[["submit"]]), file.exists(grid[["submit"]]))
  stopifnot(nzchar(slurm[["submit"]]), file.exists(slurm[["submit"]]))
  cat("liberties_grid_submit=", grid[["submit"]], "\n", sep = "")
  cat("liberties_slurm_submit=", slurm[["submit"]], "\n", sep = "")
'
echo "WSL_SCHEDULER_HEALTH_OK"
