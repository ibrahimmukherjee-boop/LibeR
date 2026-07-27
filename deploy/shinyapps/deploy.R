arguments <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
source(file.path(root, "deploy", "shinyapps", "runtime.R"), local = TRUE)
liber_shinyapps_use_library(root)
if (length(arguments) != 1L || !arguments[[1L]] %in%
    c("liberation", "liberality", "liberator")) {
  stop("Usage: Rscript deploy/shinyapps/deploy.R <liberation|liberality|liberator>")
}

name <- arguments[[1L]]
titles <- c(
  liberation = "LibeRation",
  liberality = "LibeRality",
  liberator = "LibeRator"
)

rsconnect::deployApp(
  appDir = file.path(root, "deploy", "shinyapps", name),
  appFiles = "app.R",
  appName = name,
  appTitle = unname(titles[[name]]),
  account = "svdijkman",
  server = "shinyapps.io",
  launch.browser = FALSE,
  lint = TRUE,
  forceUpdate = TRUE,
  dependencyResolution = "library",
  logLevel = "verbose"
)
