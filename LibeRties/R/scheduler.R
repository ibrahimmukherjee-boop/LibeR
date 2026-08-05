.ls_scheduler_scalar <- function(value, name, empty = FALSE) {
  value <- as.character(value %||% "")
  if (length(value) != 1L || is.na(value) || grepl("[\r\n]", value) ||
      (!isTRUE(empty) && !nzchar(trimws(value)))) {
    .ls_stop("`", name, "` must be one ", if (empty) "single-line" else
               "non-empty single-line", " value.")
  }
  trimws(value)
}

.ls_scheduler_lines <- function(value, name) {
  value <- as.character(value %||% character())
  if (anyNA(value) || any(grepl("[\r\n]", value))) {
    .ls_stop("`", name, "` must contain valid single-line shell statements.")
  }
  value
}

.ls_scheduler_args <- function(value, name = "extra_submit_args") {
  value <- as.character(value %||% character())
  if (anyNA(value) || any(!nzchar(value)) || any(grepl("[\r\n]", value))) {
    .ls_stop("`", name, "` must contain non-empty command arguments without control lines.")
  }
  value
}

.ls_scheduler_integer <- function(value, name, minimum = 1L) {
  value <- suppressWarnings(as.integer(value))
  if (length(value) != 1L || is.na(value) || value < minimum) {
    .ls_stop("`", name, "` must be an integer >= ", minimum, ".")
  }
  value
}

.ls_scheduler_number <- function(value, name, minimum = 0) {
  value <- suppressWarnings(as.numeric(value))
  if (length(value) != 1L || is.na(value) || !is.finite(value) || value < minimum) {
    .ls_stop("`", name, "` must be a finite number >= ", minimum, ".")
  }
  value
}

.ls_scheduler_optional <- function(value, name) {
  value <- .ls_scheduler_scalar(value, name, empty = TRUE)
  if (nzchar(value) && !grepl("^[A-Za-z0-9_.:@/+,-]+$", value)) {
    .ls_stop("`", name, "` contains unsupported scheduler characters.")
  }
  value
}

.ls_scheduler_executable <- function(value, name) {
  .ls_scheduler_scalar(value, name, empty = TRUE)
}

.ls_scheduler_resolve <- function(value) {
  value <- as.character(value %||% "")[[1L]]
  if (!nzchar(value)) return("")
  if (file.exists(value)) return(normalizePath(value, winslash = "/"))
  unname(Sys.which(value))
}

.ls_scheduler_run <- function(command, args = character(), timeout = 30) {
  tryCatch(
    processx::run(
      command, args = args, error_on_status = FALSE, echo = FALSE,
      timeout = max(1, as.numeric(timeout)) * 1000
    ),
    error = function(error) list(
      status = 127L, stdout = "", stderr = conditionMessage(error)
    )
  )
}

.ls_scheduler_seconds <- function(seconds, style = c("grid_engine", "slurm")) {
  style <- match.arg(style)
  seconds <- max(1L, ceiling(as.numeric(seconds)))
  days <- seconds %/% 86400L
  remaining <- seconds %% 86400L
  hours <- remaining %/% 3600L
  minutes <- (remaining %% 3600L) %/% 60L
  secs <- remaining %% 60L
  if (identical(style, "slurm") && days > 0L) {
    return(sprintf("%d-%02d:%02d:%02d", days, hours, minutes, secs))
  }
  sprintf("%02d:%02d:%02d", hours + days * 24L, minutes, secs)
}

.ls_scheduler_memory_mb <- function(value) {
  value <- trimws(as.character(value %||% ""))
  if (!nzchar(value)) return(0)
  matched <- regexec("^([0-9]+(?:[.][0-9]+)?)([KMGTPE]?)(?:i?[Bb])?(?:n|c)?$",
                     value, ignore.case = TRUE)
  pieces <- regmatches(value, matched)[[1L]]
  if (!length(pieces)) return(0)
  unit_names <- c("", "K", "M", "G", "T", "P", "E")
  units <- c(1 / 1024^2, 1 / 1024, 1, 1024, 1024^2, 1024^3, 1024^4)
  unit <- if (length(pieces) >= 3L && !is.na(pieces[[3L]]) && nzchar(pieces[[3L]])) {
    toupper(pieces[[3L]])
  } else ""
  as.numeric(pieces[[2L]]) * units[[match(unit, unit_names)]]
}

