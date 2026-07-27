args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script <- if (length(file_arg)) {
  sub("^--file=", "", file_arg[[1L]])
} else {
  "validation/ad-backends/run-benchmark.R"
}
root <- normalizePath(file.path(dirname(script), "..", ".."), mustWork = TRUE)
harness <- file.path(root, "validation", "ad-backends")
if (.Platform$OS.type == "windows") {
  compilers <- Sys.glob(
    "C:/rtools*/x86_64-w64-mingw32.static.posix/bin/g++.exe"
  )
  if (length(compilers)) {
    git_directory <- dirname(Sys.which("git"))
    git_directory <- git_directory[
      nzchar(git_directory) & dir.exists(git_directory)
    ]
    compiler_directory <- dirname(tail(sort(compilers), 1L))
    rtools_root <- dirname(dirname(compiler_directory))
    rscript_directory <- dirname(file.path(R.home("bin"), "Rscript.exe"))
    # Windows may expose both `Path` and `PATH`. Remove the inherited alias so
    # CmdStan's nested make process cannot discover an old NONMEM toolchain
    # before the selected Rtools compiler.
    Sys.unsetenv("Path")
    Sys.setenv(
      PATH = paste(c(
        normalizePath(c(
          compiler_directory, file.path(rtools_root, "usr", "bin")
        ), winslash = "/", mustWork = TRUE),
        git_directory, rscript_directory,
        "C:/Windows/System32", "C:/Windows"
      ), collapse = .Platform$path.sep),
      COMPILER_PATH = compiler_directory,
      BINPREF = paste0(gsub("\\\\", "/", compiler_directory), "/"),
      R_MAKEVARS_USER = file.path(root, "tools", "Makevars.rtools45")
    )
  }
}
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
trailing <- commandArgs(trailingOnly = TRUE)
value_after <- function(name, default = NULL) {
  liber_validation_option(name, default, args = trailing)
}
output <- value_after("output", file.path(harness, "results"))
if (!grepl("^(?:[A-Za-z]:[/\\\\]|/)", output, perl = TRUE)) {
  output <- file.path(root, output)
}
dir.create(output, recursive = TRUE, showWarnings = FALSE)

iterations_arg <- grep("^--iterations=", trailing, value = TRUE)
iterations <- if (length(iterations_arg)) {
  as.integer(sub("^--iterations=", "", iterations_arg[[1L]]))
} else {
  200L
}
if (is.na(iterations) || iterations < 1L) stop("--iterations must be positive.")

runtime <- liber_validation_library(
  root, "LibeRtAD",
  library = value_after("library", Sys.getenv("LIBER_VALIDATION_LIBRARY", ""))
)
external_library <- value_after(
  "external-library", liber_validation_dev_cache(
    root, "r-libraries", "external-comparators"
  )
)
.libPaths(unique(c(
  runtime$path,
  if (dir.exists(external_library)) {
    normalizePath(external_library, winslash = "/", mustWork = TRUE)
  } else character(),
  .libPaths()
)))

elapsed <- function(expression) {
  started <- proc.time()[["elapsed"]]
  value <- force(expression)
  list(value = value, seconds = unname(proc.time()[["elapsed"]] - started))
}
timed_calls <- function(fun, n = iterations) {
  fun()
  samples <- numeric(5)
  for (sample in seq_along(samples)) {
    started <- proc.time()[["elapsed"]]
    for (iteration in seq_len(n)) fun()
    samples[[sample]] <- (proc.time()[["elapsed"]] - started) * 1e6 / n
  }
  unname(stats::median(samples))
}
number <- function(value) format(value, digits = 17, scientific = TRUE)

cases <- local({
  dimension <- 10L
  rows <- 400L
  x <- outer(seq_len(rows), seq_len(dimension), function(row, column) {
    sin(row * (column + 0.5) / 23) + cos(row / (column + 2))
  })
  truth <- seq(-0.7, 0.7, length.out = dimension)
  probability <- stats::plogis(drop(x %*% truth))
  y <- as.integer(((seq_len(rows) * 37L) %% 101L) / 101 < probability)
  list(
    rosenbrock_10d = list(
      id = 1L, point = rep(-0.4, dimension),
      x = matrix(numeric(), 0L, dimension), y = numeric()
    ),
    logistic_400x10 = list(
      id = 2L, point = seq(-0.2, 0.2, length.out = dimension),
      x = x, y = y
    )
  )
})

