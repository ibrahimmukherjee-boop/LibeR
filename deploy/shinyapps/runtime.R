liber_shinyapps_root <- function() {
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

liber_shinyapps_library <- function(root = liber_shinyapps_root(),
                                    create = FALSE) {
  source(
    file.path(root, "tools", "validation-runtime.R"),
    local = environment()
  )
  configured <- Sys.getenv("LIBER_SHINYAPPS_LIBRARY", unset = "")
  if (nzchar(configured)) {
    path <- path.expand(configured)
    if (isTRUE(create) && !dir.exists(path)) {
      dir.create(path, recursive = TRUE, showWarnings = FALSE)
    }
    return(normalizePath(path, winslash = "/", mustWork = FALSE))
  }
  r_series <- paste(R.version$major, strsplit(R.version$minor, "\\.")[[1L]][1L],
                    sep = ".")
  liber_validation_dev_cache(
    root, "r-libraries", paste0("shinyapps-r-", r_series),
    create = create
  )
}

liber_shinyapps_use_library <- function(root = liber_shinyapps_root(),
                                        require_exact = TRUE) {
  path <- liber_shinyapps_library(root)
  if (!dir.exists(path)) {
    stop(
      "The dedicated shinyapps.io library does not exist. Run ",
      "`Rscript deploy/shinyapps/prepare-library.R` first.",
      call. = FALSE
    )
  }
  .libPaths(unique(c(path, .libPaths())))
  Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  if (isTRUE(require_exact)) {
    manifest <- jsonlite::fromJSON(
      file.path(root, "ecosystem.json"), simplifyVector = FALSE
    )
    expected <- vapply(manifest$packages, `[[`, character(1), "version")
    installed <- vapply(names(expected), function(package) {
      description <- tryCatch(
        utils::packageDescription(package, lib.loc = path),
        error = function(error) NULL
      )
      if (is.null(description)) NA_character_ else description$Version
    }, character(1))
    mismatch <- is.na(installed) | installed != expected
    if (any(mismatch)) {
      detail <- paste0(
        names(expected)[mismatch], " expected ", expected[mismatch],
        ", found ", installed[mismatch]
      )
      stop(
        "The shinyapps.io library is not synchronized: ",
        paste(detail, collapse = "; "),
        ". Re-run `Rscript deploy/shinyapps/prepare-library.R`.",
        call. = FALSE
      )
    }
  }
  invisible(path)
}
