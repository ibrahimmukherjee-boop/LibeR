liber_validation_configure_rtools <- function(root = NULL) {
  if (.Platform$OS.type != "windows") return(invisible(NULL))

  candidates <- unique(Filter(nzchar, c(
    Sys.getenv("RTOOLS45_HOME"), Sys.getenv("RTOOLS_HOME"), "C:/rtools45"
  )))
  selected <- candidates[vapply(candidates, function(path) {
    file.exists(file.path(
      path, "x86_64-w64-mingw32.static.posix", "bin", "gcc.exe"
    ))
  }, logical(1))]
  if (!length(selected)) return(invisible(NULL))

  selected <- normalizePath(selected[[1L]], winslash = "/", mustWork = TRUE)
  tool_paths <- normalizePath(c(
    file.path(selected, "x86_64-w64-mingw32.static.posix", "bin"),
    file.path(selected, "usr", "bin")
  ), winslash = "/", mustWork = TRUE)
  settings <- c(
    PATH = paste(c(tool_paths, Sys.getenv("PATH")), collapse = .Platform$path.sep)
  )
  makevars <- if (!is.null(root)) file.path(root, "tools", "Makevars.rtools45") else ""
  if (nzchar(makevars) && file.exists(makevars)) {
    settings[["R_MAKEVARS_USER"]] <- normalizePath(
      makevars, winslash = "/", mustWork = TRUE
    )
  }
  do.call(Sys.setenv, as.list(settings))
  invisible(list(root = selected, paths = tool_paths, makevars = makevars))
}

