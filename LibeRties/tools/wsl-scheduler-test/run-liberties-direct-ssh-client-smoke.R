#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
key_arg <- if (length(args) >= 1L) args[[1L]] else
  Sys.getenv("LIBER_SSH_TEST_KEY", unset = "")
if (!nzchar(key_arg)) stop("Usage: run-liberties-direct-ssh-client-smoke.R KEY")
key <- normalizePath(key_arg, winslash = "/", mustWork = TRUE)
gateway_host <- if (length(args) >= 2L) args[[2L]] else
  Sys.getenv("LIBER_SSH_TEST_HOST", unset = "127.0.0.1")

suppressPackageStartupMessages({
  library(LibeRation)
  library(LibeRties)
})
stopifnot(utils::packageVersion("LibeRation") >= "0.10.5")
stopifnot(utils::packageVersion("LibeRties") >= "0.8.3")

model <- nm_model(
  INPUT = c("ID", "TIME", "EVID", "AMT"), ADVAN = 1,
  DOSECMP = 1, OBSCMP = 1,
  PRED = "CL=THETA(1)\nV=THETA(2)\nS1=V", ERROR = "Y=F",
  THETAS = data.frame(THETA = 1:2, Value = c(2, 20))
)
job <- ls_job(
  "simulate", model,
  data.frame(ID = 1, TIME = c(0, 1), EVID = c(1, 0), AMT = c(100, 0)),
  arguments = list(n_cores = 2L), label = "Direct SSH scheduler ADVAN1 smoke"
)

exercise <- function(backend) {
  config <- list(
    backend = backend, queue_name = paste0("direct-smoke-", backend),
    root = paste0("~/LibeR-direct-smoke/", backend),
    remote_rscript = "Rscript", max_workers = 2L, max_cores_per_job = 4L,
    partition = if (identical(backend, "slurm")) "debug" else "",
    queue = if (identical(backend, "grid_engine")) "all.q" else "",
    storage_key = paste(rep(if (identical(backend, "slurm")) "ab" else "cd", 32L), collapse = ""),
    ssh = list(
      host = "127.0.0.1", user = "liber-ssh-test", port = 2223L,
      proxy_host = gateway_host, proxy_user = "liber-ssh-test",
      proxy_port = 2222L, identity_file = key,
      accept_new_host_key = TRUE, auto_start = FALSE
    )
  )
  remote <- LibeRation:::.liber_direct_scheduler(config, timeout = 30)
  auth <- remote$authenticate()
  stopifnot(identical(auth$backend, backend))
  capabilities <- remote$capabilities()
  stopifnot(!length(capabilities$scheduler_preflight$issues))
  id <- remote$submit(job, idempotency_key = paste0("direct-smoke-", backend))
  cat(backend, " submitted id=", id, " via ProxyJump\n", sep = "")
  Sys.sleep(3)
  remote <- LibeRation:::.liber_direct_scheduler(config, timeout = 30)
  deadline <- Sys.time() + 120
  repeat {
    status <- remote$status(id)
    if (status$status %in% c("completed", "failed", "cancelled")) break
    if (Sys.time() >= deadline) stop("Timed out waiting for ", backend, " job ", id)
    Sys.sleep(1)
  }
  stopifnot(identical(status$status, "completed"))
  result <- remote$result(id)
  stopifnot(isTRUE(all.equal(result$IPRED, c(5, 5 * exp(-0.1)), tolerance = 1e-10)))
  jobs <- remote$list()
  stopifnot(sum(jobs$id == id) == 1L)
  cat(backend, " recovered status=", status$status,
      " scheduler_state=", status$scheduler_state,
      " result_rows=", nrow(result), " duplicate_jobs=0\n", sep = "")
}

exercise("grid_engine")
exercise("slurm")
cat("WINDOWS_DIRECT_SSH_SCHEDULER_PROXYJUMP_SMOKE_OK\n")
