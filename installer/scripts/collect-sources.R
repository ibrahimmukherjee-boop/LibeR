arguments <- commandArgs(trailingOnly = TRUE)
value_after <- function(name, default = "") {
  hit <- grep(paste0("^--", name, "="), arguments, value = TRUE)
  if (length(hit)) sub(paste0("^--", name, "="), "", hit[[length(hit)]])
  else default
}

root <- normalizePath(value_after("root", getwd()), winslash = "/",
                      mustWork = TRUE)
library_path <- normalizePath(value_after("library"), winslash = "/",
                              mustWork = TRUE)
destination <- normalizePath(value_after("destination"), winslash = "/",
                             mustWork = FALSE)
if (dir.exists(destination) &&
    length(list.files(destination, all.files = TRUE, no.. = TRUE))) {
  stop("Corresponding-source destination is not empty: ", destination,
       call. = FALSE)
}
dir.create(destination, recursive = TRUE, showWarnings = FALSE)

base_library <- file.path(R.home(), "library")
.libPaths(unique(c(library_path, base_library)))
Sys.setenv(
  R_LIBS_USER = library_path,
  R_LIBS_SITE = "",
  R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep)
)
options(repos = c(
  CRAN = Sys.getenv("LIBER_CRAN_MIRROR", "https://cloud.r-project.org")
))

source(file.path(root, "tools", "validation-runtime.R"), local = TRUE)
manifest <- jsonlite::fromJSON(
  file.path(root, "ecosystem.json"), simplifyVector = FALSE
)
liber_packages <- names(manifest$packages)

sha256 <- function(path) {
  unname(as.character(tools::sha256sum(path)))
}
records <- list()
add_record <- function(component, version, kind, path, origin) {
  records[[length(records) + 1L]] <<- data.frame(
    component = component,
    version = version,
    kind = kind,
    path = substring(
      normalizePath(path, winslash = "/", mustWork = TRUE),
      nchar(destination) + 2L
    ),
    bytes = unname(file.info(path)$size),
    sha256 = sha256(path),
    origin = origin,
    stringsAsFactors = FALSE
  )
}

liber_dir <- file.path(destination, "liber")
dir.create(liber_dir, recursive = TRUE, showWarnings = FALSE)
old_working_directory <- getwd()
setwd(liber_dir)
on.exit(setwd(old_working_directory), add = TRUE)
for (package in liber_packages) {
  version <- manifest$packages[[package]]$version
  status <- system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "build", "--no-manual", "--no-build-vignettes",
      shQuote(file.path(root, package)))
  )
  if (!identical(status, 0L)) {
    stop("Unable to build corresponding source for ", package, ".",
         call. = FALSE)
  }
  liber_validation_clean_native_source(file.path(root, package))
  archive <- file.path(liber_dir, paste0(package, "_", version, ".tar.gz"))
  if (!file.exists(archive)) {
    stop("Missing built source archive: ", archive, call. = FALSE)
  }
  add_record(
    package, version, "liber-package", archive,
    paste0("https://github.com/svdijkman/", package)
  )
}
setwd(old_working_directory)

installed <- as.data.frame(utils::installed.packages(
  lib.loc = library_path,
  fields = c("Priority", "Repository", "RemoteType", "RemoteRepo", "RemoteSha")
), stringsAsFactors = FALSE)
installed$Package <- rownames(installed)
dependencies <- installed[
  !installed$Package %in% liber_packages &
    (is.na(installed$Priority) | !nzchar(installed$Priority)),
  ,
  drop = FALSE
]
non_cran <- dependencies[
  !is.na(dependencies$RemoteType) & nzchar(dependencies$RemoteType),
  ,
  drop = FALSE
]
if (nrow(non_cran)) {
  stop(
    "The bundled dependency library contains non-CRAN packages without an ",
    "implemented source collector: ",
    paste(non_cran$Package, collapse = ", "),
    call. = FALSE
  )
}

cran_dir <- file.path(destination, "cran")
dir.create(cran_dir, recursive = TRUE, showWarnings = FALSE)
available <- utils::available.packages(
  contriburl = utils::contrib.url(getOption("repos"), type = "source"),
  filters = list()
)
missing <- setdiff(dependencies$Package, rownames(available))
if (length(missing)) {
  stop("CRAN source metadata is unavailable for: ",
       paste(missing, collapse = ", "), call. = FALSE)
}
available_versions <- available[dependencies$Package, "Version"]
version_mismatch <- dependencies$Package[
  available_versions != dependencies$Version
]
if (length(version_mismatch)) {
  details <- paste0(
    version_mismatch, " installed=",
    dependencies[version_mismatch, "Version"],
    " source=", available[version_mismatch, "Version"]
  )
  stop(
    "Exact CRAN source versions are no longer current: ",
    paste(details, collapse = "; "),
    ". Build against a dated package snapshot.",
    call. = FALSE
  )
}

downloaded <- utils::download.packages(
  dependencies$Package,
  destdir = cran_dir,
  available = available,
  repos = getOption("repos"),
  type = "source",
  quiet = FALSE
)
downloaded <- stats::setNames(downloaded[, "destfile"], downloaded[, "Package"])
for (package in dependencies$Package) {
  archive <- unname(downloaded[[package]])
  version <- dependencies[package, "Version"]
  expected_name <- paste0(package, "_", version, ".tar.gz")
  if (!file.exists(archive) || !identical(basename(archive), expected_name)) {
    stop("Exact corresponding source was not downloaded for ", package, ".",
         call. = FALSE)
  }
  add_record(
    package, version, "cran-package", archive,
    paste0(
      sub("/+$", "", unname(getOption("repos")[["CRAN"]])),
      "/src/contrib/", expected_name
    )
  )
}

r_version <- as.character(getRversion())
r_major <- strsplit(r_version, ".", fixed = TRUE)[[1L]][[1L]]
r_dir <- file.path(destination, "r-runtime")
dir.create(r_dir, recursive = TRUE, showWarnings = FALSE)
r_name <- paste0("R-", r_version, ".tar.gz")
r_url <- paste0(
  sub("/+$", "", unname(getOption("repos")[["CRAN"]])),
  "/src/base/R-", r_major, "/", r_name
)
r_archive <- file.path(r_dir, r_name)
utils::download.file(r_url, r_archive, mode = "wb", quiet = FALSE)
if (!file.exists(r_archive) || file.info(r_archive)$size < 1e6) {
  stop("The R source archive was not downloaded correctly.", call. = FALSE)
}
add_record("R", r_version, "r-runtime", r_archive, r_url)

source_manifest <- do.call(rbind, records)
source_manifest <- source_manifest[
  order(source_manifest$kind, tolower(source_manifest$component)),
  ,
  drop = FALSE
]
utils::write.csv(
  source_manifest, file.path(destination, "sources.csv"),
  row.names = FALSE, na = ""
)
file.copy(
  file.path(root, "installer", "legal", "SOURCE-OFFER.txt"),
  file.path(destination, "SOURCE-OFFER.txt"),
  overwrite = TRUE
)
message(
  "Collected ", nrow(source_manifest),
  " exact corresponding-source archives at ", destination
)
