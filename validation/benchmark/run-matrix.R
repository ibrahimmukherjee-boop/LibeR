args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
script_path <- if (length(script_arg)) sub("^--file=", "", script_arg[[1L]]) else
  file.path("validation", "benchmark", "run-matrix.R")
benchmark_dir <- normalizePath(dirname(script_path), winslash = "/", mustWork = TRUE)
root <- normalizePath(file.path(benchmark_dir, "..", ".."),
                      winslash = "/", mustWork = TRUE)
source(file.path(benchmark_dir, "scenarios.R"), local = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)

option_value <- function(name, default = NULL) {
  liber_validation_option(name, default, args = args)
}

profile <- option_value("profile", "smoke")
methods <- option_value("methods", "deterministic")
engines <- toupper(option_value("engines", "NONMEM,LIBERATION"))
repeats <- option_value("repeats", "1")
warmups <- option_value("warmups", "0")
selected <- strsplit(
  option_value("scenarios", paste(benchmark_scenario_names(), collapse = ",")),
  ",", fixed = TRUE
)[[1L]]
selected <- trimws(tolower(selected))
unknown <- setdiff(selected, benchmark_scenario_names())
if (length(unknown)) stop("Unknown scenarios: ", paste(unknown, collapse = ", "))

stamp <- format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC")
output <- normalizePath(
  option_value("output", file.path(benchmark_dir, "results", paste0(stamp, "-matrix"))),
  winslash = "/", mustWork = FALSE
)
dir.create(output, recursive = TRUE, showWarnings = FALSE)
rscript <- file.path(
  R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
)
benchmark <- file.path(benchmark_dir, "benchmark.R")
statuses <- integer(length(selected))

for (index in seq_along(selected)) {
  scenario <- selected[[index]]
  scenario_engines <- if (scenario == "iov" && grepl("NONMEM", engines, fixed = TRUE)) {
    "LIBERATION"
  } else engines
  destination <- file.path(output, scenario)
  command <- c(
    "--vanilla", benchmark,
    paste0("--profile=", profile), paste0("--methods=", methods),
    paste0("--engines=", scenario_engines), paste0("--repeats=", repeats),
    paste0("--warmups=", warmups), paste0("--scenario=", scenario),
    paste0("--output=", destination)
  )
  cat(sprintf("[%d/%d] %s\n", index, length(selected), scenario))
  statuses[[index]] <- system2(rscript, command)
}

summaries <- lapply(selected, function(scenario) {
  path <- file.path(output, scenario, "summary.csv")
  if (!file.exists(path)) return(NULL)
  value <- utils::read.csv(path, stringsAsFactors = FALSE)
  value$scenario <- scenario
  value
})
summaries <- Filter(Negate(is.null), summaries)
if (length(summaries)) {
  utils::write.csv(
    do.call(rbind, summaries), file.path(output, "matrix-summary.csv"),
    row.names = FALSE, na = ""
  )
}
status <- data.frame(scenario = selected, status = statuses)
utils::write.csv(status, file.path(output, "matrix-status.csv"), row.names = FALSE)
if (any(statuses != 0L)) {
  stop("One or more benchmark scenarios failed. See matrix-status.csv.", call. = FALSE)
}
cat("Completed matrix:", output, "\n")
