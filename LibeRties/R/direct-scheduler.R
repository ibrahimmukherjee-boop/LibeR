# Direct SSH scheduler command ---------------------------------------------

.ls_direct_scalar <- function(value, name, default = "", empty = TRUE,
                              maximum = 1024L) {
  value <- as.character(value %||% default)
  if (length(value) != 1L || is.na(value) || grepl("[\r\n]", value) ||
      nchar(value, type = "bytes") > maximum ||
      (!isTRUE(empty) && !nzchar(trimws(value)))) {
    .ls_stop("`", name, "` must be a valid single-line value.")
  }
  trimws(value)
}

.ls_direct_integer <- function(value, name, minimum = 1L, maximum = 100000L) {
  numeric <- suppressWarnings(as.numeric(value))
  integer <- suppressWarnings(as.integer(numeric))
  if (length(numeric) != 1L || !is.finite(numeric) || numeric != integer ||
      integer < minimum || integer > maximum) {
    .ls_stop("`", name, "` must be an integer between ", minimum, " and ", maximum, ".")
  }
  integer
}

.ls_direct_scheduler_config <- function(value) {
  if (!is.list(value)) .ls_stop("Direct-scheduler configuration must be an object.")
  backend <- tolower(.ls_direct_scalar(value$backend, "backend", empty = FALSE))
  if (!backend %in% c("slurm", "grid_engine")) {
    .ls_stop("Direct-scheduler backend must be `slurm` or `grid_engine`.")
  }
  queue_name <- .ls_safe_component(value$queue_name %||% "default", "direct queue name")
  root <- .ls_direct_scalar(value$root, "root", default = "", maximum = 4096L)
  if (!nzchar(root)) {
    root <- file.path(path.expand("~"), ".local", "share", "LibeR", "direct-queues", queue_name)
  } else {
    root <- path.expand(root)
  }
  limits <- value$limits %||% list()
  if (!is.list(limits)) .ls_stop("`limits` must be an object.")
  max_workers <- .ls_direct_integer(value$max_workers %||% 8L, "max_workers", 1L, 10000L)
  if (is.null(limits$max_concurrent_jobs)) limits$max_concurrent_jobs <- max_workers
  max_cores <- .ls_direct_integer(
    value$max_cores_per_job %||% 64L, "max_cores_per_job", 1L, 100000L
  )
  optional <- function(name) .ls_direct_scalar(value[[name]], name, default = "")
  if (identical(backend, "slurm")) {
    executor <- ls_slurm_executor(
      partition = optional("partition"), account = optional("account"),
      qos = optional("qos"), constraint = optional("constraint"),
      max_cores_per_job = max_cores,
      storage_key_file = file.path(root, ".storage-key")
    )
  } else {
    executor <- ls_grid_engine_executor(
      queue = optional("queue"), project = optional("project"),
      parallel_environment = .ls_direct_scalar(
        value$parallel_environment, "parallel_environment", default = "smp", empty = FALSE
      ),
      memory_resource = .ls_direct_scalar(
        value$memory_resource, "memory_resource", default = "mem", empty = FALSE
      ),
      runtime_resource = .ls_direct_scalar(
        value$runtime_resource, "runtime_resource", default = "h_rt", empty = FALSE
      ),
      tmpfs_resource = .ls_direct_scalar(
        value$tmpfs_resource, "tmpfs_resource", default = "tmpfs", empty = FALSE
      ),
      memory_per_core = !identical(value$memory_per_core, FALSE),
      tmpfs_mb = if (is.null(value$tmpfs_mb) || !length(value$tmpfs_mb) ||
                       !nzchar(as.character(value$tmpfs_mb[[1L]]))) NULL else
        .ls_direct_integer(value$tmpfs_mb, "tmpfs_mb", 1L, 100000000L),
      max_cores_per_job = max_cores,
      storage_key_file = file.path(root, ".storage-key")
    )
  }
  list(
    backend = backend, queue_name = queue_name, root = root,
    user = .ls_safe_component(value$user %||% "local", "direct queue user"),
    max_workers = max_workers, limits = limits, executor = executor
  )
}

