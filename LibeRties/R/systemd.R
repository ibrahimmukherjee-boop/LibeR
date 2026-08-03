.ls_systemd_safe_text <- function(value, what) {
  value <- as.character(value %||% "")
  if (length(value) != 1L || is.na(value) || !nzchar(value) ||
      grepl("[\r\n]", value)) {
    .ls_stop("`", what, "` must be one non-empty line.")
  }
  value
}

.ls_systemd_user <- function(value) {
  value <- .ls_systemd_safe_text(value, "service_user")
  if (!grepl("^[A-Za-z_][A-Za-z0-9_.-]{0,127}$", value)) {
    .ls_stop("`service_user` is not a portable Linux account name.")
  }
  value
}

.ls_linux_host_user <- function(fallback = as.character(Sys.info()[["user"]] %||% "")) {
  if (!identical(Sys.info()[["sysname"]], "Linux")) return(fallback)
  status <- tryCatch(
    readLines("/proc/self/status", warn = FALSE),
    error = function(error) character()
  )
  uid_line <- grep("^Uid:", status, value = TRUE)
  inside <- if (length(uid_line)) {
    suppressWarnings(as.numeric(strsplit(trimws(sub("^Uid:", "", uid_line[[1L]])),
                                         "[[:space:]]+")[[1L]][[1L]]))
  } else NA_real_
  mapping <- tryCatch(
    readLines("/proc/self/uid_map", warn = FALSE),
    error = function(error) character()
  )
  outer <- NA_real_
  if (is.finite(inside) && length(mapping)) {
    for (line in mapping) {
      fields <- suppressWarnings(as.numeric(strsplit(trimws(line), "[[:space:]]+")[[1L]]))
      if (length(fields) == 3L && all(is.finite(fields)) &&
          inside >= fields[[1L]] && inside < fields[[1L]] + fields[[3L]]) {
        outer <- fields[[2L]] + inside - fields[[1L]]
        break
      }
    }
  }
  passwd <- tryCatch(
    readLines("/etc/passwd", warn = FALSE),
    error = function(error) character()
  )
  if (is.finite(outer) && length(passwd)) {
    fields <- strsplit(passwd, ":", fixed = TRUE)
    match <- which(vapply(fields, function(item) {
      length(item) >= 3L && identical(suppressWarnings(as.numeric(item[[3L]])), outer)
    }, logical(1)))
    if (length(match)) return(fields[[match[[1L]]]][[1L]])
  }
  fallback
}

.ls_systemd_command <- function(command, args, timeout = 30) {
  processx::run(
    command, args = args, error_on_status = FALSE,
    echo = FALSE, timeout = as.numeric(timeout) * 1000
  )
}

.ls_systemd_credential_path <- function(name = "liberties-storage-key") {
  directory <- Sys.getenv("CREDENTIALS_DIRECTORY", unset = "")
  if (!nzchar(directory)) return("")
  candidate <- file.path(directory, name)
  if (file.exists(candidate)) normalizePath(candidate, winslash = "/") else ""
}

.ls_systemd_job_mount <- "/tmp/liberties-job"

.ls_systemd_path <- function(value, what) {
  value <- normalizePath(value, winslash = "/", mustWork = TRUE)
  if (length(value) != 1L || grepl("[[:space:]:]", value)) {
    .ls_stop(
      "`", what, "` must not contain whitespace or ':' when used by systemd."
    )
  }
  value
}

