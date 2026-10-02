# Integration tests for the real server with deterministic service doubles.
# These fixtures never enter production code and make no external API calls.
run_server_tests <- function() {
  app_environment <- new.env(parent = globalenv())
  sys.source("app.R", envir = app_environment)
  fixed_today <- as.Date("2026-10-01")
  service <- new.env(parent = emptyenv())
  service$weather_fail <- character()
  service$history_fail <- FALSE
  service$model_fail <- FALSE
  service$history_calls <- 0L
  service$model_calls <- 0L
  service$weather_calls <- 0L

  cities <- data.frame(
    id = c("hyderabad-pk", "hyderabad-in", "london", "tokyo"),
    name = c("Hyderabad", "Hyderabad", "London", "Tokyo"),
    admin1 = c("Sindh", "Telangana", "England", "Tokyo"),
    country = c("Pakistan", "India", "United Kingdom", "Japan"),
    latitude = c(25.4, 17.4, 51.5, 35.7),
    longitude = c(68.4, 78.5, -0.1, 139.7),
    timezone = c("Asia/Karachi", "Asia/Kolkata", "Europe/London", "Asia/Tokyo"),
    stringsAsFactors = FALSE
  )
  cities$label <- paste(cities$name, cities$admin1, cities$country, sep = ", ")
  daily_fixture <- function(start, end, city_id = "hyderabad-in") {
    dates <- seq(as.Date(start), as.Date(end), by = "day")
    t <- as.numeric(dates - as.Date("2024-01-01"))
    city_offset <- match(city_id, cities$id)
    temperatures <- 20 + city_offset + 6 * sin(2 * pi * t / 365.25) +
      0.8 * sin(t * 0.47) + 0.3 * cos(t * 0.13)
    data.frame(date = dates, temp_min = temperatures - 4,
      temp_max = temperatures + 4, temp_mean = temperatures,
      precipitation = ifelse(t %% 5 == 0, 2, 0), wind_max = 10 + abs(sin(t)) * 5,
      weather_code = ifelse(t %% 5 == 0, 61, 2),
      mean_method = "API daily mean", source = "Deterministic test fixture")
  }
  app_environment$geocode_city <- function(query) {
    if (identical(query, "network failure")) stop("City search is temporarily unavailable.")
    cities[tolower(cities$name) == tolower(trimws(query)), , drop = FALSE]
  }
  app_environment$city_local_date <- function(city, now = Sys.time()) fixed_today
  app_environment$fetch_weather <- function(city, force = FALSE) {
    service$weather_calls <- service$weather_calls + 1L
    if (city$id %in% service$weather_fail) stop("Weather service is temporarily unavailable.")
    list(
      current = list(temperature_2m = 20 + match(city$id, cities$id),
        apparent_temperature = 23, relative_humidity_2m = 60,
        wind_speed_10m = 12, precipitation = 0, pressure_msl = 1012,
        cloud_cover = 30, weather_code = 2,
        time = "2026-10-01T12:00", interval = 900),
      daily = daily_fixture(fixed_today, fixed_today + 6, city$id),
      timezone = city$timezone,
      fetched_at = as.POSIXct("2026-10-01 06:30:00", tz = "UTC")
    )
  }
  app_environment$fetch_history <- function(city, start_date, end_date) {
    service$history_calls <- service$history_calls + 1L
    if (service$history_fail) stop("Historical weather is temporarily unavailable.")
    daily_fixture(start_date, end_date, city$id)
  }
  app_environment$fetch_model_history <- function(city, days = 365L) {
    service$model_calls <- service$model_calls + 1L
    if (service$model_fail) stop("Recent complete daily weather is unavailable.")
    daily_fixture(fixed_today - days, fixed_today - 1, city$id)
  }

  shiny::testServer(app_environment$server, {
    session$setInputs(city_query = "Hyderabad", history_days = "90",
      history_end = as.character(fixed_today - 6), model_days = "365",
      compare_query_1 = "Hyderabad", compare_query_2 = "London", compare_query_3 = "Tokyo")
    session$flushReact()
    # Hyderabad, India must be preferred even when Pakistan is returned first.
    stopifnot(state$city$id == "hyderabad-in", !is.null(state$weather),
              is.null(state$history), is.null(state$model))
    session$setInputs(city_select = "2")
    stopifnot(grepl("Telangana", output$current_weather$html, fixed = TRUE),
              grepl("22.0", output$current_weather$html, fixed = TRUE))

    # Refresh errors retain the same city's last known weather with a clear note.
    previous_weather <- state$weather
    service$weather_fail <- "hyderabad-in"
    session$setInputs(refresh = 1)
    stopifnot(identical(state$weather, previous_weather),
              grepl("unavailable", state$weather_error),
              grepl("last successful update", output$weather_status$html, fixed = TRUE))
    service$weather_fail <- character()
    session$setInputs(refresh = 2)
    stopifnot(is.null(state$weather_error))

    # Merely changing the selected window must not fetch historical data.
    calls_before <- service$history_calls
    session$setInputs(history_days = "30")
    stopifnot(service$history_calls == calls_before)
    session$setInputs(history_days = "90", analyze = 1)
    stopifnot(nrow(state$history) == 90L, state$history_city$id == "hyderabad-in",
              max(state$history$date) == fixed_today - 6)
    stopifnot(grepl("Average temperature", output$history_summary$html, fixed = TRUE))

    # Exercise the actual download handler, including CSV provenance and units.
    downloaded_file <- output$download_history
    downloaded <- utils::read.csv(downloaded_file, check.names = FALSE)
    stopifnot(nrow(downloaded) == 90L,
              all(c("date", "temperature_mean_c", "precipitation_mm", "wind_max_kmh",
                    "mean_method", "source", "city", "latitude", "longitude") %in% names(downloaded)),
              all(downloaded$city == state$history_city$label),
              all(downloaded$source == "Deterministic test fixture"))

    previous_history <- state$history
    service$history_fail <- TRUE
    session$setInputs(history_days = "30", analyze = 2)
    stopifnot(identical(state$history, previous_history))
    service$history_fail <- FALSE
    calls_before <- service$history_calls
    session$setInputs(history_end = as.character(fixed_today), analyze = 3)
    stopifnot(identical(state$history, previous_history), service$history_calls == calls_before)

    # Run the real statistical pipeline through the Train action.
    session$setInputs(train = 1)
    stopifnot(state$model_city$id == "hyderabad-in", state$model$next_date == fixed_today,
              is.finite(state$model$next_prediction), state$model$n_test > 0,
              state$model$metrics$rmse >= state$model$metrics$mae,
              grepl("R STATISTICAL MODEL PREDICTION", output$prediction_summary$html, fixed = TRUE))
    previous_model <- state$model
    service$model_fail <- TRUE
    session$setInputs(train = 2)
    stopifnot(identical(state$model, previous_model))
    service$model_fail <- FALSE

    session$setInputs(find_comparison = 1)
    stopifnot(nrow(state$comparison_options[["1"]]) == 2L,
              nrow(state$comparison_options[["2"]]) == 1L)
    session$setInputs(compare_city_1 = "2", compare_city_2 = "1", compare_city_3 = "1", compare = 1)
    stopifnot(nrow(state$comparison) == 3L, length(unique(state$comparison$city)) == 3L,
              any(grepl("London", state$comparison$city)))
    service$weather_fail <- "london"
    session$setInputs(compare = 2)
    stopifnot(nrow(state$comparison) == 2L, !any(grepl("London", state$comparison$city)))
    previous_comparison <- state$comparison
    service$weather_fail <- cities$id
    session$setInputs(compare = 3)
    stopifnot(identical(state$comparison, previous_comparison))

    # Failed searches retain the original city and its loaded analytic results.
    session$setInputs(city_query = "unknown city", search_city = 1)
    stopifnot(state$city$id == "hyderabad-in", identical(state$history, previous_history))
    session$setInputs(city_query = "network failure", search_city = 2)
    stopifnot(state$city$id == "hyderabad-in", identical(state$model, previous_model))

    # Switching city must clear the old city's data even if the new API fails.
    session$setInputs(city_query = "London", search_city = 3)
    session$flushReact()
    stopifnot(state$city$id == "london", is.null(state$weather), is.null(state$history),
              is.null(state$model), grepl("unavailable", state$weather_error))
    service$weather_fail <- character()
    session$setInputs(refresh = 3)
    stopifnot(is.null(state$weather_error), state$weather$current$temperature_2m == 23,
              grepl("London", output$current_weather$html, fixed = TRUE))
  })
  cat("PASS: Shiny server selection, refresh, history, CSV, model, comparison and failure recovery\n")
  invisible(TRUE)
}
