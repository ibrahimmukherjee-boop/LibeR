args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(left, right) if (is.null(left)) right else left
if (length(args) != 3L) {
  stop(
    "Usage: nlmixr2-worker.R <config.rds> <metrics.rds> <summary.rds>",
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
if (length(config$library_paths)) {
  .libPaths(unique(c(config$library_paths, .libPaths())))
}
suppressPackageStartupMessages({
  library(LibeRation)
})
cat(
  "nlmixr2 worker toolchain:",
  paste(names(Sys.which(c("gcc", "as", "ld", "make", "sed"))),
        unname(Sys.which(c("gcc", "as", "ld", "make", "sed"))),
        sep = "=", collapse = "; "), "\n"
)
cat(
  "PATH variants identical:",
  identical(Sys.getenv("PATH"), Sys.getenv("Path")),
  "portable-in-PATH:", grepl("Portable_PKPD", Sys.getenv("PATH"), ignore.case = TRUE),
  "portable-in-Path:", grepl("Portable_PKPD", Sys.getenv("Path"), ignore.case = TRUE),
  "\n"
)
if (length(config$expected_versions)) {
  actual_versions <- vapply(names(config$expected_versions), function(package) {
    as.character(utils::packageVersion(package))
  }, character(1))
  expected_versions <- unlist(config$expected_versions, use.names = TRUE)
  mismatch <- actual_versions != expected_versions[names(actual_versions)]
  if (any(mismatch)) {
    stop(
      "Benchmark worker package version mismatch: ",
      paste0(
        names(actual_versions)[mismatch], " expected ",
        expected_versions[names(actual_versions)[mismatch]], ", found ",
        actual_versions[mismatch], collapse = "; "
      ), call. = FALSE
    )
  }
}

startup_seconds <- elapsed() - process_started

core_started <- elapsed()
result <- tryCatch({
  operation <- if (identical(config$workload, "estimation")) {
    "estimate"
  } else if (identical(config$workload, "simulation")) {
    "simulate"
  } else {
    stop("Unknown benchmark workload: ", config$workload, call. = FALSE)
  }
  # Trigger namespace loading only after LibeRation's toolchain guard has
  # removed incompatible compiler paths, then retain temporary model DLLs for
  # the lifetime of this short-lived worker.
  restore_toolchain <- getFromNamespace(
    ".nm_nlmixr_toolchain_guard", "LibeRation"
  )()
  on.exit(restore_toolchain(), add = TRUE)
  if (!requireNamespace("rxode2", quietly = TRUE)) {
    stop("rxode2 is not installed.", call. = FALSE)
  }
  invisible(rxode2::rxAllowUnload(FALSE))
  rxode2::setRxThreads(1L)
  value <- getFromNamespace(".nm_nlmixr_run", "LibeRation")(
    config$model, config$data, operation, config$arguments
  )
  if (identical(operation, "estimate")) {
    list(
      status = "ok", workload = config$workload, method = value$method,
      objective = as.numeric(value$objective),
      convergence = as.integer(value$convergence),
      iterations = as.integer(value$iterations),
      theta = as.numeric(value$theta), omega = as.numeric(value$omega),
      sigma = as.numeric(value$sigma),
      fit_seconds = as.numeric(value$timing$total_seconds),
      covariance_seconds = NA_real_,
      engine_total_seconds = as.numeric(value$timing$total_seconds),
      covariance_status = if (is.null(value$covariance)) {
        "not requested or unavailable"
      } else as.character(value$covariance$status %||% "completed")
    )
  } else {
    observations <- value$EVID == 0L & value$MDV == 0L
    values <- as.numeric(value$DV[observations])
    list(
      status = "ok", workload = config$workload, method = "SIMULATION",
      output_rows = nrow(value), observation_rows = sum(observations),
      dv_mean = mean(values, na.rm = TRUE),
      dv_sd = stats::sd(values, na.rm = TRUE),
      checksum = sum(values * seq_along(values), na.rm = TRUE)
    )
  }
}, error = function(error) {
  compile_log <- tryCatch(
    capture.output(rxode2::rxLastCompile()), error = function(...) character()
  )
  compile_log <- compile_log[nzchar(trimws(compile_log))]
  if (length(compile_log)) {
    message("rxode2 compile diagnostics:\n", paste(compile_log, collapse = "\n"))
  }
  error
})
core_seconds <- elapsed() - core_started

wrapup_started <- elapsed()
if (inherits(result, "error")) {
  summary <- list(
    status = "error", workload = config$workload,
    method = config$method, error = conditionMessage(result)
  )
} else {
  summary <- result
}
saveRDS(summary, summary_path, version = 3L)
wrapup_seconds <- elapsed() - wrapup_started

metrics <- list(
  status = summary$status, error = summary$error %||% "",
  startup_seconds = as.numeric(startup_seconds),
  core_seconds = as.numeric(core_seconds),
  wrapup_seconds = as.numeric(wrapup_seconds),
  worker_total_seconds = as.numeric(elapsed() - process_started),
  fit_seconds = as.numeric(summary$fit_seconds %||% NA_real_),
  covariance_seconds = as.numeric(summary$covariance_seconds %||% NA_real_),
  engine_total_seconds = as.numeric(
    summary$engine_total_seconds %||% core_seconds
  ),
  peak_r_heap_mb = as.numeric(sum(gc()[, 6L], na.rm = TRUE))
)
saveRDS(metrics, metrics_path, version = 3L)

if (!identical(summary$status, "ok")) {
  stop(summary$error, call. = FALSE)
}