liber_validation_manifest <- function(root) {
  path <- file.path(root, "ecosystem.json")
  if (!file.exists(path)) stop("Missing ecosystem manifest: ", path, call. = FALSE)
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

liber_validation_assert_repository_hygiene <- function(root) {
  tracked <- suppressWarnings(system2(
    "git", c("-C", shQuote(root), "ls-files"), stdout = TRUE, stderr = FALSE
  ))
  status <- attr(tracked, "status")
  if (!is.null(status) && status != 0L) {
    stop("Unable to inspect tracked repository paths.", call. = FALSE)
  }
  tracked <- chartr("\\", "/", tracked)
  forbidden <- tracked[grepl("\\.lst$", tracked, ignore.case = TRUE)]
  if (length(forbidden)) {
    stop(
      "Raw NONMEM listing files must not be tracked or released:\n",
      paste(forbidden, collapse = "\n"),
      "\nPublish only derived numerical validation evidence.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

liber_validation_option <- function(name, default = NULL,
                                    args = commandArgs(trailingOnly = TRUE),
                                    occurrence = c("last", "first")) {
  occurrence <- match.arg(occurrence)
  prefix <- paste0("--", name, "=")
  matches <- args[startsWith(args, prefix)]
  if (!length(matches)) return(default)
  index <- if (identical(occurrence, "last")) length(matches) else 1L
  sub(prefix, "", matches[[index]], fixed = TRUE)
}

liber_validation_flag <- function(name, default = FALSE,
                                  args = commandArgs(trailingOnly = TRUE)) {
  positive <- paste0("--", name)
  negative <- paste0("--no-", name)
  positive_index <- match(positive, args, nomatch = 0L)
  negative_index <- match(negative, args, nomatch = 0L)
  if (!positive_index && !negative_index) return(isTRUE(default))
  if (!negative_index) return(TRUE)
  if (!positive_index) return(FALSE)
  positive_index > negative_index
}

liber_validation_split_option <- function(value, uppercase = FALSE) {
  values <- trimws(strsplit(as.character(value), ",", fixed = TRUE)[[1L]])
  values <- values[nzchar(values)]
  if (isTRUE(uppercase)) toupper(values) else values
}

liber_validation_output_directory <- function(root, value, default) {
  path <- as.character(if (is.null(value)) default else value)[[1L]]
  if (!grepl("^([A-Za-z]:)?[/\\\\]", path)) path <- file.path(root, path)
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

liber_validation_write_evidence <- function(
    output, comparisons = NULL, coverage = NULL, summary = NULL,
    provenance = NULL, report = NULL) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Validation evidence writing requires jsonlite.", call. = FALSE)
  }
  output <- normalizePath(output, winslash = "/", mustWork = FALSE)
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  publish <- function(path, writer) {
    temporary <- tempfile(
      paste0(".", basename(path), "-"), tmpdir = dirname(path), fileext = ".tmp"
    )
    backup <- paste0(path, ".previous")
    on.exit(unlink(temporary, force = TRUE), add = TRUE)
    writer(temporary)
    had_previous <- file.exists(path)
    if (file.exists(backup)) unlink(backup, force = TRUE)
    if (had_previous && !file.rename(path, backup)) {
      stop("Unable to rotate validation evidence: ", path, call. = FALSE)
    }
    if (!file.rename(temporary, path)) {
      if (had_previous && file.exists(backup)) file.rename(backup, path)
      stop("Unable to atomically publish validation evidence: ", path, call. = FALSE)
    }
    if (file.exists(backup)) unlink(backup, force = TRUE)
    invisible(path)
  }
  if (!is.null(comparisons)) publish(
    file.path(output, "comparisons.csv"),
    function(path) utils::write.csv(comparisons, path, row.names = FALSE, na = "")
  )
  if (!is.null(coverage)) publish(
    file.path(output, "coverage.csv"),
    function(path) utils::write.csv(coverage, path, row.names = FALSE, na = "")
  )
  write_json <- function(value, filename) publish(
    file.path(output, filename),
    function(path) jsonlite::write_json(
      value, path, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = 17
    )
  )
  if (!is.null(summary)) write_json(summary, "summary.json")
  if (!is.null(provenance)) write_json(provenance, "provenance.json")
  if (!is.null(report)) publish(
    file.path(output, "REPORT.md"),
    function(path) writeLines(enc2utf8(as.character(report)), path, useBytes = TRUE)
  )
  invisible(normalizePath(output, winslash = "/", mustWork = TRUE))
}

liber_validation_package_version <- function(package, library) {
  description <- suppressWarnings(tryCatch(
    utils::packageDescription(package, lib.loc = library),
    error = function(error) NULL
  ))
  if (!is.list(description) || length(description[["Version"]]) != 1L) {
    return(NA_character_)
  }
  as.character(description[["Version"]])
}

liber_validation_git <- function(root) {
  run_git <- function(args) {
    output <- suppressWarnings(system2(
      "git", c("-C", shQuote(root), args), stdout = TRUE, stderr = FALSE
    ))
    status <- attr(output, "status")
    if (!is.null(status) && status != 0L) return("")
    paste(output, collapse = "\n")
  }
  commit <- trimws(run_git(c("rev-parse", "HEAD")))
  status <- run_git(c("status", "--porcelain=v1", "--untracked-files=all"))
  status_lines <- if (nzchar(status)) strsplit(status, "\n", fixed = TRUE)[[1L]] else character()
  untracked_status <- status_lines[startsWith(status_lines, "?? ")]
  tracked_status <- status_lines[!startsWith(status_lines, "?? ")]
  changed_paths <- unique(substring(status_lines, 4L))
  changed_paths <- changed_paths[nzchar(changed_paths)]
  changed_paths <- sort(chartr("\\", "/", changed_paths), method = "radix")
  changed_records <- vapply(changed_paths, function(relative) {
    path <- file.path(root, relative)
    if (!file.exists(path)) return("<deleted>")
    if (dir.exists(path)) return("<directory>")
    liber_validation_sha256(path)
  }, character(1), USE.NAMES = FALSE)
  difference_material <- paste(changed_paths, changed_records, sep = "\t", collapse = "\n")
  difference_hash <- if (length(changed_paths)) {
    paste0(openssl::sha256(charToRaw(enc2utf8(difference_material))))
  } else NA_character_
  list(
    commit = if (nzchar(commit)) commit else NA_character_,
    tracked_worktree_clean = !length(tracked_status),
    tracked_status = tracked_status,
    untracked_status = untracked_status,
    tracked_diff_sha256 = difference_hash
  )
}

liber_validation_sha256 <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  connection <- file(path, "rb")
  on.exit(close(connection), add = TRUE)
  paste0(openssl::sha256(readBin(connection, "raw", n = file.info(path)$size)))
}

liber_validation_library_name <- function(root) {
  manifest <- liber_validation_manifest(root)
  git <- liber_validation_git(root)
  commit <- if (is.na(git$commit)) "no-git" else substr(git$commit, 1L, 12L)
  if (!isTRUE(git$tracked_worktree_clean)) {
    commit <- paste0(commit, "-dirty-", substr(git$tracked_diff_sha256, 1L, 12L))
  }
  paste0(gsub("[^A-Za-z0-9_.-]", "-", manifest$release), "-", commit)
}

liber_validation_library <- function(root, packages,
                                     library = Sys.getenv("LIBER_VALIDATION_LIBRARY", ""),
                                     allow_release_library = FALSE) {
  manifest <- liber_validation_manifest(root)
  packages <- unique(as.character(packages))
  unknown <- setdiff(packages, names(manifest$packages))
  if (length(unknown)) {
    stop("Validation requested packages absent from ecosystem.json: ",
         paste(unknown, collapse = ", "), call. = FALSE)
  }
  canonical <- file.path(
    root, ".validation-libraries", liber_validation_library_name(root)
  )
  candidates <- Filter(nzchar, c(library, canonical))
  if (isTRUE(allow_release_library)) {
    candidates <- c(candidates, file.path(root, ".release-buildlib"))
  }
  candidates <- unique(candidates[dir.exists(candidates)])
  if (!length(candidates)) {
    stop(
      "No versioned validation library is available. Run `Rscript tools/create-validation-library.R` ",
      "or set LIBER_VALIDATION_LIBRARY to an exact, isolated library.", call. = FALSE
    )
  }
  selected <- normalizePath(candidates[[1L]], winslash = "/", mustWork = TRUE)
  expected <- vapply(manifest$packages[packages], `[[`, character(1), "version")
  installed <- vapply(
    packages, liber_validation_package_version, character(1),
    library = selected
  )
  mismatch <- is.na(installed) | installed != expected
  if (any(mismatch)) {
    detail <- paste0(packages[mismatch], " expected ", expected[mismatch],
                     ", found ", installed[mismatch])
    stop("Validation library version mismatch: ", paste(detail, collapse = "; "),
         call. = FALSE)
  }
  marker <- file.path(selected, "LIBER_VALIDATION_LIBRARY.json")
  if (!file.exists(marker) && !nzchar(library) && !isTRUE(allow_release_library)) {
    stop("The selected library is not an immutable LibeR validation library: ", selected,
         call. = FALSE)
  }
  marker_value <- if (file.exists(marker)) {
    jsonlite::read_json(marker, simplifyVector = FALSE)
  } else {
    NULL
  }
  if (!is.null(marker_value)) {
    optional_string <- function(value) {
      if (is.null(value) || !length(value) || is.na(value[[1L]])) NA_character_
      else as.character(value[[1L]])
    }
    git <- liber_validation_git(root)
    expected_marker <- list(
      release = as.character(manifest$release),
      git_commit = optional_string(git$commit),
      tracked_diff_sha256 = optional_string(git$tracked_diff_sha256),
      source_manifest_sha256 = liber_validation_sha256(file.path(root, "ecosystem.json"))
    )
    actual_marker <- list(
      release = optional_string(marker_value$release),
      git_commit = optional_string(marker_value$git_commit),
      tracked_diff_sha256 = optional_string(marker_value$tracked_diff_sha256),
      source_manifest_sha256 = optional_string(marker_value$source_manifest_sha256)
    )
    equal_optional <- function(left, right) {
      (is.na(left) && is.na(right)) || identical(left, right)
    }
    marker_ok <- vapply(
      names(expected_marker),
      function(field) equal_optional(actual_marker[[field]], expected_marker[[field]]),
      logical(1)
    )
    if (!all(marker_ok)) {
      stop(
        "Validation library provenance does not match the current source (",
        paste(names(marker_ok)[!marker_ok], collapse = ", "),
        "). Rebuild it with `Rscript tools/create-validation-library.R --source`.",
        call. = FALSE
      )
    }
  }
  .libPaths(unique(c(selected, .libPaths())))
  list(
    path = selected,
    packages = stats::setNames(as.list(installed), packages),
    expected = stats::setNames(as.list(expected), packages),
    marker = marker_value
  )
}

liber_validation_provenance <- function(root, packages, library,
                                        inputs = character(), seeds = list(),
                                        tolerances = list(), dependencies = character(),
                                        metadata = list(), output = NULL) {
  manifest_path <- file.path(root, "ecosystem.json")
  git <- liber_validation_git(root)
  input_paths <- unique(normalizePath(inputs[file.exists(inputs)], winslash = "/",
                                     mustWork = TRUE))
  input_records <- lapply(input_paths, function(path) list(
    path = path,
    bytes = unname(file.info(path)$size),
    sha256 = liber_validation_sha256(path)
  ))
  names(input_records) <- basename(input_paths)
  dependency_names <- unique(c(packages, dependencies))
  dependency_versions <- vapply(dependency_names, function(package) {
    if (!requireNamespace(package, quietly = TRUE)) return(NA_character_)
    as.character(utils::packageVersion(package))
  }, character(1))
  value <- list(
    schema = "liber.validation-evidence/1",
    created_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
    release = liber_validation_manifest(root)$release,
    ecosystem_manifest_sha256 = liber_validation_sha256(manifest_path),
    git = git,
    validation_library = normalizePath(library, winslash = "/", mustWork = TRUE),
    packages = stats::setNames(as.list(dependency_versions[packages]), packages),
    dependencies = stats::setNames(as.list(dependency_versions[dependencies]), dependencies),
    r = list(version = R.version.string, platform = R.version$platform),
    system = as.list(Sys.info()),
    seeds = seeds,
    tolerances = tolerances,
    inputs = input_records,
    metadata = metadata
  )
  if (!is.null(output)) {
    dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
    temporary <- tempfile("validation-provenance-", tmpdir = dirname(output), fileext = ".json")
    jsonlite::write_json(value, temporary, auto_unbox = TRUE, pretty = TRUE,
                         null = "null", digits = 17)
    if (!file.rename(temporary, output)) {
      unlink(temporary)
      stop("Unable to publish validation provenance: ", output, call. = FALSE)
    }
  }
  value
}