.ls_scheduler_duration <- function(value) {
  value <- trimws(as.character(value %||% ""))
  if (!nzchar(value)) return(0)
  days <- 0
  if (grepl("-", value, fixed = TRUE)) {
    split <- strsplit(value, "-", fixed = TRUE)[[1L]]
    if (length(split) != 2L) return(0)
    days <- suppressWarnings(as.numeric(split[[1L]]))
    value <- split[[2L]]
  }
  fields <- suppressWarnings(as.numeric(strsplit(value, ":", fixed = TRUE)[[1L]]))
  if (anyNA(fields)) return(0)
  fields <- c(rep(0, max(0, 3L - length(fields))), fields)
  days * 86400 + fields[[length(fields) - 2L]] * 3600 +
    fields[[length(fields) - 1L]] * 60 + fields[[length(fields)]]
}

.ls_scheduler_age <- function(submitted) {
  submitted <- suppressWarnings(as.POSIXct(
    submitted %||% "", format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC"
  ))
  if (is.na(submitted)) return(Inf)
  max(0, as.numeric(difftime(Sys.time(), submitted, units = "secs")))
}

.ls_scheduler_unknown <- function(backend, submitted, grace, detail = "") {
  expired <- .ls_scheduler_age(submitted) > grace
  list(
    known = expired, active = !expired,
    state = if (expired) "NO_LONGER_REPORTED" else "ACCOUNTING_PENDING",
    exit_status = NA_integer_,
    usage = list(memory_mb = 0, cpu_seconds = 0, elapsed_seconds = 0),
    detail = detail, backend = backend
  )
}

.ls_slurm_control_value <- function(text, field) {
  matched <- regexec(
    paste0("(?:^|[[:space:]])", field, "=([^[:space:]]+)"),
    as.character(text %||% ""), perl = TRUE
  )
  pieces <- regmatches(as.character(text %||% ""), matched)[[1L]]
  if (length(pieces) < 2L) "" else pieces[[2L]]
}

.ls_slurm_control_status <- function(executor, id) {
  result <- .ls_scheduler_run(
    executor$control, c("show", "job", "--oneliner", id),
    executor$command_timeout
  )
  if (!identical(as.integer(result$status %||% 1L), 0L)) {
    return(list(
      status = as.integer(result$status %||% 1L), result = NULL,
      detail = trimws(paste(result$stderr %||% "", result$stdout %||% ""))
    ))
  }
  state <- toupper(.ls_slurm_control_value(result$stdout, "JobState"))
  if (!nzchar(state)) {
    return(list(status = 0L, result = NULL, detail = "scontrol returned no JobState."))
  }
  active_states <- c(
    "PENDING", "RUNNING", "CONFIGURING", "COMPLETING", "SUSPENDED",
    "REQUEUED", "REQUEUE_FED", "RESIZING", "SIGNALING", "STAGE_OUT"
  )
  exit <- .ls_slurm_control_value(result$stdout, "ExitCode")
  exit <- suppressWarnings(as.integer(strsplit(exit, ":", fixed = TRUE)[[1L]][[1L]]))
  if (is.na(exit) && identical(state, "COMPLETED")) exit <- 0L
  list(
    status = 0L,
    result = list(
      known = TRUE, active = state %in% active_states, state = state,
      exit_status = exit,
      usage = list(
        memory_mb = 0, cpu_seconds = 0,
        elapsed_seconds = .ls_scheduler_duration(
          .ls_slurm_control_value(result$stdout, "RunTime")
        )
      ),
      detail = "Completion read from scontrol; durable resource accounting requires sacct.",
      backend = "slurm"
    ), detail = ""
  )
}

