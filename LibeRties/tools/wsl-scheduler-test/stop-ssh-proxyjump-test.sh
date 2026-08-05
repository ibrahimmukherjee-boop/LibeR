#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

systemctl stop liberties-test-gateway-sshd.service \
  liberties-test-target-sshd.service 2>/dev/null || true
# Remove the disposable client's authorization while retaining host keys and
# configuration for reproducible future runs.
install -o root -g root -m 0600 /dev/null \
  /etc/ssh/liberties-test/authorized_keys
echo "SSH_PROXYJUMP_TEST_ENDPOINTS_STOPPED"
