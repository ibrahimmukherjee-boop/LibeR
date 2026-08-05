`%||%` <- function(x, y) if (is.null(x)) y else x

.ls_stop <- function(..., call. = FALSE) stop(..., call. = call.)

.ls_now <- function() {
  format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
}

.ls_safe_component <- function(x, what = "path component") {
  .liber_shared_component(
    x, what = what, max_length = 128L,
    error = function(message) {
      .ls_stop(
        "Invalid ", what,
        ": use 1-128 ASCII letters, digits, '.', '_', or '-'."
      )
    }
  )
}

.ls_default_root <- function() {
  configured <- Sys.getenv("LIBERTIES_ROOT", unset = "")
  if (nzchar(configured)) return(path.expand(configured))
  configured <- getOption("LibeRties.root", "")
  if (length(configured) == 1L && !is.na(configured) && nzchar(configured)) {
    return(path.expand(configured))
  }
  file.path(tools::R_user_dir("LibeRties", "data"), "queue")
}

.ls_ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    created <- dir.create(path, recursive = TRUE, showWarnings = FALSE)
    # Another submitter may have created the shared parent between the initial
    # existence check and dir.create(). Treat that as success, but still fail
    # closed when the path is absent (or is a non-directory filesystem entry).
    if (!isTRUE(created) && !dir.exists(path)) {
      .ls_stop("Unable to create directory: ", path)
    }
  }
  normalized <- normalizePath(path, winslash = "/", mustWork = TRUE)
  if (.Platform$OS.type != "windows") Sys.chmod(normalized, mode = "0700")
  normalized
}

.ls_worker_env <- function(job_dir) {
  keep <- c("PATH", "SystemRoot", "WINDIR", "TEMP", "TMP", "TMPDIR",
            "HOME", "USERPROFILE", "R_LIBS_USER", "R_LIBS_SITE")
  current <- Sys.getenv(keep, unset = NA_character_)
  current <- current[!is.na(current) & nzchar(current)]
  c(
    current, R_ENVIRON_USER = "", R_PROFILE_USER = "", R_HISTFILE = "",
    OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
    VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1",
    LIBER_JOB_DIR = normalizePath(job_dir, winslash = "/", mustWork = TRUE)
  )
}

.ls_resource_usage <- function(pid) {
  handle <- ps::ps_handle(as.integer(pid))
  descendants <- tryCatch(ps::ps_children(handle, recursive = TRUE),
                          error = function(error) list())
  handles <- c(list(handle), descendants)
  alive <- vapply(handles, function(value) {
    isTRUE(tryCatch(ps::ps_is_running(value), error = function(error) FALSE))
  }, logical(1))
  handles <- handles[alive]
  memory <- sum(vapply(handles, function(value) {
    tryCatch(as.numeric(ps::ps_memory_info(value)[["rss"]]), error = function(error) 0)
  }, numeric(1)), na.rm = TRUE)
  cpu <- sum(vapply(handles, function(value) {
    times <- tryCatch(ps::ps_cpu_times(value), error = function(error) NULL)
    if (is.null(times)) 0 else sum(as.numeric(times[c("user", "system")]), na.rm = TRUE)
  }, numeric(1)), na.rm = TRUE)
  list(
    memory_mb = memory / 1024^2,
    cpu_seconds = cpu,
    processes = length(handles)
  )
}

.ls_kill_process_tree <- function(pid) {
  handle <- tryCatch(ps::ps_handle(as.integer(pid)), error = function(error) NULL)
  if (is.null(handle)) return(invisible(FALSE))
  descendants <- tryCatch(ps::ps_children(handle, recursive = TRUE),
                          error = function(error) list())
  for (child in rev(descendants)) try(ps::ps_kill(child), silent = TRUE)
  try(ps::ps_kill(handle), silent = TRUE)
  invisible(TRUE)
}

.ls_pid_exists <- function(pid) {
  pid <- suppressWarnings(as.integer(pid %||% NA_integer_))
  if (length(pid) != 1L || is.na(pid) || pid <= 0L) return(FALSE)
  isTRUE(tryCatch(
    ps::ps_is_running(ps::ps_handle(pid)),
    error = function(error) FALSE
  ))
}

.ls_job_dir <- function(root, user, id) {
  user <- .ls_safe_component(user, "user id")
  id <- .ls_safe_component(id, "job id")
  root <- .ls_ensure_dir(root)
  candidate <- file.path(root, "users", user, "jobs", id)
  parent <- .ls_ensure_dir(dirname(candidate))
  path <- file.path(parent, basename(candidate))
  root_cmp <- if (.Platform$OS.type == "windows") tolower(root) else root
  path_cmp <- if (.Platform$OS.type == "windows") tolower(path) else path
  prefix <- paste0(root_cmp, "/")
  if (!startsWith(path_cmp, prefix)) .ls_stop("Resolved job path escaped the queue root.")
  path
}

