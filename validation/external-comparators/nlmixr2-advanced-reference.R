#!/usr/bin/env Rscript

arguments <- commandArgs(trailingOnly = TRUE)
script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script <- if (length(script_argument)) {
  sub("^--file=", "", script_argument[[1L]])
} else {
  "validation/external-comparators/nlmixr2-advanced-reference.R"
}
fixture_dir <- normalizePath(dirname(script), winslash = "/", mustWork = TRUE)
root <- normalizePath(file.path(fixture_dir, "..", ".."),
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

suppressPackageStartupMessages({
  library(nlmixr2)
  library(nlmixr2est)
})
# Avoid garbage-collection-driven unloading of temporary rxode2 model DLLs.
# In short-lived Windows comparator processes this can otherwise leave a stale
# native reference and cause Rscript.exe to terminate with 0xc0000005.
invisible(rxode2::rxAllowUnload(FALSE))
rxode2::setRxThreads(1L)

source(file.path(fixture_dir, "nlmixr2-fixtures.R"), local = TRUE)

quiet_fit <- function(model, data, table = NULL) {
  value <- NULL
  invisible(utils::capture.output(
    value <- suppressWarnings(suppressMessages(nlmixr2est::nlmixr2(
      model, data, est = "focei",
      control = nlmixr2est::foceiControl(
        print = 0, covMethod = "", calcTables = TRUE,
        interaction = TRUE, maxOuterIterations = 400L,
        maxInnerIterations = 180L,
        rxControl = rxode2::rxControl(cores = 1L)
      ),
      table = table %||% nlmixr2est::tableControl()
    ))),
    type = "output"
  ))
  value
}
`%||%` <- function(left, right) if (is.null(left)) right else left
eta_column <- function(fit, name) {
  eta <- as.data.frame(fit$eta)
  as.numeric(eta[[name]])
}

estimated_variance_model <- function() {
  ini({
    tcl <- log(c(.2, 1.8, 8))
    eta.cl ~ .12
    add.sd <- c(.02, .18, 1)
  })
  model({
    cl <- exp(tcl + eta.cl)
    v <- 20
    d/dt(center) <- -cl / v * center
    cp <- center / v
    cp ~ add(add.sd)
  })
}
estimated_variance_fit <- quiet_fit(
  estimated_variance_model, nlmixr2_population_data()
)

correlated_model <- function() {
  ini({
    tcl <- log(c(.2, 1.8, 8))
    tv <- log(c(5, 18, 60))
    eta.cl + eta.v ~ c(.12, .03, .18)
    add.sd <- fixed(.15)
  })
  model({
    cl <- exp(tcl + eta.cl)
    v <- exp(tv + eta.v)
    d/dt(center) <- -cl / v * center
    cp <- center / v
    cp ~ add(add.sd)
  })
}
correlated_fit <- quiet_fit(
  correlated_model, nlmixr2_population_data(32L, correlated = TRUE)
)
correlated_omega <- as.matrix(correlated_fit$omega)

iov_model <- function() {
  ini({
    tcl <- log(c(.2, 1.8, 8))
    eta.cl ~ fixed(.08)
    iov.cl ~ fixed(.04) | OCC
    add.sd <- fixed(.15)
  })
  model({
    cl <- exp(tcl + eta.cl + iov.cl)
    v <- 20
    d/dt(center) <- -cl / v * center
    cp <- center / v
    cp ~ add(add.sd)
  })
}
iov_fit <- quiet_fit(iov_model, nlmixr2_iov_data())
iov_modes <- as.data.frame(iov_fit$iov$OCC)
iov_modes <- iov_modes[
  order(as.integer(iov_modes$ID), iov_modes$OCC), , drop = FALSE
]
iov_matrix <- matrix(iov_modes$iov.cl, ncol = 2L, byrow = TRUE)

blq_model <- function() {
  ini({
    tcl <- log(c(.2, 1.8, 8))
    eta.cl ~ fixed(.12)
    add.sd <- fixed(.15)
  })
  model({
    cl <- exp(tcl + eta.cl)
    v <- 20
    d/dt(center) <- -cl / v * center
    cp <- center / v
    cp ~ add(add.sd)
  })
}
blq_m3_fit <- quiet_fit(
  blq_model, nlmixr2_blq_data("m3"),
  nlmixr2est::tableControl(censMethod = "cdf")
)
blq_m4_fit <- quiet_fit(
  blq_model, nlmixr2_blq_data("m4"),
  nlmixr2est::tableControl(censMethod = "cdf")
)

timevarying_model <- function() {
  ini({
    tcl <- log(c(.2, 1.8, 8))
    wt.effect <- c(-2, .5, 2)
    eta.cl ~ fixed(.1)
    add.sd <- fixed(.12)
  })
  model({
    cl <- exp(tcl + wt.effect * (WT - 70) / 20 + eta.cl)
    cp <- 100 / 20 * exp(-cl / 20 * TIME)
    cp ~ add(add.sd)
  })
}
timevarying_fit <- quiet_fit(
  timevarying_model, nlmixr2_timevarying_data()
)

result <- list(
  schema = "liber.external.nlmixr2-advanced-reference/1",
  package_versions = list(
    nlmixr2 = as.character(utils::packageVersion("nlmixr2")),
    nlmixr2est = as.character(utils::packageVersion("nlmixr2est")),
    rxode2 = as.character(utils::packageVersion("rxode2"))
  ),
  cases = list(
    estimated_variance = list(
      clearance = exp(unname(estimated_variance_fit$theta[["tcl"]])),
      omega = unname(as.numeric(estimated_variance_fit$omega)),
      residual_sd = unname(
        as.numeric(estimated_variance_fit$theta[["add.sd"]])
      ),
      eta = eta_column(estimated_variance_fit, "eta.cl")
    ),
    correlated_omega = list(
      theta = c(
        exp(unname(correlated_fit$theta[["tcl"]])),
        exp(unname(correlated_fit$theta[["tv"]]))
      ),
      omega = c(
        correlated_omega[1L, 1L],
        correlated_omega[2L, 1L],
        correlated_omega[2L, 2L]
      ),
      eta = cbind(
        eta_column(correlated_fit, "eta.cl"),
        eta_column(correlated_fit, "eta.v")
      )
    ),
    iov = list(
      clearance = exp(unname(iov_fit$theta[["tcl"]])),
      eta = eta_column(iov_fit, "eta.cl"),
      iov = iov_matrix
    ),
    blq_m3 = list(
      clearance = exp(unname(blq_m3_fit$theta[["tcl"]])),
      eta = eta_column(blq_m3_fit, "eta.cl")
    ),
    blq_m4 = list(
      clearance = exp(unname(blq_m4_fit$theta[["tcl"]])),
      eta = eta_column(blq_m4_fit, "eta.cl")
    ),
    timevarying_covariate = list(
      theta = c(
        exp(unname(timevarying_fit$theta[["tcl"]])),
        unname(timevarying_fit$theta[["wt.effect"]])
      ),
      eta = eta_column(timevarying_fit, "eta.cl")
    )
  )
)

dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
jsonlite::write_json(
  result, output, auto_unbox = TRUE, pretty = TRUE,
  null = "null", digits = 17, matrix = "rowmajor"
)
