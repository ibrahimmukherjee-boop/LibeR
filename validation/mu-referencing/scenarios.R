mu_validation_scenario_names <- function() {
  c("baseline-fixed", "dual-estimated", "covariate-full")
}

.mu_parameter_table <- function(values, lower, upper, fixed) {
  data.frame(
    THETA = seq_along(values), Value = values, LOWER = lower, UPPER = upper,
    FIX = fixed
  )
}

.mu_skeleton <- function(subjects, times, covariates = list()) {
  do.call(rbind, lapply(seq_len(subjects), function(id) {
    rows <- data.frame(
      ID = id, TIME = c(0, times),
      EVID = c(1L, rep(0L, length(times))),
      AMT = c(100, rep(0, length(times))), CMT = 1L,
      DV = NA_real_, MDV = c(1L, rep(0L, length(times)))
    )
    for (name in names(covariates)) {
      values <- covariates[[name]]
      rows[[name]] <- values[[id]]
    }
    rows
  }))
}

.mu_tolerances <- function(theta, eta, omega = Inf, sigma = Inf) {
  list(theta = theta, eta = eta, omega = omega, sigma = sigma)
}

mu_validation_scenario <- function(name, subjects, times, seed) {
  name <- match.arg(tolower(name), mu_validation_scenario_names())
  likelihood <- LibeRation::nm_lik_config(
    error = "additive", sigma_parameterization = "variance"
  )

  if (identical(name, "baseline-fixed")) {
    theta <- .mu_parameter_table(
      c(1.5, 20), c(0.1, 20), c(10, 20), c(FALSE, TRUE)
    )
    omega <- data.frame(OMEGA = 1L, Value = 0.12, FIX = TRUE)
    sigma <- data.frame(SIGMA = 1L, Value = 0.04, FIX = TRUE)
    conventional <- LibeRation::nm_model(
      INPUT = c("ID", "TIME", "EVID", "AMT", "CMT", "DV", "MDV"),
      ADVAN = 1L, TRANS = 2L, DOSECMP = 1L, OBSCMP = 1L,
      PRED = "CL=THETA(1)*exp(ETA(1)); V=THETA(2); S1=V",
      ERROR = "Y=F+ERR(1)", THETAS = theta, OMEGAS = omega,
      SIGMAS = sigma, LIK_CONFIG = likelihood
    )
    referenced <- LibeRation::nm_model(
      INPUT = conventional$INPUT, ADVAN = 1L, TRANS = 2L,
      DOSECMP = 1L, OBSCMP = 1L, PRED = "V=THETA(2); S1=V",
      ERROR = "Y=F+ERR(1)", THETAS = theta, OMEGAS = omega,
      SIGMAS = sigma, LIK_CONFIG = likelihood,
      MU = LibeRation::nm_mu(
        1L, "log(THETA(1))", parameter = "CL"
      )
    )
    truth <- list(theta = c(2, 20), omega = 0.12, sigma = 0.04)
    skeleton <- .mu_skeleton(subjects, times)
    records <- list(
      input = "$INPUT ID TIME EVID AMT CMT DV MDV",
      conventional_pk = c("CL=THETA(1)*EXP(ETA(1))", "V=THETA(2)", "S1=V"),
      mu_pk = c(
        "MU_1=LOG(THETA(1))", "CL=EXP(MU_1+ETA(1))",
        "V=THETA(2)", "S1=V"
      ),
      theta = c("$THETA (0.1,1.5,10)", "$THETA 20 FIX"),
      omega = "$OMEGA 0.12 FIX", sigma = "$SIGMA 0.04 FIX"
    )
    compare <- list(theta = 1L, omega = integer(), sigma = integer())
    tolerances <- list(
      within = list(
        FOCEI = .mu_tolerances(0.005, 0.02),
        IMP = .mu_tolerances(0.08, 0.20),
        SAEM = .mu_tolerances(0.12, 0.30)
      ),
      external = list(
        FOCEI = .mu_tolerances(0.02, 0.08),
        IMP = .mu_tolerances(0.10, 0.20),
        SAEM = .mu_tolerances(0.15, 0.30)
      )
    )
  } else if (identical(name, "dual-estimated")) {
    theta <- .mu_parameter_table(
      c(1.5, 18), c(0.1, 5), c(10, 50), c(FALSE, FALSE)
    )
    omega <- data.frame(
      OMEGA = 1:2, Value = c(0.10, 0.08), FIX = FALSE
    )
    sigma <- data.frame(SIGMA = 1L, Value = 0.05, FIX = FALSE)
    conventional <- LibeRation::nm_model(
      INPUT = c("ID", "TIME", "EVID", "AMT", "CMT", "DV", "MDV"),
      ADVAN = 1L, TRANS = 2L, DOSECMP = 1L, OBSCMP = 1L,
      PRED = paste(
        "CL=THETA(1)*exp(ETA(1)); V=THETA(2)*exp(ETA(2)); S1=V"
      ),
      ERROR = "Y=F+ERR(1)", THETAS = theta, OMEGAS = omega,
      SIGMAS = sigma, LIK_CONFIG = likelihood
    )
    referenced <- LibeRation::nm_model(
      INPUT = conventional$INPUT, ADVAN = 1L, TRANS = 2L,
      DOSECMP = 1L, OBSCMP = 1L, PRED = "S1=V",
      ERROR = "Y=F+ERR(1)", THETAS = theta, OMEGAS = omega,
      SIGMAS = sigma, LIK_CONFIG = likelihood,
      MU = LibeRation::nm_mu(
        1:2, c("log(THETA(1))", "log(THETA(2))"),
        parameter = c("CL", "V")
      )
    )
    truth <- list(
      theta = c(2, 20), omega = c(0.12, 0.08), sigma = 0.04
    )
    skeleton <- .mu_skeleton(subjects, times)
    records <- list(
      input = "$INPUT ID TIME EVID AMT CMT DV MDV",
      conventional_pk = c(
        "CL=THETA(1)*EXP(ETA(1))",
        "V=THETA(2)*EXP(ETA(2))", "S1=V"
      ),
      mu_pk = c(
        "MU_1=LOG(THETA(1))", "CL=EXP(MU_1+ETA(1))",
        "MU_2=LOG(THETA(2))", "V=EXP(MU_2+ETA(2))", "S1=V"
      ),
      theta = c("$THETA (0.1,1.5,10)", "$THETA (5,18,50)"),
      omega = c("$OMEGA 0.10", "$OMEGA 0.08"),
      sigma = "$SIGMA 0.05"
    )
    compare <- list(theta = 1:2, omega = 1:2, sigma = 1L)
    tolerances <- list(
      within = list(
        FOCEI = .mu_tolerances(0.01, 0.15, 0.10, 0.10),
        IMP = .mu_tolerances(0.08, 0.35, 0.25, 0.25),
        SAEM = .mu_tolerances(0.15, 0.45, 0.30, 0.35)
      ),
      external = list(
        FOCEI = .mu_tolerances(0.02, 0.20, 0.15, 0.15),
        IMP = .mu_tolerances(0.10, 0.40, 0.30, 0.35),
        SAEM = .mu_tolerances(0.12, 0.55, 0.35, 0.40)
      )
    )
  } else {
    weights <- seq(45, 105, length.out = subjects)
    theta <- .mu_parameter_table(
      c(1.5, 18, 0.5), c(0.1, 5, -1), c(10, 50, 2),
      c(FALSE, FALSE, FALSE)
    )
    omega <- data.frame(
      OMEGA = 1:3, ROW = c(1L, 2L, 2L), COL = c(1L, 1L, 2L),
      Value = c(0.10, 0.01, 0.08), FIX = FALSE
    )
    sigma <- data.frame(SIGMA = 1L, Value = 0.05, FIX = FALSE)
    conventional <- LibeRation::nm_model(
      INPUT = c(
        "ID", "TIME", "EVID", "AMT", "CMT", "DV", "MDV", "WT"
      ),
      ADVAN = 1L, TRANS = 2L, DOSECMP = 1L, OBSCMP = 1L,
      PRED = paste(
        "CL=THETA(1)*(WT/70)^THETA(3)*exp(ETA(1));",
        "V=THETA(2)*exp(ETA(2)); S1=V"
      ),
      ERROR = "Y=F+ERR(1)", THETAS = theta, OMEGAS = omega,
      SIGMAS = sigma, LIK_CONFIG = likelihood, COVARIATES = "WT"
    )
    referenced <- LibeRation::nm_model(
      INPUT = conventional$INPUT, ADVAN = 1L, TRANS = 2L,
      DOSECMP = 1L, OBSCMP = 1L, PRED = "S1=V",
      ERROR = "Y=F+ERR(1)", THETAS = theta, OMEGAS = omega,
      SIGMAS = sigma, LIK_CONFIG = likelihood, COVARIATES = "WT",
      MU = LibeRation::nm_mu(
        1:2,
        c(
          "log(THETA(1))+THETA(3)*log(WT/70)",
          "log(THETA(2))"
        ),
        parameter = c("CL", "V"),
        covariates = list("WT", character())
      )
    )
    truth <- list(
      theta = c(2, 20, 0.75),
      omega = c(0.12, 0.025, 0.08), sigma = 0.04
    )
    skeleton <- .mu_skeleton(subjects, times, list(WT = weights))
    records <- list(
      input = "$INPUT ID TIME EVID AMT CMT DV MDV WT",
      conventional_pk = c(
        "CL=THETA(1)*(WT/70)**THETA(3)*EXP(ETA(1))",
        "V=THETA(2)*EXP(ETA(2))", "S1=V"
      ),
      mu_pk = c(
        "MU_1=LOG(THETA(1))+THETA(3)*LOG(WT/70)",
        "CL=EXP(MU_1+ETA(1))",
        "MU_2=LOG(THETA(2))", "V=EXP(MU_2+ETA(2))", "S1=V"
      ),
      theta = c(
        "$THETA (0.1,1.5,10)", "$THETA (5,18,50)",
        "$THETA (-1,0.5,2)"
      ),
      omega = c("$OMEGA BLOCK(2)", "0.10", "0.01 0.08"),
      sigma = "$SIGMA 0.05"
    )
    compare <- list(theta = 1:3, omega = 1:3, sigma = 1L)
    tolerances <- list(
      within = list(
        FOCEI = .mu_tolerances(0.015, 0.20, 0.15, 0.10),
        IMP = .mu_tolerances(0.10, 0.45, 0.40, 0.30),
        SAEM = .mu_tolerances(0.12, 0.55, 0.45, 0.40)
      ),
      external = list(
        FOCEI = .mu_tolerances(0.04, 0.25, 0.30, 0.20),
        IMP = .mu_tolerances(0.15, 0.50, 0.50, 0.40),
        SAEM = .mu_tolerances(0.18, 0.65, 0.55, 0.50)
      )
    )
  }

  generated <- LibeRation::nm_simulate(
    conventional, skeleton, theta = truth$theta, omega = truth$omega,
    sigma = truth$sigma, random_effects = TRUE, residual = TRUE, seed = seed
  )
  data <- as.data.frame(generated[conventional$INPUT])
  list(
    name = name, description = switch(
      name,
      `baseline-fixed` = "single log-MU ETA with fixed OMEGA and SIGMA",
      `dual-estimated` = "two log-MU ETAs with estimated diagonal OMEGA and SIGMA",
      `covariate-full` = paste(
        "two log-MU ETAs, a weight relationship, and estimated correlated",
        "OMEGA and SIGMA"
      )
    ),
    models = list(conventional = conventional, mu = referenced),
    data = data, truth = truth, records = records,
    compare = compare, tolerances = tolerances,
    n_eta = conventional$n_eta
  )
}