.ls_idempotency_key <- function(value) {
  if (is.null(value) || !length(value) || !nzchar(as.character(value[[1L]]))) {
    return(NULL)
  }
  value <- enc2utf8(as.character(value))
  if (length(value) != 1L || is.na(value) || !nzchar(value) ||
      nchar(value, type = "bytes") > 200L || grepl("[[:cntrl:]]", value)) {
    .ls_stop("`idempotency_key` must be one non-empty value of at most 200 bytes without control characters.")
  }
  value
}

.ls_object_sha256 <- function(object) {
  unname(paste0(openssl::sha256(serialize(object, NULL, version = 3L))))
}

.ls_submission_lock <- function(root, user) {
  user <- .ls_safe_component(user, "user id")
  file.path(.ls_ensure_dir(file.path(root, "users", user)), ".submission.lock")
}

.ls_idempotency_path <- function(root, user, key) {
  user <- .ls_safe_component(user, "user id")
  key <- .ls_idempotency_key(key)
  if (is.null(key)) return(NULL)
  digest <- unname(paste0(openssl::sha256(charToRaw(key))))
  directory <- .ls_ensure_dir(file.path(root, "users", user, "idempotency"))
  file.path(directory, paste0(digest, ".rds"))
}

.ls_storage_key <- function(required = FALSE) {
  encoded <- Sys.getenv("LIBERTIES_STORAGE_KEY", unset = "")
  if (!nzchar(encoded)) encoded <- getOption("LibeRties.storage_key", "")
  if (!nzchar(encoded)) {
    key_file <- Sys.getenv("LIBERTIES_STORAGE_KEY_FILE", unset = "")
    if (nzchar(key_file) && file.exists(key_file)) {
      encoded <- tryCatch(
        readLines(key_file, n = 1L, warn = FALSE, encoding = "UTF-8"),
        error = function(error) ""
      )
    }
  }
  if (!nzchar(encoded)) {
    credential <- .ls_systemd_credential_path()
    if (nzchar(credential)) {
      encoded <- tryCatch(
        readLines(credential, n = 1L, warn = FALSE, encoding = "UTF-8"),
        error = function(error) ""
      )
    }
  }
  encoded <- trimws(as.character(encoded %||% ""))
  if (!nzchar(encoded)) {
    if (isTRUE(required)) .ls_stop("LIBERTIES_STORAGE_KEY is required for encrypted storage.")
    return(NULL)
  }
  if (length(encoded) != 1L || !grepl("^[A-Fa-f0-9]{64}$", encoded)) {
    .ls_stop("LIBERTIES_STORAGE_KEY must be exactly 64 hexadecimal characters (256 bits).")
  }
  bytes <- substring(encoded, seq.int(1L, 63L, by = 2L), seq.int(2L, 64L, by = 2L))
  as.raw(strtoi(bytes, base = 16L))
}

.ls_storage_wrap <- function(object) {
  key <- .ls_storage_key()
  if (is.null(key)) return(object)
  list(
    schema = "liberties.encrypted-rds", version = 1L,
    key_id = substr(.ls_token_hash(paste(sprintf("%02x", as.integer(key)), collapse = "")), 1L, 16L),
    payload = sodium::data_encrypt(serialize(object, NULL, version = 3L), key)
  )
}

.ls_storage_unwrap <- function(object) {
  if (!is.list(object) || !identical(object$schema %||% "", "liberties.encrypted-rds")) {
    if (!is.null(.ls_storage_key())) {
      .ls_stop(
        "Refusing a plaintext LibeRties record while encrypted storage is active. ",
        "Migrate legacy records with the storage key temporarily unset, then rewrite them."
      )
    }
    return(object)
  }
  if (!identical(as.integer(object$version), 1L) || !is.raw(object$payload)) {
    .ls_stop("Encrypted LibeRties record is malformed.")
  }
  key <- .ls_storage_key(required = TRUE)
  tryCatch(
    unserialize(sodium::data_decrypt(object$payload, key)),
    error = function(error) .ls_stop("Unable to authenticate or decrypt LibeRties storage.")
  )
}

.ls_pid_matches <- function(pid, pid_started, tolerance = 1) {
  pid <- suppressWarnings(as.integer(pid %||% NA_integer_))
  expected <- suppressWarnings(as.numeric(pid_started %||% NA_real_))
  if (is.na(pid) || pid <= 0L || !is.finite(expected)) return(FALSE)
  alive <- .ls_pid_exists(pid)
  if (!alive) return(FALSE)
  actual <- tryCatch(
    as.numeric(ps::ps_create_time(ps::ps_handle(pid))),
    error = function(error) NA_real_
  )
  is.finite(actual) && abs(actual - expected) < tolerance
}

.ls_atomic_save_rds <- function(object, path) {
  .liber_shared_atomic_publish(
    path,
    writer = function(temporary) {
      saveRDS(.ls_storage_wrap(object), temporary, version = 3)
    },
    prefix = "write-", fileext = ".rds",
    error = function(message) .ls_stop(message)
  )
}

