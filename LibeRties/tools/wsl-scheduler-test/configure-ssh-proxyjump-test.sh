#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi
if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 /path/to/disposable-test-key.pub" >&2
  exit 1
fi

test_user=liber-ssh-test
config_root=/etc/ssh/liberties-test

if ! command -v sshd >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq openssh-server
fi
# Do not expose the distribution's ordinary port-22 daemon for this harness.
systemctl disable --now ssh.service 2>/dev/null || true

if ! id "${test_user}" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "${test_user}"
fi
# Keep the account eligible for public-key authentication.  OpenSSH can reject
# a locked Unix account before it evaluates authorized_keys.  The empty local
# password is not remotely usable because PasswordAuthentication,
# KbdInteractiveAuthentication, and PAM are disabled in both test daemons.
passwd --delete "${test_user}" >/dev/null

install -d -o root -g root -m 0755 "${config_root}"
install -o "${test_user}" -g "${test_user}" -m 0600 \
  "$1" "${config_root}/authorized_keys"
for endpoint in gateway target; do
  if [[ ! -f "${config_root}/${endpoint}_host_key" ]]; then
    ssh-keygen -q -t ed25519 -N '' -f "${config_root}/${endpoint}_host_key"
  fi
done

cat >"${config_root}/gateway.conf" <<EOF
Port 2222
ListenAddress 0.0.0.0
HostKey ${config_root}/gateway_host_key
PidFile /run/liberties-test-gateway-sshd.pid
AuthorizedKeysFile ${config_root}/authorized_keys
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
PermitRootLogin no
AllowUsers ${test_user}
AllowTcpForwarding local
AllowAgentForwarding no
GatewayPorts no
PermitOpen 127.0.0.1:2223
X11Forwarding no
PermitTTY no
LogLevel VERBOSE
EOF

cat >"${config_root}/target.conf" <<EOF
Port 2223
ListenAddress 127.0.0.1
HostKey ${config_root}/target_host_key
PidFile /run/liberties-test-target-sshd.pid
AuthorizedKeysFile ${config_root}/authorized_keys
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
PermitRootLogin no
AllowUsers ${test_user}
AllowTcpForwarding local
AllowAgentForwarding no
GatewayPorts no
PermitOpen 127.0.0.1:8000 127.0.0.1:8001
X11Forwarding no
PermitTTY no
LogLevel VERBOSE
EOF

mkdir -p /run/sshd
/usr/sbin/sshd -t -f "${config_root}/gateway.conf"
/usr/sbin/sshd -t -f "${config_root}/target.conf"

for endpoint in gateway target; do
  cat >"/etc/systemd/system/liberties-test-${endpoint}-sshd.service" <<EOF
[Unit]
Description=LibeRties disposable ${endpoint} SSH test endpoint
After=network.target

[Service]
Type=simple
RuntimeDirectory=sshd
RuntimeDirectoryPreserve=yes
ExecStart=/usr/sbin/sshd -D -e -f ${config_root}/${endpoint}.conf
Restart=on-failure
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF
done
systemctl daemon-reload
systemctl restart liberties-test-gateway-sshd.service
systemctl restart liberties-test-target-sshd.service
systemctl is-active --quiet liberties-test-gateway-sshd.service
systemctl is-active --quiet liberties-test-target-sshd.service
echo "SSH_PROXYJUMP_TEST_ENDPOINTS_READY"
