#!/usr/bin/env Rscript

arguments <- commandArgs(trailingOnly = TRUE)
script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script <- if (length(script_argument)) {
  sub("^--file=", "", script_argument[[1L]])
} else {
  "validation/liberties/deployment/start-test-server.R"
}
repository <- normalizePath(
  file.path(dirname(script), "..", "..", ".."),
  winslash = "/", mustWork = TRUE
)
source(file.path(repository, "tools", "validation-runtime.R"), local = TRUE)
value_after <- function(name, default = NULL) {
  liber_validation_option(name, default, args = arguments)
}
runtime <- liber_validation_library(
  repository, c("LibeRtAD", "LibeRation", "LibeRties"),
  library = value_after("library", Sys.getenv("LIBER_VALIDATION_LIBRARY", ""))
)
.libPaths(unique(c(runtime$path, .libPaths())))

root <- value_after("root", tempfile("liberties-deployment-server-"))
token_file <- value_after(
  "token-file", file.path(root, "validation-token.txt")
)
port <- as.integer(value_after("port", "8000"))
dir.create(root, recursive = TRUE, showWarnings = FALSE)
created <- LibeRties::ls_user_create(
  root, "validation", first_name = "Deployment", last_name = "Validator",
  limits = list(
    max_concurrent_jobs = 4L, max_queued_jobs = 20L,
    max_payload_mb = 16, max_result_mb = 32,
    max_runtime_seconds = 120, max_storage_mb = 256,
    max_cpu_seconds = 120, max_memory_mb = 1024
  ),
  expires = format(Sys.time() + 3600, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
)
dir.create(dirname(token_file), recursive = TRUE, showWarnings = FALSE)
writeLines(created$token, token_file, useBytes = TRUE)
Sys.chmod(token_file, mode = "0600")

LibeRties::ls_run_api(
  root = root, host = "127.0.0.1", port = port,
  max_workers_per_user = 4L, quiet = TRUE, production = FALSE,
  policy = LibeRties::ls_security_policy(
    production = FALSE, requests_per_minute = 100000L
  )
)