#' Configure the native Linux systemd worker executor
#'
#' The executor creates one transient service for each active LibeRties job.
#' Systemd applies filesystem and process namespaces, a non-root service
#' identity, cgroup-v2 CPU/memory/task limits, and a wall-time limit before the
#' R worker starts. `CPUQuota` is set to `100% * n_cores`, so a multi-core
#' PSOCK job remains multi-core; every child process stays in the same unit.
#'
#' This executor requires Linux with systemd as PID 1 and an active systemd
#' user manager able to create transient services. On Windows it is intended
#' to run inside WSL 2;
#' on macOS it must run inside a user-provided Linux systemd environment.
#'
#' @param service_user Non-root Linux account running both the LibeRties API
#'   user service and its transient worker services. Production operators
#'   should use a dedicated account with systemd lingering enabled.
#' @param max_cores_per_job Hard ceiling for a job's requested `n_cores`.
#' @param tasks_per_core,min_tasks Cgroup task ceiling calculation. Tasks count
#'   R child processes and native threads, so this must exceed `n_cores`.
#' @param unit_prefix Safe prefix for transient systemd service names.
#' @param slice Systemd user slice containing every worker unit. Operators can
#'   place aggregate host limits on this slice without reducing per-job
#'   multi-core quotas.
#' @param networked_job_types Job types allowed to use the host network.
#'   Compute jobs receive `PrivateNetwork=yes`; literature jobs require network
#'   for explicitly configured acquisition or model providers.
#' @param systemd_run,systemctl Paths to the systemd client programs.
#' @param storage_credential Optional systemd credential file containing the
#'   hexadecimal `LIBERTIES_STORAGE_KEY`. It is loaded into workers without
#'   placing the secret in their command line or unit environment.
#' @param live_preflight Run a short sandboxed transient service during strict
#'   production preflight, rather than trusting binary and PID-1 detection.
#' @return A serializable `liberties_systemd_executor` specification.
#' @export
ls_systemd_executor <- function(
    service_user = Sys.getenv(
      "LIBERTIES_SYSTEMD_USER",
      unset = as.character(Sys.info()[["user"]] %||% "")
    ),
    max_cores_per_job = max(
      1L, as.integer(parallel::detectCores(logical = TRUE) %||% 1L),
      na.rm = TRUE
    ),
    tasks_per_core = 16L, min_tasks = 64L,
    unit_prefix = "liberties-job", slice = "liberties-workers.slice",
    networked_job_types = c(
      "library_triage", "library_parse", "library_index",
      "library_dual_extract", "library_assess", "library_adjudicate"
    ),
    systemd_run = unname(Sys.which("systemd-run")),
    systemctl = unname(Sys.which("systemctl")),
    storage_credential = Sys.getenv(
      "LIBERTIES_SYSTEMD_STORAGE_CREDENTIAL", unset = ""
    ),
    live_preflight = TRUE) {
  service_user <- .ls_systemd_user(service_user)
  scalar_integer <- function(value, name, minimum = 1L) {
    value <- as.integer(value)
    if (length(value) != 1L || is.na(value) || value < minimum) {
      .ls_stop("`", name, "` must be an integer >= ", minimum, ".")
    }
    value
  }
  unit_prefix <- .ls_safe_component(unit_prefix, "systemd unit prefix")
  slice <- .ls_systemd_safe_text(slice, "slice")
  if (!grepl("^[A-Za-z0-9_.-]+[.]slice$", slice)) {
    .ls_stop("`slice` must be a safe systemd .slice unit name.")
  }
  systemd_run <- as.character(systemd_run %||% "")
  systemctl <- as.character(systemctl %||% "")
  storage_credential <- as.character(storage_credential %||% "")
  if (length(systemd_run) != 1L || length(systemctl) != 1L ||
      length(storage_credential) != 1L) {
    .ls_stop("Systemd executable and credential paths must be scalar strings.")
  }
  structure(list(
    type = "systemd", manager = "user", service_user = service_user,
    max_cores_per_job = scalar_integer(max_cores_per_job, "max_cores_per_job"),
    tasks_per_core = scalar_integer(tasks_per_core, "tasks_per_core"),
    min_tasks = scalar_integer(min_tasks, "min_tasks"),
    unit_prefix = unit_prefix, slice = slice,
    networked_job_types = unique(as.character(networked_job_types)),
    systemd_run = systemd_run, systemctl = systemctl,
    storage_credential = storage_credential,
    live_preflight = isTRUE(live_preflight)
  ), class = c("liberties_systemd_executor", "liberties_executor"))
}

.ls_subprocess_executor <- function() {
  structure(list(type = "subprocess"), class = "liberties_executor")
}

.ls_executor <- function(executor = NULL) {
  if (is.null(executor)) return(.ls_subprocess_executor())
  if (!inherits(executor, "liberties_executor") ||
      !executor$type %in% c("subprocess", "systemd")) {
    .ls_stop("`executor` must be NULL or created by ls_systemd_executor().")
  }
  executor
}

.ls_job_requested_cores <- function(job) {
  found <- numeric()
  visit <- function(value) {
    if (!is.list(value)) return(invisible(NULL))
    if (length(value) && !is.null(names(value))) {
      indices <- which(names(value) == "n_cores")
      if (length(indices)) {
        for (index in indices) found <<- c(found, suppressWarnings(as.numeric(value[[index]])))
      }
    }
    for (item in value) if (is.list(item)) visit(item)
    invisible(NULL)
  }
  visit(job$arguments %||% list())
  if (!length(found)) return(1L)
  if (anyNA(found) || any(!is.finite(found)) || any(found < 1) ||
      any(found != floor(found))) {
    .ls_stop("Every job `n_cores` value must be a positive integer.")
  }
  as.integer(max(found))
}

