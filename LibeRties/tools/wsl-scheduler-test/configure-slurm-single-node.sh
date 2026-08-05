#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

node=$(hostname -s)
detected=$(/usr/sbin/slurmd -C)
cpus=$(sed -n 's/.*CPUs=\([0-9][0-9]*\).*/\1/p' <<<"${detected}")
memory=$(sed -n 's/.*RealMemory=\([0-9][0-9]*\).*/\1/p' <<<"${detected}")
# Leave a little memory to WSL and the scheduler daemons.
memory=$((memory - 512))

install -d -o slurm -g slurm -m 0755 /var/spool/slurmctld
install -d -o root -g root -m 0755 /var/spool/slurmd
install -d -o slurm -g slurm -m 0755 /var/log/slurm

cat >/etc/slurm/slurm.conf <<EOF
ClusterName=liberties-wsl
SlurmctldHost=${node}
SlurmUser=slurm
SlurmdUser=root
AuthType=auth/munge
CryptoType=crypto/munge
StateSaveLocation=/var/spool/slurmctld
SlurmdSpoolDir=/var/spool/slurmd
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log
SlurmctldPidFile=/run/slurmctld.pid
SlurmdPidFile=/run/slurmd.pid
SwitchType=switch/none
MpiDefault=none
ProctrackType=proctrack/linuxproc
TaskPlugin=task/affinity
ReturnToService=2
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory
AccountingStorageType=accounting_storage/none
JobCompType=jobcomp/filetxt
JobCompLoc=/var/log/slurm/jobcomp.log
MinJobAge=300
NodeName=${node} CPUs=${cpus} RealMemory=${memory} State=UNKNOWN
PartitionName=debug Nodes=${node} Default=YES MaxTime=INFINITE State=UP
EOF
chmod 0644 /etc/slurm/slurm.conf

systemctl restart munge
systemctl restart slurmctld
systemctl restart slurmd

echo "Configured Slurm node ${node} with ${cpus} CPUs and ${memory} MB."
