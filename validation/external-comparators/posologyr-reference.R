#!/usr/bin/env Rscript

arguments <- commandArgs(trailingOnly = TRUE)
script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script <- if (length(script_argument)) {
  sub("^--file=", "", script_argument[[1L]])
} else {
  "validation/external-comparators/posologyr-reference.R"
}
root <- normalizePath(file.path(dirname(script), "..", ".."),
                      winslash = "/", mustWork = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
value_after <- function(name, default = NULL) {
  liber_validation_option(name, default, args = arguments)
}

library_path <- value_after("library", "")
if (nzchar(library_path)) {
  .libPaths(unique(c(normalizePath(
    library_path, winslash = "/", mustWork = TRUE
  ), .libPaths())))
}
output <- value_after("output")
if (is.null(output)) stop("`--output` is required.", call. = FALSE)

suppressPackageStartupMessages(library(posologyr))
rxode2::setRxThreads(1L)

model <- function() {
  ini({
    THETA_Cl <- 4
    THETA_Vc <- 70
    THETA_Ka <- 1
    ETA_Cl ~ 0.2
    ETA_Vc ~ 0.2
    ETA_Ka ~ 0.2
    prop.sd <- sqrt(0.05)
  })
  model({
    TVCl <- THETA_Cl
    TVVc <- THETA_Vc
    TVKa <- THETA_Ka
    Cl <- TVCl * exp(ETA_Cl)
    Vc <- TVVc * exp(ETA_Vc)
    Ka <- TVKa * exp(ETA_Ka)
    K20 <- Cl / Vc
    Cc <- centr / Vc
    d/dt(depot) = -Ka * depot
    d/dt(centr) = Ka * depot - K20 * centr
    Cc ~ prop(prop.sd)
  })
}

data <- data.frame(
  ID = 1, TIME = c(0, 1, 14), DV = c(NA, 25, 5.5),
  AMT = c(2000, 0, 0), EVID = c(1, 0, 0),
  DUR = c(.5, NA, NA)
)
fit <- posologyr::poso_estim_map(
  dat = data, prior_model = model,
  return_model = FALSE, return_ofv = TRUE
)
dose <- posologyr::poso_dose_conc(
  dat = data, prior_model = model, tdm = TRUE,
  time_c = 15, time_dose = 14, target_conc = 20,
  starting_dose = 100, duration = .5, greater_than = TRUE
)

dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
jsonlite::write_json(
  list(
    schema = "liber.external.posologyr-reference/1",
    package_versions = list(
      posologyr = as.character(utils::packageVersion("posologyr")),
      rxode2 = as.character(utils::packageVersion("rxode2"))
    ),
    eta = unname(as.numeric(fit$eta)),
    objective = unname(as.numeric(fit$ofv)),
    target = list(
      dose = unname(as.numeric(dose$dose)),
      concentration = unname(as.numeric(dose$conc_estimate))
    )
  ),
  output, auto_unbox = TRUE, pretty = TRUE, digits = 17
)
