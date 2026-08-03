#!/usr/bin/env Rscript

if (!identical(Sys.info()[["sysname"]], "Linux")) {
  stop("The systemd concurrency test must run inside Linux.", call. = FALSE)
}
for (package in c("LibeRties", "LibeRation", "jsonlite")) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop(package, " must be installed for the concurrency test.", call. = FALSE)
  }
}

credential <- Sys.getenv("LIBERTIES_SYSTEMD_STORAGE_CREDENTIAL", unset = "")
if (!nzchar(credential) || !file.exists(credential)) {
  stop("Set LIBERTIES_SYSTEMD_STORAGE_CREDENTIAL to the protected storage-key file.",
       call. = FALSE)
}
key <- trimws(readLines(credential, n = 1L, warn = FALSE))
if (!grepl("^[A-Fa-f0-9]{64}$", key)) {
  stop("The storage-key file is not a 256-bit hexadecimal key.", call. = FALSE)
}
options(LibeRties.storage_key = key)

jobs <- as.integer(Sys.getenv("LIBERTIES_CONCURRENCY_JOBS", unset = "8"))
workers <- as.integer(Sys.getenv("LIBERTIES_CONCURRENCY_WORKERS", unset = "4"))
if (is.na(jobs) || jobs < 2L || is.na(workers) || workers < 2L || jobs < workers) {
  stop("Use at least two workers and no fewer jobs than workers.", call. = FALSE)
}

root <- tempfile("liberties-systemd-concurrency-", tmpdir = "/tmp")
on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
executor <- LibeRties::ls_systemd_executor(
  max_cores_per_job = 2L, storage_credential = credential
)
preflight <- LibeRties::ls_server_preflight(
  root, host = "127.0.0.1", behind_tls_proxy = TRUE,
  policy = LibeRties::ls_security_policy(production = TRUE),
  strict = TRUE, executor = executor
)

model <- LibeRation::nm_model(
  INPUT = c("ID", "TIME", "EVID", "AMT", "DV", "MDV"),
  ADVAN = 2L, TRANS = 2L, DOSECMP = 1L, OBSCMP = 2L,
  PRED = "CL=THETA(1); V=THETA(2); KA=THETA(3); S2=V",
  ERROR = "Y=F+ERR(1)",
  THETAS = data.frame(THETA = 1:3, Value = c(4, 40, 1.3)),
  SIGMAS = data.frame(SIGMA = 1L, Value = 0.04, FIX = TRUE)
)
data <- do.call(rbind, lapply(seq_len(80L), function(id) {
  time <- seq(0.5, 24, by = 0.5)
  data.frame(
    ID = id, TIME = c(0, time), EVID = c(1L, rep(0L, length(time))),
    AMT = c(100, rep(0, length(time))), DV = NA_real_,
    MDV = c(1L, rep(0L, length(time)))
  )
}))
queue <- LibeRties::ls_local_queue(
  root, max_workers = workers,
  limits = list(
    max_concurrent_jobs = workers, max_queued_jobs = jobs + 2L,
    max_runtime_seconds = 180, max_memory_mb = 2048,
    max_payload_mb = 64, max_result_mb = 128
  ),
  executor = executor
)

ids <- vapply(seq_len(jobs), function(index) {
  queue$submit(LibeRties::ls_job(
    "simulate", model, data,
    arguments = list(nsim = 6L, n_cores = 2L, seed = 202608030L + index),
    label = paste("systemd concurrency", index)
  ))
}, character(1))

started <- proc.time()[["elapsed"]]
maximum_running <- 0L
observations <- list()
repeat {
  queue$poll(start = TRUE)
  states <- lapply(ids, queue$status)
  status <- vapply(states, `[[`, character(1), "status")
  running <- sum(status %in% "running")
  maximum_running <- max(maximum_running, running)
  observations[[length(observations) + 1L]] <- list(
    elapsed = unname(proc.time()[["elapsed"]] - started),
    queued = sum(status == "queued"), running = running,
    terminal = sum(status %in% c("completed", "failed", "cancelled"))
  )
  if (all(status %in% c("completed", "failed", "cancelled"))) break
  if (proc.time()[["elapsed"]] - started > 180) {
    stop("Systemd concurrency test timed out.", call. = FALSE)
  }
  Sys.sleep(0.05)
}

states <- lapply(ids, queue$status)
status <- vapply(states, `[[`, character(1), "status")
if (any(status != "completed")) {
  errors <- vapply(states, function(state) {
    value <- state$error
    if (is.null(value) || !length(value) || is.na(value[[1L]])) "" else
      as.character(value[[1L]])
  }, character(1))
  stop("One or more concurrent jobs failed: ", paste(errors[nzchar(errors)], collapse = "; "),
       call. = FALSE)
}
if (maximum_running < 2L || maximum_running > workers) {
  stop("Observed concurrency was outside the configured bounds.", call. = FALSE)
}
units <- vapply(states, `[[`, character(1), "systemd_unit")
if (any(!nzchar(units)) || anyDuplicated(units)) {
  stop("Concurrent jobs did not retain distinct systemd units.", call. = FALSE)
}
results <- lapply(ids, queue$result)
if (any(!vapply(results, is.data.frame, logical(1))) ||
    any(!vapply(results, nrow, integer(1)))) {
  stop("A concurrent worker returned an invalid result.", call. = FALSE)
}

evidence <- list(
  schema = "liberties.systemd.concurrency", version = 1L,
  passed = TRUE,
  checked = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
  configured_jobs = jobs, configured_workers = workers,
  requested_cores_per_job = 2L, maximum_running = maximum_running,
  elapsed_seconds = unname(proc.time()[["elapsed"]] - started),
  preflight = unclass(preflight),
  jobs = lapply(states, function(state) state[c(
    "id", "status", "systemd_unit", "requested_cores", "tasks_max",
    "peak_memory_mb", "cpu_seconds", "elapsed_seconds"
  )]),
  observations = observations,
  packages = vapply(
    c("LibeRties", "LibeRation", "LibeRtAD"),
    function(package) as.character(utils::packageVersion(package)),
    character(1)
  )
)
output <- Sys.getenv("LIBERTIES_SYSTEMD_EVIDENCE", unset = "")
if (nzchar(output)) {
  jsonlite::write_json(evidence, output, auto_unbox = TRUE, pretty = TRUE)
}
cat(jsonlite::toJSON(evidence, auto_unbox = TRUE, pretty = TRUE), "\n")
