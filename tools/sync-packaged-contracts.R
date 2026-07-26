root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
check_only <- "--check" %in% commandArgs(trailingOnly = TRUE)
pairs <- list(
  c("ecosystem.json", "LibeRation/inst/ecosystem/compatibility.json"),
  c(
    "validation/liberality/external/baseline/manifest.json",
    "LibeRality/inst/extdata/external-validation-baseline.json"
  )
)
stale <- character()
for (pair in pairs) {
  source <- file.path(root, pair[[1L]])
  target <- file.path(root, pair[[2L]])
  source_raw <- readBin(source, "raw", n = file.info(source)$size)
  target_raw <- if (file.exists(target)) {
    readBin(target, "raw", n = file.info(target)$size)
  } else {
    raw()
  }
  if (!identical(source_raw, target_raw)) {
    stale <- c(stale, pair[[2L]])
    if (!check_only) file.copy(source, target, overwrite = TRUE)
  }
}
if (check_only && length(stale)) {
  stop(
    "Packaged contract copies are stale:\n", paste(stale, collapse = "\n"),
    "\nRun `Rscript tools/sync-packaged-contracts.R`.",
    call. = FALSE
  )
}
cat(if (check_only) "Packaged contracts are synchronized.\n" else
  "Packaged contracts updated.\n")