mu_validation_nonmem_control <- function(scenario, method, profile, seed,
                                         parameterization) {
  estimation <- switch(
    method,
    FOCEI = sprintf(
      "METHOD=COND INTERACTION MAXEVAL=%d NOABORT SIGL=6 NSIG=3",
      profile$maxit
    ),
    IMP = sprintf(
      "METHOD=IMP INTERACTION NITER=%d ISAMPLE=%d SEED=%d",
      profile$maxit, profile$imp_samples, seed
    ),
    SAEM = sprintf(
      "METHOD=SAEM INTERACTION NBURN=%d NITER=%d ISAMPLE=2 SEED=%d",
      profile$saem_burn, profile$saem_iterations, seed
    )
  )
  eta_fields <- paste0("ETA(", seq_len(scenario$n_eta), ")", collapse = " ")
  c(
    paste(
      "$PROBLEM LibeR MU comparison", scenario$name, method,
      parameterization
    ),
    scenario$records$input,
    "$DATA estimation.dat IGNORE=@",
    "$SUBROUTINES ADVAN1 TRANS2",
    "$PK",
    if (identical(parameterization, "mu")) {
      scenario$records$mu_pk
    } else {
      scenario$records$conventional_pk
    },
    "$ERROR", "IPRED=F", "Y=F+EPS(1)",
    scenario$records$theta, scenario$records$omega, scenario$records$sigma,
    paste("$ESTIMATION", estimation),
    paste(
      "$TABLE ID TIME EVID IPRED", eta_fields,
      "NOPRINT ONEHEADER FORMAT=s1PE15.8 FILE=estimation.tab"
    )
  )
}
