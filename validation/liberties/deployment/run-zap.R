#!/usr/bin/env Rscript

arguments <- commandArgs(trailingOnly = TRUE)
script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script <- if (length(script_argument)) {
  sub("^--file=", "", script_argument[[1L]])
} else {
  "validation/liberties/deployment/run-zap.R"
}
repository <- normalizePath(file.path(dirname(script), "..", "..", ".."),
                            winslash = "/", mustWork = TRUE)
source(file.path(repository, "tools", "validation-runtime.R"), local = TRUE)
value_after <- function(name, default = NULL) {
  liber_validation_option(name, default, args = arguments)
}
target <- value_after("target", "http://127.0.0.1:8000")
output <- value_after(
  "output", "validation/liberties/deployment/results/zap"
)
allow_remote <- "--allow-remote" %in% arguments
fail_on_warning <- "--fail-on-warning" %in% arguments

parsed <- tryCatch(utils::URLdecode(target), error = function(error) "")
host <- tolower(sub(
  "^[A-Za-z][A-Za-z0-9+.-]*://(\\[[^]]+\\]|[^/:]+).*$", "\\1", parsed
))
host <- gsub("^\\[|\\]$", "", host)
allowed <- c("127.0.0.1", "localhost", "::1", "host.docker.internal")
if (!grepl("^https?://", target, ignore.case = TRUE) || !nzchar(host)) {
  stop("`--target` must be an HTTP(S) URL.", call. = FALSE)
}
if (!host %in% allowed && !allow_remote) {
  stop(
    "Refusing to scan a non-loopback target without `--allow-remote`.",
    call. = FALSE
  )
}
if (!nzchar(Sys.which("docker"))) {
  stop("Docker is required for the pinned OWASP ZAP runner.", call. = FALSE)
}

dir.create(output, recursive = TRUE, showWarnings = FALSE)
output <- normalizePath(output, winslash = "/", mustWork = TRUE)
docker_target <- target
if (host %in% c("127.0.0.1", "localhost", "::1")) {
  docker_target <- sub(
    "^(https?://)(\\[[^]]+\\]|[^/:]+)",
    "\\1host.docker.internal", target, ignore.case = TRUE
  )
}
zap_arguments <- c(
  "run", "--rm", "--add-host=host.docker.internal:host-gateway",
  "-v", shQuote(paste0(output, ":/zap/wrk/:rw")),
  "ghcr.io/zaproxy/zaproxy:2.17.0",
  "zap-baseline.py", "-t", shQuote(docker_target),
  "-J", "zap-report.json", "-r", "zap-report.html"
)
if (!fail_on_warning) zap_arguments <- c(zap_arguments, "-I")
status <- system2("docker", zap_arguments)
if (!identical(as.integer(status), 0L)) {
  stop("OWASP ZAP baseline returned status ", status, ".", call. = FALSE)
}
cat("ZAP evidence:", output, "\n")
