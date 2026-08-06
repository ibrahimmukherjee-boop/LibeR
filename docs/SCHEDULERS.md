# Slurm and Grid Engine execution

LibeRties can submit its existing durable job contract to Slurm or Grid Engine.
The LibeRties API and scheduler commands run on the cluster submission host;
the R worker runs on a compute node. A centrally managed deployment exposes a
LibeRties API directly or through LibeRation's SSH-tunnel connection. A desktop
user may instead invoke the same queue directly through short-lived SSH
connections, without running the API daemon.

## Requirements

- The LibeRties root must be on storage writable from both the submission host
  and compute nodes. On UCL Myriad, use a directory below `~/Scratch`, not a
  workstation path.
- The same R installation and LibeR package library must be visible from the
  compute nodes. `prologue` may contain trusted operator-controlled module
  commands when the cluster requires them.
- NONMEM/PsN or nlmixr2/rxode2 must also be visible on compute nodes when those
  execution engines are offered. Load licensed NONMEM modules in the trusted
  executor `prologue`; clients cannot provide module or shell commands.
- `sbatch`, `squeue`, `sacct`, `scontrol`, and `scancel` must be available for
  Slurm; Grid Engine requires `qsub`, `qstat`, `qacct`, and `qdel`.
- For an API deployment, the API process accepts and reports jobs. Scheduler
  jobs themselves continue if the API restarts; the durable queue reconnects
  to their scheduler job IDs. A direct SSH queue performs this reconciliation
  during each client request and does not require a resident API process.

## Direct SSH scheduler route

In LibeRation's Jobs tab, choose **Direct SSH scheduler**, then configure the
submission host, SSH account, Slurm or Grid Engine settings, and optionally an
SSH gateway. The existing SSH assistant can discover or generate a key, load it
into `ssh-agent`, install the public key on the gateway and destination, and
test each hop. Hosted Shiny sessions do not expose this local OpenSSH route.

Every action invokes the fixed `LibeRties::ls_direct_scheduler_cli()` command
and sends a checksummed typed JSON envelope on standard input. No API token,
listener, arbitrary RDS object, client shell fragment, scheduler argument, or
private-key material is transferred. The first successful connection creates
an encrypted durable queue below
`~/.local/share/LibeR/direct-queues/<queue-name>` by default. The locally saved
connection definition retains the matching random encryption key in the
mode-restricted LibeRation workspace settings; it is not sent to browser state.

The remote login environment must make `Rscript` and compatible LibeRties,
LibeRation, and engine packages available. If the cluster requires an R module,
select a full `Rscript` path or a user-owned wrapper path in the setup dialog.
The wrapper is remote account configuration—it is never submitted in a model
job. The queue root and R package library must remain visible to compute nodes.

SSH provides transport authentication and encryption, while the personal SSH
account provides the filesystem/identity boundary. This route is suitable for
a user's own scheduler account. A shared service for mutually untrusted users
still requires the LibeRties API plus independently attested multi-tenant OS or
cluster isolation.

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
  # Site-controlled modules, for example:
  # prologue = c("module load R", "module load nonmem", "module load PsN")
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
The same two-hop harness also exercises daemon-free direct Grid Engine and
Slurm submission and checksum-validated result recovery.

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
