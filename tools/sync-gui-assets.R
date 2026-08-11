root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
check_only <- "--check" %in% commandArgs(trailingOnly = TRUE)
source_root <- file.path(root, "tools", "shared", "gui")
assets <- c(
  "liber-design-system.js",
  "liber-design-system.css",
  "liber-theme-mono.css"
)
target_roots <- c(
  "LibeRtAD/inst/htmlwidgets",
  "LibeRation/inst/htmlwidgets",
  "LibeRator/inst/htmlwidgets",
  "LibeRality/inst/htmlwidgets",
  "LibeRary/inst/shiny/www",
  "LibeRary/inst/shiny-ingest/www",
  "LibeRary/inst/shiny-reference/www",
  "LibeRties/inst/admin-assets"
)

out_of_date <- character()
for (asset in assets) {
  source <- file.path(source_root, asset)
  expected <- readBin(source, "raw", n = file.info(source)$size)
  for (directory in target_roots) {
    target <- file.path(root, directory, asset)
    actual <- if (file.exists(target)) {
      readBin(target, "raw", n = file.info(target)$size)
    } else {
      raw()
    }
    if (!identical(actual, expected)) {
      out_of_date <- c(out_of_date, target)
      if (!check_only) file.copy(source, target, overwrite = TRUE)
    }
  }
}
if (check_only && length(out_of_date)) {
  stop(
    "Generated GUI design-system assets are stale:\n",
    paste(out_of_date, collapse = "\n"),
    "\nRun `Rscript tools/sync-gui-assets.R`.",
    call. = FALSE
  )
}
cat(if (check_only) "GUI assets are synchronized.\n" else
  "GUI assets updated.\n")
