.lity_design_template_specs <- function() {
  list(
    "rich-single-dose-pk" = list(
      name = "Rich single-dose PK",
      category = "Early clinical PK",
      summary = paste(
        "One intensively sampled cohort spanning absorption, distribution,",
        "and terminal elimination after a single dose."
      ),
      default_dose = 100,
      default_subjects = 12L,
      arms = list(list(
        name = "Rich PK cohort",
        samples = c(0.25, 0.5, 1, 2, 4, 6, 8, 12, 24, 36, 48),
        dose_factor = 1
      ))
    ),
    "sparse-staggered-population-pk" = list(
      name = "Staggered sparse population PK",
      category = "Population PK",
      summary = paste(
        "Three complementary sparse-sampling cohorts covering early, middle,",
        "and late portions of the concentration-time profile."
      ),
      default_dose = 100,
      default_subjects = 24L,
      arms = list(
        list(
          name = "Early sampling cohort",
          samples = c(0.5, 1.5, 4, 12), dose_factor = 1
        ),
        list(
          name = "Middle sampling cohort",
          samples = c(1, 3, 8, 24), dose_factor = 1
        ),
        list(
          name = "Late sampling cohort",
          samples = c(2, 6, 16, 36), dose_factor = 1
        )
      )
    ),
    "multiple-dose-steady-state" = list(
      name = "Multiple-dose steady-state PK",
      category = "Repeat-dose PK",
      summary = paste(
        "One cohort evaluated across a complete dosing interval after a",
        "declared repeated regimen at steady state."
      ),
      default_dose = 100,
      default_subjects = 24L,
      arms = list(list(
        name = "Steady-state cohort",
        samples = c(0, 0.5, 1, 2, 4, 6, 8, 12),
        dose_factor = 1, ii = 12, addl = 9L, ss = 1L
      ))
    ),
    "parallel-dose-ranging" = list(
      name = "Parallel dose-ranging study",
      category = "Dose finding",
      summary = paste(
        "Three parallel active-dose cohorts for learning dose proportionality",
        "and exposure-response behavior."
      ),
      default_dose = 100,
      default_subjects = 20L,
      arms = list(
        list(
          name = "Low dose", samples = c(0.5, 1, 2, 4, 8, 24),
          dose_factor = 0.5
        ),
        list(
          name = "Middle dose", samples = c(0.5, 1, 2, 4, 8, 24),
          dose_factor = 1
        ),
        list(
          name = "High dose", samples = c(0.5, 1, 2, 4, 8, 24),
          dose_factor = 2
        )
      )
    ),
    "infusion-characterisation" = list(
      name = "IV infusion characterisation",
      category = "Early clinical PK",
      summary = paste(
        "One intravenous-infusion cohort with observations during infusion",
        "and through the post-infusion distribution and elimination phases."
      ),
      default_dose = 100,
      default_subjects = 16L,
      arms = list(list(
        name = "IV infusion cohort",
        samples = c(0.25, 0.5, 1, 2, 2.25, 3, 4, 8, 12, 24),
        dose_factor = 1, infusion_duration = 2,
        route = "intravenous"
      ))
    ),
    "paediatric-sparse-cohorts" = list(
      name = "Paediatric sparse cohorts",
      category = "Special populations",
      summary = paste(
        "Three staggered low-burden cohorts with three samples per child;",
        "population strata and covariates remain editable after loading."
      ),
      default_dose = 25,
      default_subjects = 15L,
      arms = list(
        list(
          name = "Paediatric cohort A",
          samples = c(0.5, 3, 12), dose_factor = 1, sample_volume = 1
        ),
        list(
          name = "Paediatric cohort B",
          samples = c(1, 6, 18), dose_factor = 1, sample_volume = 1
        ),
        list(
          name = "Paediatric cohort C",
          samples = c(2, 8, 24), dose_factor = 1, sample_volume = 1
        )
      )
    ),
    "parallel-exposure-response" = list(
      name = "Parallel exposure-response study",
      category = "PK/PD",
      summary = paste(
        "Three dose levels with serial early and delayed observations for",
        "joint exposure-response or biomarker learning."
      ),
      default_dose = 100,
      default_subjects = 25L,
      arms = list(
        list(
          name = "Low exposure", samples = c(0, 1, 2, 4, 8, 12, 24, 48),
          dose_factor = 0.5
        ),
        list(
          name = "Target exposure",
          samples = c(0, 1, 2, 4, 8, 12, 24, 48), dose_factor = 1
        ),
        list(
          name = "High exposure",
          samples = c(0, 1, 2, 4, 8, 12, 24, 48), dose_factor = 2
        )
      )
    ),
    "standard-be-2x2" = list(
      name = "Standard 2\u00D72 crossover bioequivalence",
      category = "Regulatory / Bioequivalence",
      summary = paste(
        "Randomised test-reference and reference-test sequences with two",
        "single-dose periods and a configurable washout."
      ),
      regulatory = TRUE,
      framework = "ICH M13A / regional bioequivalence guidance",
      caution = "Starting layout only; power, washout, analytes, sampling, and acceptance limits remain product-specific.",
      default_dose = 100,
      default_subjects = 18L,
      arms = list(
        list(
          name = "Sequence TR", sequence = "TR",
          periods = list(
            list(name = "Period 1 \u2014 Test", start = 0, treatment = "Test",
                 dose_factor = 1, covariates = list(PERIOD = 1, TEST = 1)),
            list(name = "Period 2 \u2014 Reference", start = 168,
                 treatment = "Reference", dose_factor = 1,
                 covariates = list(PERIOD = 2, TEST = 0))
          )
        ),
        list(
          name = "Sequence RT", sequence = "RT",
          periods = list(
            list(name = "Period 1 \u2014 Reference", start = 0,
                 treatment = "Reference", dose_factor = 1,
                 covariates = list(PERIOD = 1, TEST = 0)),
            list(name = "Period 2 \u2014 Test", start = 168, treatment = "Test",
                 dose_factor = 1, covariates = list(PERIOD = 2, TEST = 1))
          )
        )
      ),
      samples = c(0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 24, 36, 48, 72)
    ),
    "rsabe-full-replicate" = list(
      name = "RSABE full-replicate crossover",
      category = "Regulatory / Bioequivalence",
      summary = paste(
        "Four-period TRTR/RTRT replicate design supporting estimation of",
        "within-subject reference variability for highly variable products."
      ),
      regulatory = TRUE,
      framework = "Reference-scaled average bioequivalence",
      caution = "The applicable regulator, product-specific guidance, and prespecified RSABE analysis determine the final design and decision limits.",
      default_dose = 100,
      default_subjects = 18L,
      arms = list(
        list(
          name = "Sequence TRTR", sequence = "TRTR",
          periods = Map(function(start, test, period) list(
            name = paste("Period", period, if (test) "\u2014 Test" else "\u2014 Reference"),
            start = start, treatment = if (test) "Test" else "Reference",
            dose_factor = 1,
            covariates = list(PERIOD = period, TEST = as.integer(test))
          ), c(0, 168, 336, 504), c(TRUE, FALSE, TRUE, FALSE), 1:4)
        ),
        list(
          name = "Sequence RTRT", sequence = "RTRT",
          periods = Map(function(start, test, period) list(
            name = paste("Period", period, if (test) "\u2014 Test" else "\u2014 Reference"),
            start = start, treatment = if (test) "Test" else "Reference",
            dose_factor = 1,
            covariates = list(PERIOD = period, TEST = as.integer(test))
          ), c(0, 168, 336, 504), c(FALSE, TRUE, FALSE, TRUE), 1:4)
        )
      ),
      samples = c(0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 24, 36, 48, 72)
    ),
    "food-effect-2x2" = list(
      name = "Fed\u2013fasted food-effect crossover",
      category = "Regulatory / Clinical pharmacology",
      summary = paste(
        "Randomised fed-fast and fast-fed sequences with two single-dose",
        "periods and serial PK sampling."
      ),
      regulatory = TRUE,
      framework = "Food-effect bioavailability guidance",
      caution = "Meal composition, fasting duration, washout, and sampling must be adapted to the product and current regional guidance.",
      default_dose = 100,
      default_subjects = 16L,
      arms = list(
        list(
          name = "Sequence Fed\u2013Fast", sequence = "Fed-Fast",
          periods = list(
            list(name = "Period 1 \u2014 Fed", start = 0, treatment = "Fed",
                 dose_factor = 1, covariates = list(PERIOD = 1, FED = 1)),
            list(name = "Period 2 \u2014 Fasted", start = 168,
                 treatment = "Fasted", dose_factor = 1,
                 covariates = list(PERIOD = 2, FED = 0))
          )
        ),
        list(
          name = "Sequence Fast\u2013Fed", sequence = "Fast-Fed",
          periods = list(
            list(name = "Period 1 \u2014 Fasted", start = 0,
                 treatment = "Fasted", dose_factor = 1,
                 covariates = list(PERIOD = 1, FED = 0)),
            list(name = "Period 2 \u2014 Fed", start = 168, treatment = "Fed",
                 dose_factor = 1, covariates = list(PERIOD = 2, FED = 1))
          )
        )
      ),
      samples = c(0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 24, 36, 48, 72)
    ),
    "ddi-fixed-sequence" = list(
      name = "Clinical DDI fixed-sequence study",
      category = "Regulatory / Clinical pharmacology",
      summary = paste(
        "Within-subject victim-drug PK without and with a perpetrator at",
        "the intended maximal interaction condition."
      ),
      regulatory = TRUE,
      framework = "ICH M12 clinical drug-interaction assessment",
      caution = "Perpetrator lead-in, dose timing, enzyme/transporter mechanism, metabolites, and washout must be configured for the drug pair.",
      default_dose = 100,
      default_subjects = 18L,
      arms = list(list(
        name = "Victim alone \u2192 interaction", sequence = "Control-DDI",
        periods = list(
          list(name = "Victim drug alone", start = 0, treatment = "Control",
               dose_factor = 1,
               covariates = list(PERIOD = 1, INTERACTOR = 0)),
          list(name = "Victim with perpetrator", start = 168,
               treatment = "Interaction", dose_factor = 1,
               covariates = list(PERIOD = 2, INTERACTOR = 1))
        )
      )),
      samples = c(0, 0.5, 1, 2, 3, 4, 6, 8, 12, 24, 36, 48, 72)
    ),
    "tqt-four-arm" = list(
      name = "Thorough QT (TQT) four-arm study",
      category = "Regulatory / Cardiac safety",
      summary = paste(
        "Placebo, therapeutic, supratherapeutic, and positive-control arms",
        "with time-matched ECG and PK observations."
      ),
      regulatory = TRUE,
      framework = "ICH E14 thorough QT/QTc assessment",
      caution = "This layout requires a QTc endpoint/model, baseline handling, assay sensitivity, ECG replicates, and protocol-specific dose/safety review.",
      default_dose = 100,
      default_subjects = 40L,
      arms = list(
        list(name = "Placebo", samples = c(0, 0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 24),
             dose_factor = 0, covariates = list(TREATMENT = 0, ACTIVE = 0)),
        list(name = "Therapeutic dose", samples = c(0, 0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 24),
             dose_factor = 1, covariates = list(TREATMENT = 1, ACTIVE = 1)),
        list(name = "Supratherapeutic dose", samples = c(0, 0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 24),
             dose_factor = 2, covariates = list(TREATMENT = 2, ACTIVE = 1)),
        list(name = "Positive control", samples = c(0, 0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 24),
             dose_factor = 4, covariates = list(TREATMENT = 3, ACTIVE = 0))
      )
    ),
    "cqt-exposure-response" = list(
      name = "Concentration\u2013QTc (C-QT) exposure-response",
      category = "Regulatory / Cardiac safety",
      summary = paste(
        "Placebo and multiple active exposure levels with aligned ECG/PK",
        "sampling for concentration\u2013QTc modelling."
      ),
      regulatory = TRUE,
      framework = "ICH E14 concentration-response modelling",
      caution = "A prespecified C-QT model, baseline correction, time effects, hysteresis assessment, and adequate high-exposure coverage remain essential.",
      default_dose = 100,
      default_subjects = 30L,
      arms = list(
        list(name = "Placebo", samples = c(0, 0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 24),
             dose_factor = 0, covariates = list(DOSE_LEVEL = 0)),
        list(name = "Low exposure", samples = c(0, 0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 24),
             dose_factor = 0.5, covariates = list(DOSE_LEVEL = 1)),
        list(name = "Therapeutic exposure", samples = c(0, 0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 24),
             dose_factor = 1, covariates = list(DOSE_LEVEL = 2)),
        list(name = "High exposure", samples = c(0, 0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 24),
             dose_factor = 2, covariates = list(DOSE_LEVEL = 3))
      )
    ),
    "renal-impairment-parallel" = list(
      name = "Renal-impairment PK study",
      category = "Regulatory / Special populations",
      summary = paste(
        "Parallel matched cohorts spanning normal, moderate, severe, and",
        "end-stage renal function for covariate-effect estimation."
      ),
      regulatory = TRUE,
      framework = "Renal-impairment clinical pharmacology assessment",
      caution = "Renal categories, dialysis timing, matching factors, safety, and sample size require compound-specific justification.",
      default_dose = 100,
      default_subjects = 8L,
      arms = list(
        list(name = "Normal renal function", samples = c(0.5, 1, 2, 4, 8, 12, 24, 48, 72),
             dose_factor = 1, covariates = list(EGFR = 100, RENAL_GROUP = 0)),
        list(name = "Moderate impairment", samples = c(0.5, 1, 2, 4, 8, 12, 24, 48, 72),
             dose_factor = 1, covariates = list(EGFR = 45, RENAL_GROUP = 2)),
        list(name = "Severe impairment", samples = c(0.5, 1, 2, 4, 8, 12, 24, 48, 72),
             dose_factor = 1, covariates = list(EGFR = 20, RENAL_GROUP = 3)),
        list(name = "End-stage kidney disease", samples = c(0.5, 1, 2, 4, 8, 12, 24, 48, 72),
             dose_factor = 1, covariates = list(EGFR = 8, RENAL_GROUP = 4))
      )
    ),
    "hepatic-impairment-parallel" = list(
      name = "Hepatic-impairment PK study",
      category = "Regulatory / Special populations",
      summary = paste(
        "Parallel matched control and Child\u2013Pugh impairment cohorts for",
        "estimating hepatic-function effects on exposure."
      ),
      regulatory = TRUE,
      framework = "Hepatic-impairment clinical pharmacology assessment",
      caution = "Cohort severity, matching, protein binding, active metabolites, dose reduction, and safety require compound-specific review.",
      default_dose = 100,
      default_subjects = 8L,
      arms = list(
        list(name = "Matched control", samples = c(0.5, 1, 2, 4, 8, 12, 24, 48, 72),
             dose_factor = 1, covariates = list(CHILD_PUGH = 0)),
        list(name = "Mild impairment", samples = c(0.5, 1, 2, 4, 8, 12, 24, 48, 72),
             dose_factor = 1, covariates = list(CHILD_PUGH = 1)),
        list(name = "Moderate impairment", samples = c(0.5, 1, 2, 4, 8, 12, 24, 48, 72),
             dose_factor = 1, covariates = list(CHILD_PUGH = 2)),
        list(name = "Severe impairment", samples = c(0.5, 1, 2, 4, 8, 12, 24, 48, 72),
             dose_factor = 1, covariates = list(CHILD_PUGH = 3))
      )
    )
  )
}

