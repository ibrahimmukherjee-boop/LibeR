`%or%` <- function(left, right) {
  if (is.null(left) || !length(left)) right else left
}

root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
source(file.path(root, "deploy", "shinyapps", "runtime.R"), local = TRUE)
liber_shinyapps_use_library(root)

for (package in c("LibeRtAD", "LibeRation", "LibeRality", "LibeRator")) {
  description <- utils::packageDescription(package)
  cat(
    package,
    description$Version,
    description$RemoteRepo %or% "",
    description$RemoteRef %or% "",
    description$RemoteSha %or% "",
    "\n"
  )
}
