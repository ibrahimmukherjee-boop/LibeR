#' Create a versioned LibeR execution job
#'
#' @param type `simulate`, `estimate`, `estimate_sequence`, `individualise`, `regimen`, or
#'   `optimal_design`.
#' @param model A serializable LibeRation model (never a live external pointer).
#' @param data A serializable NONMEM-style dataset.
#' @param arguments Named arguments passed to the selected LibeRation entry point.
#' @param label Optional human-readable label.
#' @param engine Allow-listed execution engine: native `liber`, `nonmem`, or
#'   `nlmixr2`. External executable locations are server configuration and are
#'   never accepted in a submitted job.
#' @return A serializable `liber_job`.
#' @export
ls_job <- function(type = c("simulate", "estimate", "estimate_sequence", "individualise", "regimen", "optimal_design"), model, data,
                   arguments = list(), label = NULL,
                   engine = c("liber", "nonmem", "nlmixr2")) {
  type <- match.arg(type)
  engine <- match.arg(tolower(as.character(engine)), c("liber", "nonmem", "nlmixr2"))
  if (!type %in% c("simulate", "estimate", "estimate_sequence") &&
      !identical(engine, "liber")) {
    .ls_stop("External execution engines are only valid for simulation and estimation jobs.")
  }
  if (identical(engine, "nlmixr2") && identical(type, "estimate_sequence")) {
    .ls_stop(
      "Sequential estimation is not yet supported by the nlmixr2 adapter; ",
      "submit each stage as a separate estimation job."
    )
  }
  if (missing(model) || inherits(model, "NMEngine")) {
    .ls_stop("`model` must be a serializable nm_model, not a compiled pointer-backed engine.")
  }
  if (missing(data)) .ls_stop("`data` is required.")
  if (!is.list(arguments) || is.null(names(arguments)) && length(arguments)) {
    .ls_stop("`arguments` must be a named list.")
  }
  job <- structure(
    list(
      schema = "liber.job",
      version = 1L,
      type = type,
      engine = engine,
      model = model,
      data = data,
      arguments = arguments,
      label = as.character(label %||% "")[[1L]],
      created = .ls_now()
    ),
    class = "liber_job"
  )
  tryCatch(serialize(job, NULL, version = 3), error = function(e) {
    .ls_stop("Job is not serializable: ", conditionMessage(e))
  })
  job
}

#' Create a typed LibeRary literature job
#'
#' @param type A typed LibeRary pipeline task.
#' @param payload A data-only LibeRary payload.
#' @param arguments Named worker controls, including sanitized provider config.
#' @param label Optional label.
#' @return A serializable `liber_job`.
#' @export
ls_library_job <- function(type = c("library_triage", "library_parse", "library_index",
                                    "library_dual_extract", "library_assess",
                                    "library_adjudicate"), payload,
                           arguments = list(), label = NULL) {
  type <- match.arg(type)
  if (missing(payload) || !is.list(payload)) .ls_stop("`payload` must be a list.")
  if (!is.list(arguments) || (length(arguments) && is.null(names(arguments)))) {
    .ls_stop("`arguments` must be a named list.")
  }
  forbidden <- function(x) {
    if (is.function(x) || is.environment(x) || typeof(x) == "externalptr") return(TRUE)
    if (is.list(x)) return(any(vapply(x, forbidden, logical(1))))
    FALSE
  }
  if (forbidden(payload) || forbidden(arguments)) .ls_stop("Literature jobs may contain data only, not executable or pointer-backed values.")
  job <- structure(list(schema = "liber.job", version = 1L, type = type,
                        model = NULL, data = payload, arguments = arguments,
                        label = as.character(label %||% "")[[1L]], created = .ls_now()),
                   class = "liber_job")
  tryCatch(serialize(job, NULL, version = 3), error = function(e) .ls_stop("Job is not serializable: ", conditionMessage(e)))
  job
}

#' @export
print.liber_job <- function(x, ...) {
  cat("LibeR execution job\n")
  cat("  type:", x$type, " schema:", x$schema, "v", x$version, "\n")
  cat("  engine:", x$engine %||% "liber", "\n")
  if (nzchar(x$label)) cat("  label:", x$label, "\n")
  invisible(x)
}

