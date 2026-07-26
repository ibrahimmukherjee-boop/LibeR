args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) args[[1L]] else getwd()
root <- normalizePath(root, winslash = "/", mustWork = TRUE)

installer <- new.env(parent = globalenv())
sys.source(
  file.path(root, "tools", "install-ecosystem.R"),
  envir = installer
)

old_repositories <- getOption("repos")
old_mirror <- Sys.getenv("LIBER_CRAN_MIRROR", unset = NA_character_)
on.exit({
  options(repos = old_repositories)
  if (is.na(old_mirror)) Sys.unsetenv("LIBER_CRAN_MIRROR")
  else Sys.setenv(LIBER_CRAN_MIRROR = old_mirror)
}, add = TRUE)

Sys.setenv(LIBER_CRAN_MIRROR = "https://cloud.r-project.org")
options(repos = c(
  CRAN = "@CRAN@",
  Stan = "https://stan-dev.r-universe.dev"
))
repositories <- installer$.liber_configure_repositories()
stopifnot(
  identical(unname(repositories[["CRAN"]]), "https://cloud.r-project.org"),
  identical(
    unname(repositories[["Stan"]]),
    "https://stan-dev.r-universe.dev"
  )
)

releases <- list(
  list(
    tag_name = "v0.8.3-consolidation",
    draft = FALSE,
    prerelease = FALSE,
    published_at = "2026-07-23T19:25:06Z"
  ),
  list(
    tag_name = "v0.9.0-research-beta.3",
    draft = FALSE,
    prerelease = TRUE,
    published_at = "2026-07-23T23:06:57Z"
  ),
  list(
    tag_name = "v0.9.0-unpublished",
    draft = TRUE,
    prerelease = TRUE,
    published_at = "2026-07-24T23:06:57Z"
  )
)
stopifnot(
  identical(
    installer$.liber_choose_release_tag(releases, "latest"),
    "v0.9.0-research-beta.3"
  ),
  identical(
    installer$.liber_choose_release_tag(releases, "stable"),
    "v0.8.3-consolidation"
  ),
  identical(
    installer$.liber_choose_release_tag(releases, "prerelease"),
    "v0.9.0-research-beta.3"
  )
)

message("Installer mirror and release-channel checks passed.")