.ls_systemd_unit_name <- function(executor, user, id) {
  digest <- substr(.ls_token_hash(paste(user, id, sep = "::")), 1L, 24L)
  paste0(executor$unit_prefix, "-", digest, ".service")
}

.ls_systemd_show <- function(systemctl, unit, manager = "user") {
  result <- .ls_systemd_command(
    systemctl,
    c(paste0("--", manager), "--no-pager",
      "--property=ActiveState,SubState,MainPID,ExecMainStatus,Result",
      "show", unit)
  )
  if (!identical(as.integer(result$status %||% 1L), 0L)) return(list())
  lines <- strsplit(as.character(result$stdout %||% ""), "\n", fixed = TRUE)[[1L]]
  lines <- lines[grepl("=", lines, fixed = TRUE)]
  values <- sub("^[^=]*=", "", lines)
  names(values) <- sub("=.*$", "", lines)
  as.list(values)
}

LibeRSystemdProcess <- R6::R6Class(
  "LibeRSystemdProcess",
  public = list(
    unit = NULL,
    systemctl = NULL,
    manager = NULL,
    initialize = function(unit, systemctl, manager = "user") {
      self$unit <- .ls_systemd_safe_text(unit, "unit")
      self$systemctl <- .ls_systemd_safe_text(systemctl, "systemctl")
      self$manager <- match.arg(manager, c("user", "system"))
    },
    status = function() .ls_systemd_show(
      self$systemctl, self$unit, self$manager
    ),
    is_alive = function() {
      state <- self$status()$ActiveState %||% ""
      state %in% c("activating", "active", "reloading", "deactivating")
    },
    get_pid = function() {
      pid <- suppressWarnings(as.integer(self$status()$MainPID %||% NA_integer_))
      if (is.na(pid) || pid <= 0L) NA_integer_ else pid
    },
    get_exit_status = function() {
      status <- suppressWarnings(as.integer(self$status()$ExecMainStatus %||% NA_integer_))
      if (is.na(status)) NA_integer_ else status
    },
    kill_tree = function() self$kill(),
    kill = function() {
      result <- .ls_systemd_command(
        self$systemctl,
        c(paste0("--", self$manager), "--no-block", "--no-ask-password",
          "stop", self$unit)
      )
      identical(as.integer(result$status %||% 1L), 0L)
    }
  )
)

.ls_systemd_process <- function(executor, unit) {
  LibeRSystemdProcess$new(unit, executor$systemctl, executor$manager)
}

.ls_systemd_properties <- function(executor, job, metadata, job_dir,
                                   library_paths, worker_script) {
  job_dir <- .ls_systemd_path(job_dir, "job_dir")
  worker_script <- .ls_systemd_path(worker_script, "worker_script")
  cores <- .ls_job_requested_cores(job)
  if (cores > executor$max_cores_per_job) {
    .ls_stop(
      "Job requests ", cores, " cores but this systemd executor allows ",
      executor$max_cores_per_job, "."
    )
  }
  tasks <- max(executor$min_tasks, cores * executor$tasks_per_core)
  networked <- job$type %in% executor$networked_job_types
  properties <- c(
    "Type=exec", paste0("Slice=", executor$slice),
    "CollectMode=inactive-or-failed", "KillMode=control-group",
    "SendSIGKILL=yes", "TimeoutStopSec=30s", "UMask=0007",
    "OOMPolicy=kill", "CPUAccounting=yes", "MemoryAccounting=yes",
    "TasksAccounting=yes",
    "NoNewPrivileges=yes", "CapabilityBoundingSet=", "AmbientCapabilities=",
    "PrivateUsers=yes",
    "ProtectSystem=strict", "ProtectHome=tmpfs", "PrivateTmp=yes",
    "PrivateDevices=yes", "ProtectKernelTunables=yes",
    "ProtectKernelModules=yes", "ProtectKernelLogs=yes",
    "ProtectControlGroups=yes", "ProtectClock=yes", "ProtectHostname=yes",
    "ProtectProc=invisible", "ProcSubset=pid", "RestrictSUIDSGID=yes",
    "RestrictRealtime=yes", "RestrictNamespaces=yes", "LockPersonality=yes",
    "RemoveIPC=yes", "SystemCallArchitectures=native",
    "RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6",
    paste0("PrivateNetwork=", if (networked) "no" else "yes"),
    paste0("RuntimeMaxSec=", as.numeric(metadata$limits$max_runtime_seconds), "s"),
    paste0("MemoryMax=", ceiling(as.numeric(metadata$limits$max_memory_mb)), "M"),
    "MemorySwapMax=0", paste0("CPUQuota=", cores * 100L, "%"),
    paste0("TasksMax=", tasks),
    paste0("BindPaths=", job_dir, ":", .ls_systemd_job_mount),
    paste0("ReadWritePaths=", .ls_systemd_job_mount),
    paste0("StandardOutput=append:", file.path(job_dir, "stdout.log")),
    paste0("StandardError=append:", file.path(job_dir, "stderr.log"))
  )
  visible <- unique(vapply(
    c(library_paths, dirname(worker_script)), .ls_systemd_path,
    character(1), what = "library path"
  ))
  properties <- c(properties, paste0("BindReadOnlyPaths=", visible, ":", visible))
  if (nzchar(executor$storage_credential)) {
    credential <- .ls_systemd_path(
      executor$storage_credential, "storage_credential"
    )
    properties <- c(
      properties,
      paste0("LoadCredential=liberties-storage-key:", credential)
    )
  }
  list(properties = properties, cores = cores, tasks = tasks,
       networked = networked)
}

