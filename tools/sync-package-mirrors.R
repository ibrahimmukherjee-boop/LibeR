args <- commandArgs(trailingOnly = TRUE)
push <- "--push" %in% args
publish <- "--publish-releases" %in% args
branches_only <- "--branches-only" %in% args
if (publish && !push) {
  stop("`--publish-releases` requires `--push`.", call. = FALSE)
}
if (publish && branches_only) {
  stop(
    "`--publish-releases` cannot be combined with `--branches-only`.",
    call. = FALSE
  )
}

root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
manifest <- jsonlite::fromJSON(
  file.path(root, "ecosystem.json"), simplifyVector = FALSE
)
packages <- names(manifest$packages)
versions <- vapply(manifest$packages, `[[`, character(1), "version")
owner <- "svdijkman"

run <- function(command, arguments, directory = root, capture = FALSE) {
  old <- setwd(directory)
  on.exit(setwd(old), add = TRUE)
  output <- system2(
    command, arguments,
    stdout = if (capture) TRUE else "", stderr = if (capture) TRUE else ""
  )
  status <- if (capture) attr(output, "status") else as.integer(output)
  if (is.null(status)) status <- 0L
  if (status != 0L) {
    stop(
      command, " failed in ", directory, ":\n",
      if (length(output)) paste(output, collapse = "\n") else "no output",
      call. = FALSE
    )
  }
  output
}

git_status <- run(
  "git", c("status", "--porcelain=v1", "--untracked-files=no"), capture = TRUE
)
if (length(git_status) && push) {
  stop("Mirror publication requires a clean tracked monorepo.", call. = FALSE)
}
source_commit <- trimws(run("git", c("rev-parse", "HEAD"), capture = TRUE)[[1L]])

stage <- tempfile("liber-mirrors-")
dir.create(stage, recursive = TRUE, showWarnings = FALSE)
stage <- normalizePath(stage, winslash = "/", mustWork = TRUE)
on.exit({
  target <- normalizePath(stage, winslash = "/", mustWork = FALSE)
  temp_root <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
  if (startsWith(target, paste0(temp_root, "/")) && dir.exists(target)) {
    unlink(target, recursive = TRUE, force = TRUE)
  }
}, add = TRUE)