libertad_code <- function(case) {
  names <- paste0("B", seq_along(case$point))
  if (case$id == 1L) {
    terms <- unlist(lapply(seq_len(length(names) - 1L), function(index) {
      c(
        paste0(
          "R", index, " = 100 * (", names[[index + 1L]], " - ",
          names[[index]], "^2)^2"
        ),
        paste0("S", index, " = (1 - ", names[[index]], ")^2")
      )
    }))
    final <- paste(c(
      paste0("R", seq_len(length(names) - 1L)),
      paste0("S", seq_len(length(names) - 1L))
    ), collapse = " + ")
  } else {
    terms <- character(nrow(case$x) * 2L)
    likelihood <- character(nrow(case$x))
    for (row in seq_len(nrow(case$x))) {
      linear <- paste(
        paste(number(case$x[row, ]), names, sep = " * "),
        collapse = " + "
      )
      terms[[2L * row - 1L]] <- paste0("L", row, " = ", linear)
      terms[[2L * row]] <- paste0(
        "N", row, " = log1p(exp(L", row, ")) - ",
        case$y[[row]], " * L", row
      )
      likelihood[[row]] <- paste0("N", row)
    }
    final <- paste(likelihood, collapse = " + ")
  }
  paste(c(terms, paste0("Y = ", final)), collapse = "\n")
}

result_row <- function(case_name, backend, status = "completed", message = NA_character_,
                       compile_seconds = NA_real_, tape_seconds = NA_real_,
                       value_gradient_us = NA_real_, hessian_us = NA_real_,
                       value = NA_real_, max_gradient_difference = NA_real_,
                       max_hessian_difference = NA_real_,
                       object_bytes = NA_real_, tape_bytes_proxy = NA_real_,
                       version = NA_character_) {
  data.frame(
    case = case_name, backend = backend, status = status, message = message,
    compile_seconds = compile_seconds, tape_seconds = tape_seconds,
    value_gradient_microseconds = value_gradient_us,
    hessian_microseconds = hessian_us, value = value,
    max_gradient_difference = max_gradient_difference,
    max_hessian_difference = max_hessian_difference,
    object_bytes = object_bytes, tape_bytes_proxy = tape_bytes_proxy,
    version = version, stringsAsFactors = FALSE
  )
}

results <- list()
references <- list()
for (case_name in names(cases)) {
  case <- cases[[case_name]]
  names(case$point) <- paste0("B", seq_along(case$point))
  built <- elapsed(LibeRtAD::ad_compile(
    libertad_code(case), inputs = names(case$point), outputs = "Y",
    at = case$point, wrt = names(case$point)
  ))
  model <- built$value
  evaluation <- model$value_gradient(case$point)
  references[[case_name]] <- list(
    value = unname(evaluation$value[[1L]]),
    gradient = unname(evaluation$gradient),
    hessian = unname(model$hessian(case$point))
  )
  info <- model$tape_info()
  results[[length(results) + 1L]] <- result_row(
    case_name, "LibeRtAD", compile_seconds = built$seconds,
    tape_seconds = built$seconds,
    value_gradient_us = timed_calls(function() model$value_gradient(case$point)),
    hessian_us = timed_calls(function() model$hessian(case$point)),
    value = references[[case_name]]$value,
    max_gradient_difference = 0,
    max_hessian_difference = 0,
    object_bytes = as.numeric(object.size(model)),
    tape_bytes_proxy = info$resident_bytes_proxy,
    version = as.character(utils::packageVersion("LibeRtAD"))
  )
}

