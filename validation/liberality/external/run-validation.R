arguments <- commandArgs(trailingOnly = TRUE)
value_argument <- function(name, default) {
  match <- grep(paste0("^--", name, "="), arguments, value = TRUE)
  if (length(match)) sub(paste0("^--", name, "="), "", match[[1L]]) else default
}

script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script <- if (length(script_argument)) sub("^--file=", "", script_argument[[1L]]) else "run-validation.R"
external_dir <- dirname(normalizePath(script, winslash = "/", mustWork = TRUE))
root <- normalizePath(file.path(external_dir, "..", "..", ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
library_path <- normalizePath(
  value_argument(
    "library",
    liber_validation_dev_cache(root, "r-libraries", "liberality-external")
  ),
  winslash = "/", mustWork = TRUE
)
package_library <- normalizePath(
  value_argument(
    "package-library",
    liber_validation_dev_cache(root, "r-libraries", "liberality-package")
  ),
  winslash = "/", mustWork = TRUE
)
repetitions <- as.integer(value_argument("repetitions", "10"))
stamp <- format(Sys.time(), "%Y%m%d-%H%M%S", tz = "UTC")
output <- value_argument("output", file.path(external_dir, "results", stamp))

.libPaths(c(package_library, library_path, .libPaths()))
required <- c(LibeRality = "0.1.2", PopED = "0.7.0", PFIM = "7.0.3")
installed <- vapply(names(required), function(package) {
  if (!requireNamespace(package, quietly = TRUE)) NA_character_ else as.character(utils::packageVersion(package))
}, character(1))
if (anyNA(installed)) stop("Missing validation packages: ", paste(names(installed)[is.na(installed)], collapse = ", "))
drift <- installed != required
if (any(drift)) warning(
  "Validation dependency version drift: ",
  paste(names(installed)[drift], installed[drift], "(baseline", required[drift], ")", collapse = ", ")
)
message("External validation versions: ", paste(names(installed), installed, sep = "=", collapse = ", "))

result <- LibeRality::lity_external_validate(
  repetitions = repetitions, output_dir = output, design_search = TRUE
)
print(result)
print(result$comparisons)
print(result$coverage)
print(result$design_search$best)
print(result$timings)
if (!isTRUE(result$passed)) quit(save = "no", status = 1L)