.ls_systemd_start <- function(executor, job, metadata, job_dir, library_paths) {
  if (!identical(Sys.info()[["sysname"]], "Linux")) {
    .ls_stop("The systemd executor must run inside Linux (native, WSL 2, or a user-provided Linux VM).")
  }
  if (!nzchar(executor$systemd_run) || !file.exists(executor$systemd_run) ||
      !nzchar(executor$systemctl) || !file.exists(executor$systemctl)) {
    .ls_stop("systemd-run and systemctl are required for the systemd executor.")
  }
  worker_script <- system.file(
    "systemd", "liberties-systemd-worker.R", package = "LibeRties"
  )
  if (!nzchar(worker_script)) {
    namespace_path <- tryCatch(
      getNamespaceInfo(asNamespace("LibeRties"), "path"),
      error = function(error) ""
    )
    candidate <- file.path(
      namespace_path, "systemd", "liberties-systemd-worker.R"
    )
    if (file.exists(candidate)) worker_script <- candidate
  }
  if (!nzchar(worker_script) || !file.exists(worker_script)) {
    .ls_stop("The installed LibeRties systemd worker entry point is unavailable.")
  }
  unit <- .ls_systemd_unit_name(executor, metadata$user, metadata$id)
  profile <- .ls_systemd_properties(
    executor, job, metadata, normalizePath(job_dir, winslash = "/"),
    library_paths, worker_script
  )
  .ls_ensure_dir(file.path(job_dir, "tmp"))
  environment <- .ls_worker_env(job_dir)
  environment[["HOME"]] <- file.path(.ls_systemd_job_mount, "tmp")
  environment[["TMPDIR"]] <- file.path(.ls_systemd_job_mount, "tmp")
  environment[["LIBER_JOB_DIR"]] <- .ls_systemd_job_mount
  environment[["LIBERTIES_LIBRARY_PATHS"]] <- paste(
    library_paths, collapse = .Platform$path.sep
  )
  environment <- environment[!names(environment) %in% "LIBERTIES_STORAGE_KEY"]
  environment <- environment[!names(environment) %in% c("USERPROFILE", "SystemRoot", "WINDIR")]
  args <- c(
    paste0("--", executor$manager), "--quiet", "--collect", "--no-ask-password",
    paste0("--unit=", unit), paste0("--working-directory=", .ls_systemd_job_mount),
    paste0("--property=", profile$properties),
    paste0("--setenv=", names(environment), "=", unname(environment)),
    file.path(R.home("bin"), "Rscript"), "--vanilla", worker_script,
    .ls_systemd_job_mount
  )
  result <- .ls_systemd_command(executor$systemd_run, args)
  if (!identical(as.integer(result$status %||% 1L), 0L)) {
    detail <- trimws(paste(result$stderr %||% "", result$stdout %||% ""))
    .ls_stop("Unable to start the systemd worker unit", if (nzchar(detail)) paste0(": ", detail) else ".")
  }
  list(
    process = .ls_systemd_process(executor, unit), unit = unit,
    cores = profile$cores, tasks = profile$tasks,
    profile = if (profile$networked) "networked-literature" else "network-isolated-compute"
  )
}

