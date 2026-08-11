benchmark_scenario_names <- function() {
  c(
    "iv-bolus", "oral", "two-compartment", "three-compartment",
    "full-omega", "infusion-steady-state", "iov", "advan6", "advan13",
    "advan16-radau", "advan17-radau", "advan18-dde"
  )
}

.benchmark_parameter <- function(values, lower = values / 20,
                                 upper = values * 20, fixed = FALSE) {
  data.frame(
    THETA = seq_along(values), Value = as.numeric(values),
    LOWER = as.numeric(lower), UPPER = as.numeric(upper),
    FIX = rep(isTRUE(fixed), length(values))
  )
}

.benchmark_skeleton <- function(subjects, times, extra = list()) {
  do.call(rbind, lapply(seq_len(subjects), function(id) {
    rows <- data.frame(
      ID = id, TIME = c(0, times), EVID = c(1L, rep(0L, length(times))),
      AMT = c(100, rep(0, length(times))), CMT = 1L,
      DV = NA_real_, MDV = c(1L, rep(0L, length(times)))
    )
    for (name in names(extra)) rows[[name]] <- extra[[name]]
    rows
  }))
}

.benchmark_generate <- function(model, skeleton, seed, theta = NULL,
                                omega = NULL, sigma = NULL) {
  generated <- LibeRation::nm_simulate(
    model, skeleton, theta = theta, omega = omega, sigma = sigma,
    random_effects = TRUE, residual = TRUE, seed = seed
  )
  as.data.frame(generated[model$INPUT])
}

