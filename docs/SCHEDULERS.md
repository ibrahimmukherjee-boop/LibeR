# Slurm and Grid Engine execution

LibeRties can submit its existing durable job contract to Slurm or Grid Engine.
The LibeRties API and scheduler commands run on the cluster submission host;
the R worker runs on a compute node. The client continues to communicate only
with the LibeRties API, directly or through LibeRation's SSH-tunnel connection.

## Requirements

- The LibeRties root must be on storage writable from both the submission host
  and compute nodes. On UCL Myriad, use a directory below `~/Scratch`, not a
  workstation path.
- The same R installation and LibeR package library must be visible from the
  compute nodes. `prologue` may contain trusted operator-controlled module
  commands when the cluster requires them.
- `sbatch`, `squeue`, `sacct`, `scontrol`, and `scancel` must be available for
  Slurm; Grid Engine requires `qsub`, `qstat`, `qacct`, and `qdel`.
- The API process must remain available to accept and report jobs. Scheduler
  jobs themselves continue if the API restarts; the durable queue reconnects
  to their scheduler job IDs.

## UCL Myriad (Grid Engine)

Myriad uses Grid Engine. Its documented multi-core resource convention is the
`smp` parallel environment, `h_rt` for wall time, and `mem` per requested core.
LibeRties therefore divides a user's whole-job memory ceiling across the
requested slots by default.

UCL has also announced a future Myriad migration to Slurm. At deployment time,
check `command -v qsub` and `command -v sbatch` on the login node and select the
matching LibeRties executor; both paths use the same typed job contract and
durable queue.

```r
library(LibeRties)

root <- path.expand("~/Scratch/LibeRties")
key_file <- path.expand("~/.liberties-storage-key")

# One-time setup; keep this file outside the queue root and source repository.
if (!file.exists(key_file)) {
  writeLines(ls_generate_storage_key(), key_file)
  Sys.chmod(key_file, mode = "0600")
}
Sys.setenv(LIBERTIES_STORAGE_KEY = readLines(key_file, n = 1L))

executor <- ls_grid_engine_executor(
  parallel_environment = "smp",
  memory_resource = "mem",
  runtime_resource = "h_rt",
  max_cores_per_job = 36L,
  storage_key_file = key_file,
  # Add site-specific R module commands only when needed:
  prologue = character()
)

user <- ls_user_create(
  root, "ucl-test",
  limits = list(max_concurrent_jobs = 20L, max_queued_jobs = 100L)
)

ls_run_api(
  root, host = "127.0.0.1", port = 8000L,
  max_workers_per_user = 20L,
  production = FALSE,
  executor = executor
)
```

`max_workers_per_user` is the maximum number of that user's jobs submitted to
the cluster at once; additional LibeRties jobs remain durably queued. Set it
deliberately rather than using a workstation-oriented default. The user's
`max_concurrent_jobs` limit is an additional ceiling.

The example uses `production = FALSE` intentionally. Grid Engine supplies
resource scheduling, but its presence alone does not prove filesystem,
identity, and network isolation between mutually untrusted LibeRties tenants.
For the UCL research test, bind the API to loopback and use LibeRation's SSH
tunnel. A production multi-tenant deployment must provide and attest a genuine
cluster sandbox through `isolation_probe`.

Use the same executor when launching the administration GUI so its Cancel
action calls `qdel`:

```r
ls_run_admin(root, executor = executor)
```

## Slurm

```r
executor <- ls_slurm_executor(
  partition = "compute",
  account = "pharmacometrics",
  max_cores_per_job = 32L,
  storage_key_file = key_file,
  prologue = character()
)

ls_run_api(
  root, host = "127.0.0.1", port = 8000L,
  max_workers_per_user = 20L,
  production = FALSE,
  executor = executor
)
```

Each job requests one node, one task, `n_cores` CPUs per task, the user's
whole-job memory ceiling, and the wall-time ceiling. Optional `partition`,
`account`, `qos`, and `constraint` values are applied by the trusted server
operator. Slurm status and final accounting are read through `squeue` and
`sacct`; cancellation uses `scancel`. A bounded `scontrol` fallback reconciles
recently completed jobs when accounting is unavailable, but recovery after
Slurm purges controller history still requires working `sacct` accounting.

## Local WSL integration harness

`LibeRties/tools/wsl-scheduler-test` contains reproducible single-node Slurm
and Grid Engine-compatible setup and smoke scripts. Ubuntu 22.04's packaged
Grid Engine 8.1.9 qmaster has a confirmed spool-loading crash, so the harness
uses the maintained Open Cluster Scheduler 9.1.4 release under `/opt/ocs`
without replacing distribution libraries.

The real smoke suite submits a two-core LibeRation ADVAN1 simulation through
each executor, reconstructs the durable queue supervisor while the allocation
is active, checks its numerical result and terminal scheduler accounting, then
cancels a second allocation through `qdel` or `scancel`. See the harness README
for setup and restart-health commands. Its optional Windows client campaign
adds isolated gateway and target SSH daemons, submits through LibeRation's
managed ProxyJump path, deliberately removes the client tunnel while each job
runs, reconnects, and verifies durable result retrieval without duplicate jobs.

## Durability and security boundary

Scheduler job IDs, profiles, wrapper checksums, requested cores, and final
accounting are retained in job metadata. Pending and running allocations are
reattached after an API restart. A scheduler outage is treated as unknown
rather than as job death, preventing accidental duplicate submission.

Remote payloads cannot supply shell code or raw scheduler arguments. Only the
server operator can configure `prologue` or `extra_submit_args`. Storage keys
are passed to compute nodes by protected file path, not embedded in scheduler
arguments or generated job scripts. Scheduler resource controls complement,
but do not replace, systemd/container identity, mount, process, and network
isolation for hostile multi-tenant use.
