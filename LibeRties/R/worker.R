.ls_run_job <- function(job_dir) {
  claim <- file.path(job_dir, ".claimed")
  on.exit(unlink(claim, recursive = TRUE, force = TRUE), add = TRUE)
  metadata <- .ls_read_meta(job_dir)
  if (identical(metadata$status, "cancelled")) return(invisible(NULL))
  payload <- .ls_payload_path(job_dir)
  if (!.ls_digest_matches(payload, metadata, "payload")) {
    .ls_update_meta(job_dir, list(
      status = "failed", finished = .ls_now(),
      error = "Payload checksum mismatch before worker execution."
    ), allowed_status = c("queued", "running"))
    return(invisible(NULL))
  }
  .ls_update_meta(job_dir, list(
    status = "running", started = .ls_now(), pid = Sys.getpid(),
    pid_started = tryCatch(ps::ps_create_time(ps::ps_handle()), error = function(e) NA_real_),
    error = ""
  ), allowed_status = "queued")
  if (!identical(.ls_read_meta(job_dir)$status, "running")) return(invisible(NULL))
  unlink(claim, recursive = TRUE, force = TRUE)
  result <- tryCatch({
    job <- .ls_read_rds(payload)
    if (!inherits(job, "liber_job") || !identical(job$schema, "liber.job") ||
        !identical(job$version, 1L)) {
      .ls_stop("Unsupported or invalid job payload contract.")
    }
    if (startsWith(job$type, "library_")) {
      if (!requireNamespace("LibeRary", quietly = TRUE)) {
        .ls_stop("LibeRary is not installed in the worker library paths.")
      }
      LibeRary::library_worker_task(job$type, job$data, job$arguments)
    } else if (identical(job$type, "optimal_design")) {
      if (!requireNamespace("LibeRality", quietly = TRUE)) {
        .ls_stop("LibeRality is not installed in the worker library paths.")
      }
      LibeRality::lity_worker_task(job$model, job$data, job$arguments)
    } else if (job$type %in% c("individualise", "regimen")) {
      if (!requireNamespace("LibeRator", quietly = TRUE)) {
        .ls_stop("LibeRator is not installed in the worker library paths.")
      }
      LibeRator::lator_worker_task(job$type, job$model, job$data, job$arguments)
    } else {
      if (!requireNamespace("LibeRation", quietly = TRUE)) {
        .ls_stop("LibeRation is not installed in the worker library paths.")
      }
      engine <- as.character(job$engine %||% "liber")
      if (!identical(engine, "liber")) {
        if (!job$type %in% c("simulate", "estimate", "estimate_sequence")) {
          .ls_stop("External engine is invalid for job type: ", job$type)
        }
        do.call(
          LibeRation::nm_external_run,
          c(
            list(
              model = job$model, data = job$data, engine = engine,
              operation = if (identical(job$type, "simulate")) "simulate" else "estimate"
            ),
            job$arguments
          )
        )
      } else if (identical(job$type, "simulate")) {
        do.call(LibeRation::nm_simulate, c(list(model = job$model, data = job$data), job$arguments))
      } else if (identical(job$type, "estimate")) {
        do.call(LibeRation::nm_est, c(list(model = job$model, data = job$data), job$arguments))
      } else if (identical(job$type, "estimate_sequence")) {
        do.call(LibeRation::nm_est_sequence, c(list(model = job$model, data = job$data), job$arguments))
      } else {
        .ls_stop("Unsupported job type: ", job$type)
      }
    }
  }, error = identity)
  latest <- .ls_read_meta(job_dir)
  if (identical(latest$status, "cancelled")) return(invisible(NULL))
  if (inherits(result, "error")) {
    writeLines(conditionMessage(result), file.path(job_dir, "error.txt"), useBytes = TRUE)
    .ls_update_meta(job_dir, list(
      status = "failed", finished = .ls_now(), error = conditionMessage(result)
    ), allowed_status = "running")
    return(invisible(NULL))
  }
  result_bytes <- length(serialize(result, NULL, version = 3))
  limits <- .ls_limits(latest$limits %||% list())
  if (result_bytes > limits$max_result_mb * 1024^2) {
    .ls_update_meta(job_dir, list(
      status = "failed", finished = .ls_now(),
      error = "Worker result exceeds the configured max_result_mb limit.",
      termination_reason = "result-size limit exceeded"
    ), allowed_status = "running")
    return(invisible(NULL))
  }
  result_path <- .ls_result_path(job_dir)
  .ls_atomic_save_rds(result, result_path)
  published <- .ls_update_meta(job_dir, list(
    status = "completed", finished = .ls_now(),
    result_md5 = .ls_md5(result_path), result_sha256 = .ls_sha256(result_path),
    result_bytes = file.info(result_path)$size,
    termination_reason = "completed normally"
  ), allowed_status = "running")
  if (!identical(published$status, "completed")) unlink(result_path, force = TRUE)
  invisible(NULL)
}