.ls_direct_storage_key <- function(root, supplied) {
  supplied <- tolower(.ls_direct_scalar(
    supplied, "storage_key", empty = FALSE, maximum = 64L
  ))
  if (!grepl("^[a-f0-9]{64}$", supplied)) {
    .ls_stop("`storage_key` must be a 256-bit hexadecimal key.")
  }
  root <- .ls_ensure_dir(root)
  path <- file.path(root, ".storage-key")
  if (file.exists(path)) {
    current <- trimws(readLines(path, n = 1L, warn = FALSE, encoding = "UTF-8"))
    if (!identical(tolower(current), supplied)) {
      .ls_stop("The saved direct-scheduler storage key does not match this client.")
    }
  } else {
    temporary <- tempfile("storage-key-", tmpdir = root)
    on.exit(unlink(temporary, force = TRUE), add = TRUE)
    writeLines(supplied, temporary, useBytes = TRUE)
    if (.Platform$OS.type != "windows") Sys.chmod(temporary, mode = "0600")
    if (!file.rename(temporary, path)) .ls_stop("Unable to publish the scheduler storage key.")
  }
  if (.Platform$OS.type != "windows") Sys.chmod(path, mode = "0600")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

.ls_direct_request_unpack <- function(request) {
  if (!is.list(request) ||
      !identical(as.character(request$schema %||% ""), "liberties.ssh.request") ||
      !identical(as.integer(request$version %||% 0L), 1L)) {
    .ls_stop("Unsupported direct-scheduler request envelope.")
  }
  payload_json <- as.character(request$payload_json %||% "")
  checksum <- tolower(as.character(request$sha256 %||% ""))
  if (length(payload_json) != 1L || is.na(payload_json) ||
      length(checksum) != 1L || !grepl("^[a-f0-9]{64}$", checksum)) {
    .ls_stop("Malformed direct-scheduler request envelope.")
  }
  actual <- unname(paste0(openssl::sha256(charToRaw(enc2utf8(payload_json)))))
  if (!identical(checksum, actual)) .ls_stop("Direct-scheduler request checksum mismatch.")
  tryCatch(
    jsonlite::fromJSON(payload_json, simplifyVector = FALSE),
    error = function(error) .ls_stop("Invalid direct-scheduler request JSON: ", conditionMessage(error))
  )
}

.ls_direct_response <- function(payload = NULL, error = NULL) {
  inner <- jsonlite::toJSON(
    if (is.null(error)) list(ok = TRUE, payload = payload) else
      list(ok = FALSE, error = conditionMessage(error)),
    auto_unbox = TRUE, null = "null", digits = 17, force = TRUE
  )
  list(
    schema = "liberties.ssh.response", version = 1L,
    payload_json = unname(as.character(inner)),
    sha256 = unname(paste0(openssl::sha256(charToRaw(enc2utf8(inner)))))
  )
}

.ls_direct_dispatch <- function(payload) {
  if (!is.list(payload) ||
      !identical(as.character(payload$schema %||% ""), "liberties.direct-scheduler") ||
      !identical(as.integer(payload$version %||% 0L), 1L)) {
    .ls_stop("Unsupported direct-scheduler payload.")
  }
  operation <- tolower(.ls_direct_scalar(payload$operation, "operation", empty = FALSE))
  if (!operation %in% c("authenticate", "capabilities", "submit", "list", "status",
                        "result", "logs", "cancel")) {
    .ls_stop("Unsupported direct-scheduler operation.")
  }
  config <- .ls_direct_scheduler_config(payload$config)
  key_file <- .ls_direct_storage_key(config$root, payload$storage_key)
  old_key <- getOption("LibeRties.storage_key", NULL)
  options(LibeRties.storage_key = readLines(key_file, n = 1L, warn = FALSE))
  on.exit(options(LibeRties.storage_key = old_key), add = TRUE)
  config$executor$storage_key_file <- key_file
  queue <- ls_local_queue(
    root = config$root, user = config$user, max_workers = config$max_workers,
    limits = config$limits, executor = config$executor
  )
  if (identical(operation, "authenticate")) {
    return(list(
      username = config$user, system_user = unname(Sys.info()[["user"]] %||% ""),
      backend = config$backend, queue_name = config$queue_name,
      root = queue$root, isolation = queue$isolation,
      package_version = as.character(utils::packageVersion("LibeRties"))
    ))
  }
  if (identical(operation, "capabilities")) {
    preflight <- .ls_scheduler_preflight(config$executor)
    return(c(ls_queue_capabilities(), list(
      scheduler = config$backend, scheduler_preflight = preflight,
      queue_root = queue$root, isolation = queue$isolation
    )))
  }
  if (identical(operation, "submit")) {
    job <- ls_job_from_wire(payload$job)
    id <- queue$submit(
      job, start = TRUE,
      idempotency_key = payload$idempotency_key %||% NULL
    )
    return(list(
      id = unname(as.character(id)), status = "queued",
      idempotent_replay = isTRUE(attr(id, "idempotent_replay", exact = TRUE))
    ))
  }
  queue$poll(start = TRUE)
  if (identical(operation, "list")) return(list(jobs = .ls_api_jobs(queue$list())))
  id <- .ls_safe_component(payload$id, "job id")
  if (identical(operation, "status")) return(queue$status(id))
  if (identical(operation, "result")) return(ls_result_to_wire(queue$result(id)))
  if (identical(operation, "logs")) {
    stream <- match.arg(as.character(payload$stream %||% "stdout"), c("stdout", "stderr"))
    return(list(lines = .ls_redact_logs(queue$logs(id, stream = stream))))
  }
  list(cancelled = isTRUE(queue$cancel(id)))
}

#' Serve one direct SSH scheduler request
#'
#' This is the fixed, non-interactive remote entry point used by LibeRation's
#' direct SSH scheduler client. It reads a checksummed typed JSON request from
#' standard input and writes one checksummed JSON response between stable
#' markers. It is not an interactive shell and never evaluates client code.
#'
#' @param input Input connection. The default reads standard input.
#' @param output Output connection. The default writes standard output.
#' @return The response object, invisibly.
#' @export
ls_direct_scheduler_cli <- function(input = file("stdin", open = "rb"),
                                    output = stdout()) {
  close_input <- !identical(input, stdin())
  if (isTRUE(close_input)) on.exit(try(close(input), silent = TRUE), add = TRUE)
  maximum <- 200 * 1024^2
  raw <- readBin(input, what = "raw", n = maximum + 1L)
  response <- tryCatch({
    if (length(raw) > maximum) .ls_stop("Direct-scheduler request exceeds 200 MB.")
    request <- jsonlite::fromJSON(rawToChar(raw), simplifyVector = FALSE)
    .ls_direct_response(.ls_direct_dispatch(.ls_direct_request_unpack(request)))
  }, error = function(error) .ls_direct_response(error = error))
  encoded <- jsonlite::toJSON(
    response, auto_unbox = TRUE, null = "null", digits = 17, force = TRUE
  )
  writeLines(c("LIBERTIES_SSH_RESPONSE_BEGIN", encoded,
               "LIBERTIES_SSH_RESPONSE_END"), con = output, useBytes = TRUE)
  invisible(response)
}
