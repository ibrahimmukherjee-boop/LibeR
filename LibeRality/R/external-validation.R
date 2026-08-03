.lity_external_require <- function(package) {
  if (!requireNamespace(package, quietly = TRUE)) {
    .lity_stop(
      "External validation requires `", package, "`. Install it with ",
      "install.packages(\"", package, "\")."
    )
  }
  invisible(TRUE)
}

.lity_external_error_spec <- function(error) {
  switch(error,
    proportional = list(
      sigma = 0.0225, error_code = "Y=F*(1+ERR(1))",
      names = "SIGMA_PROP", values = c(SIGMA_PROP = 0.0225),
      poped_error = "prop", poped_sigma = 0.0225,
      pfim_error = "prop", pfim_sd = c(SIGMA_PROP = 0.15)
    ),
    additive = list(
      sigma = 0.25, error_code = "Y=F+ERR(1)",
      names = "SIGMA_ADD", values = c(SIGMA_ADD = 0.25),
      poped_error = "add", poped_sigma = 0.25,
      pfim_error = "add", pfim_sd = c(SIGMA_ADD = 0.5)
    ),
    combined = list(
      sigma = c(0.0225, 0.25), error_code = "Y=F*(1+ERR(1))+ERR(2)",
      names = c("SIGMA_PROP", "SIGMA_ADD"),
      values = c(SIGMA_PROP = 0.0225, SIGMA_ADD = 0.25),
      poped_error = "combined", poped_sigma = diag(c(0.0225, 0.25)),
      pfim_error = "combined", pfim_sd = c(SIGMA_ADD = 0.5, SIGMA_PROP = 0.15)
    ),
    .lity_stop("Unknown external-validation residual model.")
  )
}

.lity_external_fixture_spec <- function(id) {
  fixtures <- list(
    oral_proportional = list(
      id = "oral_proportional", route = "oral", error = "proportional",
      description = "One-compartment first-order absorption with proportional error",
      theta_names = c("KA", "CL", "V"), theta = c(KA = 1.2, CL = 4, V = 35),
      omega = c(OMEGA_KA = 0.20, OMEGA_CL = 0.10, OMEGA_V = 0.15),
      times = c(0.5, 1, 2, 4, 8, 12, 24), dose = 500, size = 60
    ),
    bolus_additive = list(
      id = "bolus_additive", route = "bolus", error = "additive",
      description = "One-compartment IV bolus with additive error",
      theta_names = c("CL", "V"), theta = c(CL = 4, V = 35),
      omega = c(OMEGA_CL = 0.10, OMEGA_V = 0.15),
      times = c(0.25, 0.5, 1, 2, 4, 8, 12, 24), dose = 500, size = 48
    ),
    oral_combined = list(
      id = "oral_combined", route = "oral", error = "combined",
      description = "One-compartment first-order absorption with combined error",
      theta_names = c("KA", "CL", "V"), theta = c(KA = 1.2, CL = 4, V = 35),
      omega = c(OMEGA_KA = 0.20, OMEGA_CL = 0.10, OMEGA_V = 0.15),
      times = c(0.5, 1, 2, 4, 8, 12, 24), dose = 500, size = 60,
      support = c(PopED = TRUE, PFIM = FALSE),
      skip_reason = c(PFIM = paste(
        "PFIM 7.0.3 implements Combined1 as (a + b*f)^2;",
        "the independent additive-plus-proportional variance a^2 + b^2*f^2 is not available."
      ))
    )
  )
  fixture <- fixtures[[id]]
  if (is.null(fixture)) .lity_stop("Unknown external-validation fixture `", id, "`.")
  residual <- .lity_external_error_spec(fixture$error)
  fixture$residual <- residual
  fixture$support <- fixture$support %||% c(PopED = TRUE, PFIM = TRUE)
  fixture$skip_reason <- fixture$skip_reason %||% character()
  fixture$parameters <- c(
    fixture$theta_names, names(fixture$omega), residual$names
  )
  fixture$values <- c(fixture$theta, fixture$omega, residual$values)[fixture$parameters]
  fixture
}

