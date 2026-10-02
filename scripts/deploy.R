# Uses the existing local rsconnect account configuration. No credentials here.
if (!requireNamespace("rsconnect", quietly = TRUE)) stop("Run scripts/install_dependencies.R first.")
account <- "sathwik-nagavelli"
app_name <- Sys.getenv("WEATHERPULSE_APP_NAME", "weather-analytics-r")
accounts <- rsconnect::accounts()
if (!any(accounts$name == account & accounts$server == "shinyapps.io")) {
  stop("The expected shinyapps.io account is not configured in this R environment.")
}
app_files <- c("app.R", list.files("R", full.names = TRUE, pattern = "\\.R$"),
               list.files("www", full.names = TRUE, recursive = TRUE))
stopifnot(all(file.exists(app_files)))
# Restrict the deployment bundle to runtime source and assets.
rsconnect::deployApp(appDir = ".", appFiles = app_files, appName = app_name,
  appTitle = "WeatherPulse", account = account, server = "shinyapps.io",
  launch.browser = FALSE, logLevel = "normal")
