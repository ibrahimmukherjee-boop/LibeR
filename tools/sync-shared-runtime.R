root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
arguments <- commandArgs(trailingOnly = TRUE)
check_only <- "--check" %in% arguments
source_path <- file.path(root, "tools", "shared", "liber-durability.R")
if (!file.exists(source_path)) stop("Missing canonical durability source.", call. = FALSE)

header <- c(
  "# Generated from tools/shared/liber-durability.R.",
  "# Run `Rscript tools/sync-shared-runtime.R`; do not edit this copy directly.",
  ""
)
expected <- c(header, readLines(source_path, warn = FALSE, encoding = "UTF-8"))
targets <- file.path(
  root, c("LibeRation", "LibeRties", "LibeRary", "LibeRator"),
  "R", "aaa-shared-durability.R"
)

out_of_date <- character()
for (target in targets) {
  actual <- if (file.exists(target)) {
    readLines(target, warn = FALSE, encoding = "UTF-8")
  } else {
    character()
  }
  if (!identical(actual, expected)) {
    out_of_date <- c(out_of_date, target)
    if (!check_only) {
      writeLines(expected, target, useBytes = TRUE)
    }
  }
}
if (check_only && length(out_of_date)) {
  stop(
    "Generated shared runtime files are stale:\n",
    paste(out_of_date, collapse = "\n"),
    "\nRun `Rscript tools/sync-shared-runtime.R`.",
    call. = FALSE
  )
}
path_source <- file.path(root, "tools", "shared", "liber-paths.R")
path_header <- c(
  "# Generated from tools/shared/liber-paths.R.",
  "# Run `Rscript tools/sync-shared-runtime.R`; do not edit this copy directly.",
  ""
)
path_expected <- c(
  path_header, readLines(path_source, warn = FALSE, encoding = "UTF-8")
)
path_targets <- file.path(
  root, c("LibeRtAD", "LibeRation", "LibeRary", "LibeRator"),
  "R", "aaa-shared-paths.R"
)
path_out_of_date <- character()
for (target in path_targets) {
  actual <- if (file.exists(target)) {
    readLines(target, warn = FALSE, encoding = "UTF-8")
  } else {
    character()
  }
  if (!identical(actual, path_expected)) {
    path_out_of_date <- c(path_out_of_date, target)
    if (!check_only) writeLines(path_expected, target, useBytes = TRUE)
  }
}
if (check_only && length(path_out_of_date)) {
  stop(
    "Generated shared path files are stale:\n",
    paste(path_out_of_date, collapse = "\n"),
    "\nRun `Rscript tools/sync-shared-runtime.R`.",
    call. = FALSE
  )
}
async_source <- file.path(root, "tools", "shared", "liber-async.R")
async_header <- c(
  "# Generated from tools/shared/liber-async.R.",
  "# Run `Rscript tools/sync-shared-runtime.R`; do not edit this copy directly.",
  ""
)
async_expected <- c(
  async_header, readLines(async_source, warn = FALSE, encoding = "UTF-8")
)
async_targets <- file.path(
  root, c(
    "LibeRtAD", "LibeRation", "LibeRality", "LibeRator",
    "LibeRary", "LibeRties"
  ),
  "R", "aaa-shared-async.R"
)
async_out_of_date <- character()
for (target in async_targets) {
  actual <- if (file.exists(target)) {
    readLines(target, warn = FALSE, encoding = "UTF-8")
  } else {
    character()
  }
  if (!identical(actual, async_expected)) {
    async_out_of_date <- c(async_out_of_date, target)
    if (!check_only) writeLines(async_expected, target, useBytes = TRUE)
  }
}
if (check_only && length(async_out_of_date)) {
  stop(
    "Generated shared asynchronous runtime files are stale:\n",
    paste(async_out_of_date, collapse = "\n"),
    "\nRun `Rscript tools/sync-shared-runtime.R`.",
    call. = FALSE
  )
}
cat(
  if (check_only) "Shared runtime copies are synchronized.\n" else
    "Shared runtime copies updated.\n"
)