#' External validation fixtures
#'
#' @return Character vector of versioned matched-design fixture identifiers.
#' @export
lity_external_validation_fixtures <- function() {
  c("oral_proportional", "bolus_additive", "oral_combined")
}

.lity_external_liberality_setup <- function(spec) {
  oral <- identical(spec$route, "oral")
  theta <- data.frame(
    THETA = seq_along(spec$theta), Value = unname(spec$theta),
    LOWER = pmax(unname(spec$theta) / 1000, 1e-8),
    UPPER = unname(spec$theta) * 1000
  )
  omega <- data.frame(OMEGA = seq_along(spec$omega), Value = unname(spec$omega))
  sigma <- data.frame(SIGMA = seq_along(spec$residual$sigma), Value = spec$residual$sigma)
  model <- LibeRation::nm_model(
    INPUT = c("ID", "TIME", "EVID", "AMT", "RATE", "CMT", "DV", "MDV", "DVID"),
    ADVAN = if (oral) 2L else 1L, TRANS = 2L,
    DOSECMP = 1L, OBSCMP = if (oral) 2L else 1L,
    PRED = if (oral) {
      "KA=THETA(1)*exp(ETA(1));CL=THETA(2)*exp(ETA(2));V=THETA(3)*exp(ETA(3));S2=V"
    } else {
      "CL=THETA(1)*exp(ETA(1));V=THETA(2)*exp(ETA(2));S1=V"
    },
    ERROR = spec$residual$error_code, THETAS = theta, OMEGAS = omega,
    SIGMAS = sigma,
    LIK_CONFIG = LibeRation::nm_lik_config(
      error = spec$error, sigma_parameterization = "variance"
    )
  )
  arm <- lity_arm(
    "Reference arm",
    lity_schedule(
      spec$times, dose = spec$dose, dose_cmt = 1L,
      observation_cmt = if (oral) 2L else 1L
    ), size = spec$size
  )
  lity_design(
    model, arms = list(reference = arm),
    endpoints = list(pk = lity_endpoint("Concentration", "continuous", dvid = 1L)),
    name = spec$description, description = paste("External validation fixture", spec$id)
  )
}

.lity_external_poped_functions <- function(spec) {
  if (identical(spec$route, "oral")) {
    ff <- function(model_switch, xt, parameters, poped.db) {
      with(as.list(parameters), {
        y <- DOSE / V * KA / (KA - CL / V) * (exp(-CL / V * xt) - exp(-KA * xt))
        list(y = y, poped.db = poped.db)
      })
    }
    fg <- function(x, a, bpop, b, bocc) {
      c(KA = bpop[1] * exp(b[1]), CL = bpop[2] * exp(b[2]),
        V = bpop[3] * exp(b[3]), DOSE = a[1])
    }
  } else {
    ff <- function(model_switch, xt, parameters, poped.db) {
      with(as.list(parameters), {
        y <- DOSE / V * exp(-CL / V * xt)
        list(y = y, poped.db = poped.db)
      })
    }
    fg <- function(x, a, bpop, b, bocc) {
      c(CL = bpop[1] * exp(b[1]), V = bpop[2] * exp(b[2]), DOSE = a[1])
    }
  }
  list(ff = ff, fg = fg)
}

.lity_external_poped_setup <- function(spec) {
  .lity_external_require("PopED")
  functions <- .lity_external_poped_functions(spec)
  error_function <- switch(spec$residual$poped_error,
    prop = PopED::feps.prop, add = PopED::feps.add,
    combined = PopED::feps.add.prop
  )
  PopED::create.poped.database(
    ff_fun = functions$ff, fg_fun = functions$fg, fError_fun = error_function,
    groupsize = spec$size, m = 1L, bpop = spec$theta,
    d = stats::setNames(unname(spec$omega), spec$theta_names),
    sigma = spec$residual$poped_sigma, xt = spec$times,
    a = matrix(spec$dose, nrow = 1L),
    notfixed_bpop = rep(1, length(spec$theta)),
    notfixed_d = rep(1, length(spec$omega)),
    notfixed_sigma = rep(1, length(spec$residual$names))
  )
}