.ls_slurm_status <- function(executor, id, submitted = "") {
  active <- .ls_scheduler_run(
    executor$query,
    c("--noheader", paste0("--jobs=", id), "--format=%T"),
    executor$command_timeout
  )
  if (identical(as.integer(active$status %||% 1L), 0L)) {
    states <- trimws(strsplit(active$stdout %||% "", "\n", fixed = TRUE)[[1L]])
    states <- states[nzchar(states)]
    if (length(states)) {
      state <- toupper(states[[1L]])
      return(list(
        known = TRUE, active = TRUE, state = state, exit_status = NA_integer_,
        usage = list(memory_mb = 0, cpu_seconds = 0, elapsed_seconds = 0),
        detail = "", backend = "slurm"
      ))
    }
  } else {
    return(.ls_scheduler_unknown(
      "slurm", submitted, Inf,
      trimws(paste(active$stderr %||% "", active$stdout %||% ""))
    ))
  }
  accounting <- .ls_scheduler_run(
    executor$accounting,
    c("--noheader", "--parsable2", "-X", paste0("--jobs=", id),
      "--format=JobIDRaw,State,ExitCode,ElapsedRaw,TotalCPU,MaxRSS"),
    executor$command_timeout
  )
  accounting_ok <- identical(as.integer(accounting$status %||% 1L), 0L)
  if (accounting_ok) {
    rows <- strsplit(accounting$stdout %||% "", "\n", fixed = TRUE)[[1L]]
    rows <- strsplit(rows[nzchar(trimws(rows))], "|", fixed = TRUE)
    row <- Filter(function(item) length(item) >= 6L && identical(item[[1L]], id), rows)
    if (length(row)) {
      row <- row[[1L]]
      state <- toupper(sub("[+ ].*$", "", trimws(row[[2L]])))
      active_states <- c(
        "PENDING", "RUNNING", "CONFIGURING", "COMPLETING", "SUSPENDED",
        "REQUEUED", "REQUEUE_FED", "RESIZING", "SIGNALING", "STAGE_OUT"
      )
      code <- suppressWarnings(as.integer(strsplit(row[[3L]], ":", fixed = TRUE)[[1L]][[1L]]))
      if (is.na(code) && identical(state, "COMPLETED")) code <- 0L
      return(list(
        known = TRUE, active = state %in% active_states, state = state,
        exit_status = code,
        usage = list(
          memory_mb = .ls_scheduler_memory_mb(row[[6L]]),
          cpu_seconds = .ls_scheduler_duration(row[[5L]]),
          elapsed_seconds = suppressWarnings(as.numeric(row[[4L]] %||% 0))
        ), detail = "", backend = "slurm"
      ))
    }
  }
  control <- .ls_slurm_control_status(executor, id)
  if (!is.null(control$result)) return(control$result)
  accounting_detail <- trimws(paste(
    accounting$stderr %||% "", accounting$stdout %||% ""
  ))
  control_absent <- grepl(
    "invalid job id|unknown job|not found|does not exist", control$detail,
    ignore.case = TRUE
  )
  .ls_scheduler_unknown(
    "slurm", submitted,
    if (accounting_ok && control_absent) executor$accounting_grace_seconds else Inf,
    trimws(paste(accounting_detail, control$detail))
  )
}

.ls_grid_engine_accounting <- function(text) {
  lines <- strsplit(as.character(text %||% ""), "\n", fixed = TRUE)[[1L]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines) & !startsWith(lines, "=")]
  values <- lapply(lines, function(line) {
    pieces <- strsplit(line, "[[:space:]]+")[[1L]]
    pieces <- pieces[nzchar(pieces)]
    if (length(pieces) < 2L) return(NULL)
    c(key = pieces[[1L]], value = paste(pieces[-1L], collapse = " "))
  })
  values <- Filter(Negate(is.null), values)
  if (!length(values)) return(list())
  result <- lapply(values, `[[`, "value")
  names(result) <- vapply(values, `[[`, character(1), "key")
  result
}

.ls_grid_engine_status <- function(executor, id, submitted = "") {
  active <- .ls_scheduler_run(
    executor$query, c("-j", id), executor$command_timeout
  )
  if (identical(as.integer(active$status %||% 1L), 0L)) {
    return(list(
      known = TRUE, active = TRUE, state = "QUEUED_OR_RUNNING",
      exit_status = NA_integer_,
      usage = list(memory_mb = 0, cpu_seconds = 0, elapsed_seconds = 0),
      detail = "", backend = "grid_engine"
    ))
  }
  active_detail <- trimws(paste(active$stderr %||% "", active$stdout %||% ""))
  expected_absence <- grepl(
    "do not exist|unknown job|not found", active_detail, ignore.case = TRUE
  )
  if (!expected_absence) {
    return(.ls_scheduler_unknown("grid_engine", submitted, Inf, active_detail))
  }
  accounting <- .ls_scheduler_run(
    executor$accounting, c("-j", id), executor$command_timeout
  )
  if (identical(as.integer(accounting$status %||% 1L), 0L)) {
    values <- .ls_grid_engine_accounting(accounting$stdout)
    if (length(values)) {
      exit <- suppressWarnings(as.integer(values$exit_status %||% NA_integer_))
      failed <- suppressWarnings(as.integer(values$failed %||% 0L))
      if (is.na(exit) && identical(failed, 0L)) exit <- 0L
      return(list(
        known = TRUE, active = FALSE,
        state = if (identical(exit, 0L) && identical(failed, 0L))
          "COMPLETED" else "FAILED",
        exit_status = exit,
        usage = list(
          memory_mb = max(
            .ls_scheduler_memory_mb(values$maxvmem %||% ""),
            .ls_scheduler_memory_mb(values$maxrss %||% "")
          ),
          cpu_seconds = suppressWarnings(as.numeric(values$cpu %||% 0)),
          elapsed_seconds = suppressWarnings(as.numeric(values$ru_wallclock %||% 0))
        ), detail = "", backend = "grid_engine"
      ))
    }
  } else {
    accounting_detail <- trimws(paste(
      accounting$stderr %||% "", accounting$stdout %||% ""
    ))
    if (!grepl("not found|unknown job|not exist", accounting_detail,
               ignore.case = TRUE)) {
      return(.ls_scheduler_unknown(
        "grid_engine", submitted, Inf, accounting_detail
      ))
    }
  }
  .ls_scheduler_unknown(
    "grid_engine", submitted, executor$accounting_grace_seconds,
    trimws(paste(accounting$stderr %||% "", accounting$stdout %||% ""))
  )
}

