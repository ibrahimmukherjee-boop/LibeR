# LibeRties 0.8.3

- Adds a fixed non-interactive SSH entry point for personal Slurm and Grid
  Engine accounts. It accepts only the checksummed typed JSON job contract,
  reopens a durable encrypted queue and returns checksummed JSON responses.
- Supports idempotent submission, restart-safe scheduler reconciliation,
  status, logs, result download and cancellation without running the LibeRties
  HTTP service. SSH authentication and optional gateway routing remain client
  responsibilities.
- Validates every scheduler and path field independently, derives safe defaults
  below the remote user's home directory, and keeps storage keys out of worker
  environments by using a mode-0600 shared credential file.

# LibeRties 0.8.2

- Adds an allow-listed execution-engine field to typed local and remote model
  jobs, plus authenticated capability discovery. Native, NONMEM/PsN, and
  nlmixr2 workers use the same durable queue, SSH tunnel, scheduler, result
  integrity, cancellation, recovery, and per-tenant isolation paths.
- Systemd operators can expose licensed engine installations through trusted
  read-only paths; scheduler prologues can load engine modules without their
  resulting PATH being overwritten by the worker environment.
- Carries optional LibeRation audit-artifact bundles through the existing typed
  result contract, with strict filename/content-shape validation and the same
  result-size quotas. Runs that do not request artifacts incur no added result
  payload.
- Adds first-class Slurm and Grid Engine executors with typed operator
  configuration, scheduler-native core/memory/wall-time requests, durable job
  identifiers, restart reattachment, accounting, logs, and cancellation.
- Provides Myriad-compatible Grid Engine defaults (`smp`, `h_rt`, and per-core
  `mem`) and Slurm single-node/cpus-per-task mappings without exposing raw
  scheduler arguments to remote job payloads.
- Delivers encrypted-storage keys to compute workers through a protected shared
  key file and records scheduler profile and wrapper checksums in job metadata.
- Keeps production isolation fail-closed: a resource scheduler is not treated
  as proof of tenant filesystem/network isolation without an independent
  deployment probe.
- Adds reproducible WSL Slurm and Open Cluster Scheduler integration harnesses
  with real submission, supervisor reattachment, terminal accounting, result,
  cancellation, and restart-health tests.
- Extends that harness through a Windows LibeRation two-hop OpenSSH tunnel and
  verifies recovery after the client forward disappears before both Grid
  Engine and Slurm jobs finish.
- Preserves the validated `addl_materialized` flag on remotely transported
  simulation data so ordinary LibeRation simulation results round-trip through
  the typed result contract.
- Accepts unitless zero-memory values emitted by real Grid Engine accounting
  records and reconciles the scheduler's terminal state after a worker has
  already published its LibeRties result.

# LibeRties 0.8.0

- Establishes hardened transient systemd user services as the native Linux
  production executor, with per-job namespaces, cgroup-v2 CPU/memory/task/time
  limits, credential-mounted encrypted storage, and network isolation.
- Production preflight now requires measured live isolation evidence; container
  marker files and descriptive labels cannot attest a sandbox.
- Fails closed on plaintext queue records while encryption is active. Existing
  plaintext stores must be migrated deliberately before enabling a storage key.
- Hardens cancellation against PID reuse, clears and recovers durable submission
  claims, authenticates write scope before payload decode, and strengthens
  administrative authentication and audit journalling.
- Adds reproducible WSL/Linux systemd smoke and concurrent multi-core queue
  campaigns. The restricted `callr` executor remains the portable research and
  local-development path, not a hostile-code isolation boundary.

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
