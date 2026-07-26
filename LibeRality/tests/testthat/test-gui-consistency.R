test_that("design GUI retains shared theme and accessible dialogs", {
  script <- paste(readLines(
    system.file("htmlwidgets", "liberalityWorkbench.js", package = "LibeRality"),
    warn = FALSE
  ), collapse = "\n")
  css <- paste(readLines(
    system.file("htmlwidgets", "liberalityWorkbench.css", package = "LibeRality"),
    warn = FALSE
  ), collapse = "\n")
  design <- paste(readLines(
    system.file("htmlwidgets", "liber-design-system.js", package = "LibeRality"),
    warn = FALSE
  ), collapse = "\n")

  expect_match(design, 'localStorage\\.getItem\\("liber\\.theme"\\)')
  expect_match(design, "liber-task-state", fixed = TRUE)
  expect_match(script, "LibeRDesign.theme", fixed = TRUE)
  expect_match(script, "LibeRDesign.taskState", fixed = TRUE)
  expect_match(script, "cancel_task", fixed = TRUE)
  expect_match(script, "useDialogFocus", fixed = TRUE)
  expect_match(script, 'event\\.key === "Escape"')
  expect_match(script, '"aria-label": p.title', fixed = TRUE)
  expect_match(css, "focus-visible", fixed = TRUE)
  expect_match(css, ".ly-header{height:58px", fixed = TRUE)
  expect_match(css, ".ly-status{height:32px", fixed = TRUE)
  expect_match(css, ".ly-brand img,.ly-logo{width:42px;height:42px", fixed = TRUE)
  expect_match(css, ".ly-panel{background:var(--ly-surface);border:1px solid var(--ly-border);border-radius:10px", fixed = TRUE)
})
