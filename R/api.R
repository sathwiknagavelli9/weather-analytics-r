# Open-Meteo access and defensive response parsing. No keys or disk cache.
# Official API documentation: https://open-meteo.com/en/docs
# Historical: https://open-meteo.com/en/docs/historical-weather-api
# Geocoding: https://open-meteo.com/en/docs/geocoding-api
.weather_cache <- new.env(parent = emptyenv())
.weather_cache_limit <- 128L
.daily_variables <- c("temperature_2m_min", "temperature_2m_max",
                      "temperature_2m_mean", "precipitation_sum",
                      "wind_speed_10m_max", "weather_code")
.current_variables <- c("temperature_2m", "apparent_temperature",
                        "relative_humidity_2m", "precipitation",
                        "wind_speed_10m", "pressure_msl", "cloud_cover",
                        "weather_code")

weather_api_abort <- function(message) {
  stop(structure(list(message = message, call = NULL),
                 class = c("weather_api_error", "error", "condition")))
}

clear_weather_cache <- function() {
  rm(list = ls(.weather_cache, all.names = TRUE), envir = .weather_cache)
  invisible(NULL)
}

weather_cache_get <- function(key, now = Sys.time()) {
  if (!exists(key, envir = .weather_cache, inherits = FALSE)) return(NULL)
  entry <- get(key, envir = .weather_cache, inherits = FALSE)
  if (as.numeric(difftime(now, entry$created, units = "secs")) >= entry$ttl) {
    rm(list = key, envir = .weather_cache)
    return(NULL)
  }
  entry$value
}

weather_cache_set <- function(key, value, ttl, now = Sys.time()) {
  keys <- ls(.weather_cache, all.names = TRUE)
  for (old_key in keys) weather_cache_get(old_key, now)
  keys <- ls(.weather_cache, all.names = TRUE)
  if (!key %in% keys && length(keys) >= .weather_cache_limit) {
    created <- vapply(keys, function(k) as.numeric(get(k, .weather_cache)$created), 0)
    rm(list = keys[which.min(created)], envir = .weather_cache)
  }
  assign(key, list(value = value, ttl = ttl, created = now), envir = .weather_cache)
  invisible(value)
}

parse_api_json <- function(text) {
  if (!is.character(text) || length(text) != 1L || is.na(text)) {
    weather_api_abort("Open-Meteo returned an unreadable response. Please try again.")
  }
  # Parse literal JSON only: fromJSON can interpret malformed text as a URL or
  # local filename, which must never happen for an untrusted response body.
  payload <- tryCatch(jsonlite::parse_json(text, simplifyVector = FALSE),
                      error = function(e) NULL)
  if (!is.list(payload) || is.null(names(payload))) {
    weather_api_abort("Open-Meteo returned malformed data. Please try again.")
  }
  if (isTRUE(payload$error)) {
    weather_api_abort("Open-Meteo could not provide the requested data. Check the city and dates, then try again.")
  }
  payload
}

api_payload <- function(payload) {
  if (is.character(payload)) payload <- parse_api_json(payload)
  if (!is.list(payload) || isTRUE(payload$error)) {
    weather_api_abort("Open-Meteo returned an invalid response. Please try again.")
  }
  payload
}

build_api_url <- function(endpoint, params) {
  encoded <- vapply(params, function(value) {
    curl::curl_escape(paste(as.character(value), collapse = ","))
  }, character(1))
  paste0(endpoint, "?", paste0(names(encoded), "=", encoded, collapse = "&"))
}

