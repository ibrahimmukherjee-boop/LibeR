test_that("criterion guidance covers every selectable objective", {
  guidance <- .lity_criterion_guidance()

  expect_setequal(names(guidance), .lity_criterion_types)
  expect_true(all(vapply(guidance, function(item) {
    all(c(
      "label", "group", "summary", "construction", "strengths",
      "limitations", "useCases", "requirements", "direction"
    ) %in% names(item)) &&
      all(nzchar(unlist(item[c(
        "label", "group", "summary", "construction", "strengths",
        "limitations", "useCases", "requirements", "direction"
      )], use.names = FALSE)))
  }, logical(1))))
})

test_that("GUI design editors update typed design components", {
  example <- lity_example()
  design <- example$design
  original_arms <- length(design$arms)

  design <- .lity_gui_upsert_arm(design, list(
    id = "", name = "Sparse cohort", size = 12, allocation = 1,
    population = "adult", samplingTimes = "1, 4, 12",
    doseTimes = "0", doseAmounts = "100", rates = "0",
    route = "oral", doseCmt = 1, observationCmt = 2, dvid = 1,
    ii = 0, addl = 0, ss = 0, sampleVolume = 3
  ))
  expect_length(design$arms, original_arms + 1L)
  arm_id <- utils::tail(names(design$arms), 1L)
  expect_equal(design$arms[[arm_id]]$size, 12L)
  expect_equal(sum(design$arms[[arm_id]]$events$EVID == 0L), 3L)

  design <- .lity_gui_upsert_scenario(design, list(
    id = "", name = "Lower adherence", probability = 0.2,
    adherence = 0.7, dropout = 0.1, missedSample = 0.05,
    theta = "", omega = "", sigma = ""
  ))
  expect_equal(sum(vapply(design$scenarios, `[[`, numeric(1), "probability")), 1)

  design <- .lity_gui_upsert_variable(design, list(
    id = "", name = "Sampling occasion", target = "sampling_time",
    arm = arm_id, index = 1, lower = 0.5, upper = 8,
    type = "discrete", values = "0.5, 1, 2, 4", covariate = ""
  ))
  expect_true(any(vapply(
    design$variables, function(item) identical(item$name, "Sampling occasion"),
    logical(1)
  )))

  payload <- .lity_gui_payload(
    design, example$criteria$local_D, revision = 3L, hosted = TRUE
  )
  expect_equal(payload$workflow$revision, 3L)
  expect_true(payload$hosted)
  expect_length(payload$criterionGuidance, length(.lity_criterion_types))
})

test_that("trial wizard templates produce ordinary validated design objects", {
  example <- lity_example()
  catalogue <- lity_design_templates()

  expect_gte(nrow(catalogue), 15L)
  expect_true(all(c(
    "template", "name", "category", "summary", "arms",
    "periods", "regulatory", "framework", "caution",
    "default_dose", "default_subjects_per_arm"
  ) %in% names(catalogue)))
  designs <- lapply(catalogue$template, function(template) {
    lity_design_from_template(
      template, model = example$model,
      endpoints = example$design$endpoints,
      population = example$design$population
    )
  })
  expect_true(all(vapply(designs, inherits, logical(1), "lity_design")))
  expect_true(all(vapply(
    designs, function(design) lity_validate(design)$valid, logical(1)
  )))
  expect_equal(
    vapply(designs, function(design) length(design$arms), integer(1)),
    catalogue$arms
  )
  regulatory <- catalogue[catalogue$regulatory, , drop = FALSE]
  expect_setequal(regulatory$template, c(
    "standard-be-2x2", "rsabe-full-replicate", "food-effect-2x2",
    "ddi-fixed-sequence", "tqt-four-arm", "cqt-exposure-response",
    "renal-impairment-parallel", "hepatic-impairment-parallel"
  ))
  expect_true(all(nzchar(regulatory$framework)))
  expect_true(all(nzchar(regulatory$caution)))

  be <- designs[[match("standard-be-2x2", catalogue$template)]]
  expect_equal(
    unname(vapply(
      be$arms, function(arm) length(arm$metadata$periods), integer(1)
    )),
    c(2L, 2L)
  )
  expect_setequal(
    unlist(lapply(be$arms, function(arm) unique(arm$events$TEST))),
    c(0, 1)
  )
  rsabe <- designs[[match("rsabe-full-replicate", catalogue$template)]]
  expect_equal(
    unname(vapply(
      rsabe$arms, function(arm) length(arm$metadata$periods), integer(1)
    )),
    c(4L, 4L)
  )
  ddi <- designs[[match("ddi-fixed-sequence", catalogue$template)]]
  expect_setequal(ddi$arms[[1L]]$events$INTERACTOR, c(0, 1))
  tqt <- designs[[match("tqt-four-arm", catalogue$template)]]
  expect_length(tqt$arms, 4L)
  multi <- lity_design_from_template(
    "rich-single-dose-pk", model = example$model,
    endpoints = list(
      pk = lity_endpoint("PK", dvid = 1L),
      pd = lity_endpoint("PD", dvid = 2L)
    )
  )
  observed <- multi$arms[[1L]]$events$EVID == 0L
  expect_setequal(multi$arms[[1L]]$events$DVID[observed], c(1L, 2L))
})

test_that("endpoint definitions expose and enforce GUI-selectable choices", {
  options <- LibeRality:::.lity_endpoint_options()
  expect_setequal(
    names(options),
    c(
      "continuous", "binary", "ordinal", "count",
      "time_to_event", "recurrent_event"
    )
  )
  expect_identical(
    lity_endpoint(
      "Count", "count", distribution = "negbin"
    )$distribution,
    "negative_binomial"
  )
  expect_error(
    lity_endpoint("Count", "count", link = "logit"),
    "Unsupported count endpoint link"
  )
  payload <- .lity_gui_payload(
    lity_example()$design, lity_criterion_D(), revision = 1L
  )
  expect_identical(
    payload$endpointOptions$count$links,
    c("log", "identity")
  )
  expect_true("negative_binomial" %in%
                payload$endpointOptions$count$distributions)
  expect_gte(length(payload$designTemplates), 7L)
})
