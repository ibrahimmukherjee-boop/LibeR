# LibeRties

LibeRties provides durable local and remote job execution for the LibeR
population PK/PD modelling system. It uses a versioned typed-JSON contract,
background R workers, per-tenant namespaces, authenticated HTTP access,
restart recovery, quotas, resource limits, integrity checks, cancellation,
logs, and result provenance. Production workers run as transient systemd user
services with user, mount, process, and (by default) network namespaces plus
cgroup-v2 resource controls.

LibeRties is distributed as part of the LibeR 0.9 research beta. Use the
[ecosystem installer](../docs/INSTALL.md) for a compatible package set and
review `LibeRation::liber_support_matrix("LibeRties")`, especially the
deployment-owned isolation boundary, before operating a remote service.

## Local queue

```r
library(LibeRties)

queue <- ls_local_queue("~/LibeR/workspace/.jobs")
queue$poll(start = TRUE)
```

LibeRation creates and restores this persistent queue automatically when
`liber_gui()` is launched with LibeRties installed.

## Remote service

```r
library(LibeRties)

root <- "D:/liberties-data"
user <- ls_user_create(
  root, "alice", first_name = "Alice",
  scopes = c("jobs:read", "jobs:write"),
  expires = Sys.time() + 90 * 24 * 3600
)
# Store user$token securely; it is returned only when created or rotated.
Sys.setenv(LIBERTIES_STORAGE_KEY = ls_generate_storage_key())
ls_server_preflight(root, "127.0.0.1")
ls_run_api(root, host = "127.0.0.1", port = 8000L, production = FALSE)
```

Bind the R service to a private or loopback interface and terminate TLS at a
maintained reverse proxy for remote deployment. On Linux,
`ls_run_api(..., production = TRUE)` now selects [ls_systemd_executor()] and
performs a fail-closed live preflight. Run the API under a dedicated non-root
account whose systemd user manager remains active (`loginctl enable-linger`).
The preflight verifies systemd as PID 1, cgroup v2, the user manager, transient
namespace creation, storage-key delivery, and the configured account. Windows
hosts must provide this Linux environment through WSL 2; macOS operators must
provide their own Linux systemd environment. LibeR does not bundle either.
See [the systemd deployment guide](../docs/SYSTEMD.md).

Each job's `n_cores` becomes `CPUQuota = 100% * n_cores`, not a one-core cap.
`TasksMax` is sized above the requested core count, and `KillMode=control-group`
keeps every PSOCK/FORK child in the same job boundary. Consequently the current
multi-core estimators and simulations continue to work while aggregate CPU,
memory, process/thread count, and wall time are constrained. Compute jobs have
no external network; the explicitly typed LibeRary literature jobs retain
network access. All workers live below `liberties-workers.slice`, where an
operator may add aggregate host ceilings across tenants. Configure
`trusted_proxies` explicitly before forwarded client
addresses are accepted. Rate-limit state is memory bounded, remote logs are
size-limited and secret-redacted, and terminal logs are authenticated-encrypted
when a storage key is configured.

Remote submissions accept a user-scoped `Idempotency-Key`; the key is bound to
the payload digest and claimed atomically with quota enforcement. Security
events are written to append-only encrypted hash-chain journals and can be
mirrored to deployment-owned external storage with `LIBERTIES_AUDIT_MIRROR`.
The mirror is canonical JSON rather than a second encrypted LibeRties store;
the deployment must provide its access control, transport security, retention,
and immutability/WORM policy.
Trusted local queues deliberately retain the cross-platform subprocess backend;
it is not presented as a hostile-code sandbox or accepted by production
preflight.

The administration interface is launched with `ls_run_admin()`. Persistent
users and job history are read from `LIBERTIES_ROOT` or
`options(LibeRties.root = ...)`, not from the installed package directory.

## AI-assisted development

GPT-5.6 was used as an AI engineering collaborator to help implement and review
the typed job contracts, queue and server infrastructure, security controls, administration GUI, tests, and documentation.
Architecture, threat-model decisions, validation criteria, and release approval remain the responsibility of the project owner.

LibeRties requires R 4.1 or newer and is MIT licensed.
