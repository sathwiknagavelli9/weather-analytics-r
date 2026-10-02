# Live integration test: only real Open-Meteo data enters this workflow.
for (p in c("shiny", "bslib", "ggplot2", "curl", "jsonlite", "rsconnect")) {
  if (!requireNamespace(p, quietly = TRUE)) stop("Missing package: ", p)
  cat("Package:", p, as.character(packageVersion(p)), "\n")
}
for (module in c("utils", "weather_codes", "api", "analytics", "prediction")) {
  source(file.path("R", paste0(module, ".R")))
}
cities <- geocode_city("Hyderabad")
city <- cities[cities$country == "India", , drop = FALSE][1, , drop = FALSE]
stopifnot(nrow(city) == 1L, is.finite(city$latitude))
weather <- fetch_weather(city, force = TRUE)
stopifnot(length(weather$current$temperature_2m) == 1L,
          is.finite(weather$current$temperature_2m), nrow(weather$daily) == 7L,
          nzchar(weather_label(weather$current$weather_code)))
history <- clean_history(fetch_model_history(city, 365L))
stopifnot(nrow(history) == 365L, max(history$date) == city_local_date(city) - 1L,
          all(c("source", "mean_method") %in% names(history)))
summary <- summarize_history(history)
stopifnot(is.finite(summary$avg_temp), is.finite(summary$total_precipitation))
model <- train_temperature_model(history)
stopifnot(is.finite(model$next_prediction), model$n_train > model$n_test,
          is.finite(model$metrics$mae), is.finite(model$metrics$rmse),
          model$next_date == city_local_date(city))
cat("\nPASS: geocoding, current weather, forecast, historical analytics and R model\n")
cat("City:", city$label, "\n")
cat("History:", as.character(min(history$date)), "through", as.character(max(history$date)), "\n")
cat("Train:", model$n_train, "Test:", model$n_test, "\n")
cat(sprintf("MAE: %.6f C\nRMSE: %.6f C\nR-squared: %.6f\n", model$metrics$mae, model$metrics$rmse, model$metrics$r_squared))
cat(sprintf("Persistence MAE: %.6f C\n", model$baseline_metrics$mae))
cat("Next-day target:", as.character(model$next_date), "Prediction:", model$next_prediction, "C\n")
if ("--record" %in% commandArgs(trailingOnly = TRUE)) {
  dir.create("tmp", showWarnings = FALSE)
  jsonlite::write_json(list(checked_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    city = city$label, history_start = as.character(min(history$date)), history_end = as.character(max(history$date)),
    n_train = model$n_train, n_test = model$n_test, metrics = model$metrics,
    baseline_metrics = model$baseline_metrics, target_date = as.character(model$next_date),
    prediction_c = model$next_prediction), "tmp/smoke-results.json", auto_unbox = TRUE, pretty = TRUE, digits = 8)
}
