#!/usr/bin/env Rscript

if (!identical(Sys.info()[["sysname"]], "Linux")) {
  stop("The systemd smoke test must run inside Linux.", call. = FALSE)
}
for (package in c("LibeRties", "LibeRation")) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop(package, " must be installed for the systemd smoke test.", call. = FALSE)
  }
}

credential <- Sys.getenv("LIBERTIES_SYSTEMD_STORAGE_CREDENTIAL", unset = "")
if (!nzchar(credential) || !file.exists(credential)) {
  stop(
    "Set LIBERTIES_SYSTEMD_STORAGE_CREDENTIAL to the protected storage-key file.",
    call. = FALSE
  )
}
key <- trimws(readLines(credential, n = 1L, warn = FALSE))
if (!grepl("^[A-Fa-f0-9]{64}$", key)) {
  stop("The storage-key file is not a 256-bit hexadecimal key.", call. = FALSE)
}
old_key <- getOption("LibeRties.storage_key")
on.exit(options(LibeRties.storage_key = old_key), add = TRUE)
options(LibeRties.storage_key = key)

root <- tempfile("liberties-systemd-smoke-", tmpdir = "/tmp")
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
  INPUT = c("ID", "TIME", "EVID", "AMT"),
  ADVAN = 1L, DOSECMP = 1L, OBSCMP = 1L,
  PRED = "CL=THETA(1); V=THETA(2); S1=V",
  ERROR = "Y=F",
  THETAS = data.frame(THETA = 1:2, Value = c(2, 20))
)
data <- data.frame(
  ID = 1L, TIME = c(0, 1, 4), EVID = c(1L, 0L, 0L),
  AMT = c(100, 0, 0)
)
job <- LibeRties::ls_job(
  "simulate", model, data,
  arguments = list(nsim = 4L, n_cores = 2L, seed = 20260803L),
  label = "systemd two-core smoke test"
)
queue <- LibeRties::ls_local_queue(
  root, max_workers = 1L,
  limits = list(max_runtime_seconds = 120, max_memory_mb = 2048),
  executor = executor
)
id <- queue$submit(job)
status <- queue$wait(id, timeout = 120, poll_interval = 0.1)
if (!identical(status$status, "completed")) {
  stop("Systemd worker failed: ", status$error, call. = FALSE)
}
result <- queue$result(id)
if (!is.data.frame(result) || !nrow(result)) {
  stop("Systemd worker returned an invalid simulation result.", call. = FALSE)
}
if (!identical(as.integer(status$requested_cores), 2L) ||
    !identical(status$isolation, "systemd-transient-service") ||
    !nzchar(status$systemd_unit)) {
  stop("Systemd execution provenance was not retained.", call. = FALSE)
}

evidence <- list(
  schema = "liberties.systemd.smoke",
  version = 1L,
  passed = TRUE,
  checked = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
  preflight = unclass(preflight),
  job = status[c(
    "id", "status", "isolation", "executor", "systemd_unit",
    "systemd_profile", "requested_cores", "tasks_max",
    "peak_memory_mb", "cpu_seconds", "elapsed_seconds"
  )],
  packages = vapply(
    c("LibeRties", "LibeRation", "LibeRtAD"),
    function(package) if (requireNamespace(package, quietly = TRUE)) {
      as.character(utils::packageVersion(package))
    } else NA_character_,
    character(1)
  )
)
output <- Sys.getenv("LIBERTIES_SYSTEMD_EVIDENCE", unset = "")
if (nzchar(output)) {
  jsonlite::write_json(evidence, output, auto_unbox = TRUE, pretty = TRUE)
}
cat(jsonlite::toJSON(evidence, auto_unbox = TRUE, pretty = TRUE), "\n")