# The transport argument makes network failures/retries testable without the network.
api_request_json <- function(endpoint, params, ttl = 300, force = FALSE,
                             attempts = 3L, timeout = 15,
                             transport = curl::curl_fetch_memory,
                             sleep = Sys.sleep) {
  url <- build_api_url(endpoint, params)
  if (!force) {
    cached <- weather_cache_get(url)
    if (!is.null(cached)) return(cached)
  }
  if (length(attempts) != 1L || !is.finite(attempts) || attempts < 1L) {
    weather_api_abort("Invalid retry configuration.")
  }
  message <- "The weather service is temporarily unavailable. Please try again shortly."
  for (attempt in seq_len(as.integer(attempts))) {
    handle <- curl::new_handle(connecttimeout = 8, timeout = timeout,
                               useragent = "WeatherPulse-R/1.0",
                               followlocation = TRUE)
    response <- tryCatch(transport(url, handle = handle), error = function(e) NULL)
    retry <- TRUE
    if (is.null(response)) {
      message <- "Could not connect to Open-Meteo before the request timed out. Check your connection and try again."
    } else if (!is.numeric(response$status_code) || length(response$status_code) != 1L ||
               !is.finite(response$status_code)) {
      message <- "Open-Meteo returned an invalid HTTP response. Please try again."
    } else if (response$status_code >= 200 && response$status_code < 300) {
      payload <- tryCatch({
        body <- if (is.raw(response$content)) rawToChar(response$content) else response$content
        # JSON over HTTP is UTF-8. Mark raw bytes explicitly on Windows, where
        # the process locale may otherwise corrupt international city names.
        if (is.character(body)) Encoding(body) <- "UTF-8"
        parse_api_json(body)
      }, error = function(e) e)
      if (!inherits(payload, "error")) {
        attr(payload, "fetched_at") <- Sys.time()
        if (ttl > 0) weather_cache_set(url, payload, ttl)
        return(payload)
      }
      message <- conditionMessage(payload)
    } else if (response$status_code == 429L) {
      message <- "Open-Meteo is receiving too many requests. Please wait a few minutes before trying again."
    } else if (response$status_code >= 500L || response$status_code == 408L) {
      message <- "Open-Meteo is temporarily unavailable. Please try again shortly."
    } else {
      message <- paste0("Open-Meteo could not serve this request (HTTP ",
                         response$status_code, "). Check the location and date range.")
      retry <- FALSE
    }
    if (!retry) break
    if (attempt < attempts) sleep(0.5 * 2^(attempt - 1L))
  }
  weather_api_abort(message)
}

api_string <- function(x, default = "") {
  if (is.null(x) || length(x) != 1L || !is.atomic(x) || is.na(x)) return(default)
  as.character(x)
}

api_numeric <- function(x, n, field = "weather variable") {
  if (is.null(x)) return(rep(NA_real_, n))
  if (length(x) != n) {
    weather_api_abort(paste0("Open-Meteo returned incomplete ", field, " data. Please try again."))
  }
  values <- vapply(as.list(x), function(value) {
    if (is.null(value) || length(value) != 1L || !is.atomic(value) || is.logical(value)) return(NA_real_)
    number <- suppressWarnings(as.numeric(value))
    if (!is.finite(number)) NA_real_ else number
  }, numeric(1))
  unname(values)
}

empty_cities <- function() {
  data.frame(id = character(), name = character(), admin1 = character(),
             country = character(), latitude = numeric(), longitude = numeric(),
             timezone = character(), label = character(), stringsAsFactors = FALSE)
}