.ls_systemd_preflight <- function(executor, live = executor$live_preflight) {
  issues <- evidence <- character()
  linux <- identical(Sys.info()[["sysname"]], "Linux")
  if (!linux) issues <- c(issues, "The systemd executor is not running inside Linux.")
  pid1 <- if (linux && file.exists("/proc/1/comm")) {
    trimws(tryCatch(readLines("/proc/1/comm", n = 1L, warn = FALSE), error = function(e) ""))
  } else ""
  if (linux && !identical(pid1, "systemd")) {
    issues <- c(issues, "systemd is not PID 1 in this Linux environment.")
  }
  cgroup2 <- linux && file.exists("/sys/fs/cgroup/cgroup.controllers")
  if (linux && !cgroup2) issues <- c(issues, "A unified cgroup-v2 hierarchy is required.")
  for (item in c("systemd_run", "systemctl")) {
    path <- executor[[item]]
    if (!nzchar(path) || !file.exists(path)) {
      issues <- c(issues, paste0(item, " executable was not found."))
    }
  }
  if (identical(executor$service_user, "root")) {
    issues <- c(issues, "Production systemd workers may not run as root.")
  }
  current_user <- .ls_linux_host_user()
  if (linux && !identical(current_user, executor$service_user)) {
    issues <- c(issues, paste0(
      "The systemd user manager belongs to '", current_user,
      "', not configured service user '", executor$service_user, "'."
    ))
  }
  if (nzchar(executor$storage_credential) && !file.exists(executor$storage_credential)) {
    issues <- c(issues, "The configured systemd storage credential does not exist.")
  }
  if (!length(issues) && isTRUE(live)) {
    true <- unname(Sys.which("true"))
    if (!nzchar(true)) true <- "/usr/bin/true"
    unit <- paste0(executor$unit_prefix, "-preflight-", Sys.getpid(), ".service")
    probe_directory <- tempfile("liberties-systemd-preflight-", tmpdir = "/tmp")
    if (!dir.create(probe_directory, mode = "0700", showWarnings = FALSE)) {
      issues <- c(issues, "Unable to create a private systemd preflight directory.")
    }
    on.exit(unlink(probe_directory, recursive = TRUE, force = TRUE), add = TRUE)
    args <- c(
      paste0("--", executor$manager), "--wait", "--quiet", "--collect",
      "--no-ask-password", paste0("--unit=", unit),
      paste0("--working-directory=", .ls_systemd_job_mount),
      "--property=NoNewPrivileges=yes", "--property=ProtectSystem=strict",
      "--property=ProtectHome=tmpfs", "--property=PrivateTmp=yes",
      "--property=PrivateDevices=yes", "--property=PrivateNetwork=yes",
      "--property=PrivateUsers=yes",
      paste0("--property=BindPaths=", probe_directory, ":", .ls_systemd_job_mount),
      paste0("--property=ReadWritePaths=", .ls_systemd_job_mount),
      "--property=MemoryMax=64M", "--property=CPUQuota=100%",
      "--property=TasksMax=16", true
    )
    result <- if (length(issues)) list(status = 1L, stdout = "", stderr = "") else
      .ls_systemd_command(executor$systemd_run, args)
    if (!identical(as.integer(result$status %||% 1L), 0L)) {
      detail <- trimws(paste(result$stderr %||% "", result$stdout %||% ""))
      issues <- c(issues, paste0(
        "A live transient systemd sandbox could not be started",
        if (nzchar(detail)) paste0(": ", detail) else "."
      ))
    } else evidence <- c(evidence, "live transient sandbox completed")
  }
  evidence <- c(
    evidence, paste0("pid1=", pid1), paste0("cgroup_v2=", cgroup2),
    paste0("service_user=", executor$service_user),
    paste0("manager=", executor$manager),
    paste0("worker_slice=", executor$slice),
    paste0("max_cores_per_job=", executor$max_cores_per_job),
    "per-job CPUQuota=100%*n_cores; child processes remain in the unit cgroup"
  )
  list(
    active = !length(issues), provider = "systemd-transient-service",
    evidence = evidence, issues = issues
  )
}