#' Create the transport manifest for a job payload
#'
#' @param job A [ls_job()] object.
#' @return A JSON-compatible manifest with an exact serialized-payload checksum.
#' @export
ls_job_manifest <- function(job) {
  if (!inherits(job, "liber_job")) .ls_stop("`job` must be created by ls_job().")
  raw <- serialize(job, NULL, version = 3)
  tmp <- tempfile(fileext = ".rds")
  on.exit(unlink(tmp, force = TRUE), add = TRUE)
  writeBin(raw, tmp)
  list(
    schema = "liber.job.manifest",
    version = 1L,
    job_schema = job$schema,
    job_version = job$version,
    type = job$type,
    engine = job$engine %||% "liber",
    created = job$created,
    payload_bytes = length(raw),
    payload_md5 = .ls_md5(tmp),
    payload_sha256 = .ls_sha256(tmp),
    integrity = "sha256",
    requirements = if (startsWith(job$type, "library_")) {
      list(LibeRary = ">= 0.7.3", LibeRties = ">= 0.7.1")
    } else if (identical(job$type, "optimal_design")) {
      list(LibeRality = ">= 0.2.1", LibeRation = ">= 0.8.1", LibeRtAD = ">= 0.7.6")
    } else if (job$type %in% c("individualise", "regimen")) {
      list(LibeRator = ">= 0.2.4", LibeRation = ">= 0.8.1", LibeRtAD = ">= 0.7.6")
    } else {
      requirements <- list(LibeRation = ">= 0.8.1", LibeRtAD = ">= 0.7.6")
      if (identical(job$engine %||% "liber", "nlmixr2")) {
        requirements <- c(requirements, list(
          nlmixr2 = "installed", nlmixr2est = "installed", rxode2 = "installed"
        ))
      }
      if (identical(job$engine %||% "liber", "nonmem")) {
        requirements <- c(requirements, list(NONMEM_PsN = "administrator configured"))
      }
      requirements
    }
  )
}

#' Report queue and remote-worker contract capabilities
#' @export
ls_queue_capabilities <- function() {
  engine_status <- if (
    requireNamespace("LibeRation", quietly = TRUE) &&
    "nm_execution_engines" %in% getNamespaceExports("LibeRation")
  ) {
    LibeRation::nm_execution_engines()
  } else {
    data.frame(
      id = c("liber", "nonmem", "nlmixr2"),
      label = c("LibeR", "NONMEM", "nlmixr2"),
      available = c(FALSE, FALSE, FALSE), version = "", location = "",
      stringsAsFactors = FALSE
    )
  }
  list(
    contract = "liber.job/1",
    wire_contract = "liber.job.wire/2",
    result_contract = "liber.result.wire/2",
    model_contract = "liberation.model/3",
    job_types = c("simulate", "estimate", "estimate_sequence", "individualise", "regimen", "optimal_design",
                  "library_triage", "library_parse",
                  "library_index", "library_dual_extract", "library_assess",
                  "library_adjudicate"),
    execution_engines = c("liber", "nonmem", "nlmixr2"),
    execution_engine_status = unname(lapply(
      seq_len(nrow(engine_status)), function(index) {
        as.list(engine_status[index, , drop = FALSE])
      }
    )),
    states = c("queued", "running", "completed", "failed", "cancelled"),
    worker = paste(
      "trusted-local restricted R subprocess, production transient systemd",
      "user service, or Slurm/Grid Engine allocation with typed entry points"
    ),
    local_platform = R.version$platform,
    remote_target = paste(
      "Linux with systemd, Slurm, or Grid Engine; scheduler roots and R/package",
      "libraries must be shared with compute nodes"
    ),
    executors = c("subprocess", "systemd", "slurm", "grid_engine"),
    integrity = "SHA-256 payload and result digests (MD5 retained for v1 diagnostics)",
    isolation = c("non-executable typed remote contract", "per-tenant filesystem namespace",
                  "systemd mount/user/network namespaces in production",
                  "scheduler-enforced cores, memory and wall time",
                  "whole-cgroup CPU, task, memory and wall-time limits",
                  "multi-core child workers retained inside one job cgroup",
                  "single-thread numerical libraries per R process")
  )
}