if (!requireNamespace("TMB", quietly = TRUE)) {
  for (case_name in names(cases)) {
    results[[length(results) + 1L]] <- result_row(
      case_name, "TMB", status = "skipped",
      message = "R package TMB is not installed."
    )
  }
} else {
  tmb_source <- file.path(harness, "tmb_objective.cpp")
  build_dir <- file.path(output, "tmb-build")
  dir.create(build_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(tmb_source, build_dir, overwrite = TRUE)
  old <- getwd()
  compiled <- tryCatch(
    {
      setwd(build_dir)
      elapsed(TMB::compile("tmb_objective.cpp", flags = "-O2"))
    },
    error = identity,
    finally = setwd(old)
  )
  tmb_dll <- NULL
  if (!inherits(compiled, "error")) {
    tmb_dll <- normalizePath(
      file.path(build_dir, TMB::dynlib("tmb_objective")),
      mustWork = TRUE
    )
    dyn.load(tmb_dll)
  }
  for (case_name in names(cases)) {
    case <- cases[[case_name]]
    if (inherits(compiled, "error")) {
      results[[length(results) + 1L]] <- result_row(
        case_name, "TMB", status = "failed",
        message = conditionMessage(compiled)
      )
      next
    }
    taped <- elapsed(TMB::MakeADFun(
      data = list(case_id = case$id, x = case$x, y = case$y),
      parameters = list(beta = case$point), DLL = "tmb_objective",
      silent = TRUE
    ))
    objective <- taped$value
    value <- objective$fn(case$point)
    gradient <- objective$gr(case$point)
    hessian <- objective$he(case$point)
    results[[length(results) + 1L]] <- result_row(
      case_name, "TMB", compile_seconds = compiled$seconds,
      tape_seconds = taped$seconds,
      value_gradient_us = timed_calls(function() {
        objective$fn(case$point); objective$gr(case$point)
      }),
      hessian_us = timed_calls(function() objective$he(case$point)),
      value = value,
      max_gradient_difference = max(abs(
        gradient - references[[case_name]]$gradient
      )),
      max_hessian_difference = max(abs(
        hessian - references[[case_name]]$hessian
      )),
      object_bytes = as.numeric(object.size(objective)),
      version = as.character(utils::packageVersion("TMB"))
    )
  }
  if (!is.null(tmb_dll)) {
    try(dyn.unload(tmb_dll), silent = TRUE)
  }
}

if (requireNamespace("cmdstanr", quietly = TRUE)) {
  local_cmdstan_root <- liber_validation_dev_cache(
    root, "external-tools", "cmdstan"
  )
  local_cmdstan <- if (dir.exists(local_cmdstan_root)) {
    list.dirs(local_cmdstan_root, recursive = FALSE, full.names = TRUE)
  } else {
    character()
  }
  local_cmdstan <- local_cmdstan[
    grepl("^cmdstan-[0-9]", basename(local_cmdstan))
  ]
  if (length(local_cmdstan)) {
    cmdstanr::set_cmdstan_path(tail(sort(local_cmdstan), 1L))
  }
}
cmdstan_available <- requireNamespace("cmdstanr", quietly = TRUE) &&
  tryCatch(nzchar(cmdstanr::cmdstan_path()), error = function(error) FALSE)
if (!cmdstan_available) {
  for (case_name in names(cases)) {
    results[[length(results) + 1L]] <- result_row(
      case_name, "CmdStan", status = "skipped",
      message = "cmdstanr and a configured CmdStan toolchain are required."
    )
  }
} else {
  stan_build_dir <- file.path(output, "stan-build")
  dir.create(stan_build_dir, recursive = TRUE, showWarnings = FALSE)
  stan_source <- file.path(stan_build_dir, "stan_objective.stan")
  file.copy(
    file.path(harness, "stan_objective.stan"), stan_source,
    overwrite = TRUE
  )
  stan_build <- tryCatch(
    elapsed(cmdstanr::cmdstan_model(
      stan_source, quiet = TRUE,
      compile_model_methods = TRUE, force_recompile = TRUE
    )),
    error = identity
  )
  for (case_name in names(cases)) {
    case <- cases[[case_name]]
    if (inherits(stan_build, "error")) {
      results[[length(results) + 1L]] <- result_row(
        case_name, "CmdStan", status = "failed",
        message = conditionMessage(stan_build)
      )
      next
    }
    data <- list(
      case_id = case$id, N = nrow(case$x), K = length(case$point),
      x = case$x, y = as.integer(case$y)
    )
    initialized <- tryCatch(elapsed({
      fit <- stan_build$value$optimize(
        data = data, init = list(list(beta = unname(case$point))),
        iter = 1L, refresh = 0L
      )
      fit$init_model_methods(verbose = FALSE, hessian = TRUE)
      fit
    }), error = identity)
    if (inherits(initialized, "error")) {
      results[[length(results) + 1L]] <- result_row(
        case_name, "CmdStan", status = "failed",
        message = conditionMessage(initialized)
      )
      next
    }
    fit <- initialized$value
    gradient <- fit$grad_log_prob(case$point, jacobian = FALSE)
    hessian_result <- fit$hessian(case$point, jacobian = FALSE)
    hessian <- if (is.list(hessian_result) &&
                   !is.null(hessian_result$hessian)) {
      hessian_result$hessian
    } else {
      hessian_result
    }
    hessian <- as.matrix(hessian)
    value <- -as.numeric(attr(gradient, "log_prob"))
    results[[length(results) + 1L]] <- result_row(
      case_name, "CmdStan", compile_seconds = stan_build$seconds,
      tape_seconds = initialized$seconds,
      value_gradient_us = timed_calls(function() {
        fit$grad_log_prob(case$point, jacobian = FALSE)
      }),
      hessian_us = timed_calls(function() {
        fit$hessian(case$point, jacobian = FALSE)
      }),
      value = value,
      max_gradient_difference = max(abs(
        -as.numeric(gradient) - references[[case_name]]$gradient
      )),
      max_hessian_difference = max(abs(
        -as.matrix(hessian) - references[[case_name]]$hessian
      )),
      object_bytes = as.numeric(object.size(fit)),
      version = paste0(
        utils::packageVersion("cmdstanr"), " / CmdStan ",
        cmdstanr::cmdstan_version()
      )
    )
  }
}

table <- do.call(rbind, results)
table$value_difference <- ave(
  table$value, table$case,
  FUN = function(value) abs(value - value[[1L]])
)
tolerances <- list(value = 1e-8, gradient = 1e-7, hessian = 2e-6)
table$validation_passed <- ifelse(
  table$status == "skipped", NA,
  table$status == "completed" &
    is.finite(table$value_difference) &
    table$value_difference <= tolerances$value &
    is.finite(table$max_gradient_difference) &
    table$max_gradient_difference <= tolerances$gradient &
    is.finite(table$max_hessian_difference) &
    table$max_hessian_difference <= tolerances$hessian
)
bad <- table$status == "completed" & !table$validation_passed
table$status[bad] <- "failed"
table$message[bad] <- paste(
  "Numerical value or derivative agreement exceeded a declared tolerance."
)
require_cmdstan <- "--require-cmdstan" %in% trailing
cmdstan_complete <- all(
  table$status[table$backend == "CmdStan"] == "completed"
)
passed <- !any(table$status == "failed") &&
  (!require_cmdstan || cmdstan_complete)
manifest <- list(
  schema = "libertad.external-ad-validation/1",
  generated_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  R = R.version.string,
  platform = R.version$platform,
  iterations = iterations,
  passed = passed,
  complete = !require_cmdstan || cmdstan_complete,
  require_cmdstan = require_cmdstan,
  tolerances = tolerances,
  results = table
)
utils::write.csv(table, file.path(output, "benchmark.csv"), row.names = FALSE)
saveRDS(manifest, file.path(output, "benchmark.rds"), version = 3L)
jsonlite::write_json(
  manifest, file.path(output, "summary.json"), auto_unbox = TRUE,
  pretty = TRUE, null = "null", digits = 17
)
print(table, row.names = FALSE)
if (!passed) quit(status = 1L)
