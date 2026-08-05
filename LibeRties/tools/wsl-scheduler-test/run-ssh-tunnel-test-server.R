#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L) {
  stop("Usage: run-ssh-tunnel-test-server.R BACKEND ROOT PORT TOKEN_FILE")
}
backend <- match.arg(args[[1L]], c("grid_engine", "slurm"))
root <- normalizePath(args[[2L]], winslash = "/", mustWork = FALSE)
port <- as.integer(args[[3L]])
token_file <- normalizePath(args[[4L]], winslash = "/", mustWork = FALSE)

suppressPackageStartupMessages(library(LibeRties))

unlink(root, recursive = TRUE, force = TRUE)
dir.create(root, recursive = TRUE, mode = "0700")
user <- ls_user_create(
  root, "ssh-smoke", scopes = c("jobs:read", "jobs:write"),
  limits = list(
    max_concurrent_jobs = 2L, max_queued_jobs = 10L,
    max_runtime_seconds = 90, max_memory_mb = 1024
  )
)
dir.create(dirname(token_file), recursive = TRUE, showWarnings = FALSE)
writeLines(user$token, token_file, useBytes = TRUE)
Sys.chmod(token_file, mode = "0600")

executor <- if (identical(backend, "grid_engine")) {
  ls_grid_engine_executor(
    queue = "all.q", parallel_environment = "smp",
    memory_resource = "mem", runtime_resource = "h_rt",
    max_cores_per_job = 4L, prologue = "sleep 3",
    submit = "/opt/ocs/bin/lx-amd64/qsub",
    query = "/opt/ocs/bin/lx-amd64/qstat",
    accounting = "/opt/ocs/bin/lx-amd64/qacct",
    cancel = "/opt/ocs/bin/lx-amd64/qdel"
  )
} else {
  ls_slurm_executor(
    partition = "debug", max_cores_per_job = 4L, prologue = "sleep 3"
  )
}

ls_run_api(
  root, host = "127.0.0.1", port = port,
  max_workers_per_user = 2L, quiet = TRUE,
  production = FALSE, executor = executor
)
