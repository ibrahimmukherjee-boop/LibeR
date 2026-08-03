test_that("design history saves immutable sequential versions", {
  workspace <- tempfile("lity-history-")
  dir.create(workspace)
  on.exit(unlink(workspace, recursive = TRUE, force = TRUE), add = TRUE)
  original <- lity_example()$design
  original$information_approximation <- NULL
  original$version <- 1L

  first <- lity_design_version_save(
    original, workspace, series_name = "Theo study design"
  )
  expect_equal(first$version_number, 1L)
  expect_equal(first$label, "Version 001")
  expect_equal(first$parent_version, "")

  revised <- original
  revised$name <- "Theo study design revised"
  second <- lity_design_version_save(
    revised, workspace, series_id = first$series_id,
    label = "Sparse schedule"
  )
  expect_equal(second$version_number, 2L)
  expect_equal(second$parent_version, first$version_id)

  history <- lity_design_history(workspace)
  expect_equal(nrow(history), 2L)
  expect_setequal(history$version_id, c(first$version_id, second$version_id))
  expect_true(all(file.exists(file.path(
    workspace, "liberality", "designs", "objects",
    history$series_id, paste0(history$version_id, ".rds")
  ))))

  expect_equal(
    lity_design_version_load(workspace, first$series_id, "latest")$name,
    revised$name
  )
  expect_equal(
    lity_design_version_load(workspace, first$series_id, 1L)$name,
    original$name
  )
  expect_equal(
    lity_design_version_load(
      workspace, first$series_id, "Sparse schedule"
    )$name,
    revised$name
  )
  upgraded <- lity_design_version_load(workspace, first$series_id, 1L)
  expect_equal(upgraded$version, 2L)
  expect_equal(upgraded$information_approximation, "fo_block")
})

test_that("design histories keep separate designs and expose GUI state", {
  workspace <- tempfile("lity-history-")
  dir.create(workspace)
  on.exit(unlink(workspace, recursive = TRUE, force = TRUE), add = TRUE)
  design <- lity_example()$design
  first <- lity_design_version_save(
    design, workspace, series_name = "First design"
  )
  design$name <- "Second design"
  second <- lity_design_version_save(
    design, workspace, series_name = "Second design"
  )

  history <- lity_design_history(workspace)
  expect_equal(length(unique(history$series_id)), 2L)
  payload <- LibeRality:::.lity_design_history_payload(
    history, second$series_id, second$version_id, dirty = FALSE
  )
  expect_length(payload$records, 2L)
  expect_equal(payload$currentSeries, second$series_id)
  expect_equal(payload$currentVersion, second$version_id)
  expect_false(payload$dirty)
  expect_error(
    lity_design_version_load(workspace, "../escape"),
    "Invalid design-series id"
  )
  expect_s3_class(
    lity_design_version_load(workspace, first$series_id),
    "lity_design"
  )
})