.lity_external_pfim_setup <- function(spec) {
  .lity_external_require("PFIM")
  model_parameters <- lapply(seq_along(spec$theta_names), function(index) {
    PFIM::ModelParameter(
      name = switch(spec$theta_names[[index]], KA = "ka", CL = "Cl", V = "V"),
      distribution = PFIM::LogNormal(
        mu = unname(spec$theta[[index]]), omega = sqrt(unname(spec$omega[[index]]))
      )
    )
  })
  error_model <- switch(spec$residual$pfim_error,
    prop = list(PFIM::Proportional(output = "RespPK", sigmaSlope = 0.15)),
    add = list(PFIM::Constant(output = "RespPK", sigmaInter = 0.5)),
    combined = list(PFIM::Combined1(
      output = "RespPK", sigmaInter = 0.5, sigmaSlope = 0.15,
      # PFIM's default Combined1 uses (a + b*f)^2.  PopED and LibeRality
      # use independent additive and proportional errors, a^2 + b^2*f^2.
      equation = expression(sqrt(sigmaInter^2 + (sigmaSlope * RespPK)^2))
    ))
  )
  administration <- PFIM::Administration(
    outcome = "RespPK", timeDose = 0, dose = spec$dose
  )
  sampling <- PFIM::SamplingTimes(outcome = "RespPK", samplings = spec$times)
  arm <- PFIM::Arm(
    name = "reference", size = spec$size,
    administrations = list(administration), samplingTimes = list(sampling)
  )
  design <- PFIM::Design(name = spec$id, arms = list(arm))
  PFIM::Evaluation(
    name = paste0("LibeRality-", spec$id),
    modelFromLibrary = list(PKModel = if (identical(spec$route, "oral")) {
      "Linear1FirstOrderSingleDose_kaClV"
    } else "Linear1BolusSingleDose_ClV"),
    modelParameters = model_parameters, modelError = error_model,
    outputs = list("RespPK"), designs = list(design), fimType = "population"
  )
}

.lity_external_time <- function(setup, evaluate, repetitions) {
  clock <- function() as.numeric(Sys.time())
  setup_start <- clock()
  object <- setup()
  setup_seconds <- clock() - setup_start
  cold_start <- clock()
  result <- evaluate(object)
  cold_evaluation_seconds <- clock() - cold_start
  core <- numeric(repetitions)
  for (index in seq_len(repetitions)) {
    start <- clock()
    evaluate(object)
    core[[index]] <- clock() - start
  }
  end_to_end <- numeric(repetitions)
  for (index in seq_len(repetitions)) {
    start <- clock()
    candidate <- setup()
    evaluate(candidate)
    end_to_end[[index]] <- clock() - start
  }
  list(
    object = object, result = result, setup_seconds = setup_seconds, core_seconds = core,
    cold_evaluation_seconds = cold_evaluation_seconds,
    cold_end_to_end_seconds = setup_seconds + cold_evaluation_seconds,
    end_to_end_seconds = end_to_end
  )
}

.lity_external_reorder <- function(matrix, native_order, canonical_order, scale = NULL) {
  matrix <- as.matrix(matrix)
  if (!all(dim(matrix) == length(native_order))) {
    .lity_stop("External FIM dimension did not match the declared fixture parameter map.")
  }
  if (is.null(scale)) scale <- rep(1, length(native_order))
  transform <- diag(as.numeric(scale), length(scale))
  matrix <- transform %*% matrix %*% transform
  dimnames(matrix) <- list(native_order, native_order)
  matrix[canonical_order, canonical_order, drop = FALSE]
}

