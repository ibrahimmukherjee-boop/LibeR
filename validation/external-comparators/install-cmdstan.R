#!/usr/bin/env Rscript

arguments <- commandArgs(trailingOnly = TRUE)
script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script <- if (length(script_argument)) {
  sub("^--file=", "", script_argument[[1L]])
} else {
  "validation/external-comparators/install-cmdstan.R"
}
root <- normalizePath(
  file.path(dirname(script), "..", ".."), winslash = "/", mustWork = TRUE
)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
value_after <- function(name, default = NULL) {
  liber_validation_option(name, default, args = arguments)
}
external_library <- file.path(root, ".external-comparator-lib")
.libPaths(unique(c(external_library, .libPaths())))

if (!requireNamespace("cmdstanr", quietly = TRUE)) {
  stop(
    "Install cmdstanr into .external-comparator-lib before installing CmdStan.",
    call. = FALSE
  )
}

if (.Platform$OS.type == "windows") {
  compilers <- Sys.glob(
    "C:/rtools*/x86_64-w64-mingw32.static.posix/bin/g++.exe"
  )
  if (length(compilers)) {
    compiler_directory <- dirname(tail(sort(compilers), 1L))
    rtools_root <- dirname(dirname(compiler_directory))
    Sys.setenv(PATH = paste(c(
      normalizePath(
        c(compiler_directory, file.path(rtools_root, "usr", "bin")),
        winslash = "/", mustWork = TRUE
      ),
      Sys.getenv("PATH")
    ), collapse = .Platform$path.sep))
  }
}

destination <- file.path(root, ".external-tools", "cmdstan")
dir.create(destination, recursive = TRUE, showWarnings = FALSE)
version <- value_after("version", "2.39.0")
if (!grepl("^[0-9]+[.][0-9]+[.][0-9]+$", version)) {
  stop("--version must be a semantic CmdStan version.", call. = FALSE)
}
cores_argument <- grep("^--cores=", arguments, value = TRUE)
cores <- if (length(cores_argument)) {
  as.integer(sub("^--cores=", "", cores_argument[[length(cores_argument)]]))
} else {
  min(4L, max(1L, parallel::detectCores(logical = FALSE)))
}
if (is.na(cores) || cores < 1L) stop("--cores must be positive.", call. = FALSE)

cmdstanr::check_cmdstan_toolchain(quiet = FALSE)
existing <- list.dirs(destination, recursive = FALSE, full.names = TRUE)
existing <- existing[grepl("^cmdstan-[0-9]", basename(existing))]
selected <- file.path(destination, paste0("cmdstan-", version))
if (!dir.exists(selected) || "--force" %in% arguments) {
  cmdstanr::install_cmdstan(
    dir = destination, version = version, cores = cores, quiet = FALSE,
    overwrite = "--force" %in% arguments, timeout = 1800
  )
}

if (!dir.exists(selected)) {
  stop("Pinned CmdStan ", version, " installation was not created.", call. = FALSE)
}
cmdstanr::set_cmdstan_path(selected)
record <- data.frame(
  component = c("cmdstanr", "CmdStan"),
  version = c(
    as.character(utils::packageVersion("cmdstanr")),
    as.character(cmdstanr::cmdstan_version())
  ),
  path = c(
    normalizePath(
      system.file(package = "cmdstanr"), winslash = "/", mustWork = TRUE
    ),
    normalizePath(selected, winslash = "/", mustWork = TRUE)
  ),
  installed_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  stringsAsFactors = FALSE
)
utils::write.csv(
  record, file.path(destination, "cmdstan-lock.csv"), row.names = FALSE
)
print(record, row.names = FALSE)