#' List built-in clinical trial design templates
#'
#' Templates define a complete, editable trial-layout starting point. Applying
#' one returns the same versioned [lity_design()] object used throughout
#' LibeRality; it does not create a separate or simplified design format.
#'
#' @return A data frame describing the available templates.
#' @export
lity_design_templates <- function() {
  specs <- .lity_design_template_specs()
  data.frame(
    template = names(specs),
    name = vapply(specs, `[[`, character(1), "name"),
    category = vapply(specs, `[[`, character(1), "category"),
    summary = vapply(specs, `[[`, character(1), "summary"),
    arms = vapply(specs, function(item) length(item$arms), integer(1)),
    periods = vapply(specs, function(item) {
      max(c(1L, vapply(
        item$arms,
        function(arm) length(arm$periods %||% list()),
        integer(1)
      )))
    }, integer(1)),
    regulatory = vapply(specs, function(item) isTRUE(item$regulatory), logical(1)),
    framework = vapply(
      specs, function(item) as.character(item$framework %||% ""),
      character(1)
    ),
    caution = vapply(
      specs, function(item) as.character(item$caution %||% ""),
      character(1)
    ),
    default_dose = vapply(specs, `[[`, numeric(1), "default_dose"),
    default_subjects_per_arm = vapply(
      specs, `[[`, integer(1), "default_subjects"
    ),
    stringsAsFactors = FALSE
  )
}

