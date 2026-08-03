# LibeRties 0.7.7

- Makes recursive queue-directory creation idempotent under concurrent Linux
  submissions and validates the production bind-mount boundary during live
  systemd preflight.
- Publishes the final shared asynchronous task-state runtime under a new
  immutable package version after the 0.7.6 release tag.
- Makes remote submissions idempotent with user-scoped, payload-bound atomic
  claims and support for the HTTP `Idempotency-Key` header.
- Writes append-only per-event encrypted, hash-chained audit journals with an
  optional external mirror, and validates recovery and tamper evidence.
- Consolidates resource-limit enforcement and adds concurrent-quota race,
  stuck-claim, plaintext-rejection, cancellation/PID, and complete HTTP
  authorization-matrix regression coverage.
- Adds the native Linux production executor: each job runs as a hardened
  transient systemd user service with private namespaces, per-job cgroup-v2
  CPU/task/memory/wall-time limits, complete-control-group cancellation,
  restart recovery, credential-mounted encrypted storage, and explicit network
  isolation for compute jobs. `CPUQuota` scales with requested `n_cores`, so
  existing multi-process estimation and simulation remain available.

# LibeRties 0.7.6

- Adopts the consolidated asynchronous task-state refresh helper so local and
  remote queue views avoid redundant reactive invalidation when worker state
  has not changed.

# LibeRties 0.7.5

- Updates admin users, jobs, and logs only when their persisted state changes,
  preventing unchanged queue polling from blocking or fading the interface.
- Applies the shared responsive busy-state behavior throughout the admin GUI.

# LibeRties 0.7.4

- Uses LibeRation model contract v3 so direct `$PRED` and combined
  `$PK -> ADVAN -> $PRED` jobs retain both editable sources and their
  execution mode across local and remote workers.
- Makes queue status reads resilient to the brief Windows atomic-write
  rotation window where `metadata.rds` has moved to its durable previous
  generation, eliminating a rare `Unknown job id` race in active workers.

# LibeRties 0.7.3

- Recovers durable queue and server records from their previous atomic-write
  generation when the primary RDS is interrupted or corrupt.
- Joins the LibeR 0.9 research-beta evidence matrix with explicit boundaries
  between built-in process controls and deployment-provided hostile-code
  isolation.

# LibeRties 0.7.2

- Restores the established high-resolution LibeR dove and aligns cards,
  controls, panels, and shadows with the client workbenches.
- Aligns server administration theme persistence, version labelling,
  typography, keyboard focus, and transparent red dove branding with the client
  applications.

# LibeRties 0.7.1

- Requires measured OS/container isolation evidence in production instead of
  trusting an environment label, and applies trusted-proxy-aware client IPs.
- Bounds rate-limit state and returned logs, redacts common secrets, and
  encrypts terminal worker logs at rest when queue encryption is configured.
- Adds malformed-contract fuzz coverage and browser-level admin GUI coverage.

# LibeRties 0.7.0

- Upgrades typed jobs and results to wire contract v2, while retaining read
  compatibility with v1. The contract now preserves all current LibeRation
  model semantics and typed LibeRality result classes.
- Adds scoped and expiring tokens, per-token/IP request throttling, a
  hash-chained administrative audit trail, production preflight checks, and
  security response headers.
- Adds optional authenticated at-rest encryption for queue RDS metadata,
  payloads, and results using a server-owned key; checksums continue to verify
  the encrypted artefacts.
- Monitors and terminates complete worker process trees. Documentation and
  status metadata now call the built-in boundary a restricted subprocess, not
  an operating-system sandbox; production mode requires TLS termination and a
  separately configured OS/container isolation layer.

# LibeRties 0.6.1

- Added typed local and remote queue execution for ordered LibeRation
  estimation sequences, preserving stage configuration and model output
  selections across the wire contract.

# LibeRties 0.6.0

- Extended the typed literature contract from indexing/assessment to the full
  LibeRary pipeline: triage, Docling parsing, independent dual extraction, and
  third-model adjudication.

- Rebuilt local and remote execution around a versioned typed-JSON job and
  result contract.
- Added persistent cross-platform local queues with background workers,
  cancellation, logs, restart recovery, and result provenance.
- Added authenticated multi-tenant HTTP execution with token digests,
  tenant-derived namespaces, checksums, quotas, resource limits, and locked
  state transitions.
- Added durable users, first/last-name administration, searchable/selectable
  admin tables, job-state dashboards, worker logs, and matching light/dark
  branding.
- Added secure client/server settings persistence across package upgrades.

This release is an architectural and API break from the 0.4.x series.
