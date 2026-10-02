# Lightweight offline test runner; no weather requests are made here.
for (p in c("shiny", "bslib", "ggplot2", "jsonlite", "curl")) {
  if (!requireNamespace(p, quietly = TRUE)) stop("Install dependencies first: ", p)
}
source("tests/test_api.R")
run_api_tests()
source("tests/test_analytics.R")
source("tests/test_prediction.R")
if (file.exists("tests/test_server.R")) {
  source("tests/test_server.R")
  run_server_tests()
}
cat("PASS: all offline tests\n")