parse_geocoding <- function(payload) {
  payload <- api_payload(payload)
  results <- payload$results
  if (is.null(results) || length(results) == 0L) return(empty_cities())
  if (is.data.frame(results)) {
    results <- lapply(seq_len(nrow(results)), function(i) as.list(results[i, , drop = FALSE]))
  }
  if (!is.list(results)) weather_api_abort("Open-Meteo returned invalid city search results.")
  rows <- lapply(results, function(city) {
    if (!is.list(city)) return(NULL)
    lat <- api_numeric(city$latitude, 1L)
    lon <- api_numeric(city$longitude, 1L)
    name <- api_string(city$name)
    timezone <- api_string(city$timezone)
    if (!is.finite(lat) || !is.finite(lon) || abs(lat) > 90 || abs(lon) > 180 ||
        !nzchar(name) || !timezone %in% OlsonNames()) return(NULL)
    admin <- api_string(city$admin1)
    country <- api_string(city$country)
    parts <- unique(c(name, admin, country))
    label <- paste(parts[nzchar(parts)], collapse = ", ")
    data.frame(id = api_string(city$id, paste(lat, lon, sep = ":")), name = name,
               admin1 = admin, country = country, latitude = lat, longitude = lon,
               timezone = timezone, label = label, stringsAsFactors = FALSE)
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) return(empty_cities())
  result <- do.call(rbind, rows)
  result <- result[!duplicated(result$id), , drop = FALSE]
  rownames(result) <- NULL
  result
}

geocode_city <- function(query) {
  if (!is.character(query) || length(query) != 1L || is.na(query) ||
      nchar(trimws(query)) < 2L || nchar(query) > 120L) {
    weather_api_abort("Enter a city name between 2 and 120 characters.")
  }
  parse_geocoding(api_request_json("https://geocoding-api.open-meteo.com/v1/search",
    list(name = trimws(query), count = 10L, language = "en", format = "json"), ttl = 86400))
}

validate_city <- function(city) {
  if (is.data.frame(city) && nrow(city) != 1L) weather_api_abort("Choose one city first.")
  if (!is.list(city)) weather_api_abort("Choose a valid city first.")
  latitude <- api_numeric(city$latitude, 1L)
  longitude <- api_numeric(city$longitude, 1L)
  if (!is.finite(latitude) || abs(latitude) > 90 ||
      !is.finite(longitude) || abs(longitude) > 180) {
    weather_api_abort("The selected city has invalid coordinates. Search for it again.")
  }
  list(latitude = latitude, longitude = longitude,
       timezone = api_string(city$timezone))
}

city_local_date <- function(city, now = Sys.time()) {
  city <- validate_city(city)
  if (!nzchar(city$timezone) || !city$timezone %in% OlsonNames()) {
    weather_api_abort("This city has no recognized local timezone. Please choose another search result.")
  }
  as.Date(format(now, tz = city$timezone, format = "%Y-%m-%d"))
}

parse_daily <- function(payload, source = "Open-Meteo") {
  payload <- api_payload(payload)
  daily <- payload$daily
  if (!is.list(daily) || is.null(daily$time) || !length(daily$time)) {
    weather_api_abort("Daily weather data is unavailable for this location and date range.")
  }
  date_text <- vapply(as.list(daily$time), api_string, character(1))
  dates <- suppressWarnings(as.Date(date_text, format = "%Y-%m-%d"))
  if (anyNA(dates) || any(format(dates, "%Y-%m-%d") != date_text) || anyDuplicated(dates)) {
    weather_api_abort("Open-Meteo returned invalid daily dates. Please try again.")
  }
  n <- length(dates)
  take <- function(field) api_numeric(daily[[field]], n, field)
  result <- data.frame(date = dates, temp_min = take("temperature_2m_min"),
                       temp_max = take("temperature_2m_max"), temp_mean = take("temperature_2m_mean"),
                       precipitation = take("precipitation_sum"), wind_max = take("wind_speed_10m_max"),
                       weather_code = take("weather_code"))
  # Reject impossible ranges; leave unavailable measurements as NA, never zero.
  for (field in c("temp_min", "temp_max", "temp_mean")) {
    result[[field]][result[[field]] < -100 | result[[field]] > 70] <- NA_real_
  }
  reversed <- which(result$temp_min > result$temp_max)
  result[reversed, c("temp_min", "temp_max", "temp_mean")] <- NA_real_
  result$precipitation[result$precipitation < 0] <- NA_real_
  result$wind_max[result$wind_max < 0] <- NA_real_
  result$mean_method <- ifelse(is.na(result$temp_mean), "Unavailable", "API daily mean")
  midpoint <- is.na(result$temp_mean) & is.finite(result$temp_min) & is.finite(result$temp_max)
  result$temp_mean[midpoint] <- (result$temp_min[midpoint] + result$temp_max[midpoint]) / 2
  result$mean_method[midpoint] <- "Midpoint of daily min/max"
  if (!any(is.finite(result$temp_mean))) {
    weather_api_abort("Temperature history is unavailable for these dates. Try an earlier date range.")
  }
  result$source <- source
  result <- result[order(result$date), , drop = FALSE]
  rownames(result) <- NULL
  attr(result, "timezone") <- api_string(payload$timezone)
  attr(result, "fetched_at") <- attr(payload, "fetched_at")
  result
}

parse_weather <- function(payload) {
  payload <- api_payload(payload)
  if (!is.list(payload$current)) weather_api_abort("Current weather is unavailable. Please try again.")
  current <- lapply(.current_variables, function(field) api_numeric(payload$current[[field]], 1L, field))
  names(current) <- .current_variables
  current$time <- api_string(payload$current$time)
  current$interval <- api_numeric(payload$current$interval, 1L)
  if (!is.finite(current$temperature_2m) || current$temperature_2m < -100 || current$temperature_2m > 70) {
    weather_api_abort("Current temperature data is unavailable for this location. Please try again later.")
  }
  timezone <- api_string(payload$timezone)
  valid_time <- grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$", current$time)
  date_text <- substr(current$time, 1L, 10L)
  parsed_date <- suppressWarnings(as.Date(date_text, format = "%Y-%m-%d"))
  if (!valid_time || is.na(parsed_date) || format(parsed_date, "%Y-%m-%d") != date_text ||
      !timezone %in% OlsonNames()) {
    weather_api_abort("Open-Meteo returned an invalid local weather time. Please try again.")
  }
  if (!is.finite(current$interval) || current$interval <= 0) current["interval"] <- list(NULL)
  if (is.finite(current$apparent_temperature) &&
      (current$apparent_temperature < -120 || current$apparent_temperature > 100)) current$apparent_temperature <- NA_real_
  for (field in c("relative_humidity_2m", "cloud_cover")) {
    if (is.finite(current[[field]]) && (current[[field]] < 0 || current[[field]] > 100)) current[[field]] <- NA_real_
  }
  for (field in c("precipitation", "wind_speed_10m", "pressure_msl")) {
    if (is.finite(current[[field]]) && current[[field]] < 0) current[[field]] <- NA_real_
  }
  fetched_at <- attr(payload, "fetched_at")
  if (is.null(fetched_at)) fetched_at <- Sys.time()
  list(current = current, daily = parse_daily(payload, "Open-Meteo forecast"),
       timezone = timezone, fetched_at = fetched_at)
}

weather_params <- function(city) {
  city <- validate_city(city)
  list(latitude = city$latitude, longitude = city$longitude, timezone = "auto",
       daily = .daily_variables, temperature_unit = "celsius",
       wind_speed_unit = "kmh", precipitation_unit = "mm")
}

fetch_weather <- function(city, force = FALSE) {
  params <- c(weather_params(city), list(current = .current_variables, forecast_days = 7L))
  parse_weather(api_request_json("https://api.open-meteo.com/v1/forecast", params,
                                 ttl = 300, force = force))
}

validate_history_dates <- function(start_date, end_date, today) {
  to_date <- function(value) {
    if (length(value) != 1L || is.na(value)) return(as.Date(NA))
    tryCatch(as.Date(value), error = function(e) as.Date(NA))
  }
  start <- to_date(start_date)
  end <- to_date(end_date)
  if (is.na(start) || is.na(end) || start > end) {
    weather_api_abort("Choose a valid date range with the start on or before the end.")
  }
  if (start < as.Date("1940-01-01") || end >= today) {
    weather_api_abort("Historical dates must be from 1940 onward and end before today in the selected city.")
  }
  if (as.integer(end - start) > 730L) weather_api_abort("Choose a historical range of at most 731 days.")
  list(start = start, end = end)
}

fetch_history <- function(city, start_date, end_date) {
  dates <- validate_history_dates(start_date, end_date, city_local_date(city))
  params <- c(weather_params(city), list(start_date = format(dates$start), end_date = format(dates$end)))
  payload <- api_request_json("https://archive-api.open-meteo.com/v1/archive", params, ttl = 21600)
  result <- parse_daily(payload, "Open-Meteo archive (reanalysis / model estimates)")
  result <- result[result$date >= dates$start & result$date <= dates$end, , drop = FALSE]
  if (!nrow(result)) weather_api_abort("No historical data was returned for the selected date range.")
  result
}

# ERA5 may lag by five days. Complete the most recent five CLOSED local days
# with archived forecast-model values; they are explicitly distinguished from
# the archive in the source column. Never include today's incomplete aggregate.
fetch_model_history <- function(city, days = 365L) {
  if (length(days) != 1L || !is.finite(days) || days < 30L || days > 731L || days != floor(days)) {
    weather_api_abort("Choose between 30 and 731 complete days for model history.")
  }
  today <- city_local_date(city)
  archived <- fetch_history(city, today - as.integer(days), today - 6L)
  params <- c(weather_params(city), list(past_days = 5L, forecast_days = 1L))
  payload <- api_request_json("https://api.open-meteo.com/v1/forecast", params, ttl = 1800)
  recent <- parse_daily(payload, "Open-Meteo recent forecast-model history")
  recent <- recent[recent$date > today - 6L & recent$date < today, , drop = FALSE]
  if (nrow(recent) != 5L || max(recent$date) != today - 1L || !is.finite(tail(recent$temp_mean, 1L))) {
    weather_api_abort("Recent complete daily weather is not yet available. Please retry the model later.")
  }
  result <- rbind(archived, recent)
  result <- result[order(result$date), , drop = FALSE]
  rownames(result) <- NULL
  attr(result, "timezone") <- validate_city(city)$timezone
  attr(result, "fetched_at") <- attr(payload, "fetched_at")
  attr(result, "source_note") <- paste("Archive data is supplemented with five completed days of forecast-model history.",
                                        "The next-day target is the day after the last complete row, usually today locally.")
  result
}
