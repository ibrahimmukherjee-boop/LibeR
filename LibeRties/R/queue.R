#' Persistent cross-platform LibeR job queue
#'
#' Each user receives a separate filesystem namespace. Trusted local jobs can
#' run in fresh `callr` R processes; external jobs can run as hardened,
#' cgroup-limited transient systemd services or through Slurm/Grid Engine.
#' Every backend reconstructs C++ pointers from serialized models.
#'
#' @export
LibeRQueue <- R6::R6Class(
  "LibeRQueue",
  public = list(
    #' @field root Normalized persistent queue storage directory.
    root = NULL,
    #' @field user Safe tenant namespace used by default for queue operations.
    user = NULL,
    #' @field max_workers Maximum simultaneous background workers.
    max_workers = NULL,
    #' @field limits Effective resource and storage limits.
    limits = NULL,
    #' @field isolation Description of the worker isolation strategy.
    isolation = NULL,
    #' @field executor Worker execution backend specification.
    executor = NULL,
    #' @field processes Internal environment of live `callr` worker handles.
    processes = NULL,

    #' @description
    #' Create or reopen a persistent local queue.
    #' @param root Persistent queue storage directory.
    #' @param user Default isolated tenant namespace.
    #' @param max_workers Maximum simultaneous background workers.
    #' @param limits Named overrides for runtime, CPU, memory, payload, result,
    #'   concurrency, queue, and storage limits.
    #' @param executor Optional executor created by [ls_systemd_executor()],
    #'   [ls_slurm_executor()], or [ls_grid_engine_executor()]. `NULL` retains
    #'   the trusted-local `callr` subprocess backend.
    #' @return A new `LibeRQueue` object.
    initialize = function(root = .ls_default_root(), user = "local",
                          max_workers = 1L, limits = list(), executor = NULL) {
      self$root <- .ls_ensure_dir(root)
      self$user <- .ls_safe_component(user, "user id")
      self$max_workers <- as.integer(max_workers)
      self$limits <- .ls_limits(limits)
      self$max_workers <- min(self$max_workers, self$limits$max_concurrent_jobs)
      self$executor <- .ls_executor(executor)
      self$isolation <- switch(
        self$executor$type,
        systemd = "systemd-transient-service",
        slurm = "slurm-scheduled-worker",
        grid_engine = "grid-engine-scheduled-worker",
        "restricted-subprocess"
      )
      if (length(self$max_workers) != 1L || is.na(self$max_workers) || self$max_workers < 1L) {
        .ls_stop("`max_workers` must be a positive integer.")
      }
      self$processes <- new.env(parent = emptyenv())
      .ls_ensure_dir(file.path(self$root, "users", self$user, "jobs"))
    },

    #' @description
    #' Persist a serializable job and optionally start available workers.
    #' @param job A job created by [ls_job()].
    #' @param user Tenant namespace receiving the job.
    #' @param start Start available queued work immediately.
    #' @param idempotency_key Optional user-scoped retry key. Reusing a key
    #'   with the same payload returns the original job id; reuse with a
    #'   different payload is rejected.
    #' @return The durable job identifier, invisibly.
    submit = function(job, user = self$user, start = TRUE,
                      idempotency_key = NULL) {
      if (!inherits(job, "liber_job")) .ls_stop("`job` must be created by ls_job().")
      requested_cores <- .ls_job_requested_cores(job)
      if (!is.null(self$executor$max_cores_per_job) &&
          requested_cores > self$executor$max_cores_per_job) {
        .ls_stop(
          "Job requests ", requested_cores, " cores but this queue allows ",
          self$executor$max_cores_per_job, " for executor `",
          self$executor$type, "`."
        )
      }
      user <- .ls_safe_component(user, "user id")
      payload_bytes <- length(serialize(job, NULL, version = 3))
      if (payload_bytes > self$limits$max_payload_mb * 1024^2) {
        .ls_stop("Payload exceeds this queue's max_payload_mb limit.")
      }
      key <- .ls_idempotency_key(idempotency_key)
      digest <- .ls_object_sha256(job)
      result <- .liber_shared_with_lock(
        .ls_submission_lock(self$root, user),
        function() private$submit_locked(
          job, user, payload_bytes, key, digest
        ),
        timeout = 10, stale_after = 60,
        owner = paste(Sys.getpid(), .ls_now()),
        error = function(message) .ls_stop(message)
      )
      if (isTRUE(start)) self$poll(start = TRUE)
      id <- as.character(result$id)
      if (isTRUE(result$replayed)) attr(id, "idempotent_replay") <- TRUE
      invisible(id)
    },

    #' @description
    #' Refresh worker state, enforce limits, recover jobs, and start queued work.
    #' @param start Whether to start queued work when capacity is available.
    #' @return The current job table, invisibly.
    poll = function(start = TRUE) {
      private$enforce_limits()
      private$reap()
      private$recover_claims()
      private$recover_untracked()
      private$seal_terminal_logs()
      if (isTRUE(start)) private$start_available()
      invisible(self$list())
    },

    #' @description
    #' Read durable metadata for one job.
    #' @param id Durable job identifier.
    #' @param user Tenant namespace owning the job.
    #' @return A named metadata list.
    status = function(id, user = self$user) {
      job_dir <- .ls_job_dir(self$root, user, id)
      if (!dir.exists(job_dir)) .ls_stop("Unknown job id.")
      tryCatch(
        .ls_read_meta(job_dir),
        error = function(error) {
          primary <- .ls_meta_path(job_dir)
          if (!file.exists(primary) && !file.exists(paste0(primary, ".previous"))) {
            .ls_stop("Unknown job id.")
          }
          stop(error)
        }
      )
    },

    #' @description
    #' List durable jobs in a tenant namespace.
    #' @param user Tenant namespace to list.
    #' @return A data frame ordered from newest to oldest submission.
    list = function(user = self$user) {
      user <- .ls_safe_component(user, "user id")
      root <- file.path(self$root, "users", user, "jobs")
      if (!dir.exists(root)) return(.ls_empty_jobs())
      directories <- list.dirs(root, full.names = TRUE, recursive = FALSE)
      if (!length(directories)) return(.ls_empty_jobs())
      records <- lapply(directories, function(path) {
        tryCatch(.ls_read_meta(path), error = function(e) NULL)
      })
      records <- Filter(Negate(is.null), records)
      if (!length(records)) return(.ls_empty_jobs())
      result <- do.call(rbind, lapply(records, function(x) data.frame(
        id = x$id, user = x$user, type = x$type, label = x$label,
        status = x$status, submitted = x$submitted, started = x$started,
        finished = x$finished, stringsAsFactors = FALSE
      )))
      result[order(result$submitted, decreasing = TRUE), , drop = FALSE]
    },

    #' @description
    #' Read and verify a completed job result.
    #' @param id Durable job identifier.
    #' @param user Tenant namespace owning the job.
    #' @return The deserialized job result.
    result = function(id, user = self$user) {
      job_dir <- .ls_job_dir(self$root, user, id)
      metadata <- .ls_read_meta(job_dir)
      if (!identical(metadata$status, "completed")) {
        .ls_stop("Job ", id, " is ", metadata$status, "; no completed result is available.")
      }
      path <- .ls_result_path(job_dir)
      if (!.ls_digest_matches(path, metadata, "result")) {
        .ls_stop("Result checksum mismatch for job ", id, ".")
      }
      .ls_read_rds(path)
    },

    #' @description
    #' Read a worker log stream.
    #' @param id Durable job identifier.
    #' @param user Tenant namespace owning the job.
    #' @param stream Standard-output or standard-error stream.
    #' @return A character vector containing log lines.
    logs = function(id, user = self$user, stream = c("stdout", "stderr")) {
      stream <- match.arg(stream)
      job_dir <- .ls_job_dir(self$root, user, id)
      metadata <- .ls_read_meta(job_dir)
      if (.ls_terminal(metadata$status)) {
        pid <- suppressWarnings(as.integer(metadata$pid %||% NA_integer_))
        alive <- .ls_pid_exists(pid)
        if (!alive) .ls_seal_job_logs(job_dir)
      }
      .ls_read_job_log(job_dir, stream)
    },

    #' @description
    #' Cancel a queued or running job.
    #' @param id Durable job identifier.
    #' @param user Tenant namespace owning the job.
    #' @return `TRUE` when cancellation changed the job state and `FALSE` when
    #'   the job was already terminal, invisibly.
    cancel = function(id, user = self$user) {
      job_dir <- .ls_job_dir(self$root, user, id)
      metadata <- .ls_read_meta(job_dir)
      if (.ls_terminal(metadata$status)) return(invisible(FALSE))
      key <- paste(user, id, sep = "::")
      if (exists(key, envir = self$processes, inherits = FALSE)) {
        process <- get(key, envir = self$processes, inherits = FALSE)
        if (isTRUE(process$is_alive())) {
          private$cancel_process(process)
        }
      } else {
        process <- .ls_executor_process(self$executor, metadata)
        if (!is.null(process)) {
          if (isTRUE(process$is_alive())) private$cancel_process(process)
        } else {
          pid <- suppressWarnings(as.integer(metadata$pid %||% NA_integer_))
          if (.ls_pid_matches(pid, metadata$pid_started)) {
            .ls_kill_process_tree(pid)
          }
        }
      }
      updated <- .ls_update_meta(job_dir, list(
        status = "cancelled", finished = .ls_now(), error = "Cancelled by user."
      ), allowed_status = c("queued", "running"))
      unlink(file.path(job_dir, ".claimed"), recursive = TRUE, force = TRUE)
      invisible(identical(updated$status, "cancelled"))
    },

    #' @description
    #' Poll until a job reaches a terminal state.
    #' @param id Durable job identifier.
    #' @param user Tenant namespace owning the job.
    #' @param timeout Maximum elapsed seconds; `Inf` waits indefinitely.
    #' @param poll_interval Delay between polls in seconds.
    #' @return Final job metadata.
    wait = function(id, user = self$user, timeout = Inf, poll_interval = 0.1) {
      started <- proc.time()[["elapsed"]]
      repeat {
        self$poll(start = TRUE)
        metadata <- self$status(id, user)
        if (.ls_terminal(metadata$status)) return(metadata)
        if (is.finite(timeout) && proc.time()[["elapsed"]] - started >= timeout) {
          .ls_stop("Timed out waiting for job ", id, ".")
        }
        Sys.sleep(max(0.01, as.numeric(poll_interval)))
      }
    },

    #' @description
    #' Print queue location, capacity, limits, and job count.
    #' @param ... Unused.
    #' @return The queue, invisibly.
    print = function(...) {
      jobs <- self$list()
      cat("LibeR local queue\n")
      cat("  root:", self$root, "\n")
      cat("  user:", self$user, " workers:", self$max_workers,
          " jobs:", nrow(jobs), "\n")
      cat("  isolation:", self$isolation, " memory:", self$limits$max_memory_mb,
          "MB runtime:", self$limits$max_runtime_seconds, "s\n")
      invisible(self)
    }
  ),
  private = list(
    cancel_process = function(process) {
      if (self$executor$type %in% c("slurm", "grid_engine")) {
        accepted <- isTRUE(tryCatch(
          process$kill(), error = function(error) FALSE
        ))
        if (!accepted) {
          .ls_stop(
            "The ", self$executor$type,
            " scheduler did not accept the cancellation request; job state was not changed."
          )
        }
        return(invisible(TRUE))
      }
      private$terminate_process(process)
    },
    terminate_process = function(process) {
      if (is.function(process$kill_tree)) {
        try(process$kill_tree(), silent = TRUE)
      } else {
        pid <- tryCatch(process$get_pid(), error = function(error) NA_integer_)
        if (!is.na(pid) && pid > 0L) .ls_kill_process_tree(pid)
        try(process$kill(), silent = TRUE)
      }
      invisible(TRUE)
    },
    submit_locked = function(job, user, payload_bytes, key, digest) {
      record_path <- .ls_idempotency_path(self$root, user, key)
      record <- NULL
      replayed <- FALSE
      if (!is.null(record_path) && file.exists(record_path)) {
        record <- .ls_read_rds(record_path)
        replayed <- TRUE
        if (!is.list(record) ||
            !identical(record$schema %||% "", "liberties.idempotency") ||
            !identical(as.integer(record$version %||% 0L), 1L) ||
            !nzchar(as.character(record$id %||% ""))) {
          .ls_stop("The idempotency record is malformed; submission was not retried.")
        }
        if (!identical(record$payload_sha256 %||% "", digest)) {
          .ls_stop("The idempotency key was already used for a different payload.")
        }
        job_dir <- .ls_job_dir(self$root, user, record$id)
        if (file.exists(.ls_meta_path(job_dir))) {
          metadata <- .ls_read_meta(job_dir)
          if (!identical(metadata$id, record$id) ||
              !identical(metadata$user, user) ||
              !identical(metadata$payload_object_sha256 %||% "", digest)) {
            .ls_stop("The idempotent job metadata does not match its submission claim.")
          }
          return(list(id = record$id, replayed = TRUE))
        }
      }

      jobs <- self$list(user)
      if (sum(jobs$status == "queued") >= self$limits$max_queued_jobs) {
        .ls_stop("Queued-job limit reached for user ", user, ".")
      }
      if (.ls_storage_bytes(self$root, user) + payload_bytes >
          self$limits$max_storage_mb * 1024^2) {
        .ls_stop("Storage quota reached for user ", user, ".")
      }

      id <- if (is.null(record)) .ls_new_id() else as.character(record$id)
      key_hash <- if (is.null(record_path)) "" else
        tools::file_path_sans_ext(basename(record_path))
      if (!is.null(record_path) && is.null(record)) {
        record <- list(
          schema = "liberties.idempotency", version = 1L,
          id = id, user = user, payload_sha256 = digest,
          key_sha256 = key_hash, state = "claimed", created = .ls_now()
        )
        .ls_atomic_save_rds(record, record_path)
      }

      job_dir <- .ls_job_dir(self$root, user, id)
      if (!dir.exists(job_dir) &&
          !dir.create(job_dir, recursive = FALSE, showWarnings = FALSE)) {
        .ls_stop("Unable to create job sandbox: ", job_dir)
      }
      payload <- .ls_payload_path(job_dir)
      .ls_atomic_save_rds(job, payload)
      metadata <- list(
        schema = "liber.queue.metadata", version = 2L, id = id, user = user,
        type = job$type, label = job$label, status = "queued",
        submitted = .ls_now(), started = "", finished = "", updated = .ls_now(),
        pid = NA_integer_, pid_started = NA_real_, error = "", payload_md5 = .ls_md5(payload),
        payload_sha256 = .ls_sha256(payload), payload_object_sha256 = digest,
        idempotency_key_sha256 = key_hash, result_md5 = "",
        result_sha256 = "", result_bytes = 0,
        limits = self$limits, isolation = self$isolation,
        executor = self$executor$type,
        requested_cores = .ls_job_requested_cores(job),
        systemd_unit = "", systemd_profile = "", tasks_max = NA_integer_,
        scheduler_job_id = "", scheduler_backend = "", scheduler_queue = "",
        scheduler_profile = "", scheduler_submitted = "",
        scheduler_script_sha256 = "", scheduler_state = "",
        peak_memory_mb = 0, cpu_seconds = 0, elapsed_seconds = 0,
        termination_reason = ""
      )
      .ls_write_meta(job_dir, metadata)
      if (!is.null(record_path)) {
        record$state <- "committed"
        record$committed <- .ls_now()
        .ls_atomic_save_rds(record, record_path)
      }
      list(id = id, replayed = replayed)
    },
    recover_claims = function() {
      queued <- self$list()
      queued <- queued[queued$status == "queued", , drop = FALSE]
      if (!nrow(queued)) return(invisible(NULL))
      for (index in seq_len(nrow(queued))) {
        key <- paste(queued$user[[index]], queued$id[[index]], sep = "::")
        tracked <- exists(key, envir = self$processes, inherits = FALSE) &&
          isTRUE(get(key, envir = self$processes, inherits = FALSE)$is_alive())
        if (tracked) next
        job_dir <- .ls_job_dir(
          self$root, queued$user[[index]], queued$id[[index]]
        )
        claim <- file.path(job_dir, ".claimed")
        if (!dir.exists(claim)) next
        metadata <- .ls_read_meta(job_dir)
        if (.ls_scheduler_executor_mismatch(self$executor, metadata)) {
          .ls_update_meta(job_dir, list(
            error = .ls_scheduler_mismatch_message(self$executor, metadata),
            scheduler_state = "RECOVERY_EXECUTOR_MISMATCH"
          ), allowed_status = "queued")
          next
        }
        external <- .ls_executor_process(self$executor, metadata)
        if (!is.null(external)) {
          # Scheduler allocations may legitimately remain pending for a long
          # time. Reattach their durable handles so capacity accounting and
          # cancellation continue to work after an API restart.
          assign(key, external, envir = self$processes)
          next
        }
        if (.ls_pid_matches(metadata$pid, metadata$pid_started)) next
        age <- suppressWarnings(as.numeric(difftime(
          Sys.time(), file.info(claim)$mtime, units = "secs"
        )))
        # A newly spawned worker may not have published its PID yet.  Preserve
        # that small hand-off window; only an old, untracked claim is stale.
        if (is.finite(age) && age >= 5) {
          unlink(claim, recursive = TRUE, force = TRUE)
        }
      }
      invisible(NULL)
    },
    seal_terminal_logs = function() {
      jobs <- self$list()
      jobs <- jobs[.ls_terminal(jobs$status), , drop = FALSE]
      if (!nrow(jobs) || is.null(.ls_storage_key())) return(invisible(NULL))
      for (index in seq_len(nrow(jobs))) {
        job_dir <- .ls_job_dir(self$root, jobs$user[[index]], jobs$id[[index]])
        metadata <- .ls_read_meta(job_dir)
        pid <- suppressWarnings(as.integer(metadata$pid %||% NA_integer_))
        alive <- .ls_pid_exists(pid)
        if (!alive) .ls_seal_job_logs(job_dir)
      }
      invisible(NULL)
    },
    enforce_limits = function() {
      keys <- ls(self$processes, all.names = TRUE)
      for (key in keys) {
        process <- get(key, envir = self$processes, inherits = FALSE)
        if (!isTRUE(process$is_alive())) next
        parts <- strsplit(key, "::", fixed = TRUE)[[1L]]
        job_dir <- .ls_job_dir(self$root, parts[[1L]], parts[[2L]])
        metadata <- .ls_read_meta(job_dir)
        if (.ls_terminal(metadata$status)) next
        limits <- .ls_limits(metadata$limits %||% self$limits)
        started <- suppressWarnings(as.POSIXct(
          metadata$started, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC"
        ))
        elapsed <- if (is.na(started)) 0 else as.numeric(difftime(Sys.time(), started, units = "secs"))
        usage <- .ls_process_resource_usage(process)
        scheduler_status <- if (self$executor$type %in% c("slurm", "grid_engine")) {
          tryCatch(process$status(), error = function(error) NULL)
        } else NULL
        peak <- max(as.numeric(metadata$peak_memory_mb %||% 0), usage$memory_mb)
        reason <- ""
        if (elapsed > limits$max_runtime_seconds) {
          reason <- paste0("wall-time limit exceeded (", limits$max_runtime_seconds, " seconds)")
        } else if (usage$cpu_seconds > limits$max_cpu_seconds) {
          reason <- paste0("CPU-time limit exceeded (", limits$max_cpu_seconds, " seconds)")
        } else if (usage$memory_mb > limits$max_memory_mb) {
          reason <- paste0("memory limit exceeded (", limits$max_memory_mb, " MB)")
        }
        if (nzchar(reason)) {
          private$terminate_process(process)
          .ls_update_meta(job_dir, list(
            status = "failed", finished = .ls_now(),
            error = paste("Resource limit exceeded:", reason),
            termination_reason = reason, peak_memory_mb = peak,
            cpu_seconds = usage$cpu_seconds, elapsed_seconds = elapsed
          ), allowed_status = c("queued", "running"))
        } else {
          .ls_update_meta(job_dir, list(
            peak_memory_mb = peak, cpu_seconds = usage$cpu_seconds,
            elapsed_seconds = elapsed,
            scheduler_state = if (is.list(scheduler_status))
              scheduler_status$state %||% metadata$scheduler_state %||% "" else
              metadata$scheduler_state %||% ""
          ), allowed_status = c("queued", "running"))
        }
      }
      invisible(NULL)
    },

    recover_untracked = function() {
      jobs <- self$list()
      jobs <- jobs[jobs$status == "running", , drop = FALSE]
      if (!nrow(jobs)) return(invisible(NULL))
      for (i in seq_len(nrow(jobs))) {
        key <- paste(jobs$user[[i]], jobs$id[[i]], sep = "::")
        if (exists(key, envir = self$processes, inherits = FALSE)) next
        job_dir <- .ls_job_dir(self$root, jobs$user[[i]], jobs$id[[i]])
        metadata <- .ls_read_meta(job_dir)
        if (.ls_scheduler_executor_mismatch(self$executor, metadata)) {
          .ls_update_meta(job_dir, list(
            error = .ls_scheduler_mismatch_message(self$executor, metadata),
            scheduler_state = "RECOVERY_EXECUTOR_MISMATCH"
          ), allowed_status = "running")
          next
        }
        external <- .ls_executor_process(self$executor, metadata)
        if (!is.null(external)) {
          process <- external
          if (isTRUE(process$is_alive())) {
            assign(key, process, envir = self$processes)
            next
          }
        }
        pid <- suppressWarnings(as.integer(metadata$pid %||% NA_integer_))
        alive <- .ls_pid_matches(pid, metadata$pid_started)
        if (!alive) {
          .ls_update_meta(job_dir, list(
            status = "failed", finished = .ls_now(),
            error = "Worker process was not alive during durable-queue recovery."
          ), allowed_status = c("queued", "running"))
          next
        }
        limits <- .ls_limits(metadata$limits %||% self$limits)
        started <- suppressWarnings(as.POSIXct(
          metadata$started, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC"
        ))
        elapsed <- if (is.na(started)) 0 else {
          as.numeric(difftime(Sys.time(), started, units = "secs"))
        }
        usage <- if (!is.null(external)) {
          .ls_process_resource_usage(external)
        } else tryCatch(.ls_resource_usage(pid), error = function(e) {
          list(memory_mb = 0, cpu_seconds = 0)
        })
        peak <- max(as.numeric(metadata$peak_memory_mb %||% 0), usage$memory_mb)
        reason <- ""
        if (elapsed > limits$max_runtime_seconds) {
          reason <- paste0("wall-time limit exceeded (", limits$max_runtime_seconds, " seconds)")
        } else if (usage$cpu_seconds > limits$max_cpu_seconds) {
          reason <- paste0("CPU-time limit exceeded (", limits$max_cpu_seconds, " seconds)")
        } else if (usage$memory_mb > limits$max_memory_mb) {
          reason <- paste0("memory limit exceeded (", limits$max_memory_mb, " MB)")
        }
        if (nzchar(reason)) {
          if (!is.null(external)) {
            private$terminate_process(external)
          } else {
            .ls_kill_process_tree(pid)
          }
          .ls_update_meta(job_dir, list(
            status = "failed", finished = .ls_now(),
            error = paste("Resource limit exceeded after queue recovery:", reason),
            termination_reason = reason, peak_memory_mb = peak,
            cpu_seconds = usage$cpu_seconds, elapsed_seconds = elapsed
          ), allowed_status = "running")
        } else {
          .ls_update_meta(job_dir, list(
            peak_memory_mb = peak, cpu_seconds = usage$cpu_seconds,
            elapsed_seconds = elapsed
          ), allowed_status = "running")
        }
      }
      invisible(NULL)
    },

    reap = function() {
      keys <- ls(self$processes, all.names = TRUE)
      for (key in keys) {
        process <- get(key, envir = self$processes, inherits = FALSE)
        if (isTRUE(process$is_alive())) next
        parts <- strsplit(key, "::", fixed = TRUE)[[1L]]
        job_dir <- .ls_job_dir(self$root, parts[[1L]], parts[[2L]])
        metadata <- .ls_read_meta(job_dir)
        scheduler_status <- if (self$executor$type %in% c("slurm", "grid_engine")) {
          tryCatch(process$status(), error = function(error) NULL)
        } else NULL
        usage <- .ls_process_resource_usage(process)
        if (!.ls_terminal(metadata$status)) {
          code <- tryCatch(process$get_exit_status(), error = function(e) NA_integer_)
          detail <- if (is.list(scheduler_status)) {
            paste0("; scheduler state ", scheduler_status$state %||% "unknown")
          } else ""
          .ls_update_meta(job_dir, list(
            status = "failed", finished = .ls_now(),
            error = paste0(
              "Worker exited before publishing a result (exit ", code, detail, ")."
            ),
            scheduler_state = if (is.list(scheduler_status))
              scheduler_status$state %||% "" else "",
            peak_memory_mb = max(
              as.numeric(metadata$peak_memory_mb %||% 0), usage$memory_mb
            ),
            cpu_seconds = max(
              as.numeric(metadata$cpu_seconds %||% 0), usage$cpu_seconds
            ),
            elapsed_seconds = max(
              as.numeric(metadata$elapsed_seconds %||% 0),
              as.numeric(usage$elapsed_seconds %||% 0), na.rm = TRUE
            )
          ), allowed_status = c("queued", "running"))
        } else if (is.list(scheduler_status)) {
          # The worker may publish its result just before the scheduler moves
          # the allocation to its terminal state. Preserve that final native
          # state and accounting without rewriting the LibeRties outcome.
          .ls_update_meta(job_dir, list(
            scheduler_state = scheduler_status$state %||% metadata$scheduler_state %||% "",
            peak_memory_mb = max(
              as.numeric(metadata$peak_memory_mb %||% 0), usage$memory_mb
            ),
            cpu_seconds = max(
              as.numeric(metadata$cpu_seconds %||% 0), usage$cpu_seconds
            ),
            elapsed_seconds = max(
              as.numeric(metadata$elapsed_seconds %||% 0),
              as.numeric(usage$elapsed_seconds %||% 0), na.rm = TRUE
            )
          ), allowed_status = c("completed", "failed", "cancelled"))
        }
        unlink(file.path(job_dir, ".claimed"), recursive = TRUE, force = TRUE)
        rm(list = key, envir = self$processes)
      }
    },

    start_available = function() {
      running <- self$list()
      metadata_running <- sum(running$status == "running")
      tracked_running <- sum(vapply(
        as.list(self$processes), function(p) isTRUE(p$is_alive()), logical(1)
      ))
      n_running <- max(metadata_running, tracked_running)
      slots <- self$max_workers - min(self$max_workers, n_running)
      if (slots <= 0L) return(invisible(NULL))
      queued <- running[running$status == "queued", , drop = FALSE]
      if (!nrow(queued)) return(invisible(NULL))
      queued <- queued[order(queued$submitted), , drop = FALSE]
      for (i in seq_len(min(slots, nrow(queued)))) {
        private$start_one(queued$user[[i]], queued$id[[i]])
      }
      invisible(NULL)
    },

    start_one = function(user, id) {
      job_dir <- .ls_job_dir(self$root, user, id)
      claim <- file.path(job_dir, ".claimed")
      if (!dir.create(claim, showWarnings = FALSE)) return(invisible(FALSE))
      metadata <- .ls_read_meta(job_dir)
      if (!identical(metadata$status, "queued")) {
        unlink(claim, recursive = TRUE, force = TRUE)
        return(invisible(FALSE))
      }
      key <- paste(user, id, sep = "::")
      launch <- tryCatch(
        if (identical(self$executor$type, "systemd")) {
          job <- .ls_read_rds(.ls_payload_path(job_dir))
          .ls_systemd_start(
            self$executor, job, metadata, job_dir, .libPaths()
          )
        } else if (self$executor$type %in% c("slurm", "grid_engine")) {
          job <- .ls_read_rds(.ls_payload_path(job_dir))
          .ls_scheduler_start(
            self$executor, job, metadata, job_dir, .libPaths()
          )
        } else {
          list(process = r_bg(
            function(job_dir, library_paths) {
              .libPaths(unique(c(library_paths, .libPaths())))
              library(LibeRties)
              LibeRties:::.ls_run_job(job_dir)
            },
            args = list(job_dir = job_dir, library_paths = .libPaths()),
            libpath = .libPaths(), supervise = TRUE,
            wd = job_dir, env = .ls_worker_env(job_dir),
            stdout = file.path(job_dir, "stdout.log"),
            stderr = file.path(job_dir, "stderr.log")
          ))
        },
        error = identity
      )
      if (inherits(launch, "error")) {
        unlink(claim, recursive = TRUE, force = TRUE)
        .ls_update_meta(job_dir, list(
          status = "failed", finished = .ls_now(), error = conditionMessage(launch)
        ), allowed_status = "queued")
        return(invisible(FALSE))
      }
      if (identical(self$executor$type, "systemd")) {
        .ls_update_meta(job_dir, list(
          systemd_unit = launch$unit,
          systemd_profile = launch$profile,
          requested_cores = launch$cores,
          tasks_max = launch$tasks
        ), allowed_status = c("queued", "running", "completed", "failed", "cancelled"))
      } else if (self$executor$type %in% c("slurm", "grid_engine")) {
        .ls_update_meta(job_dir, list(
          scheduler_job_id = launch$scheduler_job_id,
          scheduler_backend = launch$scheduler_backend,
          scheduler_queue = launch$scheduler_queue,
          scheduler_profile = launch$profile,
          scheduler_submitted = .ls_now(),
          scheduler_script_sha256 = launch$script_sha256,
          scheduler_state = "SUBMITTED",
          requested_cores = launch$cores
        ), allowed_status = c("queued", "running", "completed", "failed", "cancelled"))
      }
      assign(key, launch$process, envir = self$processes)
      invisible(TRUE)
    }
  )
)

#' Create a local LibeR queue
#'
#' @param root Persistent queue root.
#' @param user Isolated user namespace.
#' @param max_workers Maximum simultaneous worker subprocesses for this queue.
#' @param limits Named resource limits, including wall time, CPU time, memory,
#'   payload, result, and storage quotas.
#' @param executor Optional [ls_systemd_executor()], [ls_slurm_executor()], or
#'   [ls_grid_engine_executor()] specification. `NULL` uses the trusted-local
#'   subprocess backend.
#' @return A persistent `LibeRQueue` object.
#' @examples
#' queue <- ls_local_queue(tempfile("liberties-queue-"), max_workers = 1L)
#' queue$list()
#' @export
ls_local_queue <- function(root = .ls_default_root(), user = "local", max_workers = 1L,
                           limits = list(), executor = NULL) {
  LibeRQueue$new(
    root = root, user = user, max_workers = max_workers, limits = limits,
    executor = executor
  )
}
