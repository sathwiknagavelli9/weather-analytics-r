# Run from the project root with Rscript scripts/install_dependencies.R.
options(timeout = 180)
required <- c("shiny", "bslib", "ggplot2", "jsonlite", "curl", "rsconnect")
mirrors <- c("https://cloud.r-project.org", "https://cran.rstudio.com", "https://cran.ma.imperial.ac.uk")
is_ready <- function(p) isTRUE(tryCatch(requireNamespace(p, quietly = TRUE), error = function(e) FALSE))
all_required <- function() {
  dependencies <- tools::package_dependencies(required, db = installed.packages(), recursive = TRUE)
  unique(c(required, unlist(dependencies, use.names = FALSE)))
}
missing_packages <- function() {
  packages <- all_required()
  packages[!vapply(packages, is_ready, logical(1))]
}
missing <- missing_packages()
for (repo in mirrors) {
  if (!length(missing)) break
  for (attempt in seq_len(2L)) {
    message("Installing missing packages from ", repo, " (attempt ", attempt, ")")
    tryCatch(install.packages(missing, repos = repo,
      type = if (.Platform$OS.type == "windows") "win.binary" else "binary",
      dependencies = NA), error = function(e) message("Download failed; trying another route."))
    missing <- missing_packages()
    if (!length(missing)) break
    Sys.sleep(attempt)
  }
}
if (length(missing) && .Platform$OS.type == "windows") {
  downloader <- Sys.which("curl.exe")
  if (!nzchar(downloader)) stop("Windows curl.exe is required for the binary download fallback.")
  temp <- tempfile("weatherpulse-packages-")
  dir.create(temp)
  download_binary <- function(url, dest) {
    status <- system2(downloader, c("--fail", "--location", "--silent", "--show-error",
      "--retry", "3", "--connect-timeout", "20", "--max-time", "180",
      "--output", shQuote(dest), shQuote(url)))
    if (status != 0L) stop("Windows binary download failed.")
  }
  installed_now <- character()
  for (repo in mirrors) {
    if (!length(missing)) break
    tryCatch({
      base <- contrib.url(repo, type = "win.binary")
      index <- file.path(temp, "PACKAGES.gz")
      download_binary(paste0(base, "/PACKAGES.gz"), index)
      con <- gzfile(index)
      available <- read.dcf(con)
      close(con)
      rownames(available) <- available[, "Package"]
      installing <- character()
      install_one <- function(p) {
        if (is_ready(p) || p %in% installed_now) return(invisible(NULL))
        if (!p %in% rownames(available)) stop("No binary available for ", p)
        if (p %in% installing) stop("Circular dependency encountered for ", p)
        installing <<- c(installing, p)
        row <- available[p, ]
        fields <- intersect(c("Depends", "Imports", "LinkingTo"), names(row))
        deps <- unlist(strsplit(paste(row[fields][!is.na(row[fields])], collapse = ","), ","))
        deps <- unique(trimws(sub("\\s*\\(.*$", "", deps)))
        for (dep in setdiff(deps[nzchar(deps)], "R")) install_one(dep)
        zip <- file.path(temp, paste0(p, "_", row[["Version"]], ".zip"))
        download_binary(paste0(base, "/", basename(zip)), zip)
        install.packages(zip, repos = NULL, type = "win.binary")
        installed_now <<- c(installed_now, p)
        installing <<- setdiff(installing, p)
      }
      for (p in missing) install_one(p)
    }, error = function(e) message(conditionMessage(e)))
    missing <- missing_packages()
  }
  unlink(temp, recursive = TRUE)
}
if (length(missing)) stop("Unable to load required packages: ", paste(missing, collapse = ", "))
for (p in required) {
  library(p, character.only = TRUE)
  cat(p, as.character(packageVersion(p)), "OK\n")
}