#' Create an editable LibeRality design from a trial template
#'
#' @param template Template identifier from [lity_design_templates()].
#' @param model A validated LibeRation `nm_model`.
#' @param endpoints Optional endpoint definitions; by default they are inferred
#'   by [lity_design()].
#' @param base_dose Reference dose multiplied by any template arm-specific dose
#'   factors.
#' @param subjects_per_arm Exact subject count assigned to every generated arm.
#' @param name Optional design name.
#' @param population,scenarios Population and uncertainty definitions retained
#'   in the resulting design.
#' @param metadata Additional design metadata.
#' @return A complete versioned `lity_design`.
#' @export
lity_design_from_template <- function(
    template, model, endpoints = NULL, base_dose = NULL,
    subjects_per_arm = NULL, name = NULL,
    population = lity_population(), scenarios = NULL, metadata = list()) {
  specs <- .lity_design_template_specs()
  template <- match.arg(as.character(template)[[1L]], names(specs))
  spec <- specs[[template]]
  if (!inherits(model, "nm_model")) {
    .lity_stop("`model` must be a LibeRation nm_model.")
  }
  base_dose <- .lity_number(
    base_dose %||% spec$default_dose, "base_dose", lower = 0
  )
  subjects_per_arm <- as.integer(
    subjects_per_arm %||% spec$default_subjects
  )
  if (
    length(subjects_per_arm) != 1L || is.na(subjects_per_arm) ||
      subjects_per_arm < 1L
  ) {
    .lity_stop("`subjects_per_arm` must be a positive integer.")
  }
  dose_cmt <- as.integer(model$DOSECMP %||% 1L)
  observation_cmt <- as.integer(model$OBSCMP %||% dose_cmt)
  covariates <- stats::setNames(
    lapply(
      as.character(model$COVARIATES %||% character()),
      .lity_covariate_default
    ),
    as.character(model$COVARIATES %||% character())
  )
  endpoint_dvid <- if (length(endpoints)) {
    as.integer(endpoints[[1L]]$dvid %||% 1L)
  } else {
    1L
  }
  arms <- lapply(spec$arms, function(arm) {
    periods <- arm$periods %||% list(arm)
    events <- do.call(rbind, lapply(seq_along(periods), function(period_index) {
      period <- periods[[period_index]]
      start <- as.numeric(period$start %||% 0)
      samples <- as.numeric(
        period$samples %||% arm$samples %||% spec$samples
      )
      if (!length(samples)) {
        .lity_stop(
          "Template `", template, "` arm `", arm$name,
          "` does not define sampling times."
        )
      }
      sampling <- if (length(endpoints) > 1L) {
        do.call(rbind, lapply(endpoints, function(endpoint) {
          data.frame(
            TIME = start + samples,
            DVID = as.integer(endpoint$dvid),
            CMT = observation_cmt
          )
        }))
      } else {
        start + samples
      }
      duration <- period$infusion_duration %||%
        arm$infusion_duration %||% NULL
      period_covariates <- utils::modifyList(
        covariates,
        utils::modifyList(
          arm$covariates %||% list(),
          period$covariates %||% list()
        )
      )
      schedule <- lity_schedule(
        sampling_times = sampling,
        dose = base_dose * as.numeric(
          period$dose_factor %||% arm$dose_factor %||% 1
        ),
        dose_times = start + as.numeric(
          period$dose_times %||% arm$dose_times %||% 0
        ),
        dose_cmt = dose_cmt,
        observation_cmt = observation_cmt,
        duration = duration,
        ii = as.numeric(period$ii %||% arm$ii %||% 0),
        addl = as.integer(period$addl %||% arm$addl %||% 0L),
        ss = as.integer(period$ss %||% arm$ss %||% 0L),
        route = as.character(
          period$route %||% arm$route %||%
            if (is.null(duration)) "extravascular" else "intravenous"
        ),
        dvid = endpoint_dvid,
        covariates = period_covariates
      )
      schedule$.LITY_PERIOD <- period_index
      schedule
    }))
    events <- events[
      order(events$TIME, -events$EVID, events$.LITY_PERIOD),
      , drop = FALSE
    ]
    events$.LITY_OBS <- ifelse(
      events$EVID == 0L, seq_len(nrow(events)), NA_integer_
    )
    events$.LITY_DOSE <- ifelse(
      events$EVID != 0L, seq_len(nrow(events)), NA_integer_
    )
    rownames(events) <- NULL
    attr(events, "lity_schedule") <- list(
      route = as.character(
        arm$route %||%
          if (is.null(arm$infusion_duration)) {
            "extravascular"
          } else {
            "intravenous"
          }
      ),
      template = template,
      sequence = as.character(arm$sequence %||% "")
    )
    lity_arm(
      arm$name, events, size = subjects_per_arm,
      sample_volume = as.numeric(arm$sample_volume %||% 3),
      metadata = list(
        route = as.character(
          attr(events, "lity_schedule")$route %||% "extravascular"
        ),
        template = template,
        sequence = as.character(arm$sequence %||% ""),
        periods = lapply(seq_along(periods), function(index) list(
          index = index,
          name = as.character(
            periods[[index]]$name %||% paste("Period", index)
          ),
          start = as.numeric(periods[[index]]$start %||% 0),
          treatment = as.character(periods[[index]]$treatment %||% "")
        ))
      )
    )
  })
  names(arms) <- make.unique(vapply(
    spec$arms,
    function(arm) {
      value <- tolower(gsub("[^a-zA-Z0-9]+", "-", arm$name))
      gsub("(^-+|-+$)", "", value)
    },
    character(1)
  ))
  constraints <- list(
    minimum_separation = lity_constraint(
      "At least 15 minutes between samples",
      "min_separation", 0.25
    )
  )
  lity_design(
    model = model, arms = arms, endpoints = endpoints,
    population = population, scenarios = scenarios,
    constraints = constraints,
    name = name %||% spec$name,
    description = spec$summary,
    metadata = utils::modifyList(metadata, list(
      design_template = list(
        id = template, version = 1L, applied_at = .lity_now(),
        base_dose = base_dose,
        subjects_per_arm = subjects_per_arm,
        regulatory = isTRUE(spec$regulatory),
        framework = as.character(spec$framework %||% ""),
        caution = as.character(spec$caution %||% "")
      )
    ))
  )
}

.lity_gui_apply_design_template <- function(design, event) {
  template <- as.character(event$template %||% "")[[1L]]
  design_name <- trimws(as.character(event$name %||% "")[[1L]])
  base_dose <- suppressWarnings(as.numeric(event$baseDose))
  if (length(base_dose) != 1L || !is.finite(base_dose)) base_dose <- NULL
  subjects <- suppressWarnings(as.integer(event$subjectsPerArm))
  if (length(subjects) != 1L || is.na(subjects)) subjects <- NULL
  history <- design$metadata$template_history %||% list()
  history[[length(history) + 1L]] <- list(
    applied_at = .lity_now(),
    template = template,
    previous_design_id = design$id,
    previous_design_hash = .lity_hash(design)
  )
  metadata <- design$metadata
  metadata$template_history <- history
  lity_design_from_template(
    template = template,
    model = design$model,
    endpoints = design$endpoints,
    base_dose = base_dose,
    subjects_per_arm = subjects,
    name = if (nzchar(design_name)) design_name else NULL,
    population = design$population,
    scenarios = design$scenarios,
    metadata = metadata
  )
}
