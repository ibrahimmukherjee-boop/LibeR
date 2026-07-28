# Install one exact LibeR compatibility set from a consolidated GitHub release.
#
# From a trusted R session:
# source("https://raw.githubusercontent.com/svdijkman/LibeR/main/tools/install-ecosystem.R")
# liber_install()

.liber_configure_repositories <- function() {
  mirror <- Sys.getenv("LIBER_CRAN_MIRROR", "https://cloud.r-project.org")
  if (!nzchar(mirror) || !grepl("^https?://", mirror, ignore.case = TRUE)) {
    stop(
      "LIBER_CRAN_MIRROR must be a non-empty HTTP(S) URL.",
      call. = FALSE
    )
  }
  repositories <- getOption("repos")
  if (is.null(repositories) || !length(repositories)) {
    repositories <- c(CRAN = mirror)
  } else {
    invalid <- is.na(repositories) | !nzchar(repositories) |
      repositories == "@CRAN@"
    repositories[invalid] <- mirror
    if (is.null(names(repositories))) {
      names(repositories) <- rep("", length(repositories))
    }
    if (!"CRAN" %in% names(repositories)) {
      repositories <- c(CRAN = mirror, repositories)
    }
  }
  options(repos = repositories)
  invisible(repositories)
}

.liber_choose_release_tag <- function(releases, channel = "latest") {
  channel <- match.arg(channel, c("latest", "stable", "prerelease"))
  eligible <- Filter(function(release) {
    draft <- isTRUE(release$draft)
    prerelease <- isTRUE(release$prerelease)
    !draft && switch(
      channel,
      latest = TRUE,
      stable = !prerelease,
      prerelease = prerelease
    )
  }, releases)
  if (!length(eligible)) {
    stop(
      "No published LibeR release is available for channel '", channel, "'.",
      call. = FALSE
    )
  }
  published <- vapply(eligible, function(release) {
    value <- release$published_at
    if (is.null(value) || !nzchar(value)) value <- release$created_at
    if (is.null(value) || !nzchar(value)) ""
    else as.character(value)
  }, character(1))
  selected <- eligible[[order(published, decreasing = TRUE)[[1L]]]]
  tag <- selected$tag_name
  if (is.null(tag) || length(tag) != 1L || !nzchar(tag)) {
    stop("The selected GitHub release has no usable tag.", call. = FALSE)
  }
  tag
}

.liber_resolve_release_tag <- function(repository, channel = "latest") {
  if (!grepl("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", repository)) {
    stop("repository must have the form 'owner/name'.", call. = FALSE)
  }
  endpoint <- paste0(
    "https://api.github.com/repos/", repository, "/releases?per_page=100"
  )
  destination <- tempfile(fileext = ".json")
  on.exit(unlink(destination, force = TRUE), add = TRUE)
  headers <- c(
    Accept = "application/vnd.github+json",
    `X-GitHub-Api-Version` = "2022-11-28"
  )
  token <- Sys.getenv("GH_TOKEN", Sys.getenv("GITHUB_TOKEN", ""))
  if (nzchar(token)) {
    headers <- c(headers, Authorization = paste("Bearer", token))
  }
  status <- tryCatch(
    utils::download.file(
      endpoint, destination, mode = "wb", quiet = TRUE, headers = headers
    ),
    error = identity,
    warning = identity
  )
  size <- if (file.exists(destination)) file.info(destination)$size else NA_real_
  if (inherits(status, "condition") || !identical(status, 0L) ||
      is.na(size) || size <= 0) {
    detail <- if (inherits(status, "condition")) conditionMessage(status)
    else paste0("download status ", status)
    stop(
      "Unable to discover the latest LibeR release from GitHub (", detail,
      "). Pass an explicit tag, for example ",
      "liber_install(tag = \"v0.9.0-research-beta.6\").",
      call. = FALSE
    )
  }
  releases <- jsonlite::fromJSON(destination, simplifyVector = FALSE)
  .liber_choose_release_tag(releases, channel = channel)
}