.lity_external_engine_run <- function(spec, engine, repetitions) {
  if (identical(engine, "LibeRality")) {
    timed <- .lity_external_time(
      function() .lity_external_liberality_setup(spec),
      function(design) lity_information(design, approximation = "fo_block"),
      repetitions
    )
    native_order <- spec$parameters
    matrix <- .lity_external_reorder(timed$result$matrix, native_order, spec$parameters)
    full <- lity_information(timed$object)
    full_matrix <- .lity_external_reorder(full$matrix, native_order, spec$parameters)
  } else if (identical(engine, "PopED")) {
    timed <- .lity_external_time(
      function() .lity_external_poped_setup(spec),
      function(database) PopED::evaluate_design(database, silent = TRUE),
      repetitions
    )
    native_order <- c(spec$theta_names, names(spec$omega), spec$residual$names)
    matrix <- .lity_external_reorder(timed$result$fim, native_order, spec$parameters)
    full_matrix <- NULL
  } else {
    timed <- .lity_external_time(
      function() .lity_external_pfim_setup(spec), PFIM::run, repetitions
    )
    native_order <- c(
      spec$theta_names, names(spec$omega),
      if (identical(spec$error, "combined")) c("SIGMA_ADD", "SIGMA_PROP") else spec$residual$names
    )
    native <- PFIM::getFisherMatrix(timed$result)$fisherMatrix
    scale <- rep(1, length(native_order)); names(scale) <- native_order
    for (name in names(spec$residual$pfim_sd)) {
      scale[[name]] <- 1 / (2 * spec$residual$pfim_sd[[name]])
    }
    matrix <- .lity_external_reorder(native, native_order, spec$parameters, scale)
    full_matrix <- NULL
  }
  covariance <- .lity_safe_inverse(matrix)
  se <- sqrt(pmax(diag(covariance), 0)); names(se) <- spec$parameters
  rse <- 100 * se / abs(spec$values[spec$parameters])
  eigenvalues <- eigen((matrix + t(matrix)) / 2, symmetric = TRUE, only.values = TRUE)$values
  positive <- eigenvalues[eigenvalues > max(abs(eigenvalues), 1) * 1e-12]
  log_determinant <- if (length(positive) == nrow(matrix)) sum(log(positive)) else -Inf
  list(
    engine = engine, matrix = matrix, full_gaussian_matrix = full_matrix,
    se = se, rse = rse, log_determinant = log_determinant,
    setup_seconds = timed$setup_seconds, core_seconds = timed$core_seconds,
    cold_evaluation_seconds = timed$cold_evaluation_seconds,
    cold_end_to_end_seconds = timed$cold_end_to_end_seconds,
    end_to_end_seconds = timed$end_to_end_seconds
  )
}

.lity_external_compare <- function(reference, candidate, tolerance) {
  delta <- candidate$matrix - reference$matrix
  threshold <- tolerance$absolute + tolerance$relative * pmax(
    abs(reference$matrix), abs(candidate$matrix)
  )
  denominator <- pmax(abs(reference$matrix), abs(candidate$matrix), tolerance$absolute)
  list(
    pass = all(abs(delta) <= threshold) &&
      max(abs(candidate$rse - reference$rse), na.rm = TRUE) <= tolerance$rse,
    max_absolute = max(abs(delta)),
    max_relative = max(abs(delta) / denominator),
    frobenius_relative = sqrt(sum(delta^2)) / max(sqrt(sum(reference$matrix^2)), tolerance$absolute),
    rse_max_absolute = max(abs(candidate$rse - reference$rse), na.rm = TRUE),
    log_determinant_absolute = abs(candidate$log_determinant - reference$log_determinant)
  )
}

.lity_external_comparison_row <- function(fixture, reference, candidate, metrics) {
  data.frame(
    fixture = fixture, reference = reference, candidate = candidate,
    pass = metrics$pass, max_absolute = metrics$max_absolute,
    max_relative = metrics$max_relative,
    frobenius_relative = metrics$frobenius_relative,
    rse_max_absolute = metrics$rse_max_absolute,
    log_determinant_absolute = metrics$log_determinant_absolute,
    stringsAsFactors = FALSE
  )
}

.lity_external_timing_rows <- function(fixture, result) {
  data.frame(
    fixture = fixture, engine = result$engine,
    setup_seconds = result$setup_seconds,
    cold_evaluation_seconds = result$cold_evaluation_seconds,
    cold_end_to_end_seconds = result$cold_end_to_end_seconds,
    core_median_seconds = stats::median(result$core_seconds),
    core_min_seconds = min(result$core_seconds),
    end_to_end_median_seconds = stats::median(result$end_to_end_seconds),
    end_to_end_min_seconds = min(result$end_to_end_seconds),
    repetitions = length(result$core_seconds), stringsAsFactors = FALSE
  )
}

