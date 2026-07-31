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
  expect_match(css, ".ly-header{height:58px", fixed = TRUE)
  expect_match(css, "background:var(--ly-header-bg)", fixed = TRUE)
  expect_match(css, "--ly-header-bg:#3c2c27", fixed = TRUE)
  expect_match(css, ".ly-brand strong{font-size:19px;letter-spacing:.2px;color:var(--ly-header-text)}", fixed = TRUE)
  expect_match(css, ".ly-button.ly-primary{background:var(--ly-accent-strong)", fixed = TRUE)
  expect_match(css, "color:var(--ly-surface)", fixed = TRUE)
  expect_match(css, ".ly-dark .ly-switch input:checked+i{background:var(--ly-accent-strong)}", fixed = TRUE)
  expect_match(css, ".ly-header .ly-badge-warning{color:var(--ly-header-text)", fixed = TRUE)
  expect_match(css, ".ly-status{height:32px", fixed = TRUE)
  expect_match(css, ".ly-brand img,.ly-logo{width:42px;height:42px", fixed = TRUE)
  expect_match(css, ".ly-panel{background:var(--ly-surface);border:1px solid var(--ly-border);border-radius:10px", fixed = TRUE)
  expect_match(script, "CriterionHelpModal", fixed = TRUE)
  expect_match(script, "ly-tab-step", fixed = TRUE)
  expect_match(script, "Design workflow and results", fixed = TRUE)
  expect_false(grepl("e\\(Workflow", script))
  expect_match(css, "--ly-accent:#b87333;--ly-accent-strong:#b87333", fixed = TRUE)
  expect_match(css, ".ly-tabs button.done .ly-tab-step{background:#b87333;border-color:#b87333;color:#fff}", fixed = TRUE)
  expect_match(css, "grid-template-rows:46px minmax(0,1fr)", fixed = TRUE)
  expect_match(script, "criterionGuidance", fixed = TRUE)
  expect_match(script, "ArmModal", fixed = TRUE)
  expect_match(script, "EndpointModal", fixed = TRUE)
  expect_match(script, "ScenarioModal", fixed = TRUE)
  expect_match(script, "VariableModal", fixed = TRUE)
  expect_match(script, "ConstraintModal", fixed = TRUE)
  expect_match(script, "DesignWizardModal", fixed = TRUE)
  expect_match(script, "DesignHistory", fixed = TRUE)
  expect_match(script, "SaveDesignVersionModal", fixed = TRUE)
  expect_match(script, "Save version and switch", fixed = TRUE)
  expect_match(script, "Regulatory-informed", fixed = TRUE)
  expect_match(script, "ModelEditorModal", fixed = TRUE)
  expect_match(script, "model.typeLabel", fixed = TRUE)
  expect_match(script, "endpointOptions", fixed = TRUE)
  expect_match(script, "Type YES to confirm", fixed = TRUE)
})
