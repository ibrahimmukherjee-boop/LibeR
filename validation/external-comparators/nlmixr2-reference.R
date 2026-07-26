#!/usr/bin/env Rscript

arguments <- commandArgs(trailingOnly = TRUE)
script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script <- if (length(script_argument)) {
  sub("^--file=", "", script_argument[[1L]])
} else {
  "validation/external-comparators/nlmixr2-reference.R"
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
data_path <- value_after("data")
if (is.null(output) || is.null(data_path)) {
  stop("`--output` and `--data` are required.", call. = FALSE)
}

suppressPackageStartupMessages({
  library(nlmixr2)
  library(nlmixr2est)
})
# rxode2 compiles each model into a temporary DLL.  On Windows, letting
# garbage collection unload one of those DLLs while nlmixr2 still retains a
# native reference can terminate Rscript with an access violation.  These
# comparator processes are deliberately short lived, so keep the DLLs loaded
# and let process teardown release them safely.
invisible(rxode2::rxAllowUnload(FALSE))
rxode2::setRxThreads(1L)

model <- function() {
  ini({
    tcl <- log(c(0.1, 1, 10))
    eta.cl ~ fixed(0.1)
    add.sd <- fixed(0.2)
  })
  model({
    cl <- exp(tcl + eta.cl)
    v <- 20
    d/dt(center) <- -cl / v * center
    cp <- center / v
    cp ~ add(add.sd)
  })
}

data <- utils::read.table(
  data_path,
  col.names = c("ID", "TIME", "EVID", "AMT", "CMT", "DV", "MDV"),
  na.strings = "."
)
methods <- c("FO", "FOCE", "FOCEI")
results <- stats::setNames(lapply(methods, function(method) {
  fit <- nlmixr2est::nlmixr2(
    model, data, est = "focei",
    control = nlmixr2est::foceiControl(
      print = 0, covMethod = "", calcTables = TRUE,
      maxOuterIterations = 100L, maxInnerIterations = 100L,
      fo = identical(method, "FO"),
      interaction = identical(method, "FOCEI"),
      rxControl = rxode2::rxControl(cores = 1L)
    )
  )
  eta <- as.matrix(fit$eta)
  eta_columns <- setdiff(colnames(eta), "ID")
  if (!length(eta_columns)) {
    stop("nlmixr2 did not return an ETA column for ", method, ".", call. = FALSE)
  }
  list(
    clearance = unname(exp(as.numeric(fit$theta[["tcl"]]))),
    objective = unname(as.numeric(fit$objective)),
    eta = unname(as.numeric(eta[, eta_columns[[1L]]]))
  )
}), methods)

dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
jsonlite::write_json(
  list(
    schema = "liber.external.nlmixr2-reference/1",
    package_versions = list(
      nlmixr2 = as.character(utils::packageVersion("nlmixr2")),
      nlmixr2est = as.character(utils::packageVersion("nlmixr2est")),
      rxode2 = as.character(utils::packageVersion("rxode2"))
    ),
    methods = results
  ),
  output, auto_unbox = TRUE, pretty = TRUE, digits = 17
)
