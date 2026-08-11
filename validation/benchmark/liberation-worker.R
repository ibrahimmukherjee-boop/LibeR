args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(left, right) if (is.null(left)) right else left
if (length(args) != 3L) {
  stop("Usage: liberation-worker.R <config.rds> <metrics.rds> <summary.rds>",
       call. = FALSE)
}

config_path <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
metrics_path <- normalizePath(args[[2L]], winslash = "/", mustWork = FALSE)
summary_path <- normalizePath(args[[3L]], winslash = "/", mustWork = FALSE)

elapsed <- function() unname(proc.time()[["elapsed"]])
diagnostic_scalar <- function(value) {
  if (is.null(value) || !length(value)) return("")
  flattened <- unlist(value, recursive = TRUE, use.names = TRUE)
  if (!length(flattened)) return("")
  formatted <- vapply(flattened, function(item) {
    if (is.numeric(item)) format(item, digits = 12L, trim = TRUE) else
      as.character(item)
  }, character(1))
  labels <- names(flattened)
  if (!is.null(labels) && any(nzchar(labels))) {
    paste0(ifelse(nzchar(labels), paste0(labels, "="), ""), formatted,
           collapse = ";")
  } else paste(formatted, collapse = ";")
}
invisible(gc(reset = TRUE))
process_started <- elapsed()
config <- readRDS(config_path)
if (length(config$library_paths)) {
  .libPaths(unique(c(config$library_paths, .libPaths())))
}
suppressPackageStartupMessages(library(LibeRation))
if (length(config$expected_versions)) {
  actual_versions <- vapply(names(config$expected_versions), function(package) {
    as.character(utils::packageVersion(package))
  }, character(1))
  expected_versions <- unlist(config$expected_versions, use.names = TRUE)
  mismatch <- actual_versions != expected_versions[names(actual_versions)]
  if (any(mismatch)) {
    stop(
      "Benchmark worker package version mismatch: ",
      paste0(names(actual_versions)[mismatch], " expected ",
             expected_versions[names(actual_versions)[mismatch]], ", found ",
             actual_versions[mismatch], collapse = "; "), call. = FALSE
    )
  }
}
options(
  LibeRation.cpp_population_objective = isTRUE(
    config$cpp_population_objective %||% TRUE
  )
)
startup_seconds <- elapsed() - process_started