.lity_external_grid_search <- function(engines) {
  spec <- .lity_external_fixture_spec("oral_proportional")
  candidates <- c(0.1, 0.25, 0.5, 0.75)
  rows <- list()
  for (candidate in candidates) {
    candidate_spec <- spec
    candidate_spec$times <- c(candidate, 1, 2, 4, 8, 12, 24)
    for (engine in c("LibeRality", engines)) {
      run <- .lity_external_engine_run(candidate_spec, engine, 1L)
      rows[[length(rows) + 1L]] <- data.frame(
        fixture = "oral_proportional_grid", engine = engine,
        candidate_time = candidate, log_determinant = run$log_determinant,
        d_optimality = exp(run$log_determinant / nrow(run$matrix)),
        end_to_end_seconds = run$end_to_end_seconds[[1L]],
        stringsAsFactors = FALSE
      )
    }
  }
  rows <- do.call(rbind, rows)
  rows$is_best <- stats::ave(rows$log_determinant, rows$engine, FUN = function(value) {
    value >= max(value) - 1e-10
  }) == 1
  best <- rows[rows$is_best, c("engine", "candidate_time", "log_determinant", "d_optimality"), drop = FALSE]
  best <- best[!duplicated(best$engine), , drop = FALSE]
  pass <- length(unique(best$candidate_time)) == 1L &&
    diff(range(best$log_determinant)) <= 1e-4
  list(rows = rows, best = best, pass = pass)
}

.lity_external_write <- function(result, output_dir) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  matrix_dir <- file.path(output_dir, "matrices")
  dir.create(matrix_dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(result, file.path(output_dir, "external-validation.rds"), version = 3)
  utils::write.csv(result$comparisons, file.path(output_dir, "comparisons.csv"), row.names = FALSE)
  utils::write.csv(result$coverage, file.path(output_dir, "coverage.csv"), row.names = FALSE)
  utils::write.csv(result$timings, file.path(output_dir, "timings.csv"), row.names = FALSE)
  utils::write.csv(result$design_search$rows, file.path(output_dir, "design-search.csv"), row.names = FALSE)
  for (fixture in names(result$fixtures)) {
    for (engine in names(result$fixtures[[fixture]]$engines)) {
      utils::write.csv(
        result$fixtures[[fixture]]$engines[[engine]]$matrix,
        file.path(matrix_dir, paste0(fixture, "-", tolower(engine), ".csv"))
      )
    }
  }
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    manifest <- unclass(result)
    for (fixture in names(manifest$fixtures)) {
      for (engine in names(manifest$fixtures[[fixture]]$engines)) {
        manifest$fixtures[[fixture]]$engines[[engine]]$matrix <- NULL
        manifest$fixtures[[fixture]]$engines[[engine]]$full_gaussian_matrix <- NULL
      }
    }
    jsonlite::write_json(
      manifest, file.path(output_dir, "manifest.json"), auto_unbox = TRUE,
      pretty = TRUE, digits = 16, null = "null", na = "null"
    )
  }
  lity_external_validation_report(result, file.path(output_dir, "report.html"))
  normalizePath(output_dir, winslash = "/", mustWork = TRUE)
}

