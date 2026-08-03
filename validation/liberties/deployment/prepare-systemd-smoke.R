#!/usr/bin/env Rscript

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 1L || !nzchar(arguments[[1L]])) {
  stop("Provide one private credential-file path.", call. = FALSE)
}
if (!requireNamespace("LibeRties", quietly = TRUE)) {
  stop("LibeRties must be installed before preparing the smoke test.", call. = FALSE)
}
path <- path.expand(arguments[[1L]])
dir.create(dirname(path), recursive = TRUE, mode = "0700", showWarnings = FALSE)
if (!file.exists(path)) {
  writeLines(LibeRties::ls_generate_storage_key(), path, useBytes = TRUE)
}
Sys.chmod(dirname(path), mode = "0700")
Sys.chmod(path, mode = "0600")
key <- trimws(readLines(path, n = 1L, warn = FALSE))
if (!grepl("^[A-Fa-f0-9]{64}$", key)) {
  stop("The credential file is not a 256-bit hexadecimal key.", call. = FALSE)
}
cat(normalizePath(path, winslash = "/", mustWork = TRUE), "\n", sep = "")
