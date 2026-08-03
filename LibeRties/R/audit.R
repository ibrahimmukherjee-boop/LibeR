.ls_audit_path <- function(root) {
  file.path(.ls_ensure_dir(file.path(root, "server")), "audit.rds")
}

.ls_audit_event_dir <- function(root) {
  .ls_ensure_dir(file.path(root, "server", "audit-events"))
}

.ls_audit_mirror <- function() {
  path <- Sys.getenv("LIBERTIES_AUDIT_MIRROR", unset = "")
  if (!nzchar(path)) path <- getOption("LibeRties.audit_mirror", "")
  path <- trimws(as.character(path %||% ""))
  if (length(path) != 1L || is.na(path) || !nzchar(path)) return(NULL)
  .ls_ensure_dir(path.expand(path))
}

.ls_audit_hash <- function(value) {
  unname(paste0(openssl::sha256(serialize(value, NULL, version = 3L))))
}

.ls_audit_recover_journal <- function(root, audit) {
  directory <- file.path(root, "server", "audit-events")
  if (!dir.exists(directory)) return(audit)
  files <- sort(list.files(
    directory, pattern = "^[0-9]{12}-.*[.]rds$", full.names = TRUE
  ))
  if (!length(files)) return(audit)
  for (path in files) {
    event <- .ls_read_rds(path)
    sequence <- suppressWarnings(as.integer(event$sequence %||% NA_integer_))
    if (!is.finite(sequence) || sequence < 1L) {
      .ls_stop("An append-only audit journal event has an invalid sequence.")
    }
    supplied <- event$hash %||% ""
    unhashed <- event
    unhashed$hash <- NULL
    previous <- if (sequence == 1L) "GENESIS" else if (
      sequence - 1L <= length(audit$events)
    ) audit$events[[sequence - 1L]]$hash else ""
    if (!nzchar(supplied) || !identical(supplied, .ls_audit_hash(unhashed)) ||
        !identical(event$previous, previous)) {
      .ls_stop("The append-only audit journal failed hash-chain verification.")
    }
    if (sequence <= length(audit$events)) {
      if (!identical(event, audit$events[[sequence]])) {
        .ls_stop("The audit index and append-only journal disagree.")
      }
    } else if (sequence == length(audit$events) + 1L) {
      audit$events[[sequence]] <- event
    } else {
      .ls_stop("The append-only audit journal contains a sequence gap.")
    }
  }
  audit
}

.ls_audit_append <- function(root, action, username = "", details = list()) {
  path <- .ls_audit_path(root)
  lock <- paste0(path, ".lock")
  started <- proc.time()[["elapsed"]]
  repeat {
    if (dir.create(lock, showWarnings = FALSE)) break
    if (proc.time()[["elapsed"]] - started > 5) .ls_stop("Timed out acquiring audit lock.")
    Sys.sleep(0.01)
  }
  on.exit(unlink(lock, recursive = TRUE, force = TRUE), add = TRUE)
  audit <- if (file.exists(path)) .ls_read_rds(path) else list(
    schema = "liberties.audit", version = 1L, events = list()
  )
  audit <- .ls_audit_recover_journal(root, audit)
  previous <- if (length(audit$events)) audit$events[[length(audit$events)]]$hash else "GENESIS"
  event <- list(
    sequence = length(audit$events) + 1L,
    id = .ls_new_id(), at = .ls_now(), action = as.character(action),
    username = as.character(username %||% ""), details = details,
    previous = previous
  )
  event$hash <- .ls_audit_hash(event)
  event_name <- sprintf("%012d-%s", event$sequence, event$id)
  journal_path <- file.path(.ls_audit_event_dir(root), paste0(event_name, ".rds"))
  if (file.exists(journal_path)) .ls_stop("Audit event journal collision.")
  .ls_atomic_save_rds(event, journal_path)

  mirror <- .ls_audit_mirror()
  if (!is.null(mirror)) {
    mirror_path <- file.path(mirror, paste0(event_name, ".json"))
    tryCatch({
      if (file.exists(mirror_path)) .ls_stop("External audit mirror event already exists.")
      .liber_shared_atomic_publish(
        mirror_path,
        writer = function(temporary) jsonlite::write_json(
          event, temporary, auto_unbox = TRUE, null = "null", digits = 17,
          pretty = FALSE
        ),
        prefix = "audit-", fileext = ".json",
        error = function(message) .ls_stop(message)
      )
    }, error = function(error) {
      warning(
        "The local audit event was committed but the configured external mirror failed: ",
        conditionMessage(error), call. = FALSE
      )
    })
  }
  audit$events[[length(audit$events) + 1L]] <- event
  .ls_atomic_save_rds(audit, path)
  invisible(event)
}

#' Read and verify the LibeRties administration audit chain
#'
#' @param root LibeRties server root.
#' @return A data frame with a logical `valid` attribute.
#' @export
ls_audit_read <- function(root = .ls_default_root()) {
  path <- .ls_audit_path(root)
  if (!file.exists(path)) return(structure(data.frame(), valid = TRUE))
  audit <- .ls_read_rds(path)
  valid <- is.list(audit) && identical(audit$schema %||% "", "liberties.audit")
  previous <- "GENESIS"
  if (valid) {
    for (stored in audit$events) {
      supplied <- stored$hash
      event <- stored
      event$hash <- NULL
      valid <- valid && identical(event$previous, previous) &&
        identical(supplied, .ls_audit_hash(event))
      previous <- supplied
    }
  }
  journal_valid <- TRUE
  journal_dir <- file.path(root, "server", "audit-events")
  journal_files <- if (dir.exists(journal_dir)) {
    sort(list.files(journal_dir, pattern = "^[0-9]{12}-.*[.]rds$", full.names = TRUE))
  } else character()
  if (length(journal_files)) {
    for (journal_file in journal_files) {
      journal <- tryCatch(.ls_read_rds(journal_file), error = function(error) NULL)
      sequence <- suppressWarnings(as.integer(sub("^([0-9]{12}).*$", "\\1", basename(journal_file))))
      indexed <- if (is.finite(sequence) && sequence >= 1L &&
                     sequence <= length(audit$events)) audit$events[[sequence]] else NULL
      journal_valid <- journal_valid && is.list(journal) && is.list(indexed) &&
        identical(journal, indexed) && identical(journal$sequence, sequence)
    }
  }
  valid <- valid && journal_valid
  rows <- if (!length(audit$events %||% list())) data.frame() else do.call(rbind, lapply(
    audit$events, function(event) data.frame(
      id = event$id, at = event$at, action = event$action,
      username = event$username, hash = event$hash, stringsAsFactors = FALSE
    )
  ))
  structure(
    rows, valid = valid, journal_valid = journal_valid,
    journal_events = length(journal_files)
  )
}
