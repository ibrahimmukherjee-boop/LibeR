#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

node=$(hostname -s)
cpus=$(nproc)
memory_mb=$(awk '/^MemTotal:/ { print int($2 / 1024) - 1024 }' /proc/meminfo)
work=$(mktemp -d /tmp/liberties-ocs-config.XXXXXX)
trap 'rm -rf "${work}"' EXIT

set +u
# shellcheck disable=SC1091
source /opt/ocs/default/common/settings.sh
set -u

qconf -sc >"${work}/complex"
if ! grep -qE '^mem[[:space:]]' "${work}/complex"; then
  printf '%-19s %-10s %-11s %-5s %-11s %-10s %-8s %s\n' \
    mem mem MEMORY '<=' YES YES 0 0 >>"${work}/complex"
  qconf -Mc "${work}/complex"
fi

qconf -mattr exechost complex_values "slots=${cpus},mem=${memory_mb}M" "${node}"

cat >"${work}/smp" <<EOF
pe_name            smp
slots              ${cpus}
user_lists         NONE
xuser_lists        NONE
start_proc_args    /bin/true
stop_proc_args     /bin/true
allocation_rule    \$pe_slots
control_slaves     FALSE
job_is_first_task  TRUE
urgency_slots      min
accounting_summary TRUE
ign_sreq_on_mhost FALSE
daemon_forks_slaves FALSE
master_forks_slaves FALSE
EOF
if qconf -spl | grep -Fxq smp; then
  qconf -Mp "${work}/smp"
else
  qconf -Ap "${work}/smp"
fi

qconf -sq all.q >"${work}/queue"
sed -i -E 's/^pe_list[[:space:]].*/pe_list               make smp/' "${work}/queue"
qconf -Mq "${work}/queue"

qconf -sp smp
qstat -f
echo "Configured OCS with ${cpus} SMP slots and ${memory_mb} MB of consumable mem."