.ls_read_rds <- function(path, attempts = 4L, warn_recovery = TRUE) {
  .liber_shared_durable_read(
    path,
    reader = function(candidate) {
      .ls_storage_unwrap(suppressWarnings(readRDS(candidate)))
    },
    attempts = attempts, delay = 0.01, warn_recovery = warn_recovery,
    error = function(message) .ls_stop(message)
  )
}

.ls_meta_path <- function(job_dir) file.path(job_dir, "metadata.rds")
.ls_payload_path <- function(job_dir) file.path(job_dir, "payload.rds")
.ls_result_path <- function(job_dir) file.path(job_dir, "result.rds")
.ls_log_path <- function(job_dir, stream) file.path(job_dir, paste0(stream, ".log"))
.ls_log_archive_path <- function(job_dir, stream) file.path(job_dir, paste0(stream, ".log.rds"))

.ls_seal_job_logs <- function(job_dir) {
  if (is.null(.ls_storage_key())) return(invisible(FALSE))
  changed <- FALSE
  for (stream in c("stdout", "stderr")) {
    path <- .ls_log_path(job_dir, stream)
    archive <- .ls_log_archive_path(job_dir, stream)
    if (!file.exists(path)) next
    lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
    .ls_atomic_save_rds(lines, archive)
    verified <- .ls_read_rds(archive)
    if (!identical(as.character(verified), as.character(lines))) {
      .ls_stop("Unable to verify encrypted ", stream, " log archive.")
    }
    unlink(path, force = TRUE)
    changed <- TRUE
  }
  error_path <- file.path(job_dir, "error.txt")
  if (file.exists(error_path)) {
    error <- readLines(error_path, warn = FALSE, encoding = "UTF-8")
    .ls_atomic_save_rds(error, file.path(job_dir, "error.txt.rds"))
    unlink(error_path, force = TRUE)
    changed <- TRUE
  }
  invisible(changed)
}

.ls_read_job_log <- function(job_dir, stream) {
  archive <- .ls_log_archive_path(job_dir, stream)
  if (file.exists(archive)) return(as.character(.ls_read_rds(archive)))
  path <- .ls_log_path(job_dir, stream)
  if (!file.exists(path)) return(character())
  readLines(path, warn = FALSE, encoding = "UTF-8")
}

.ls_read_meta <- function(job_dir) {
  .ls_read_rds(
    .ls_meta_path(job_dir),
    warn_recovery = !dir.exists(file.path(job_dir, ".metadata.lock"))
  )
}
.ls_write_meta <- function(job_dir, metadata) {
  metadata$updated <- .ls_now()
  .ls_atomic_save_rds(metadata, .ls_meta_path(job_dir))
}

.ls_with_job_lock <- function(job_dir, operation, timeout = 5, stale_after = 1) {
  lock <- file.path(job_dir, ".metadata.lock")
  .liber_shared_with_lock(
    lock, operation, timeout = timeout, stale_after = stale_after,
    error = function(message) .ls_stop(message)
  )
}

.ls_update_meta <- function(job_dir, update, allowed_status = NULL) {
  .ls_with_job_lock(job_dir, function() {
    metadata <- .ls_read_meta(job_dir)
    if (!is.null(allowed_status) && !metadata$status %in% allowed_status) return(metadata)
    for (name in names(update)) metadata[[name]] <- update[[name]]
    .ls_write_meta(job_dir, metadata)
    metadata
  })
}

.ls_md5 <- function(path) unname(tools::md5sum(path)[[1L]])

.ls_sha256 <- function(path) {
  connection <- file(path, open = "rb")
  on.exit(close(connection), add = TRUE)
  unname(paste0(openssl::sha256(connection)))
}

.ls_digest_matches <- function(path, metadata, prefix) {
  sha_name <- paste0(prefix, "_sha256")
  md5_name <- paste0(prefix, "_md5")
  expected_sha <- as.character(metadata[[sha_name]] %||% "")
  if (nzchar(expected_sha)) return(identical(.ls_sha256(path), expected_sha))
  expected_md5 <- as.character(metadata[[md5_name]] %||% "")
  nzchar(expected_md5) && identical(.ls_md5(path), expected_md5)
}

.ls_random_hex <- function(bytes) {
  paste(sprintf("%02x", as.integer(openssl::rand_bytes(as.integer(bytes)))), collapse = "")
}

.ls_new_id <- function() {
  paste0(format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"), "-", .ls_random_hex(16L))
}

.ls_terminal <- function(status) status %in% c("completed", "failed", "cancelled")

.ls_empty_jobs <- function() {
  data.frame(
    id = character(), user = character(), type = character(), label = character(),
    status = character(), submitted = character(), started = character(),
    finished = character(), stringsAsFactors = FALSE
  )
}
