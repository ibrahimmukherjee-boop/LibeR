packages <- c("LibeRtAD", "LibeRation", "LibeRary", "LibeRator", "LibeRality", "LibeRties")
root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
local_library <- Sys.getenv(
  "LIBER_INSTALL_LIBRARY",
  liber_validation_dev_cache(root, "r-libraries", "integration", create = TRUE)
)
dir.create(local_library, recursive = TRUE, showWarnings = FALSE)
.libPaths(unique(c(local_library, .libPaths())))
Sys.setenv(
  LIBER_INSTALL_LIBRARY = local_library,
  R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep)
)
if (!identical(tolower(Sys.getenv("LIBER_SKIP_INSTALL")), "true")) {
  status <- system2(
    file.path(R.home("bin"), "Rscript"),
    file.path(root, "tools", "install-local-stack.R")
  )
  if (!identical(status, 0L)) stop("Unable to install local package stack.")
}

library(LibeRation)
library(LibeRality)
library(LibeRties)

model <- nm_model(
  INPUT = c("ID", "TIME", "EVID", "AMT", "DV", "MDV"), ADVAN = 1,
  PRED = "CL=THETA(1)*exp(ETA(1));V=THETA(2);S1=V", ERROR = "Y=F+ERR(1)",
  THETAS = data.frame(THETA = 1:2, Value = c(2, 20), FIX = TRUE),
  OMEGAS = data.frame(OMEGA = 1, Value = 0.1, FIX = TRUE),
  SIGMAS = data.frame(SIGMA = 1, Value = 0.1, FIX = TRUE)
)
data <- data.frame(
  ID = 1, TIME = c(0, 1, 4), EVID = c(1, 0, 0), AMT = c(100, 0, 0),
  DV = c(NA, 4.5, 3.1), MDV = c(1, 0, 0)
)
job <- ls_job("estimate", model, data, arguments = list(method = "FOCEI", maxit = 2L))
rebuilt <- ls_job_decode(ls_job_encode(job))
stopifnot(inherits(rebuilt$model, "nm_model"), rebuilt$type == "estimate")

evaluation <- lity_evaluate(lity_example()$design, lity_criterion_D())
roundtrip <- ls_result_decode(ls_result_encode(evaluation))
stopifnot(inherits(roundtrip, "lity_evaluation"), inherits(roundtrip$design, "lity_design"))

queue <- ls_local_queue(tempfile("liber-ci-queue-"), max_workers = 1L)
on.exit(queue$shutdown(), add = TRUE)
id <- queue$submit(job)
deadline <- Sys.time() + 120
repeat {
  queue$poll()
  status <- queue$status(id)$status
  if (status %in% c("completed", "failed", "cancelled")) break
  if (Sys.time() > deadline) stop("Integration worker timed out.")
  Sys.sleep(0.1)
}
stopifnot(status == "completed", inherits(queue$result(id), "nm_fit"))
message("Cross-package job, result, and worker integration passed.")