#' Validate LibeRality against PopED and PFIM
#'
#' Runs matched population-FO designs through LibeRality, PopED, and PFIM,
#' transforms all residual-error parameters to a common variance scale, and
#' compares complete Fisher matrices, RSEs, determinants, and runtimes.
#'
#' @param fixtures Fixture identifiers returned by
#'   [lity_external_validation_fixtures()].
#' @param engines External engines to run in addition to LibeRality.
#' @param repetitions Number of core and end-to-end timing repetitions.
#' @param tolerance Named list with `absolute`, `relative`, and `rse`
#'   tolerances. RSE tolerance is in percentage points.
#' @param output_dir Optional directory for RDS, CSV, JSON, matrix, and HTML
#'   artifacts.
#' @param design_search Whether to run a matched D-optimal candidate-grid search.
#' @return A `lity_external_validation` object.
#' @export
lity_external_validate <- function(
    fixtures = lity_external_validation_fixtures(),
    engines = c("PopED", "PFIM"), repetitions = 3L,
    tolerance = list(absolute = 1e-5, relative = 1e-4, rse = 0.01),
    output_dir = NULL, design_search = TRUE) {
  fixtures <- unique(as.character(fixtures))
  unknown <- setdiff(fixtures, lity_external_validation_fixtures())
  if (length(unknown)) .lity_stop("Unknown validation fixtures: ", paste(unknown, collapse = ", "), ".")
  engines <- unique(match.arg(engines, c("PopED", "PFIM"), several.ok = TRUE))
  repetitions <- as.integer(repetitions)
  if (length(repetitions) != 1L || is.na(repetitions) || repetitions < 1L) {
    .lity_stop("`repetitions` must be one positive integer.")
  }
  tolerance <- utils::modifyList(list(absolute = 1e-5, relative = 1e-4, rse = 0.01), tolerance)
  if (any(!is.finite(unlist(tolerance[c("absolute", "relative", "rse")]))) ||
      any(unlist(tolerance[c("absolute", "relative", "rse")]) < 0)) {
    .lity_stop("External-validation tolerances must be finite and non-negative.")
  }
  for (engine in engines) .lity_external_require(engine)
  versions <- c(
    LibeRality = tryCatch(as.character(utils::packageVersion("LibeRality")), error = function(e) "development"),
    stats::setNames(vapply(engines, function(engine) as.character(utils::packageVersion(engine)), character(1)), engines)
  )
  fixture_results <- list(); comparisons <- list(); timings <- list()
  coverage <- list()
  for (fixture in fixtures) {
    spec <- .lity_external_fixture_spec(fixture)
    supported <- engines[vapply(engines, function(engine) isTRUE(spec$support[[engine]]), logical(1))]
    for (engine in engines) {
      available <- engine %in% supported
      coverage[[length(coverage) + 1L]] <- data.frame(
        fixture = fixture, engine = engine,
        status = if (available) "validated" else "not supported by common convention",
        reason = if (available) "" else as.character(spec$skip_reason[[engine]] %||% "No mathematically equivalent fixture is available."),
        stringsAsFactors = FALSE
      )
    }
    run_names <- c("LibeRality", supported)
    runs <- stats::setNames(lapply(run_names, function(engine) {
      .lity_external_engine_run(spec, engine, repetitions)
    }), run_names)
    reference <- runs$LibeRality
    for (engine in supported) {
      metrics <- .lity_external_compare(reference, runs[[engine]], tolerance)
      comparisons[[length(comparisons) + 1L]] <- .lity_external_comparison_row(
        fixture, "LibeRality", engine, metrics
      )
    }
    if (all(c("PopED", "PFIM") %in% names(runs))) {
      metrics <- .lity_external_compare(runs$PopED, runs$PFIM, tolerance)
      comparisons[[length(comparisons) + 1L]] <- .lity_external_comparison_row(
        fixture, "PopED", "PFIM", metrics
      )
    }
    timings <- c(timings, lapply(runs, function(run) .lity_external_timing_rows(fixture, run)))
    fixture_results[[fixture]] <- list(
      description = spec$description, parameters = spec$parameters,
      values = spec$values, engines = runs
    )
  }
  comparisons <- do.call(rbind, comparisons)
  timings <- do.call(rbind, timings)
  coverage <- do.call(rbind, coverage)
  search <- if (isTRUE(design_search)) .lity_external_grid_search(engines) else {
    list(rows = data.frame(), best = data.frame(), pass = TRUE)
  }
  result <- structure(list(
    schema = "liberality.external-validation", version = 1L,
    created_at = .lity_now(), passed = all(comparisons$pass) && isTRUE(search$pass),
    fixtures = fixture_results, comparisons = comparisons, timings = timings,
    coverage = coverage,
    design_search = search,
    tolerance = tolerance, versions = versions,
    platform = list(R = R.version.string, os = Sys.info()[["sysname"]],
                    release = Sys.info()[["release"]], machine = Sys.info()[["machine"]]),
    method = list(
      canonical_parameters = "fixed effects, OMEGA variances, residual variances",
      information = "block-diagonal population FO",
      PFIM_transform = "residual SD information transformed to residual variance scale",
      timing = "elapsed wall-clock; median and minimum reported"
    ), output_dir = NULL
  ), class = "lity_external_validation")
  if (!is.null(output_dir)) result$output_dir <- .lity_external_write(result, output_dir)
  result
}

