args <- commandArgs(trailingOnly = TRUE)
run_nonmem <- "--run" %in% args

script_arg <- grep("^--file=", commandArgs(), value = TRUE)
script <- if (length(script_arg)) sub("^--file=", "", script_arg[[1L]]) else "run-validation.R"
fixture_dir <- normalizePath(dirname(script), winslash = "/", mustWork = TRUE)
root <- normalizePath(file.path(fixture_dir, "..", ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
option_value <- function(name, default = NULL) {
  liber_validation_option(name, default, args = args)
}
validation_runtime <- liber_validation_library(
  root, c("LibeRtAD", "LibeRation"),
  library = option_value("library", Sys.getenv("LIBER_VALIDATION_LIBRARY", ""))
)

if (!requireNamespace("LibeRation", quietly = TRUE)) {
  stop("Install LibeRation before running NONMEM validation.", call. = FALSE)
}

run_execute <- function(model, expected_table) {
  execute <- Sys.which("execute")
  if (!nzchar(execute)) stop("PsN execute is not available in PATH.", call. = FALSE)
  stamp <- format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC")
  directory <- paste0(
    tools::file_path_sans_ext(model), "_run_", stamp, "_", Sys.getpid()
  )
  if (.Platform$OS.type == "windows") {
    script <- sub("\\.bat$", "", execute, ignore.case = TRUE)
    perl <- file.path(dirname(execute), "perl.exe")
    if (!file.exists(perl)) perl <- Sys.which("perl")
    if (!nzchar(perl) || !file.exists(script)) {
      stop("The Windows PsN Perl launcher could not be resolved.", call. = FALSE)
    }
    portable_root <- dirname(dirname(dirname(execute)))
    nonmem_paths <- c(
      file.path(portable_root, "nm_7.3.0_g", "run"),
      file.path(portable_root, "scripts"),
      file.path(portable_root, "Perl", "bin"),
      file.path(portable_root, "gfortran", "libexec", "gcc", "i586-pc-mingw32", "4.6.0"),
      file.path(portable_root, "gfortran", "bin")
    )
    Sys.setenv(PATH = paste(c(nonmem_paths, Sys.getenv("PATH")), collapse = ";"))
    status <- system2(perl, c(shQuote(script), paste0("-directory=", directory), model))
  } else {
    status <- system2(execute, c(paste0("-directory=", directory), model))
  }
  if (!identical(status, 0L)) stop("PsN execute returned status ", status, ".", call. = FALSE)
  listing <- file.path(directory, "NM_run1", "psn.lst")
  if (!file.exists(listing) || !file.exists(expected_table)) {
    nmtran <- file.path(directory, "NM_run1", "nmtran_error.txt")
    detail <- if (file.exists(nmtran)) paste(readLines(nmtran, warn = FALSE), collapse = "\n") else ""
    stop("NONMEM execution did not complete. ", detail, call. = FALSE)
  }
  invisible(directory)
}

read_nonmem_table <- function(path) {
  if (!file.exists(path)) stop("NONMEM did not publish expected table: ", path, call. = FALSE)
  utils::read.table(path, skip = 1L, header = TRUE, check.names = FALSE)
}

old <- setwd(fixture_dir)
on.exit(setwd(old), add = TRUE)

columns <- c("ID", "TIME", "EVID", "AMT", "RATE", "CMT", "DV", "MDV")
theta_table <- function(x) data.frame(THETA = seq_along(x), Value = x)
omega_zero <- data.frame(OMEGA = 1, Value = 0, FIX = TRUE)
validation_results <- list()

validate_case <- function(name, model, tolerance, data_columns = columns,
                          allow_unavailable = FALSE) {
  data_path <- paste0(tolower(name), ".dat")
  model_path <- paste0(tolower(name), ".mod")
  table_path <- paste0(tolower(name), ".tab")
  if (run_nonmem || !file.exists(table_path)) {
    execution_error <- tryCatch({
      run_execute(model_path, table_path)
      NULL
    }, error = identity)
    if (!is.null(execution_error)) {
      detail <- conditionMessage(execution_error)
      unavailable <- isTRUE(allow_unavailable) &&
        grepl("UNKNOWN SUBROUTINE", detail, ignore.case = TRUE)
      if (!unavailable) stop(execution_error)
      cat(name, ": NOT RUN (installed NONMEM does not provide this ADVAN)\n", sep = "")
      validation_results[[name]] <<- data.frame(
        case = name, kind = "prediction", passed = NA,
        maximum_absolute_difference = NA_real_, compared_records = 0L,
        theta_difference = NA_real_, eta_difference = NA_real_,
        covariance_se_difference = NA_real_,
        tolerance = tolerance, status = "not-run",
        detail = detail, stringsAsFactors = FALSE
      )
      return(invisible(NULL))
    }
  }
  data <- utils::read.table(data_path, col.names = data_columns)
  n_subjects <- length(unique(data$ID))
  eta <- matrix(0, n_subjects, nrow(model$OMEGAS))
  liber <- LibeRation::nm_simulate(model, data, eta = eta)
  nonmem <- read_nonmem_table(table_path)

  key <- paste(nonmem$ID, nonmem$TIME, nonmem$EVID, sep = "/")
  liber_key <- paste(liber$ID, liber$TIME, liber$EVID, sep = "/")
  order <- match(liber_key, key)
  if (anyNA(order)) stop(name, " NONMEM and LibeR event keys do not align.", call. = FALSE)
  compare <- liber$EVID == 0L
  difference <- liber$IPRED[compare] - nonmem$IPRED[order][compare]
  maximum <- max(abs(difference))
  if (!is.finite(maximum) || maximum > tolerance) {
    stop(name, " NONMEM comparison failed; maximum absolute difference = ", maximum, call. = FALSE)
  }
  cat(sprintf(
    "%s: PASS (max |LibeR - NONMEM| = %.9g; %d compared records)\n",
    name, maximum, sum(compare)
  ))
  validation_results[[name]] <<- data.frame(
    case = name, kind = "prediction", passed = TRUE,
    maximum_absolute_difference = maximum, compared_records = sum(compare),
    theta_difference = NA_real_, eta_difference = NA_real_,
    covariance_se_difference = NA_real_,
    tolerance = tolerance, status = "passed", detail = "",
    stringsAsFactors = FALSE
  )
}

base_input <- columns
validate_case("ADVAN1", LibeRation::nm_model(
  INPUT = base_input, ADVAN = 1, TRANS = 2, DOSECMP = 1, OBSCMP = 1,
  PRED = "CL=THETA(1)*exp(ETA(1))\nV=THETA(2)\nS1=V", ERROR = "Y=F",
  THETAS = theta_table(c(2, 20)), OMEGAS = omega_zero
), 1e-7)

validate_case("ADVAN2", LibeRation::nm_model(
  INPUT = base_input, ADVAN = 2, TRANS = 2, DOSECMP = 1, OBSCMP = 2,
  PRED = "KA=THETA(1)\nCL=THETA(2)*exp(ETA(1))\nV=THETA(3)\nS2=V",
  ERROR = "Y=F", THETAS = theta_table(c(1.5, 2, 20)), OMEGAS = omega_zero
), 1e-7)

validate_case("ADVAN3", LibeRation::nm_model(
  INPUT = base_input, ADVAN = 3, TRANS = 4, DOSECMP = 1, OBSCMP = 1,
  PRED = paste(
    "CL=THETA(1)*exp(ETA(1))", "V1=THETA(2)", "Q=THETA(3)",
    "V2=THETA(4)", "S1=V1", sep = "\n"
  ),
  ERROR = "Y=F", THETAS = theta_table(c(2, 20, 1, 10)), OMEGAS = omega_zero
), 2e-7)

validate_case("ADVAN4", LibeRation::nm_model(
  INPUT = base_input, ADVAN = 4, TRANS = 4, DOSECMP = 1, OBSCMP = 2,
  PRED = paste(
    "KA=THETA(1)", "CL=THETA(2)*exp(ETA(1))", "VC=THETA(3)",
    "Q=THETA(4)", "VP=THETA(5)", "S2=VC", sep = "\n"
  ),
  ERROR = "Y=F", THETAS = theta_table(c(1.5, 2, 20, 1, 10)), OMEGAS = omega_zero
), 2e-7)

linear_graph <- LibeRation::nm_matrix_model(
  data.frame(id = 1:2, name = c("CENTRAL", "PERIPHERAL")),
  data.frame(
    from = c(1L, 1L, 2L), to = c(0L, 2L, 1L), type = "rate",
    parameter = c("K10", "K12", "K21")
  )
)
for (advan in c(5L, 7L)) {
  validate_case(paste0("ADVAN", advan), LibeRation::nm_model(
    INPUT = base_input, ADVAN = advan, TRANS = 1, DOSECMP = 1, OBSCMP = 1,
    PRED = paste(
      "K10=THETA(1)*exp(ETA(1))", "K12=THETA(2)", "K21=THETA(3)",
      "S1=THETA(4)", sep = "\n"
    ),
    ERROR = "Y=F", THETAS = theta_table(c(.2, .1, .05, 20)),
    OMEGAS = omega_zero, GRAPH = linear_graph
  ), 3e-7)
}

stiff_model <- function(advan) LibeRation::nm_model(
  INPUT = base_input, ADVAN = advan, DOSECMP = 1, OBSCMP = 2,
  PRED = "KFAST=THETA(1)*exp(ETA(1))\nKSLOW=THETA(2)\nS2=1",
  DES = "DADT(1)=-KFAST*A(1)\nDADT(2)=KFAST*A(1)-KSLOW*A(2)",
  ERROR = "Y=F", THETAS = theta_table(c(1000, 1)), OMEGAS = omega_zero,
  ODE_CONTROL = list(rtol = 2e-7, atol = 1e-10)
)
for (advan in c(8L, 9L)) {
  validate_case(paste0("ADVAN", advan), stiff_model(advan), 2e-5)
}

validate_case("ADVAN9EQ", LibeRation::nm_model(
  INPUT = base_input, ADVAN = 9, TRANS = 1, DOSECMP = 1, OBSCMP = 1,
  PRED = paste(
    "K=THETA(1)*exp(ETA(1))", "BIND=THETA(2)", "S1=THETA(3)",
    sep = "\n"
  ),
  DES = "DADT(1)=-K*FREE",
  ALG = "RES(1)=FREE-A(1)/(1+BIND)",
  DAE_CONFIG = LibeRation::nm_dae_config("FREE", initial = 0),
  EXPERIMENTAL = LibeRation::nm_experimental_config(
    enabled = TRUE, label = "ADVAN9 equilibrium validation"
  ),
  ERROR = "Y=F", THETAS = theta_table(c(.4, 1, 20)),
  OMEGAS = omega_zero, ODE_CONTROL = list(rtol = 2e-7, atol = 1e-10)
), 2e-5)

validate_case("ADVAN10", LibeRation::nm_model(
  INPUT = base_input, ADVAN = 10, TRANS = 1, DOSECMP = 1, OBSCMP = 1,
  PRED = "VM=THETA(1)*exp(ETA(1))\nKM=THETA(2)\nS1=THETA(3)",
  ERROR = "Y=F", THETAS = theta_table(c(20, 50, 20)), OMEGAS = omega_zero,
  ODE_CONTROL = list(rtol = 1e-9, atol = 1e-11)
), 2e-6)

validate_case("ADVAN11", LibeRation::nm_model(
  INPUT = base_input, ADVAN = 11, TRANS = 4, DOSECMP = 1, OBSCMP = 1,
  PRED = paste(
    "CL=THETA(1)*exp(ETA(1))", "V1=THETA(2)", "Q2=THETA(3)",
    "V2=THETA(4)", "Q3=THETA(5)", "V3=THETA(6)", "S1=V1", sep = "\n"
  ),
  ERROR = "Y=F", THETAS = theta_table(c(2, 20, 1, 10, 0.5, 30)),
  OMEGAS = omega_zero
), 3e-7)

validate_case("ADVAN12", LibeRation::nm_model(
  INPUT = base_input, ADVAN = 12, TRANS = 4, DOSECMP = 1, OBSCMP = 2,
  PRED = paste(
    "KA=THETA(1)", "CL=THETA(2)*exp(ETA(1))", "VC=THETA(3)",
    "Q2=THETA(4)", "VP1=THETA(5)", "Q3=THETA(6)",
    "VP2=THETA(7)", "S2=VC", sep = "\n"
  ),
  ERROR = "Y=F", THETAS = theta_table(c(1.5, 2, 20, 1, 10, 0.5, 30)),
  OMEGAS = omega_zero
), 3e-7)

validate_case("ADVAN6", LibeRation::nm_model(
  INPUT = base_input, ADVAN = 6, DOSECMP = 1, OBSCMP = 1,
  PRED = "K=THETA(1)*exp(ETA(1))\nS1=THETA(2)",
  DES = "DADT(1)=-K*A(1)", ERROR = "Y=F",
  THETAS = theta_table(c(0.4, 20)), OMEGAS = omega_zero
), 2e-7)

validate_case("ADVAN13", stiff_model(13), 2e-5)

validate_case("ADVAN14", stiff_model(14), 2e-5, allow_unavailable = TRUE)

steady_state_input <- c(columns[1:6], "SS", "II", columns[7:8])
validate_case("SSBOLUS", LibeRation::nm_model(
  INPUT = steady_state_input, ADVAN = 1, TRANS = 2, DOSECMP = 1, OBSCMP = 1,
  PRED = "CL=THETA(1)*exp(ETA(1))\nV=THETA(2)\nS1=V", ERROR = "Y=F",
  THETAS = theta_table(c(2, 20)), OMEGAS = omega_zero
), 1e-7, steady_state_input)

validate_case("SSINFUSION", LibeRation::nm_model(
  INPUT = steady_state_input, ADVAN = 1, TRANS = 2, DOSECMP = 1, OBSCMP = 1,
  PRED = "CL=THETA(1)*exp(ETA(1))\nV=THETA(2)\nS1=V", ERROR = "Y=F",
  THETAS = theta_table(c(2, 20)), OMEGAS = omega_zero
), 2e-7, steady_state_input)

validate_case("RATE1", LibeRation::nm_model(
  INPUT = base_input, ADVAN = 1, TRANS = 2, DOSECMP = 1, OBSCMP = 1,
  PRED = "CL=THETA(1)*exp(ETA(1));V=THETA(2);R1=THETA(3);S1=V",
  ERROR = "Y=F", THETAS = theta_table(c(2, 20, 20)), OMEGAS = omega_zero
), 2e-7)

validate_case("RATE2", LibeRation::nm_model(
  INPUT = base_input, ADVAN = 1, TRANS = 2, DOSECMP = 1, OBSCMP = 1,
  PRED = "CL=THETA(1)*exp(ETA(1));V=THETA(2);D1=THETA(3);S1=V",
  ERROR = "Y=F", THETAS = theta_table(c(2, 20, 5)), OMEGAS = omega_zero
), 2e-7)

validate_estimation <- function() {
  if (run_nonmem || !file.exists("estimation.tab") || !file.exists("estimation.ext")) {
    run_execute("estimation.mod", "estimation.tab")
  }
  data <- utils::read.table(
    "estimation.dat", col.names = c("ID", "TIME", "EVID", "AMT", "CMT", "DV", "MDV"),
    na.strings = "."
  )
  model <- LibeRation::nm_model(
    INPUT = names(data), ADVAN = 1, TRANS = 2, DOSECMP = 1, OBSCMP = 1,
    PRED = "CL=THETA(1)*exp(ETA(1));V=THETA(2);S1=V",
    ERROR = "Y=F+ERR(1)",
    THETAS = data.frame(THETA = 1:2, Value = c(1, 20), FIX = c(FALSE, TRUE)),
    OMEGAS = data.frame(OMEGA = 1, Value = 0.1, FIX = TRUE),
    SIGMAS = data.frame(SIGMA = 1, Value = 0.04, FIX = TRUE),
    LIK_CONFIG = LibeRation::nm_lik_config(
      error = "additive", sigma_parameterization = "variance"
    )
  )
  fit <- LibeRation::nm_est(
    model, data, method = "FOCEI", maxit = 300L, eta_maxit = 150L,
    tolerance = 1e-8, covariance = TRUE, covariance_type = "hessian"
  )
  extension <- readLines("estimation.ext", warn = FALSE)
  header <- grep("^[[:space:]]*ITERATION", extension)[[1L]]
  records <- extension[(header + 1L):length(extension)]
  records <- records[nzchar(trimws(records)) & !grepl("^TABLE", trimws(records))]
  parsed <- utils::read.table(
    text = paste(c(extension[[header]], records), collapse = "\n"),
    header = TRUE, check.names = FALSE
  )
  final <- parsed[parsed$ITERATION == -1000000000, , drop = FALSE]
  if (nrow(final) != 1L) stop("Unable to identify the final NONMEM estimation record.", call. = FALSE)
  nonmem_theta <- final$THETA1[[1L]]
  standard_error <- parsed[parsed$ITERATION == -1000000001, , drop = FALSE]
  if (nrow(standard_error) != 1L) {
    stop("Unable to identify the NONMEM standard-error record.", call. = FALSE)
  }
  nonmem_se <- standard_error$THETA1[[1L]]
  liber_se <- unname(fit$covariance$se[["THETA1"]])
  table <- read_nonmem_table("estimation.tab")
  eta_column <- grep("^ETA", names(table), value = TRUE)[[1L]]
  nonmem_eta <- tapply(table[[eta_column]], table$ID, function(value) value[[1L]])
  theta_difference <- abs(fit$theta[[1L]] - nonmem_theta)
  eta_difference <- max(abs(fit$eta[, 1L] - unname(nonmem_eta)))
  covariance_se_difference <- abs(liber_se - nonmem_se)
  if (!is.finite(theta_difference) || theta_difference > 0.03 ||
      !is.finite(eta_difference) || eta_difference > 0.08 ||
      !is.finite(covariance_se_difference) || covariance_se_difference > 0.01) {
    stop(
      "FOCEI NONMEM comparison failed; THETA difference = ", theta_difference,
      ", ETA difference = ", eta_difference,
      ", covariance SE difference = ", covariance_se_difference, ".", call. = FALSE
    )
  }
  cat(sprintf(
    paste0("FOCEI estimation: PASS (|THETA1| difference %.6g; ",
           "max |ETA1| difference %.6g; |SE| difference %.6g)\n"),
    theta_difference, eta_difference, covariance_se_difference
  ))
  validation_results[["FOCEI estimation"]] <<- data.frame(
    case = "FOCEI", kind = "estimation", passed = TRUE,
    maximum_absolute_difference = NA_real_, compared_records = length(nonmem_eta),
    theta_difference = theta_difference, eta_difference = eta_difference,
    covariance_se_difference = covariance_se_difference,
    tolerance = max(0.03, 0.08), status = "passed", detail = "",
    stringsAsFactors = FALSE
  )
}

validate_estimation()

stamp <- format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC")
output <- option_value("output", file.path(fixture_dir, "results", stamp))
if (!grepl("^(?:[A-Za-z]:[/\\\\]|/)", output, perl = TRUE)) {
  output <- file.path(root, output)
}
dir.create(output, recursive = TRUE, showWarnings = FALSE)
results <- do.call(rbind, validation_results)
executed <- !is.na(results$passed)
all_executed_passed <- any(executed) && all(results$passed[executed])
complete <- all(executed)
evidence_inputs <- list.files(
  fixture_dir, pattern = "[.](dat|mod|tab|ext)$", full.names = TRUE
)
provenance <- liber_validation_provenance(
  root = root, packages = c("LibeRtAD", "LibeRation"),
  library = validation_runtime$path,
  inputs = evidence_inputs,
  seeds = list(),
  tolerances = list(
    prediction = stats::setNames(as.list(results$tolerance[results$kind == "prediction"]),
                                 results$case[results$kind == "prediction"]),
    focei_theta = 0.03, focei_eta = 0.08, focei_covariance_se = 0.01
  ),
  dependencies = c("Rcpp", "jsonlite", "openssl"),
  metadata = list(
    nonmem_executed = run_nonmem,
    execute = unname(Sys.which("execute")),
    cases = nrow(results), executed_cases = sum(executed),
    all_executed_passed = all_executed_passed,
    complete = complete
  )
)
summary <- list(
  schema = "liber.nonmem-validation/1", passed = all_executed_passed,
  complete = complete,
  comparisons = split(results, seq_len(nrow(results))), provenance = provenance
)
liber_validation_write_evidence(
  output, comparisons = results, summary = summary, provenance = provenance
)
cat("Validation evidence:", normalizePath(output, winslash = "/"), "\n")
