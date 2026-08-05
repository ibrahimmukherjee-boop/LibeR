#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) {
  stop("Usage: run-liberties-ssh-client-smoke.R LIBRARY KEY TOKEN_DIRECTORY")
}
.libPaths(c(normalizePath(args[[1L]], winslash = "/"), .libPaths()))
key <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
token_directory <- normalizePath(args[[3L]], winslash = "/", mustWork = TRUE)

suppressPackageStartupMessages({
  library(LibeRation)
  library(LibeRties)
})
stopifnot(utils::packageVersion("LibeRation") >= "0.10.2")
stopifnot(utils::packageVersion("LibeRties") >= "0.8.1")

model <- nm_model(
  INPUT = c("ID", "TIME", "EVID", "AMT"), ADVAN = 1,
  DOSECMP = 1, OBSCMP = 1,
  PRED = "CL=THETA(1)\nV=THETA(2)\nS1=V", ERROR = "Y=F",
  THETAS = data.frame(THETA = 1:2, Value = c(2, 20))
)
job <- ls_job(
  "simulate", model,
  data.frame(ID = 1, TIME = c(0, 1), EVID = c(1, 0), AMT = c(100, 0)),
  arguments = list(n_cores = 2L), label = "SSH ProxyJump ADVAN1 smoke test"
)

exercise <- function(name, remote_port) {
  token <- readLines(file.path(token_directory, paste0(name, ".token")), n = 1L)
  config <- list(
    host = "127.0.0.1", user = "liber-ssh-test", port = 2223L,
    remote_host = "127.0.0.1", remote_port = remote_port, local_port = 0L,
    proxy_host = "127.0.0.1", proxy_user = "liber-ssh-test",
    proxy_port = 2222L, identity_file = key,
    accept_new_host_key = TRUE, auto_start = TRUE
  )
  tunnel <- LibeRation:::.liber_ssh_tunnel_start(config, wait_seconds = 15)
  remote <- ls_remote(tunnel$url, token, timeout = 20)
  auth <- remote$authenticate()
  stopifnot(identical(auth$username, "ssh-smoke"))
  id <- remote$submit(job)
  cat(name, " submitted id=", id, " through=", tunnel$url, "\n", sep = "")

  # Deliberately drop the client tunnel while the scheduler allocation runs.
  stopifnot(isTRUE(LibeRation:::.liber_ssh_tunnel_stop(tunnel)))
  Sys.sleep(6)

  tunnel <- LibeRation:::.liber_ssh_tunnel_start(config, wait_seconds = 15)
  on.exit(LibeRation:::.liber_ssh_tunnel_stop(tunnel), add = TRUE)
  remote <- ls_remote(tunnel$url, token, timeout = 20)
  deadline <- Sys.time() + 90
  repeat {
    status <- remote$status(id)
    if (status$status %in% c("completed", "failed", "cancelled")) break
    if (Sys.time() >= deadline) stop("Timed out waiting for ", name, " job ", id)
    Sys.sleep(0.25)
  }
  stopifnot(identical(status$status, "completed"))
  result <- remote$result(id)
  stopifnot(isTRUE(all.equal(
    result$IPRED, c(5, 5 * exp(-0.1)), tolerance = 1e-10
  )))
  jobs <- remote$list()
  stopifnot(sum(jobs$id == id) == 1L)
  cat(
    name, " recovered status=", status$status,
    " scheduler_state=", status$scheduler_state,
    " result_rows=", nrow(result), " duplicate_jobs=0\n", sep = ""
  )
  invisible(TRUE)
}

exercise("grid", 8000L)
exercise("slurm", 8001L)
cat("WINDOWS_LIBERATION_PROXYJUMP_SMOKE_OK\n")
