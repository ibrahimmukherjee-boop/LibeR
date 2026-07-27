args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(left, right) if (is.null(left)) right else left

if (length(args) != 3L) {
  stop(
    "Usage: liberation-worker.R <config.rds> <metrics.rds> <summary.rds>",
    call. = FALSE
  )
}

config_path <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
metrics_path <- normalizePath(args[[2L]], winslash = "/", mustWork = FALSE)
summary_path <- normalizePath(args[[3L]], winslash = "/", mustWork = FALSE)
elapsed <- function() unname(proc.time()[["elapsed"]])

invisible(gc(reset = TRUE))
process_started <- elapsed()
config <- readRDS(config_path)
.libPaths(unique(c(config$library_paths, .libPaths())))
suppressPackageStartupMessages(library(LibeRation))

actual <- vapply(names(config$expected_versions), function(package) {
  as.character(utils::packageVersion(package))
}, character(1))
expected <- unlist(config$expected_versions, use.names = TRUE)
if (any(actual != expected[names(actual)])) {
  stop("MU validation worker package versions do not match the request.",
       call. = FALSE)
}
startup_seconds <- elapsed() - process_started

fit_started <- elapsed()
fit <- tryCatch(
  do.call(
    LibeRation::nm_est,
    c(
      list(model = config$model, data = config$data, method = config$method),
      config$arguments
    )
  ),
  error = identity
)
core_seconds <- elapsed() - fit_started

if (inherits(fit, "error")) {
  summary <- list(status = "error", error = conditionMessage(fit))
} else {
  mu <- fit$diagnostics$mu_specialization %||% list()
  summary <- list(
    status = "ok",
    error = "",
    method = fit$method,
    objective = as.numeric(fit$objective),
    convergence = as.integer(fit$convergence),
    termination = as.character(fit$message %||% ""),
    iterations = as.integer(fit$iterations),
    theta = as.numeric(fit$theta),
    omega = as.numeric(fit$omega),
    sigma = as.numeric(fit$sigma),
    eta = unname(as.matrix(fit$eta)),
    fit_seconds = as.numeric(fit$timing$model_fit_seconds),
    engine_total_seconds = as.numeric(fit$timing$total_seconds),
    objective_evaluations = as.integer(fit$objective_evaluations %||% NA_integer_),
    gradient_evaluations = as.integer(
      fit$diagnostics$optimizer$gradient_evaluations %||% NA_integer_
    ),
    mu_enabled = isTRUE(mu$enabled),
    mu_active = isTRUE(mu$active),
    mu_reason = as.character(mu$reason %||% mu$runtime_reason %||% ""),
    mu_recentered_mode_starts = as.integer(
      mu$recentered_mode_starts %||% 0L
    ),
    mu_closed_form_updates = as.integer(mu$closed_form_updates %||% 0L),
    mu_closed_form_only_iterations = as.integer(
      mu$closed_form_only_iterations %||% 0L
    ),
    mu_gls_system_calls = as.integer(mu$gls_system_calls %||% 0L),
    mu_gls_cache_hits = as.integer(mu$gls_cache_hits %||% 0L),
    mu_gls_cache_misses = as.integer(mu$gls_cache_misses %||% 0L),
    mu_gls_vectorized = isTRUE(mu$gls_vectorized),
    mu_runtime_fallbacks = as.integer(mu$runtime_fallbacks %||% 0L)
  )
}

wrapup_started <- elapsed()
saveRDS(summary, summary_path, version = 3L)
wrapup_seconds <- elapsed() - wrapup_started
metrics <- list(
  status = summary$status,
  error = summary$error,
  startup_seconds = startup_seconds,
  core_seconds = if (identical(summary$status, "ok")) {
    summary$engine_total_seconds %||% core_seconds
  } else {
    core_seconds
  },
  measured_fit_seconds = summary$fit_seconds %||% NA_real_,
  wrapup_seconds = wrapup_seconds,
  worker_total_seconds = elapsed() - process_started
)
saveRDS(metrics, metrics_path, version = 3L)

if (!identical(summary$status, "ok")) {
  stop(summary$error, call. = FALSE)
}
