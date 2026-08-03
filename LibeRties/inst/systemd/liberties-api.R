#!/usr/bin/env Rscript

value <- function(name, default = "") {
  result <- Sys.getenv(name, unset = default)
  if (!length(result) || is.na(result)) default else result[[1L]]
}
flag <- function(name, default = FALSE) {
  text <- tolower(trimws(value(name, if (default) "true" else "false")))
  if (!text %in% c("true", "false", "1", "0", "yes", "no")) {
    stop(name, " must be true or false.", call. = FALSE)
  }
  text %in% c("true", "1", "yes")
}
positive_integer <- function(name, default) {
  result <- suppressWarnings(as.integer(value(name, as.character(default))))
  if (length(result) != 1L || is.na(result) || result < 1L) {
    stop(name, " must be a positive integer.", call. = FALSE)
  }
  result
}

suppressPackageStartupMessages(library(LibeRties))
trusted <- trimws(strsplit(
  value("LIBERTIES_TRUSTED_PROXIES", ""), ",", fixed = TRUE
)[[1L]])
trusted <- trusted[nzchar(trusted)]
policy <- ls_security_policy(
  production = TRUE,
  trusted_proxies = trusted,
  requests_per_minute = positive_integer("LIBERTIES_REQUESTS_PER_MINUTE", 120L)
)
ls_run_api(
  root = value(
    "LIBERTIES_ROOT",
    file.path(tools::R_user_dir("LibeRties", "data"), "queue")
  ),
  host = value("LIBERTIES_HOST", "127.0.0.1"),
  port = positive_integer("LIBERTIES_PORT", 8000L),
  max_workers_per_user = positive_integer(
    "LIBERTIES_MAX_WORKERS_PER_USER", 2L
  ),
  quiet = flag("LIBERTIES_QUIET", TRUE),
  production = TRUE,
  behind_tls_proxy = flag("LIBERTIES_BEHIND_TLS_PROXY", TRUE),
  policy = policy
)