core_started <- elapsed()
result <- tryCatch({
  if (identical(config$workload, "estimation")) {
    fit <- do.call(
      LibeRation::nm_est,
      c(list(model = config$model, data = config$data), config$arguments)
    )
    list(
      status = "ok",
      workload = config$workload,
      method = fit$method,
      objective = as.numeric(fit$objective),
      convergence = as.integer(fit$convergence),
      iterations = as.integer(fit$iterations),
      theta = as.numeric(fit$theta),
      omega = as.numeric(fit$omega),
      sigma = as.numeric(fit$sigma),
      fit_seconds = as.numeric(fit$timing$model_fit_seconds),
      covariance_seconds = as.numeric(fit$timing$covariance_seconds),
      engine_total_seconds = as.numeric(fit$timing$total_seconds),
      covariance_status = if (is.null(fit$covariance)) "not requested" else
        as.character(fit$covariance$status %||% "completed"),
      optimizer_backend = fit$diagnostics$optimizer$backend %||% "unknown",
      objective_backend = fit$diagnostics$optimizer$objective_backend %||% "unknown",
      population_parameter_evaluations =
        fit$diagnostics$optimizer$population_objective$parameter_evaluations %||% NA_integer_,
      population_shared_state_hits =
        fit$diagnostics$optimizer$population_objective$shared_state_hits %||% NA_integer_,
      objective_evaluations = fit$diagnostics$optimizer$objective_evaluations %||%
        fit$objective_evaluations,
      gradient_evaluations = fit$diagnostics$optimizer$gradient_evaluations %||% NA_integer_,
      conditional_iterations = fit$diagnostics$conditional_mode_work$iterations %||%
        fit$diagnostics$conditional_modes$iterations %||% NA_integer_,
      conditional_evaluations = fit$diagnostics$conditional_mode_work$evaluations %||%
        fit$diagnostics$conditional_modes$evaluations %||% NA_integer_,
      tape_records = fit$diagnostics$tapes$records %||% NA_integer_,
      tape_retapes = fit$diagnostics$tapes$retapes %||% NA_integer_,
      shared_prediction_tapes = fit$diagnostics$tapes$shared_prediction_tapes %||% NA_integer_,
      its_mstep_schedule = diagnostic_scalar(
        fit$diagnostics$mstep_schedule %||% ""
      ),
      its_acceleration = fit$diagnostics$acceleration$method %||% "",
      imp_sampling = fit$diagnostics$sampling %||% "",
      imp_proposal = fit$diagnostics$proposal %||% "",
      imp_sample_schedule = diagnostic_scalar(
        fit$diagnostics$sample_schedule %||% ""
      ),
      imp_mstep_schedule = if (identical(fit$method, "IMP")) {
        diagnostic_scalar(fit$diagnostics$mstep_schedule %||% "")
      } else "",
      saem_kernel = fit$diagnostics$eta_sampler$resolved_kernel %||% "",
      stochastic_stopped_early = isTRUE(
        fit$diagnostics$stationarity$stopped_early %||% FALSE
      ),
      stochastic_retained_support = as.integer(
        fit$diagnostics$stochastic_approximation$retained_latent_support %||%
          NA_integer_
      ),
      stochastic_phase_timing = {
        phase <- unlist(
          fit$diagnostics$phase_timing$seconds %||% list(),
          use.names = TRUE
        )
        if (length(phase)) paste(
          sprintf("%s=%.9g", names(phase), as.numeric(phase)),
          collapse = ";"
        ) else ""
      },
      bayes_outer_kernel = fit$diagnostics$outer_sampler$resolved_kernel %||% "",
      stochastic_outer_acceptance = fit$diagnostics$outer_acceptance %||% NA_real_,
      stochastic_eta_acceptance = fit$diagnostics$eta_acceptance %||%
        fit$diagnostics$acceptance %||% NA_real_,
      posterior_min_ess = if (length(fit$posterior$population$ess)) {
        min(fit$posterior$population$ess, na.rm = TRUE)
      } else NA_real_,
      posterior_median_ess = if (length(fit$posterior$population$ess)) {
        stats::median(fit$posterior$population$ess, na.rm = TRUE)
      } else NA_real_
    )
  } else if (identical(config$workload, "simulation")) {
    simulated <- do.call(
      LibeRation::nm_simulate,
      c(list(model = config$model, data = config$data), config$arguments)
    )
    observations <- simulated$EVID == 0L & simulated$MDV == 0L
    values <- as.numeric(simulated$DV[observations])
    list(
      status = "ok",
      workload = config$workload,
      method = "SIMULATION",
      output_rows = nrow(simulated),
      observation_rows = sum(observations),
      dv_mean = mean(values, na.rm = TRUE),
      dv_sd = stats::sd(values, na.rm = TRUE),
      checksum = sum(values * seq_along(values), na.rm = TRUE)
    )
  } else {
    stop("Unknown benchmark workload: ", config$workload, call. = FALSE)
  }
}, error = identity)
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
  status = summary$status,
  error = summary$error %||% "",
  startup_seconds = as.numeric(startup_seconds),
  core_seconds = as.numeric(core_seconds),
  wrapup_seconds = as.numeric(wrapup_seconds),
  worker_total_seconds = as.numeric(elapsed() - process_started),
  fit_seconds = as.numeric(summary$fit_seconds %||% NA_real_),
  covariance_seconds = as.numeric(summary$covariance_seconds %||% NA_real_),
  engine_total_seconds = as.numeric(summary$engine_total_seconds %||% core_seconds),
  peak_r_heap_mb = as.numeric(sum(gc()[, 6L], na.rm = TRUE))
)
saveRDS(metrics, metrics_path, version = 3L)

if (!identical(summary$status, "ok")) {
  stop(summary$error, call. = FALSE)
}
