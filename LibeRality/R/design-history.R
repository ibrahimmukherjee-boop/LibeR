.lity_design_store_root <- function(workspace = NULL, create = FALSE) {
  workspace <- workspace %||% .lity_default_liberation_workspace()
  base <- if (inherits(workspace, "nm_workspace")) {
    workspace$path
  } else {
    path.expand(as.character(workspace)[[1L]])
  }
  if (!nzchar(base)) {
    .lity_stop("A workspace path is required for design history.")
  }
  root <- file.path(base, "liberality", "designs")
  if (isTRUE(create) && !dir.exists(root) &&
      !dir.create(root, recursive = TRUE, showWarnings = FALSE)) {
    .lity_stop("Unable to create the LibeRality design store at ", root, ".")
  }
  normalizePath(root, winslash = "/", mustWork = FALSE)
}

.lity_design_store_component <- function(value, name) {
  value <- as.character(value %||% "")[[1L]]
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", value)) {
    .lity_stop("Invalid ", name, ".")
  }
  value
}

.lity_design_store_publish <- function(value, path) {
  directory <- dirname(path)
  if (!dir.exists(directory) &&
      !dir.create(directory, recursive = TRUE, showWarnings = FALSE)) {
    .lity_stop("Unable to create design-history directory ", directory, ".")
  }
  temporary <- tempfile(".lity-write-", tmpdir = directory, fileext = ".rds")
  on.exit(if (file.exists(temporary)) unlink(temporary, force = TRUE), add = TRUE)
  saveRDS(value, temporary, version = 3)
  if (!file.rename(temporary, path)) {
    .lity_stop("Unable to publish design-history record ", basename(path), ".")
  }
  if (.Platform$OS.type != "windows") Sys.chmod(path, mode = "0600")
  invisible(path)
}

.lity_design_history_empty <- function() {
  data.frame(
    series_id = character(), series_name = character(),
    version_id = character(), version_number = integer(),
    label = character(), created = character(), description = character(),
    design_id = character(), design_hash = character(),
    parent_version = character(), model_name = character(),
    stringsAsFactors = FALSE
  )
}

#' List saved LibeRality design versions
#'
#' Design history is stored beside the shared LibeR workspace, separately from
#' LibeRation model projects. Every row identifies one immutable design
#' version.
#'
#' @param workspace LibeR workspace path or `nm_workspace`.
#' @return A data frame ordered by most recently saved version.
#' @export
lity_design_history <- function(workspace = NULL) {
  root <- .lity_design_store_root(workspace, create = FALSE)
  record_root <- file.path(root, "records")
  if (!dir.exists(record_root)) return(.lity_design_history_empty())
  files <- list.files(
    record_root, pattern = "\\.rds$", recursive = TRUE, full.names = TRUE
  )
  records <- lapply(files, function(path) {
    tryCatch(readRDS(path), error = function(error) NULL)
  })
  records <- Filter(function(record) {
    is.list(record) &&
      identical(record$schema, "liberality.design-version") &&
      identical(as.integer(record$version), 1L)
  }, records)
  if (!length(records)) return(.lity_design_history_empty())
  output <- do.call(rbind, lapply(records, function(record) {
    data.frame(
      series_id = as.character(record$series_id),
      series_name = as.character(record$series_name),
      version_id = as.character(record$version_id),
      version_number = as.integer(record$version_number),
      label = as.character(record$label),
      created = as.character(record$created),
      description = as.character(record$description %||% ""),
      design_id = as.character(record$design_id),
      design_hash = as.character(record$design_hash),
      parent_version = as.character(record$parent_version %||% ""),
      model_name = as.character(record$model_name %||% ""),
      stringsAsFactors = FALSE
    )
  }))
  output[order(output$created, decreasing = TRUE), , drop = FALSE]
}

