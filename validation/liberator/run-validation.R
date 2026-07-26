#!/usr/bin/env Rscript

arguments <- commandArgs(trailingOnly = TRUE)

script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(script_argument)) sub("^--file=", "", script_argument[[1L]]) else "validation/liberator/run-validation.R"
root <- normalizePath(file.path(dirname(script_path), "..", ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
value_after <- function(name, default = NULL) {
  liber_validation_option(name, default, args = arguments, occurrence = "first")
}

packages <- c("LibeRtAD", "LibeRation", "LibeRator")
validation_library <- liber_validation_library(
  root, packages, library = value_after("library")
)
.libPaths(c(validation_library$path, .libPaths()))
suppressPackageStartupMessages(library(LibeRator))

output <- value_after("output", file.path(
  root, "validation", "liberator", "results",
  format(Sys.time(), "%Y%m%dT%H%M%S")
))
if (!grepl("^([A-Za-z]:)?[/\\]", output)) output <- file.path(root, output)
dir.create(output, recursive = TRUE, showWarnings = FALSE)

true_eta <- log(1.4)
theta <- c(CL = 3, V = 30)
dose <- 120
sample_times <- c(1, 3, 6, 12)
analytic_concentration <- function(time, eta = true_eta) {
  dose / theta[["V"]] * exp(-theta[["CL"]] * exp(eta) / theta[["V"]] * time)
}

model <- LibeRation::nm_model(
  INPUT = c("ID", "TIME", "EVID", "AMT", "CMT", "DV", "MDV"),
  ADVAN = 1, TRANS = 2,
  PRED = "CL=THETA(1)*exp(ETA(1));V=THETA(2);S1=V",
  ERROR = "Y=F+ERR(1)",
  THETAS = data.frame(THETA = 1:2, Value = unname(theta), FIX = TRUE),
  OMEGAS = data.frame(OMEGA = 1, Value = 0.25, FIX = TRUE),
  SIGMAS = data.frame(SIGMA = 1, Value = 1e-6, FIX = TRUE)
)
patient <- lator_patient_new("VP-001", "VALIDATION", "Analytic virtual patient")
patient <- lator_patient_add_event(patient, "dose", 0, "Virtual drug", dose, "mg")
for (index in seq_along(sample_times)) {
  patient <- lator_patient_add_event(
    patient, "concentration", sample_times[[index]], "Virtual drug",
    analytic_concentration(sample_times[[index]]), "mg/L"
  )
}
endpoint <- lator_endpoint_aed(
  "Virtual drug", 1.5, 3.5, "mg/L",
  source = "Analytic software-validation target; not a clinical range"
)

early <- lator_assess(
  patient, model, endpoint, cutoff = 3, maxit = 150, tolerance = 1e-10
)
complete <- lator_assess(
  patient, model, endpoint, cutoff = 12, maxit = 150, tolerance = 1e-10
)

observed <- complete$predictions[
  complete$predictions$EVID == 0L & complete$predictions$MDV == 0L, , drop = FALSE
]
expected_observed <- analytic_concentration(observed$TIME)

candidates <- lator_regimen_candidates(
  amounts = c(60, 120, 240), intervals = 24, horizon = 24
)
comparison <- lator_regimen_optimise(
  complete, patient, candidates, endpoint = endpoint,
  nsim = 64, grid_step = 1, seed = 20260723
)
forecast <- lator_regimen_predict(comparison, comparison$summary$candidate_id[[1L]])
ordered_metrics <- comparison$summary$median_metric[
  order(comparison$summary$amount)
]

checks <- data.frame(
  check = c(
    "complete assessment converged",
    "ETA recovered from analytic observations",
    "additional observations do not worsen ETA recovery",
    "individual predictions reproduce analytic concentrations",
    "candidate exposure is monotone in dose",
    "selected regimen produces an auditable future prediction"
  ),
  observed = c(
    as.numeric(complete$convergence),
    abs(complete$eta[[1L]] - true_eta),
    abs(complete$eta[[1L]] - true_eta) - abs(early$eta[[1L]] - true_eta),
    max(abs(observed$IPRED - expected_observed)),
    min(diff(ordered_metrics)),
    nrow(forecast$forecast)
  ),
  comparison = c("== 0", "<= 0.01", "<= 1e-6", "<= 0.01", "> 0", "> 1"),
  tolerance = c(0, 0.01, 1e-6, 0.01, 0, 1),
  passed = c(
    identical(as.integer(complete$convergence), 0L),
    abs(complete$eta[[1L]] - true_eta) <= 0.01,
    abs(complete$eta[[1L]] - true_eta) <= abs(early$eta[[1L]] - true_eta) + 1e-6,
    max(abs(observed$IPRED - expected_observed)) <= 0.01,
    all(diff(ordered_metrics) > 0),
    nrow(forecast$forecast) > 1L && identical(forecast$assessment_id, complete$assessment_id)
  ),
  stringsAsFactors = FALSE
)

utils::write.csv(checks, file.path(output, "comparisons.csv"), row.names = FALSE)
jsonlite::write_json(
  list(
    schema = "liberator.virtual-patient-validation/1",
    passed = all(checks$passed), true_eta = true_eta,
    early_eta = unname(early$eta), complete_eta = unname(complete$eta),
    selected_regimen = as.list(comparison$summary[1L, , drop = FALSE]),
    checks = lapply(seq_len(nrow(checks)), function(index) as.list(checks[index, , drop = FALSE]))
  ),
  file.path(output, "summary.json"), auto_unbox = TRUE, pretty = TRUE, null = "null"
)
invisible(liber_validation_provenance(
  root = root, output = file.path(output, "provenance.json"),
  library = validation_library$path, packages = packages,
  seeds = list(regimen = 20260723L),
  tolerances = list(eta = 0.01, prediction = 0.01, longitudinal = 1e-6),
  inputs = file.path(root, "validation", "liberator", "run-validation.R"),
  metadata = list(
    suite = "LibeRator analytic virtual-patient validation",
    scenario = "one-compartment IV bolus with known log-normal ETA",
    research_only = TRUE
  )
))

cat("LibeRator analytic virtual-patient validation:",
    if (all(checks$passed)) "PASS" else "FAIL", "\n")
cat("Evidence:", normalizePath(output, winslash = "/", mustWork = TRUE), "\n")
if (!all(checks$passed)) quit(status = 1L)
