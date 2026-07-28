test_that("built-in model catalogue is lightweight and resolvable", {
  expect_identical(
    LibeRality:::.lity_model_name(lity_example()$model),
    "One-compartment oral PK"
  )
  catalogue <- LibeRality:::.lity_builtin_catalogue()
  expect_gte(length(catalogue), 21L)
  expect_true(all(vapply(catalogue, function(x) {
    all(c("id", "key", "source", "label", "metadata") %in% names(x))
  }, logical(1))))
  expect_false(any(vapply(catalogue, function(x) {
    any(vapply(x, inherits, logical(1), "nm_model"))
  }, logical(1))))

  markov <- Filter(function(x) identical(x$id, "markov"), catalogue)[[1L]]
  resolved <- LibeRality:::.lity_resolve_model_record(markov)
  expect_s3_class(resolved$model, "nm_model")
  expect_identical(resolved$provenance$source, "Built-in")
})

test_that("model change remaps schedules and records immutable provenance", {
  design <- lity_example()$design
  old_hash <- digest::digest(design$model, algo = "sha256", serialize = TRUE)
  model <- LibeRation::nm_model_template("parent_metabolite")
  provenance <- list(
    source = "Built-in", label = "Parent-metabolite",
    parameter_source = "template values"
  )
  changed <- LibeRality:::.lity_apply_model(
    design, model, provenance, covariates = list()
  )

  expect_true(lity_validate(changed)$valid)
  expect_true(all(vapply(changed$arms, function(arm) {
    all(arm$events$CMT[arm$events$EVID != 0] == model$DOSECMP) &&
      all(arm$events$CMT[arm$events$EVID == 0] == model$OBSCMP)
  }, logical(1))))
  expect_null(changed$prior_fim)
  expect_length(changed$alternative_models, 0L)
  expect_identical(
    changed$metadata$model_history[[1L]]$previous_hash, old_hash
  )
  expect_identical(changed$metadata$model_provenance$source, "Built-in")
})

test_that("missing model covariates require explicit design values", {
  design <- lity_example()$design
  model <- design$model
  model$COVARIATES <- "RENAL"
  compatibility <- LibeRality:::.lity_model_compatibility(design, model)
  expect_identical(
    vapply(compatibility$requiredCovariates, `[[`, character(1), "name"),
    "RENAL"
  )
  expect_error(
    LibeRality:::.lity_apply_model(design, model, list(source = "test")),
    "Provide design values"
  )
  changed <- LibeRality:::.lity_apply_model(
    design, model, list(source = "test"), list(RENAL = 1.2)
  )
  expect_true(all(vapply(changed$arms, function(arm) {
    all(arm$events$RENAL == 1.2)
  }, logical(1))))
})

test_that("LibeRation model versions can be imported without loading a catalogue", {
  workspace <- LibeRation::nm_workspace(tempfile("lity-model-browser-"))
  project <- LibeRation::nm_project_create(workspace, "Browser test")
  model <- lity_example()$design$model
  version <- LibeRation::nm_project_save(
    workspace, project$id, model = model, label = "Mod001"
  )
  imported <- lity_model_from_liberation(
    workspace, project$id, version, use_estimates = FALSE
  )
  expect_s3_class(imported, "nm_model")
  provenance <- attr(imported, "liberation_provenance", exact = TRUE)
  expect_identical(provenance$source, "LibeRation")
  expect_identical(provenance$parameter_source, "initial estimates")

  catalogue <- LibeRality:::.lity_liberation_catalogue(workspace)
  expect_length(catalogue$records, 1L)
  expect_identical(catalogue$records[[1L]]$metadata$entryType, "version")
})

test_that("workbench exposes the model browser and dedicated Model tab", {
  source <- paste(
    readLines(system.file(
      "htmlwidgets", "liberalityWorkbench.js", package = "LibeRality"
    ), warn = FALSE),
    collapse = "\n"
  )
  expect_match(source, "Choose structural model", fixed = TRUE)
  expect_match(source, "LibeRation", fixed = TRUE)
  expect_match(source, "LibeRary", fixed = TRUE)
  expect_match(source, "Control stream", fixed = TRUE)
  expect_match(source, "[\"model\", \"Model\"]", fixed = TRUE)
})
