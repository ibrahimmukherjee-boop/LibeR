#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(LibeRties)
  library(LibeRation)
})

root <- tempfile("liberties-real-grid-engine-")
dir.create(root, recursive = TRUE)
cat("queue_root=", root, "\n", sep = "")

model <- LibeRation::nm_model(
  INPUT = c("ID", "TIME", "EVID", "AMT"), ADVAN = 1,
  DOSECMP = 1, OBSCMP = 1,
  PRED = "CL=THETA(1)\nV=THETA(2)\nS1=V", ERROR = "Y=F",
  THETAS = data.frame(THETA = 1:2, Value = c(2, 20))
)
job <- ls_job(
  "simulate", model,
  data.frame(ID = 1, TIME = c(0, 1), EVID = c(1, 0), AMT = c(100, 0)),
  arguments = list(n_cores = 2L), label = "real Grid Engine ADVAN1 smoke test"
)

bin <- "/opt/ocs/bin/lx-amd64"
executor <- ls_grid_engine_executor(
  queue = "all.q", parallel_environment = "smp",
  memory_resource = "mem", runtime_resource = "h_rt",
  max_cores_per_job = 4L, prologue = "sleep 2",
  submit = file.path(bin, "qsub"), query = file.path(bin, "qstat"),
  accounting = file.path(bin, "qacct"), cancel = file.path(bin, "qdel")
)
queue <- ls_local_queue(
  root, max_workers = 2L,
  limits = list(max_runtime_seconds = 90, max_memory_mb = 1024),
  executor = executor
)
id <- queue$submit(job)
submitted <- queue$status(id)
stopifnot(nzchar(submitted$scheduler_job_id))
cat(
  "submitted=", id, " scheduler_job_id=", submitted$scheduler_job_id,
  " profile=", submitted$scheduler_profile, "\n", sep = ""
)

# Reopen the queue while the allocation is pending/running. The replacement
# supervisor must reconnect to the scheduler ID rather than submit it twice.
reopened <- ls_local_queue(
  root, max_workers = 2L,
  limits = list(max_runtime_seconds = 90, max_memory_mb = 1024),
  executor = executor
)
reopened$poll(start = FALSE)
key <- paste("local", id, sep = "::")
stopifnot(exists(key, envir = reopened$processes, inherits = FALSE))

finished <- reopened$wait(id, timeout = 120, poll_interval = 0.2)
stopifnot(identical(finished$status, "completed"))
result <- reopened$result(id)
stopifnot(isTRUE(all.equal(
  result$IPRED, c(5, 5 * exp(-0.1)), tolerance = 1e-10
)))
for (attempt in seq_len(100L)) {
  reopened$poll(start = FALSE)
  finished <- reopened$status(id)
  if (finished$scheduler_state %in% c("COMPLETED", "FAILED")) break
  Sys.sleep(0.1)
}
stopifnot(identical(finished$scheduler_state, "COMPLETED"))
cat(
  "completed scheduler_state=", finished$scheduler_state,
  " result_rows=", nrow(result), "\n", sep = ""
)

cancel_executor <- ls_grid_engine_executor(
  queue = "all.q", parallel_environment = "smp",
  memory_resource = "mem", runtime_resource = "h_rt",
  max_cores_per_job = 4L, prologue = "sleep 30",
  submit = file.path(bin, "qsub"), query = file.path(bin, "qstat"),
  accounting = file.path(bin, "qacct"), cancel = file.path(bin, "qdel")
)
cancel_queue <- ls_local_queue(
  tempfile("liberties-real-grid-engine-cancel-"), executor = cancel_executor,
  limits = list(max_runtime_seconds = 90, max_memory_mb = 1024)
)
cancel_id <- cancel_queue$submit(job)
cancel_meta <- cancel_queue$status(cancel_id)
Sys.sleep(1)
stopifnot(isTRUE(cancel_queue$cancel(cancel_id)))
stopifnot(identical(cancel_queue$status(cancel_id)$status, "cancelled"))
cat(
  "cancelled scheduler_job_id=", cancel_meta$scheduler_job_id,
  " via=qdel\n", sep = ""
)

cat("REAL_GRID_ENGINE_LIBERTIES_SMOKE_OK\n")
