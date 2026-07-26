test_that("administration GUI retains shared theme and version branding", {
  source <- paste(deparse(body(LibeRties::ls_admin_gui)), collapse = "\n")
  css <- paste(readLines(
    system.file("admin-assets", "admin.css", package = "LibeRties"),
    warn = FALSE
  ), collapse = "\n")
  design <- paste(readLines(
    system.file("admin-assets", "liber-design-system.js", package = "LibeRties"),
    warn = FALSE
  ), collapse = "\n")
  design_css <- paste(readLines(
    system.file("admin-assets", "liber-design-system.css", package = "LibeRties"),
    warn = FALSE
  ), collapse = "\n")

  expect_match(design, 'localStorage\\.getItem\\("liber\\.theme"\\)')
  expect_match(source, "LibeRDesign.theme", fixed = TRUE)
  expect_match(source, "package_version", fixed = TRUE)
  expect_match(source, "la-version-pill", fixed = TRUE)
  expect_match(source, "identical(shiny::isolate(jobs()), next_jobs)", fixed = TRUE)
  expect_match(source, "identical(shiny::isolate(logs()), next_logs)", fixed = TRUE)
  expect_match(design_css, ".shiny-bound-output.recalculating", fixed = TRUE)
  expect_match(css, "focus-visible", fixed = TRUE)
  expect_match(css, ".la-header { min-height:58px", fixed = TRUE)
  expect_match(css, ".la-message-bar { min-height:32px", fixed = TRUE)
  expect_match(css, ".la-panel { min-width:0; max-width:100%; overflow:hidden; padding:16px; border:1px solid var(--la-line); border-radius:10px", fixed = TRUE)
  expect_match(css, ".la-panel .shiny-input-container,.la-panel .form-control { width:100%; max-width:100%; }", fixed = TRUE)
})