LibeRSchedulerProcess <- R6::R6Class(
  "LibeRSchedulerProcess",
  public = list(
    executor = NULL, job_id = "", submitted = "",
    cached = NULL, checked = NULL,
    initialize = function(executor, job_id, submitted = "") {
      self$executor <- executor
      self$job_id <- .ls_safe_component(job_id, "scheduler job id")
      self$submitted <- as.character(submitted %||% "")[[1L]]
      self$checked <- as.POSIXct(NA)
    },
    status = function(refresh = FALSE) {
      age <- suppressWarnings(as.numeric(difftime(Sys.time(), self$checked, units = "secs")))
      if (!isTRUE(refresh) && !is.null(self$cached) && is.finite(age) && age < 0.25) {
        return(self$cached)
      }
      self$cached <- if (identical(self$executor$type, "slurm")) {
        .ls_slurm_status(self$executor, self$job_id, self$submitted)
      } else {
        .ls_grid_engine_status(self$executor, self$job_id, self$submitted)
      }
      self$checked <- Sys.time()
      self$cached
    },
    is_alive = function() isTRUE(self$status()$active),
    get_pid = function() NA_integer_,
    get_exit_status = function() {
      suppressWarnings(as.integer(self$status()$exit_status %||% NA_integer_))
    },
    resource_usage = function() {
      usage <- self$status()$usage %||% list()
      list(
        memory_mb = as.numeric(usage$memory_mb %||% 0),
        cpu_seconds = as.numeric(usage$cpu_seconds %||% 0),
        elapsed_seconds = as.numeric(usage$elapsed_seconds %||% 0)
      )
    },
    kill_tree = function() self$kill(),
    kill = function() {
      result <- .ls_scheduler_run(
        self$executor$cancel, self$job_id, self$executor$command_timeout
      )
      identical(as.integer(result$status %||% 1L), 0L)
    }
  )
)

.ls_scheduler_process <- function(executor, id, submitted = "") {
  if (!nzchar(as.character(id %||% ""))) return(NULL)
  LibeRSchedulerProcess$new(executor, as.character(id), submitted)
}

.ls_scheduler_start <- function(executor, job, metadata, job_dir, library_paths) {
  if (identical(executor$type, "slurm")) {
    .ls_slurm_start(executor, job, metadata, job_dir, library_paths)
  } else {
    .ls_grid_engine_start(executor, job, metadata, job_dir, library_paths)
  }
}

.ls_executor_process <- function(executor, metadata) {
  if (identical(executor$type, "systemd")) {
    unit <- as.character(metadata$systemd_unit %||% "")[[1L]]
    if (nzchar(unit)) return(.ls_systemd_process(executor, unit))
  }
  if (executor$type %in% c("slurm", "grid_engine")) {
    backend <- as.character(metadata$scheduler_backend %||% "")[[1L]]
    id <- as.character(metadata$scheduler_job_id %||% "")[[1L]]
    if (identical(backend, executor$type) && nzchar(id)) {
      return(.ls_scheduler_process(
        executor, id, metadata$scheduler_submitted %||% metadata$submitted %||% ""
      ))
    }
  }
  NULL
}

.ls_scheduler_executor_mismatch <- function(executor, metadata) {
  job_id <- as.character(metadata$scheduler_job_id %||% "")[[1L]]
  recorded <- as.character(metadata$scheduler_backend %||% "")[[1L]]
  nzchar(job_id) && recorded %in% c("slurm", "grid_engine") &&
    !identical(recorded, executor$type)
}

.ls_scheduler_mismatch_message <- function(executor, metadata) {
  paste0(
    "The durable job belongs to scheduler backend `",
    as.character(metadata$scheduler_backend %||% "")[[1L]],
    "`, but this queue was reopened with executor `", executor$type,
    "`. LibeRties has preserved the existing allocation and will not ",
    "resubmit or falsely fail it. Restore the original executor to reconcile ",
    "or cancel scheduler job ",
    as.character(metadata$scheduler_job_id %||% "")[[1L]], "."
  )
}

