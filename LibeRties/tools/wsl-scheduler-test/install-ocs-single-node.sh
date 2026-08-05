#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

version=9.1.4
root=/opt/ocs
cache=/var/cache/liberties-schedulers/ocs-${version}
node=$(hostname -s)
arch=lx-amd64

bin_name="ocs-${version}-bin-${arch}.tar.gz"
common_name="ocs-${version}-common.tar.gz"
bin_url=https://hpc-gridware.com/download/12208/
common_url=https://hpc-gridware.com/download/12220/
bin_md5=ccb32163851b14981d97196c57973478
common_md5=12e6266fb33bb4f0c470b252aad41841

install -d -m 0755 "${cache}"
if [[ ! -f "${cache}/${bin_name}" ]]; then
  wget -q -O "${cache}/${bin_name}" "${bin_url}"
fi
if [[ ! -f "${cache}/${common_name}" ]]; then
  wget -q -O "${cache}/${common_name}" "${common_url}"
fi
printf '%s  %s\n' "${bin_md5}" "${cache}/${bin_name}" | md5sum -c -
printf '%s  %s\n' "${common_md5}" "${cache}/${common_name}" | md5sum -c -

# Ubuntu 22.04's gridengine qmaster currently crashes while reading its spool.
# Keep those packaged services disabled and install OCS independently.
systemctl disable --now gridengine-master gridengine-exec 2>/dev/null || true
if [[ ! -f "${root}/.liberties-ocs-${version}" ]]; then
  pkill -x sge_qmaster 2>/dev/null || true
  pkill -x sge_execd 2>/dev/null || true
fi

# WSL changes its virtual NIC address across restarts. OCS correctly refuses a
# cluster hostname that resolves only to loopback, so refresh the hosts entry at
# boot and before every installation run.
cat >/usr/local/sbin/liberties-refresh-wsl-hostname <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
node=$(hostname -s)
address=$(hostname -I | awk '{print $1}')
if [[ -z "${address}" ]]; then
  echo "Unable to determine the WSL IPv4 address." >&2
  exit 1
fi
sed -i -E "/[[:space:]]${node}([[:space:]]|$)/d" /etc/hosts
printf '%s\t%s\n' "${address}" "${node}" >>/etc/hosts
EOF
chmod 0755 /usr/local/sbin/liberties-refresh-wsl-hostname
cat >/etc/systemd/system/liberties-wsl-hostname.service <<'EOF'
[Unit]
Description=Refresh the WSL hostname address for local schedulers
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/liberties-refresh-wsl-hostname
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable liberties-wsl-hostname.service >/dev/null
/usr/local/sbin/liberties-refresh-wsl-hostname

marker="${root}/.liberties-ocs-${version}"
if [[ -f "${marker}" && ! -f "${root}/default/common/bootstrap" ]]; then
  # Recover a prior interrupted installation owned by this script.
  rm -f "${marker}"
fi
if [[ -e "${root}" && ! -f "${marker}" && ! -x "${root}/inst_sge" ]]; then
  echo "${root} exists but is not this managed OCS ${version} installation." >&2
  exit 1
fi

if [[ ! -f "${marker}" ]]; then
  if [[ ! -x "${root}/inst_sge" ]]; then
    stage=/opt/.ocs-${version}-stage
    rm -rf "${stage}"
    install -d -m 0755 "${stage}"
    tar -xzf "${cache}/${common_name}" -C "${stage}"
    tar -xzf "${cache}/${bin_name}" -C "${stage}"
    if ldd "${stage}/bin/${arch}/sge_qmaster" | grep -q 'not found'; then
      ldd "${stage}/bin/${arch}/sge_qmaster" >&2
      exit 1
    fi
    mv "${stage}" "${root}"
  fi

  install -d -m 0755 /etc/ocs /var/spool/ocs/qmaster /var/spool/ocs/execd
  chown -R sgeadmin:sgeadmin "${root}"
  chown -R sgeadmin:sgeadmin /var/spool/ocs
  cat >/etc/ocs/install.conf <<EOF
