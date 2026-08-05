#!/usr/bin/env bash
set -euo pipefail

# Ubuntu 22.04's packaged Berkeley DB spool helper can fault in some WSL
# kernels while importing the default configuration.  Classic spooling uses
# the same Grid Engine scheduler interfaces exercised by LibeRties and is
# sufficient for this deliberately single-node integration harness.
export SGE_ROOT=/var/lib/gridengine
export SGE_CELL=default

common="${SGE_ROOT}/${SGE_CELL}/common"
qmaster=/var/spool/gridengine/qmaster
spooling_params="${common};${qmaster}"

/usr/lib/gridengine/spoolinit classic libspoolc "${spooling_params}" init
/usr/lib/gridengine/spooldefaults configuration \
  /usr/share/gridengine/default-configuration
/usr/lib/gridengine/spooldefaults complexes \
  /usr/share/gridengine/util/resources/centry
/usr/lib/gridengine/spooldefaults usersets \
  /usr/share/gridengine/util/resources/usersets
/usr/lib/gridengine/spooldefaults managers sgeadmin

cat >"${common}/settings.sh" <<EOF
SGE_ROOT=${SGE_ROOT}; export SGE_ROOT
SGE_CELL=${SGE_CELL}; export SGE_CELL
SGE_ARCH=lx-amd64; export SGE_ARCH
EOF

cat >"${common}/settings.csh" <<EOF
setenv SGE_ROOT ${SGE_ROOT}
setenv SGE_CELL ${SGE_CELL}
setenv SGE_ARCH lx-amd64
EOF