.ls_process_resource_usage <- function(process) {
  method <- tryCatch(process$resource_usage, error = function(error) NULL)
  if (is.function(method)) {
    usage <- tryCatch(method(), error = function(error) NULL)
    if (is.list(usage)) {
      return(list(
        memory_mb = as.numeric(usage$memory_mb %||% 0),
        cpu_seconds = as.numeric(usage$cpu_seconds %||% 0),
        elapsed_seconds = as.numeric(usage$elapsed_seconds %||% 0)
      ))
    }
  }
  pid <- tryCatch(process$get_pid(), error = function(error) NA_integer_)
  usage <- tryCatch(.ls_resource_usage(pid), error = function(error) {
    list(memory_mb = 0, cpu_seconds = 0)
  })
  c(usage, list(elapsed_seconds = NA_real_))
}

.ls_scheduler_shell_quote <- function(value) {
  shQuote(as.character(value), type = "sh")
}

.ls_scheduler_worker_script <- function() {
  worker <- system.file("scheduler", "liberties-scheduler-worker.R", package = "LibeRties")
  if (!nzchar(worker)) {
    namespace_path <- tryCatch(
      getNamespaceInfo(asNamespace("LibeRties"), "path"),
      error = function(error) ""
    )
    candidate <- file.path(namespace_path, "scheduler", "liberties-scheduler-worker.R")
    if (file.exists(candidate)) worker <- candidate
  }
  if (!nzchar(worker) || !file.exists(worker)) {
    .ls_stop("The installed LibeRties scheduler worker entry point is unavailable.")
  }
  normalizePath(worker, winslash = "/", mustWork = TRUE)
}