#' Write an external-validation report
#'
#' @param x A `lity_external_validation` object.
#' @param file Output HTML file.
#' @return Normalized report path.
#' @export
lity_external_validation_report <- function(x, file) {
  if (!inherits(x, "lity_external_validation")) .lity_stop("`x` must be an external-validation result.")
  file <- normalizePath(file, winslash = "/", mustWork = FALSE)
  dir.create(dirname(file), recursive = TRUE, showWarnings = FALSE)
  table_html <- function(data) {
    if (!is.data.frame(data) || !nrow(data)) return("<p>No rows.</p>")
    header <- paste0("<tr>", paste0("<th>", names(data), "</th>", collapse = ""), "</tr>")
    rows <- apply(data, 1L, function(row) paste0(
      "<tr>", paste0("<td>", format(row, digits = 6), "</td>", collapse = ""), "</tr>"
    ))
    paste0("<table>", header, paste(rows, collapse = ""), "</table>")
  }
  status <- if (isTRUE(x$passed)) "PASS" else "FAIL"
  colour <- if (isTRUE(x$passed)) "#177245" else "#b42318"
  html <- paste0(
    "<!doctype html><html><head><meta charset='utf-8'><title>LibeRality external validation</title>",
    "<style>body{font-family:Inter,Segoe UI,sans-serif;margin:36px;color:#27231d;background:#faf8f3}",
    "h1,h2{color:#6d4611}.status{display:inline-block;padding:6px 12px;border-radius:999px;color:white;background:", colour, "}",
    "table{border-collapse:collapse;width:100%;margin:14px 0 28px;background:white}th,td{border:1px solid #ded7ca;padding:7px 9px;text-align:left}",
    "th{background:#f1eadc}code{background:#eee8dc;padding:2px 5px;border-radius:4px}</style></head><body>",
    "<h1>LibeRality external validation</h1><p class='status'>", status, "</p>",
    "<p>Generated ", x$created_at, ". Complete population-FO Fisher matrices were compared after harmonising residual-error parameterisation.</p>",
    "<h2>Engine versions</h2><p>", paste(names(x$versions), x$versions, sep = " ", collapse = " &middot; "), "</p>",
    "<h2>Coverage</h2>", table_html(x$coverage),
    "<h2>Numerical agreement</h2>", table_html(x$comparisons),
    "<h2>Runtime benchmark</h2>", table_html(x$timings),
    "<h2>Matched D-optimal grid search</h2>", table_html(x$design_search$best),
    "<h2>Interpretation</h2><p>The pass/fail decision applies to LibeRality's default conventional block-diagonal population-FO approximation shared by PopED and PFIM. The optional full-Gaussian mode intentionally includes additional fixed-effect covariance information and is reported separately.</p>",
    "</body></html>"
  )
  writeLines(html, file, useBytes = TRUE)
  normalizePath(file, winslash = "/", mustWork = TRUE)
}

#' @export
print.lity_external_validation <- function(x, ...) {
  cat("LibeRality external validation:", if (isTRUE(x$passed)) "PASS" else "FAIL", "\n")
  cat("  fixtures:", length(x$fixtures), " comparisons:", nrow(x$comparisons), "\n")
  cat("  engines:", paste(names(x$versions), x$versions, sep = " ", collapse = ", "), "\n")
  if (!is.null(x$output_dir)) cat("  artifacts:", x$output_dir, "\n")
  invisible(x)
}