SGE_ROOT="${root}"
SGE_QMASTER_PORT="6444"
SGE_EXECD_PORT="6445"
SGE_ENABLE_SMF="false"
SGE_CLUSTER_NAME="liberties-wsl"
CELL_NAME="default"
ADMIN_USER="sgeadmin"
QMASTER_SPOOL_DIR="/var/spool/ocs/qmaster"
EXECD_SPOOL_DIR="/var/spool/ocs/execd"
GID_RANGE="20000-20100"
SPOOLING_METHOD="classic"
DB_SPOOLING_DIR="spooldb"
PAR_EXECD_INST_COUNT="1"
ADMIN_HOST_LIST="${node}"
SUBMIT_HOST_LIST="${node}"
EXEC_HOST_LIST="${node}"
EXECD_SPOOL_DIR_LOCAL="/var/spool/ocs/execd"
HOSTNAME_RESOLVING="true"
SHELL_NAME="ssh"
COPY_COMMAND="scp"
DEFAULT_DOMAIN="none"
ADMIN_MAIL="none"
ADD_TO_RC="true"
SLICE_NAME="ocs"
SET_FILE_PERMS="true"
RESCHEDULE_JOBS="wait"
SHADOW_HOST="${node}"
EXEC_HOST_LIST_RM="${node}"
REMOVE_RC="true"
CSP_RECREATE="false"
CSP_COPY_CERTS="false"
CSP_COUNTRY_CODE="GB"
CSP_STATE="England"
CSP_LOCATION="WSL"
CSP_ORGA="LibeR"
CSP_ORGA_UNIT="Testing"
CSP_MAIL_ADDRESS="none"
EOF

  cd "${root}"
  set +e
  ./inst_sge -m -x -auto /etc/ocs/install.conf -noremote -nosmf
  status=$?
  set -e
  latest_log=$(find /tmp -maxdepth 1 -type f -name 'install.*' -printf '%T@ %p\n' |
    sort -rn | sed -n '1s/^[^ ]* //p')
  if [[ -n "${latest_log}" && -f "${latest_log}" ]]; then
    cp "${latest_log}" /var/log/ocs-install.log
  fi
  if [[ ${status} -ne 0 ]]; then
    cat /var/log/ocs-install.log >&2 2>/dev/null || true
    exit "${status}"
  fi
  touch "${marker}"
fi

for service in ocs-qmaster ocs-execd; do
  install -d -m 0755 "/etc/systemd/system/${service}.service.d"
  cat >"/etc/systemd/system/${service}.service.d/10-wsl-hostname.conf" <<'EOF'
[Unit]
Requires=liberties-wsl-hostname.service
After=liberties-wsl-hostname.service
EOF
done
systemctl daemon-reload
systemctl enable --now ocs-qmaster.service ocs-execd.service >/dev/null

cat >/etc/profile.d/ocs.sh <<'EOF'
if [[ -f /opt/ocs/default/common/settings.sh ]]; then
  . /opt/ocs/default/common/settings.sh
fi
EOF
chmod 0644 /etc/profile.d/ocs.sh
for command in qsub qstat qacct qdel qconf qhost; do
  cat >"/usr/local/bin/${command}" <<'EOF'
#!/usr/bin/env bash
set -e
set +u
. /opt/ocs/default/common/settings.sh
exec "/opt/ocs/bin/lx-amd64/$(basename "$0")" "$@"
EOF
  chmod 0755 "/usr/local/bin/${command}"
done

export SGE_ROOT="${root}"
export SGE_CELL=default
export SGE_QMASTER_PORT=6444
export SGE_EXECD_PORT=6445
export PATH="${root}/bin/${arch}:${PATH}"

for _ in $(seq 1 30); do
  if qstat -help >/dev/null 2>&1; then break; fi
  sleep 1
done
qstat -help >/dev/null
qconf -sh | grep -Fx "${node}" >/dev/null
echo "Installed Open Cluster Scheduler ${version} on ${node} at ${root}."