.ls_scheduler_write_script <- function(executor, job_dir, library_paths) {
  job_dir <- normalizePath(job_dir, winslash = "/", mustWork = TRUE)
  worker <- .ls_scheduler_worker_script()
  rscript <- .ls_scheduler_resolve(executor$rscript)
  if (!nzchar(rscript)) .ls_stop("The configured Rscript executable is unavailable.")
  environment <- .ls_worker_env(job_dir)
  environment <- environment[!names(environment) %in% c(
    "LIBERTIES_STORAGE_KEY", "HOME", "TEMP", "TMP", "TMPDIR",
    "USERPROFILE", "SystemRoot", "WINDIR"
  )]
  environment[["LIBERTIES_LIBRARY_PATHS"]] <- paste(
    unique(as.character(library_paths)), collapse = .Platform$path.sep
  )
  if (nzchar(executor$storage_key_file)) {
    environment[["LIBERTIES_STORAGE_KEY_FILE"]] <- normalizePath(
      executor$storage_key_file, winslash = "/", mustWork = TRUE
    )
  }
  exports <- paste0(
    "export ", names(environment), "=",
    vapply(unname(environment), .ls_scheduler_shell_quote, character(1))
  )
  script <- c(
    paste0("#!", executor$shell, " -l"), "set -eu", "umask 0077",
    executor$prologue, exports,
    paste(
      "exec", .ls_scheduler_shell_quote(rscript), "--vanilla",
      .ls_scheduler_shell_quote(worker), .ls_scheduler_shell_quote(job_dir)
    )
  )
  path <- file.path(job_dir, "scheduler-job.sh")
  writeLines(script, path, useBytes = TRUE)
  Sys.chmod(path, mode = "0700")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

.ls_scheduler_job_name <- function(executor, metadata) {
  digest <- substr(.ls_token_hash(paste(metadata$user, metadata$id, sep = "::")), 1L, 16L)
  paste0(executor$job_name_prefix, "-", digest)
}

.ls_slurm_start <- function(executor, job, metadata, job_dir, library_paths) {
  script <- .ls_scheduler_write_script(executor, job_dir, library_paths)
  cores <- .ls_job_requested_cores(job)
  if (cores > executor$max_cores_per_job) {
    .ls_stop("Job requests ", cores, " cores but this Slurm executor allows ",
             executor$max_cores_per_job, ".")
  }
  args <- c(
    "--parsable", paste0("--job-name=", .ls_scheduler_job_name(executor, metadata)),
    paste0("--chdir=", normalizePath(job_dir, winslash = "/")),
    paste0("--output=", file.path(normalizePath(job_dir, winslash = "/"), "stdout.log")),
    paste0("--error=", file.path(normalizePath(job_dir, winslash = "/"), "stderr.log")),
    "--open-mode=append", "--export=NONE", "--nodes=1", "--ntasks=1",
    paste0("--cpus-per-task=", cores),
    paste0("--time=", .ls_scheduler_seconds(metadata$limits$max_runtime_seconds, "slurm")),
    paste0("--mem=", ceiling(metadata$limits$max_memory_mb), "M")
  )
  if (nzchar(executor$partition)) args <- c(args, paste0("--partition=", executor$partition))
  if (nzchar(executor$account)) args <- c(args, paste0("--account=", executor$account))
  if (nzchar(executor$qos)) args <- c(args, paste0("--qos=", executor$qos))
  if (nzchar(executor$constraint)) args <- c(args, paste0("--constraint=", executor$constraint))
  args <- c(args, executor$extra_submit_args, script)
  submitted <- .ls_scheduler_run(executor$submit, args, executor$command_timeout)
  if (!identical(as.integer(submitted$status %||% 1L), 0L)) {
    .ls_stop("Slurm rejected the LibeRties job: ",
             trimws(paste(submitted$stderr %||% "", submitted$stdout %||% "")))
  }
  id <- sub(";.*$", "", trimws(as.character(submitted$stdout %||% "")))
  if (!grepl("^[0-9]+$", id)) .ls_stop("Slurm returned an invalid job id: ", id, ".")
  process <- .ls_scheduler_process(executor, id, .ls_now())
  list(
    process = process, scheduler_job_id = id, scheduler_backend = "slurm",
    scheduler_queue = executor$partition,
    profile = paste0("cpus=", cores, ";memory=", ceiling(metadata$limits$max_memory_mb),
                     "M", if (nzchar(executor$partition)) paste0(";partition=", executor$partition) else ""),
    cores = cores, script = script, script_sha256 = .ls_sha256(script)
  )
}

.ls_grid_engine_start <- function(executor, job, metadata, job_dir, library_paths) {
  script <- .ls_scheduler_write_script(executor, job_dir, library_paths)
  cores <- .ls_job_requested_cores(job)
  if (cores > executor$max_cores_per_job) {
    .ls_stop("Job requests ", cores, " cores but this Grid Engine executor allows ",
             executor$max_cores_per_job, ".")
  }
  directory <- normalizePath(job_dir, winslash = "/")
  memory <- if (isTRUE(executor$memory_per_core)) {
    ceiling(metadata$limits$max_memory_mb / cores)
  } else ceiling(metadata$limits$max_memory_mb)
  resources <- c(
    paste0(executor$runtime_resource, "=",
           .ls_scheduler_seconds(metadata$limits$max_runtime_seconds, "grid_engine")),
    paste0(executor$memory_resource, "=", memory, "M")
  )
  if (!is.null(executor$tmpfs_mb)) {
    resources <- c(resources, paste0(executor$tmpfs_resource, "=", executor$tmpfs_mb, "M"))
  }
  args <- c(
    "-terse", "-N", .ls_scheduler_job_name(executor, metadata),
    "-wd", directory, "-o", file.path(directory, "stdout.log"),
    "-e", file.path(directory, "stderr.log"), "-j", "n", "-m", "n",
    "-l", paste(resources, collapse = ",")
  )
  if (cores > 1L) args <- c(args, "-pe", executor$parallel_environment, as.character(cores))
  if (nzchar(executor$queue)) args <- c(args, "-q", executor$queue)
  if (nzchar(executor$project)) args <- c(args, "-P", executor$project)
  args <- c(args, executor$extra_submit_args, script)
  submitted <- .ls_scheduler_run(executor$submit, args, executor$command_timeout)
  if (!identical(as.integer(submitted$status %||% 1L), 0L)) {
    .ls_stop("Grid Engine rejected the LibeRties job: ",
             trimws(paste(submitted$stderr %||% "", submitted$stdout %||% "")))
  }
  output <- trimws(as.character(submitted$stdout %||% ""))
  matched <- regexec("^([0-9]+)", output)
  pieces <- regmatches(output, matched)[[1L]]
  if (length(pieces) < 2L) .ls_stop("Grid Engine returned an invalid job id: ", output, ".")
  id <- pieces[[2L]]
  process <- .ls_scheduler_process(executor, id, .ls_now())
  list(
    process = process, scheduler_job_id = id,
    scheduler_backend = "grid_engine", scheduler_queue = executor$queue,
    profile = paste0("slots=", cores, ";memory_per_", if (executor$memory_per_core) "core" else "job",
                     "=", memory, "M", if (nzchar(executor$queue)) paste0(";queue=", executor$queue) else ""),
    cores = cores, script = script, script_sha256 = .ls_sha256(script)
  )
}

#' Configure a Slurm worker executor
#'
#' Each LibeRties job is submitted as one single-node Slurm allocation. The
#' scheduler receives the job's core, memory, and wall-time limits. The queue
#' root, R installation, and package libraries must be visible on compute
#' nodes. `prologue` and `extra_submit_args` are trusted operator configuration,
#' never values accepted from a remote job payload.
#'
#' @param partition,account,qos,constraint Optional Slurm routing values.
#' @param max_cores_per_job Maximum `n_cores` accepted for one job.
#' @param job_name_prefix Prefix used for scheduler-visible job names.
#' @param prologue Trusted shell statements run before the R worker.
#' @param extra_submit_args Additional trusted `sbatch` arguments.
#' @param submit,query,accounting,control,cancel Slurm command paths or names.
#' @param rscript,shell Compute-node Rscript and shell paths.
#' @param storage_key_file Optional shared, mode-0600 file containing the
#'   hexadecimal LibeRties storage key.
#' @param accounting_grace_seconds Time allowed for scheduler accounting to
#'   publish a completed job before an absent job is considered lost.
#' @param command_timeout Scheduler command timeout in seconds.
#' @return A serializable `liberties_slurm_executor` specification.
#' @export
ls_slurm_executor <- function(
    partition = "", account = "", qos = "", constraint = "",
    max_cores_per_job = max(1L, parallel::detectCores(logical = TRUE), na.rm = TRUE),
    job_name_prefix = "liber", prologue = character(), extra_submit_args = character(),
    submit = unname(Sys.which("sbatch")), query = unname(Sys.which("squeue")),
    accounting = unname(Sys.which("sacct")), control = unname(Sys.which("scontrol")),
    cancel = unname(Sys.which("scancel")),
    rscript = file.path(R.home("bin"), "Rscript"), shell = "/bin/bash",
    storage_key_file = Sys.getenv("LIBERTIES_SCHEDULER_STORAGE_KEY_FILE", unset = ""),
    accounting_grace_seconds = 120, command_timeout = 30) {
  structure(list(
    type = "slurm", partition = .ls_scheduler_optional(partition, "partition"),
    account = .ls_scheduler_optional(account, "account"),
    qos = .ls_scheduler_optional(qos, "qos"),
    constraint = .ls_scheduler_optional(constraint, "constraint"),
    max_cores_per_job = .ls_scheduler_integer(max_cores_per_job, "max_cores_per_job"),
    job_name_prefix = .ls_safe_component(job_name_prefix, "job name prefix"),
    prologue = .ls_scheduler_lines(prologue, "prologue"),
    extra_submit_args = .ls_scheduler_args(extra_submit_args),
    submit = .ls_scheduler_executable(submit, "submit"),
    query = .ls_scheduler_executable(query, "query"),
    accounting = .ls_scheduler_executable(accounting, "accounting"),
    control = .ls_scheduler_executable(control, "control"),
    cancel = .ls_scheduler_executable(cancel, "cancel"),
    rscript = .ls_scheduler_executable(rscript, "rscript"),
    shell = .ls_scheduler_executable(shell, "shell"),
    storage_key_file = .ls_scheduler_scalar(storage_key_file, "storage_key_file", empty = TRUE),
    accounting_grace_seconds = .ls_scheduler_number(
      accounting_grace_seconds, "accounting_grace_seconds", 1
    ), command_timeout = .ls_scheduler_number(command_timeout, "command_timeout", 1)
  ), class = c("liberties_slurm_executor", "liberties_scheduler_executor", "liberties_executor"))
}

#' Configure a Grid Engine worker executor
#'
#' The adapter supports Sun/Oracle/Univa/Open Grid Engine command-line
#' interfaces and UCL Myriad's `smp`, `h_rt`, `mem`, and optional `tmpfs`
#' resources. Memory is requested per core by default, matching Myriad.
#'
#' @param queue,project Optional Grid Engine queue and project.
#' @param parallel_environment Parallel environment used for multi-core jobs.
#' @param memory_resource,runtime_resource,tmpfs_resource Site resource names.
#' @param memory_per_core Interpret the LibeRties memory limit as a whole-job
#'   ceiling and divide it across requested Grid Engine slots.
#' @param tmpfs_mb Optional temporary-filesystem request in MB.
#' @inheritParams ls_slurm_executor
#' @param extra_submit_args Additional trusted `qsub` arguments.
#' @param submit,query,accounting,cancel Grid Engine command paths or names.
#' @return A serializable `liberties_grid_engine_executor` specification.
#' @export
ls_grid_engine_executor <- function(
    queue = "", project = "", parallel_environment = "smp",
    memory_resource = "mem", runtime_resource = "h_rt",
    tmpfs_resource = "tmpfs", memory_per_core = TRUE, tmpfs_mb = NULL,
    max_cores_per_job = max(1L, parallel::detectCores(logical = TRUE), na.rm = TRUE),
    job_name_prefix = "liber", prologue = character(), extra_submit_args = character(),
    submit = unname(Sys.which("qsub")), query = unname(Sys.which("qstat")),
    accounting = unname(Sys.which("qacct")), cancel = unname(Sys.which("qdel")),
    rscript = file.path(R.home("bin"), "Rscript"), shell = "/bin/bash",
    storage_key_file = Sys.getenv("LIBERTIES_SCHEDULER_STORAGE_KEY_FILE", unset = ""),
    accounting_grace_seconds = 120, command_timeout = 30) {
  resource <- function(value, name) {
    value <- .ls_scheduler_scalar(value, name)
    if (!grepl("^[A-Za-z][A-Za-z0-9_.-]*$", value)) {
      .ls_stop("`", name, "` is not a safe Grid Engine resource name.")
    }
    value
  }
  if (!is.null(tmpfs_mb)) tmpfs_mb <- .ls_scheduler_integer(tmpfs_mb, "tmpfs_mb")
  structure(list(
    type = "grid_engine", queue = .ls_scheduler_optional(queue, "queue"),
    project = .ls_scheduler_optional(project, "project"),
    parallel_environment = resource(parallel_environment, "parallel_environment"),
    memory_resource = resource(memory_resource, "memory_resource"),
    runtime_resource = resource(runtime_resource, "runtime_resource"),
    tmpfs_resource = resource(tmpfs_resource, "tmpfs_resource"),
    memory_per_core = isTRUE(memory_per_core), tmpfs_mb = tmpfs_mb,
    max_cores_per_job = .ls_scheduler_integer(max_cores_per_job, "max_cores_per_job"),
    job_name_prefix = .ls_safe_component(job_name_prefix, "job name prefix"),
    prologue = .ls_scheduler_lines(prologue, "prologue"),
    extra_submit_args = .ls_scheduler_args(extra_submit_args),
    submit = .ls_scheduler_executable(submit, "submit"),
    query = .ls_scheduler_executable(query, "query"),
    accounting = .ls_scheduler_executable(accounting, "accounting"),
    cancel = .ls_scheduler_executable(cancel, "cancel"),
    rscript = .ls_scheduler_executable(rscript, "rscript"),
    shell = .ls_scheduler_executable(shell, "shell"),
    storage_key_file = .ls_scheduler_scalar(storage_key_file, "storage_key_file", empty = TRUE),
    accounting_grace_seconds = .ls_scheduler_number(
      accounting_grace_seconds, "accounting_grace_seconds", 1
    ), command_timeout = .ls_scheduler_number(command_timeout, "command_timeout", 1)
  ), class = c("liberties_grid_engine_executor", "liberties_scheduler_executor", "liberties_executor"))
}

.ls_scheduler_preflight <- function(executor) {
  issues <- evidence <- character()
  if (!identical(Sys.info()[["sysname"]], "Linux")) {
    issues <- c(issues, "Scheduler executors must run on a Linux scheduler submission host.")
  }
  commands <- c("submit", "query", "accounting", "cancel", "rscript", "shell")
  if (identical(executor$type, "slurm")) commands <- c(commands, "control")
  resolved <- vapply(executor[commands], .ls_scheduler_resolve, character(1))
  missing <- names(resolved)[!nzchar(resolved)]
  if (length(missing)) {
    issues <- c(issues, paste0("Scheduler executable(s) unavailable: ",
                               paste(missing, collapse = ", "), "."))
  }
  if (nzchar(executor$storage_key_file)) {
    if (!file.exists(executor$storage_key_file)) {
      issues <- c(issues, "The scheduler storage-key file does not exist.")
    } else if (.Platform$OS.type != "windows") {
      mode <- as.integer(file.info(executor$storage_key_file)$mode)
      if (is.finite(mode) && bitwAnd(mode, as.octmode("077")) != 0L) {
        issues <- c(issues, "The scheduler storage-key file must not be accessible by group or other users.")
      }
    }
  }
  evidence <- c(
    paste0("backend=", executor$type),
    paste0("max_cores_per_job=", executor$max_cores_per_job),
    paste0("commands=", paste(ifelse(nzchar(resolved), resolved, "missing"), collapse = ",")),
    "scheduler requests enforce cores, whole-job memory, and wall time",
    "scheduler presence alone does not attest hostile multi-tenant filesystem isolation"
  )
  list(
    active = FALSE, provider = paste0(executor$type, "-resource-scheduler"),
    evidence = evidence, issues = issues
  )
}