for (package in packages) {
  repository <- paste0("https://github.com/", owner, "/", package, ".git")
  clone <- file.path(stage, package)
  message("Synchronising ", package, " ", versions[[package]])
  run("git", c("clone", "--quiet", repository, shQuote(clone)))
  run("git", c("config", "core.autocrlf", "false"), clone)
  run("git", c("config", "user.name", shQuote("Sven C. van Dijkman")), clone)
  run(
    "git",
    c("config", "user.email", "svdijkman@users.noreply.github.com"),
    clone
  )

  existing <- list.files(clone, all.files = TRUE, no.. = TRUE, full.names = TRUE)
  preserved <- file.path(clone, c(".git", ".github"))
  remove <- setdiff(
    normalizePath(existing, winslash = "/", mustWork = FALSE),
    normalizePath(preserved, winslash = "/", mustWork = FALSE)
  )
  if (length(remove)) unlink(remove, recursive = TRUE, force = TRUE)

  tracked <- run(
    "git", c("ls-files", "--", package), root, capture = TRUE
  )
  tracked <- tracked[nzchar(tracked)]
  if (!length(tracked)) {
    stop("No tracked source files were found for ", package, ".",
         call. = FALSE)
  }
  package_prefix <- paste0(package, "/")
  if (any(!startsWith(tracked, package_prefix))) {
    stop("Unexpected tracked path while staging ", package, ".", call. = FALSE)
  }
  relative <- substring(tracked, nchar(package_prefix) + 1L)
  generated <- relative[
    grepl(
      "(^|/)src/.*\\.(o|obj|so|dll|a|def)$|(^|/)src/symbols\\.rds$",
      relative, ignore.case = TRUE
    )
  ]
  if (length(generated)) {
    stop(
      "Tracked generated native artifacts are not publishable for ", package,
      ": ", paste(generated, collapse = ", "), call. = FALSE
    )
  }
  for (index in seq_along(tracked)) {
    from <- file.path(root, tracked[[index]])
    to <- file.path(clone, relative[[index]])
    dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(
      from, to, overwrite = TRUE, copy.mode = TRUE, copy.date = TRUE
    )) {
      stop("Unable to copy ", tracked[[index]], " into the mirror clone.",
           call. = FALSE)
    }
  }
  run("git", c("add", "-A"), clone)
  changes <- run("git", c("status", "--porcelain=v1"), clone, capture = TRUE)
  if (length(changes)) {
    run(
      "git",
      c(
        "commit", "--quiet", "-m",
        shQuote(paste0(
          "Release ", package, " ", versions[[package]],
          " from LibeR ", manifest$release
        ))
      ),
      clone
    )
  }
  mirror_commit <- trimws(
    run("git", c("rev-parse", "HEAD"), clone, capture = TRUE)[[1L]]
  )
  message(
    "  monorepo ", substr(source_commit, 1L, 12L),
    " -> mirror ", substr(mirror_commit, 1L, 12L)
  )

  if (push) {
    run("git", c("push", "origin", "HEAD:main"), clone)
    if (branches_only) {
      message("  branch synchronized; existing release tags were left unchanged")
      next
    }
    tag <- paste0("v", versions[[package]])
    remote_tag <- run(
      "git", c("ls-remote", "--tags", "origin", paste0("refs/tags/", tag)),
      clone, capture = TRUE
    )
    tag_exists <- length(remote_tag) > 0L
    if (tag_exists) {
      tagged_tree <- trimws(
        run(
          "git", c("rev-parse", paste0(tag, "^{tree}")),
          clone, capture = TRUE
        )[[1L]]
      )
      mirror_tree <- trimws(
        run(
          "git", c("rev-parse", paste0(mirror_commit, "^{tree}")),
          clone, capture = TRUE
        )[[1L]]
      )
      if (!identical(tagged_tree, mirror_tree)) {
        stop(
          "Remote tag ", tag, " for ", package,
          " contains a different source tree. Advance the package version ",
          "instead of rewriting the immutable tag.", call. = FALSE
        )
      }
      message(
        "  existing tag ", tag,
        " already matches the mirror source tree"
      )
    } else {
      run(
        "git", c("tag", "-a", tag, "-m",
                 shQuote(paste0(package, " ", versions[[package]]))),
        clone
      )
      run("git", c("push", "origin", tag), clone)
    }

    if (publish && !tag_exists) {
      release_dir <- file.path(root, "releases", manifest$release)
      assets <- file.path(
        release_dir,
        c(
          paste0(package, "_", versions[[package]], ".tar.gz"),
          paste0(package, "_", versions[[package]], ".zip"),
          paste0(package, "_", versions[[package]], ".pdf")
        )
      )
      assets <- assets[file.exists(assets)]
      if (!length(assets)) {
        stop("No release assets were found for ", package, ".", call. = FALSE)
      }
      run(
        "gh",
        c(
          "release", "create", tag, "--repo", paste0(owner, "/", package),
          "--title", shQuote(paste0(package, " ", versions[[package]])),
          if (grepl("research-beta", manifest$release, fixed = TRUE)) {
            "--prerelease"
          } else {
            character()
          },
          "--notes",
          shQuote(paste0(
            "Research-beta package mirror generated from LibeR ecosystem ",
            manifest$release, " (monorepo ", source_commit, ")."
          )),
          shQuote(assets)
        ),
        clone
      )
    }
  }
}

message(
  if (push) "Package mirrors synchronised." else
    "Dry run completed. Re-run with --push after release validation."
)