liber_install <- function(
    tag = NULL,
    channel = Sys.getenv("LIBER_RELEASE_CHANNEL", "latest"),
    library = .libPaths()[[1L]],
    binary = FALSE,
    repository = "svdijkman/LibeR") {
  if (getRversion() < "4.1.0") stop("LibeR requires R 4.1 or newer.", call. = FALSE)
  channel <- match.arg(channel, c("latest", "stable", "prerelease"))
  library <- path.expand(library)
  if (!dir.exists(library) && !dir.create(library, recursive = TRUE, showWarnings = FALSE)) {
    stop("Unable to create R library: ", library, call. = FALSE)
  }
  library <- normalizePath(library, winslash = "/", mustWork = TRUE)
  .libPaths(unique(c(library, .libPaths())))
  .liber_configure_repositories()
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    utils::install.packages("jsonlite", lib = library)
  }
  requested_tag <- if (is.null(tag) || !length(tag)) "" else as.character(tag[[1L]])
  environment_tag <- Sys.getenv("LIBER_RELEASE_TAG", "")
  if (!nzchar(requested_tag) && nzchar(environment_tag)) {
    requested_tag <- environment_tag
  }
  if (tolower(requested_tag) %in% c("auto", "latest")) requested_tag <- ""
  if (!nzchar(requested_tag)) {
    requested_tag <- .liber_resolve_release_tag(repository, channel = channel)
  }
  if (!grepl("^[A-Za-z0-9._/-]+$", requested_tag)) {
    stop("The release tag contains unsupported characters.", call. = FALSE)
  }
  tag <- requested_tag
  message("Resolved LibeR release tag: ", tag, " (channel: ", channel, ")")

  raw_root <- paste0("https://raw.githubusercontent.com/", repository, "/", tag)
  manifest_path <- tempfile(fileext = ".json")
  on.exit(unlink(manifest_path, force = TRUE), add = TRUE)
  utils::download.file(
    paste0(raw_root, "/ecosystem.json"), manifest_path,
    mode = "wb", quiet = FALSE
  )
  manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = FALSE)
  packages <- names(manifest$packages)
  versions <- vapply(manifest$packages, `[[`, character(1), "version")

  stage <- tempfile("liber-install-")
  dir.create(stage, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(stage, recursive = TRUE, force = TRUE), add = TRUE)
  descriptions <- file.path(stage, paste0(packages, "-DESCRIPTION"))
  for (index in seq_along(packages)) {
    utils::download.file(
      paste0(raw_root, "/", packages[[index]], "/DESCRIPTION"),
      descriptions[[index]], mode = "wb", quiet = TRUE
    )
  }
  description_dependencies <- function(path) {
    description <- read.dcf(path)
    fields <- intersect(c("Depends", "Imports", "LinkingTo"),
                        colnames(description))
    if (!length(fields)) return(character())
    entries <- unlist(strsplit(
      paste(description[1L, fields], collapse = ","), ",", fixed = TRUE
    ), use.names = FALSE)
    trimws(sub("\\s*\\([^)]*\\)\\s*$", "", entries))
  }
  direct <- unique(unlist(lapply(
    descriptions, description_dependencies
  ), use.names = FALSE))
  base_packages <- rownames(utils::installed.packages(priority = "base"))
  external <- setdiff(
    direct[nzchar(direct)], c("R", packages, base_packages)
  )
  missing <- external[!vapply(
    external, requireNamespace, logical(1), quietly = TRUE
  )]
  if (length(missing)) {
    message("Installing missing R dependencies: ", paste(missing, collapse = ", "))
    utils::install.packages(missing, lib = library, dependencies = NA)
  }
  unresolved <- external[!vapply(
    external, requireNamespace, logical(1), quietly = TRUE
  )]
  if (length(unresolved)) {
    stop("Unresolved R dependencies: ", paste(unresolved, collapse = ", "),
         call. = FALSE)
  }

  use_binary <- isTRUE(binary) && .Platform$OS.type == "windows"
  if (isTRUE(binary) && !use_binary) {
    warning("Precompiled LibeR archives are Windows-specific; using source packages.",
            call. = FALSE)
  }
  if (use_binary && !identical(paste(R.version$major, R.version$minor, sep = "."),
                               "4.6.0")) {
    warning(
      "The published Windows binaries were built with R 4.6.0; using source ",
      "packages for this R version.", call. = FALSE
    )
    use_binary <- FALSE
  }
  extension <- if (use_binary) ".zip" else ".tar.gz"
  release_root <- paste0(
    "https://github.com/", repository, "/releases/download/", tag, "/"
  )
  archives <- paste0(
    release_root, packages, "_", unname(versions[packages]), extension
  )
  archive_files <- file.path(
    stage, paste0(packages, "_", unname(versions[packages]), extension)
  )

  for (index in seq_along(packages)) {
    message(
      "Installing ", packages[[index]], " ", versions[[packages[[index]]]],
      " from ", tag
    )
    utils::download.file(
      archives[[index]], archive_files[[index]], mode = "wb", quiet = FALSE
    )
    utils::install.packages(
      archive_files[[index]], lib = library, repos = NULL,
      type = if (use_binary) "win.binary" else "source",
      dependencies = FALSE
    )
  }

  installed <- vapply(packages, function(package) {
    as.character(utils::packageVersion(package, lib.loc = library))
  }, character(1))
  mismatch <- installed != unname(versions[packages])
  if (any(mismatch)) {
    stop(
      "Installed package set does not match the release manifest: ",
      paste0(
        packages[mismatch], " expected ", unname(versions[packages][mismatch]),
        " but found ", installed[mismatch], collapse = "; "
      ),
      call. = FALSE
    )
  }
  doctor <- getExportedValue("LibeRation", "liber_doctor")
  result <- doctor(strict = TRUE, verbose = TRUE)
  message("Installed LibeR compatibility set ", manifest$release, " into ", library)
  invisible(result)
}