#' Save an immutable LibeRality design version
#'
#' @param design A validated `lity_design`.
#' @param workspace LibeR workspace path or `nm_workspace`.
#' @param series_id Existing design-series identifier. Omit to start a new
#'   design.
#' @param series_name Human-readable design-series name.
#' @param label Optional version label; blank labels become `Version 001`,
#'   `Version 002`, and so on.
#' @return The saved version record, invisibly.
#' @export
lity_design_version_save <- function(
    design, workspace = NULL, series_id = NULL,
    series_name = NULL, label = NULL) {
  validation <- lity_validate(design)
  if (!validation$valid) {
    .lity_stop(
      "Cannot save an invalid design: ",
      paste(validation$errors, collapse = "; ")
    )
  }
  root <- .lity_design_store_root(workspace, create = TRUE)
  history <- lity_design_history(workspace)
  if (is.null(series_id) || !nzchar(as.character(series_id)[[1L]])) {
    series_id <- .lity_id("design-series")
  }
  series_id <- .lity_design_store_component(series_id, "design-series id")
  existing <- history[history$series_id == series_id, , drop = FALSE]
  series_name <- trimws(as.character(
    series_name %||%
      if (nrow(existing)) existing$series_name[[1L]] else design$name
  ))
  if (length(series_name) != 1L || is.na(series_name) || !nzchar(series_name)) {
    .lity_stop("`series_name` must be one non-empty string.")
  }
  version_number <- if (nrow(existing)) {
    max(existing$version_number) + 1L
  } else {
    1L
  }
  label <- trimws(as.character(label %||% ""))
  if (length(label) != 1L || is.na(label)) {
    .lity_stop("`label` must be one character value.")
  }
  if (!nzchar(label)) label <- sprintf("Version %03d", version_number)
  version_id <- .lity_id("design-version")
  version_id <- .lity_design_store_component(version_id, "design-version id")
  created <- .lity_now()
  parent <- if (nrow(existing)) {
    existing$version_id[[which.max(existing$version_number)]]
  } else {
    ""
  }
  model_name <- tryCatch(
    .lity_model_name(design$model), error = function(error) ""
  )
  record <- list(
    schema = "liberality.design-version", version = 1L,
    series_id = series_id, series_name = series_name,
    version_id = version_id, version_number = version_number,
    label = label, created = created, description = design$description,
    design_id = design$id, design_hash = .lity_hash(design),
    parent_version = parent, model_name = model_name
  )
  object_path <- file.path(root, "objects", series_id, paste0(version_id, ".rds"))
  record_path <- file.path(root, "records", series_id, paste0(version_id, ".rds"))
  .lity_design_store_publish(design, object_path)
  .lity_design_store_publish(record, record_path)
  invisible(record)
}

#' Load a saved LibeRality design version
#'
#' @param workspace LibeR workspace path or `nm_workspace`.
#' @param series_id Design-series identifier.
#' @param version_id Version identifier, version label, version number, or
#'   `"latest"`.
#' @return A validated `lity_design`.
#' @export
lity_design_version_load <- function(
    workspace = NULL, series_id, version_id = "latest") {
  series_id <- .lity_design_store_component(series_id, "design-series id")
  history <- lity_design_history(workspace)
  candidates <- history[history$series_id == series_id, , drop = FALSE]
  if (!nrow(candidates)) .lity_stop("Unknown saved design: ", series_id, ".")
  requested <- as.character(version_id %||% "latest")[[1L]]
  if (identical(tolower(requested), "latest")) {
    selected <- candidates[which.max(candidates$version_number), , drop = FALSE]
  } else if (grepl("^[0-9]+$", requested)) {
    selected <- candidates[candidates$version_number == as.integer(requested), ,
                           drop = FALSE]
  } else {
    selected <- candidates[
      candidates$version_id == requested | candidates$label == requested,
      , drop = FALSE
    ]
  }
  if (nrow(selected) != 1L) {
    .lity_stop("Saved design version is missing or ambiguous: ", requested, ".")
  }
  root <- .lity_design_store_root(workspace, create = FALSE)
  path <- file.path(
    root, "objects", series_id, paste0(selected$version_id[[1L]], ".rds")
  )
  if (!file.exists(path)) {
    .lity_stop("Saved design object is missing: ", selected$version_id[[1L]], ".")
  }
  design <- readRDS(path)
  validation <- lity_validate(design)
  if (!validation$valid) {
    .lity_stop(
      "Saved design is invalid: ", paste(validation$errors, collapse = "; ")
    )
  }
  design
}

.lity_design_history_payload <- function(
    history, current_series = "", current_version = "", dirty = TRUE) {
  list(
    records = .lity_rows(history),
    currentSeries = as.character(current_series %||% ""),
    currentVersion = as.character(current_version %||% ""),
    dirty = isTRUE(dirty)
  )
}
