test_that("benchmark GUI retains shared theme and responsive controls", {
  script <- paste(readLines(
    system.file("htmlwidgets", "libertadWorkbench.js", package = "LibeRtAD"),
    warn = FALSE
  ), collapse = "\n")
  css <- paste(readLines(
    system.file("htmlwidgets", "libertadWorkbench.css", package = "LibeRtAD"),
    warn = FALSE
  ), collapse = "\n")
  design <- paste(readLines(
    system.file("htmlwidgets", "liber-design-system.js", package = "LibeRtAD"),
    warn = FALSE
  ), collapse = "\n")
  design_css <- paste(readLines(
    system.file("htmlwidgets", "liber-design-system.css", package = "LibeRtAD"),
    warn = FALSE
  ), collapse = "\n")

  expect_match(design, 'localStorage\\.getItem\\("liber\\.theme"\\)')
  expect_match(design, "liber-task-state", fixed = TRUE)
  expect_match(script, "LibeRDesign.theme", fixed = TRUE)
  expect_match(script, "LibeRDesign.taskState", fixed = TRUE)
  expect_match(script, "libertad-workbench-patch", fixed = TRUE)
  expect_match(script, "ecosystemLogAppend", fixed = TRUE)
  expect_match(design_css, ".shiny-bound-output.recalculating", fixed = TRUE)
  expect_match(script, "cancel_task", fixed = TRUE)
  expect_match(script, "ad-nav-toggle")
  expect_match(script, "ad-config-toggle")
  expect_match(script, "aria-expanded", fixed = TRUE)
  expect_match(css, "\\.ad-sidebar\\.open")
  expect_match(css, "\\.ad-config\\.open")
  expect_match(css, "focus-visible", fixed = TRUE)
  expect_match(
    css,
    "grid-template-rows:58px 32px minmax(0,1fr) 27px",
    fixed = TRUE
  )
  expect_match(css, ".ad-logo{width:42px;height:42px", fixed = TRUE)
  expect_match(css, ".ad-panel{margin-bottom:11px;border:1px solid var(--line);border-radius:10px", fixed = TRUE)
})