benchmark_scenario <- function(name, subjects, times, seed) {
  name <- match.arg(tolower(name), benchmark_scenario_names())
  proportional <- LibeRation::nm_lik_config(
    error = "proportional", sigma_parameterization = "variance"
  )
  sigma <- data.frame(SIGMA = 1L, Value = 0.02, FIX = FALSE)
  nonmem_supported <- TRUE
  model_record <- NULL
  nonmem_model <- NULL
  comparison_mapping <- "direct"

  if (name == "iv-bolus") {
    data <- .benchmark_skeleton(subjects, times)
    model <- LibeRation::nm_model(
      INPUT = names(data), ADVAN = 1L, TRANS = 2L, DOSECMP = 1L, OBSCMP = 1L,
      PRED = "CL=THETA(1)*exp(ETA(1)); V=THETA(2); S1=V",
      ERROR = "Y=F+F*ERR(1)",
      THETAS = .benchmark_parameter(c(1.5, 18), c(0.1, 5), c(10, 50)),
      OMEGAS = data.frame(OMEGA = 1L, Value = 0.1, FIX = FALSE),
      SIGMAS = sigma, LIK_CONFIG = proportional
    )
    truth <- list(theta = c(2, 20), omega = 0.12, sigma = 0.02)
  } else if (name == "oral") {
    oral_times <- sort(unique(c(0.25, 0.5, times)))
    data <- .benchmark_skeleton(subjects, oral_times)
    model <- LibeRation::nm_model(
      INPUT = names(data), ADVAN = 2L, TRANS = 2L, DOSECMP = 1L, OBSCMP = 2L,
      PRED = paste(
        "KA=THETA(1)*exp(ETA(1)); CL=THETA(2)*exp(ETA(2));",
        "V=THETA(3); S2=V"
      ), ERROR = "Y=F+F*ERR(1)",
      THETAS = .benchmark_parameter(c(0.8, 1.5, 18), c(0.05, 0.1, 5), c(5, 10, 50)),
      OMEGAS = data.frame(OMEGA = 1:2, Value = c(0.1, 0.1), FIX = FALSE),
      SIGMAS = sigma, LIK_CONFIG = proportional
    )
    truth <- list(theta = c(1.1, 2, 20), omega = c(0.12, 0.1), sigma = 0.02)
  } else if (name == "two-compartment") {
    data <- .benchmark_skeleton(subjects, times)
    model <- LibeRation::nm_model(
      INPUT = names(data), ADVAN = 3L, TRANS = 4L, DOSECMP = 1L, OBSCMP = 1L,
      PRED = paste(
        "CL=THETA(1)*exp(ETA(1)); V1=THETA(2)*exp(ETA(2));",
        "Q=THETA(3); V2=THETA(4); S1=V1"
      ), ERROR = "Y=F+F*ERR(1)",
      THETAS = .benchmark_parameter(c(1.5, 12, 2.5, 25)),
      OMEGAS = data.frame(OMEGA = 1:2, Value = c(0.1, 0.08), FIX = FALSE),
      SIGMAS = sigma, LIK_CONFIG = proportional
    )
    truth <- list(theta = c(2, 15, 3, 30), omega = c(0.12, 0.1), sigma = 0.02)
  } else if (name == "three-compartment") {
    data <- .benchmark_skeleton(subjects, times)
    model <- LibeRation::nm_model(
      INPUT = names(data), ADVAN = 11L, TRANS = 4L, DOSECMP = 1L, OBSCMP = 1L,
      PRED = paste(
        "CL=THETA(1)*exp(ETA(1)); V1=THETA(2); Q2=THETA(3);",
        "V2=THETA(4); Q3=THETA(5); V3=THETA(6); S1=V1"
      ), ERROR = "Y=F+F*ERR(1)",
      THETAS = .benchmark_parameter(c(1.5, 10, 2, 20, 0.8, 50)),
      OMEGAS = data.frame(OMEGA = 1L, Value = 0.1, FIX = FALSE),
      SIGMAS = sigma, LIK_CONFIG = proportional
    )
    truth <- list(
      theta = c(2, 12, 3, 25, 1.2, 60), omega = 0.12, sigma = 0.02
    )
  } else if (name == "full-omega") {
    data <- .benchmark_skeleton(subjects, times)
    model <- LibeRation::nm_model(
      INPUT = names(data), ADVAN = 1L, TRANS = 2L,
      PRED = "CL=THETA(1)*exp(ETA(1)); V=THETA(2)*exp(ETA(2)); S1=V",
      ERROR = "Y=F+F*ERR(1)",
      THETAS = .benchmark_parameter(c(1.5, 18), c(0.1, 5), c(10, 50)),
      OMEGAS = data.frame(
        OMEGA = 1:3, ROW = c(1L, 2L, 2L), COL = c(1L, 1L, 2L),
        Value = c(0.12, 0.035, 0.1), FIX = FALSE
      ), SIGMAS = sigma, LIK_CONFIG = proportional
    )
    truth <- list(theta = c(2, 20), omega = c(0.15, 0.04, 0.12), sigma = 0.02)
  } else if (name == "infusion-steady-state") {
    ss_times <- sort(unique(times[times < 12]))
    data <- .benchmark_skeleton(subjects, ss_times, list(RATE = 20, II = 12, SS = 0L))
    dose <- data$EVID == 1L
    data$SS[dose] <- 1L
    data$AMT[dose] <- 100
    model <- LibeRation::nm_model(
      INPUT = names(data), ADVAN = 1L, TRANS = 2L,
      PRED = "CL=THETA(1)*exp(ETA(1)); V=THETA(2); S1=V",
      ERROR = "Y=F+F*ERR(1)",
      THETAS = .benchmark_parameter(c(1.5, 18), c(0.1, 5), c(10, 50)),
      OMEGAS = data.frame(OMEGA = 1L, Value = 0.1, FIX = FALSE),
      SIGMAS = sigma, LIK_CONFIG = proportional
    )
    truth <- list(theta = c(2, 20), omega = 0.12, sigma = 0.02)
  } else if (name == "iov") {
    sample_times <- sort(unique(times[times < 12]))
    data <- do.call(rbind, lapply(seq_len(subjects), function(id) {
      rbind(
        transform(.benchmark_skeleton(1L, sample_times), ID = id, OCC = 1L),
        transform(.benchmark_skeleton(1L, sample_times), ID = id,
                  TIME = TIME + 24, OCC = 2L)
      )
    }))
    model <- LibeRation::nm_model(
      INPUT = names(data), ADVAN = 1L, TRANS = 2L,
      PRED = "CL=THETA(1)*exp(ETA(1)+ETA(2)); V=THETA(2); S1=V",
      ERROR = "Y=F+F*ERR(1)", IOV = 1L,
      THETAS = .benchmark_parameter(c(1.5, 18), c(0.1, 5), c(10, 50)),
      OMEGAS = data.frame(OMEGA = 1:2, Value = c(0.1, 0.05), FIX = FALSE),
      SIGMAS = sigma, LIK_CONFIG = LibeRation::nm_lik_config(
        error = "proportional", sigma_parameterization = "variance",
        iov = 1L, occasion_col = "OCC"
      )
    )
    truth <- list(theta = c(2, 20), omega = c(0.12, 0.06), sigma = 0.02)
    # The LibeRation expanded-occasion ETA layout has no one-line NONMEM
    # equivalent; this case remains in the native validation matrix.
    nonmem_supported <- FALSE
  } else if (name %in% c("advan16-radau", "advan17-radau", "advan18-dde")) {
    data <- .benchmark_skeleton(subjects, times)
    build_dde <- function(advan) {
      combined <- advan == 17L
      LibeRation::nm_model(
        INPUT = names(data), ADVAN = advan, TRANS = 1L,
        DOSECMP = 1L, OBSCMP = 1L,
        PRED = paste(
          "K=THETA(1)*exp(ETA(1)); FB=THETA(2);",
          "TAU1=THETA(3); V=THETA(4); S1=V"
        ),
        DES = if (combined) {
          "DADT(1)=-K*FREE+FB*LAG(FREE,TAU1)"
        } else {
          "DADT(1)=-K*A(1)+FB*LAG(A(1),TAU1)"
        },
        ALG = if (combined) "RES(1)=FREE-A(1)" else "",
        ERROR = "Y=F+F*ERR(1)",
        THETAS = .benchmark_parameter(
          c(0.3, 0.06, 2, 18), c(0.01, 0.001, 0.5, 5),
          c(2, 0.5, 8, 50)
        ),
        OMEGAS = data.frame(OMEGA = 1L, Value = 0.1, FIX = FALSE),
        SIGMAS = sigma, LIK_CONFIG = proportional,
        DDE_CONFIG = LibeRation::nm_dde_config(
          history = 0, step = 0.05, minimum_delay = 0.05
        ),
        DAE_CONFIG = if (combined) {
          LibeRation::nm_dae_config("FREE", initial = 0)
        } else NULL,
        SOLVER = "dde",
        EXPERIMENTAL = LibeRation::nm_experimental_config(
          TRUE, paste0("benchmark ADVAN", advan)
        )
      )
    }
    advan <- switch(
      name, `advan16-radau` = 16L, `advan17-radau` = 17L,
      `advan18-dde` = 18L
    )
    model <- build_dde(advan)
    # Keep the delay and feedback fixed in the timing workload. Estimating a
    # delay deliberately exercises parameter-dependent discontinuity retaping
    # and is reported by validation diagnostics rather than conflated with the
    # propagation-kernel benchmark.
    model$THETAS$FIX <- c(FALSE, TRUE, TRUE, TRUE)
    truth <- list(theta = c(0.4, 0.08, 2, 20), omega = 0.12, sigma = 0.02)
    if (advan %in% c(16L, 17L)) {
      # The installed NONMEM licence lacks RADAR5NM.  ADVAN18 evaluates the
      # same mathematical DDE and is retained as an explicitly labelled
      # equivalent-numerics comparator, never as a direct ADVAN match.
      nonmem_model <- build_dde(18L)
      nonmem_model$THETAS$FIX <- model$THETAS$FIX
      comparison_mapping <- "equivalent DDE under licensed NONMEM ADVAN18"
    }
  } else {
    advan <- if (name == "advan6") 6L else 13L
    data <- .benchmark_skeleton(subjects, times)
    model <- LibeRation::nm_model(
      INPUT = names(data), ADVAN = advan, TRANS = 1L,
      PRED = "K=THETA(1)*exp(ETA(1)); V=THETA(2); S1=V",
      DES = "DADT(1)=-K*A(1)", ERROR = "Y=F+F*ERR(1)",
      THETAS = .benchmark_parameter(c(0.08, 18), c(0.005, 5), c(1, 50)),
      OMEGAS = data.frame(OMEGA = 1L, Value = 0.1, FIX = FALSE),
      SIGMAS = sigma, LIK_CONFIG = proportional
    )
    truth <- list(theta = c(0.1, 20), omega = 0.12, sigma = 0.02)
    model_record <- "COMP=(CENTRAL)"
  }

  generated <- .benchmark_generate(
    model, data, seed, theta = truth$theta, omega = truth$omega,
    sigma = truth$sigma
  )
  if (!is.null(model_record)) {
    attr(model, "nonmem_control") <- list(model_record = model_record)
  }
  list(
    name = name, model = model, data = generated, truth = truth,
    nonmem_model = nonmem_model, comparison_mapping = comparison_mapping,
    nonmem_supported = nonmem_supported,
    description = switch(
      name,
      `iv-bolus` = "one-compartment IV bolus (ADVAN1/TRANS2)",
      oral = "one-compartment first-order oral absorption (ADVAN2/TRANS2)",
      `two-compartment` = "two-compartment IV bolus (ADVAN3/TRANS4)",
      `three-compartment` = "three-compartment IV bolus (ADVAN11/TRANS4)",
      `full-omega` = "correlated two-effect full OMEGA model",
      `infusion-steady-state` = "analytical steady-state intermittent infusion",
      iov = "between-subject plus inter-occasion variability",
      advan6 = "ADVAN6 adaptive ODE",
      advan13 = "ADVAN13 stiff-capable adaptive ODE",
      `advan16-radau` = "ADVAN16 clean-room Radau IIA delay equation",
      `advan17-radau` = "ADVAN17 clean-room Radau IIA delay algebraic equation",
      `advan18-dde` = "ADVAN18 fixed-step RK4 delay equation"
    )
  )
}
