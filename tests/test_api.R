# Offline fixtures exercise parsing, unavailable values, failures, and cache limits.
source(file.path("R", "api.R"))
source(file.path("R", "weather_codes.R"))

run_api_tests <- function() {
  expect_error <- function(expression, pattern = NULL) {
    result <- tryCatch(force(expression), error = function(e) e)
    stopifnot(inherits(result, "error"))
    if (!is.null(pattern)) stopifnot(grepl(pattern, conditionMessage(result), fixed = TRUE))
    invisible(result)
  }
  city_payload <- '{"results":[{"id":1,"name":"Hyderabad","admin1":"Telangana","country":"India","latitude":17.38,"longitude":78.48,"timezone":"Asia/Kolkata"},{"id":2,"name":"Incomplete"}]}'
  cities <- parse_geocoding(city_payload)
  stopifnot(nrow(cities) == 1L, cities$country == "India", cities$latitude == 17.38,
            cities$label == "Hyderabad, Telangana, India", nrow(parse_geocoding('{}')) == 0L)
  stopifnot(nrow(parse_geocoding(list(results = cities))) == 1L)
  stopifnot(nrow(parse_geocoding(list(results = list()))) == 0L,
            nrow(parse_geocoding('{"results":[{"name":"Bad timezone","latitude":17,"longitude":78,"timezone":"Invalid/Timezone"}]}')) == 0L,
            nrow(parse_geocoding('{"results":[{"name":"No timezone","latitude":17,"longitude":78}]}')) == 0L)
  expect_error(geocode_city("x"), "city name")
  expect_error(geocode_city(NA_character_), "city name")
  expect_error(geocode_city(character()), "city name")
  expect_error(geocode_city(c("Paris", "London")), "city name")
  expect_error(geocode_city(paste(rep("a", 121), collapse = "")), "city name")
  expect_error(validate_city(list(latitude = 91, longitude = 20)), "coordinates")
  expect_error(validate_city(list(latitude = 17, longitude = NA_real_)), "coordinates")
  expect_error(validate_city(cities[FALSE, , drop = FALSE]), "one city")
  expect_error(validate_city(rbind(cities, cities)), "one city")
  expect_error(validate_city("Hyderabad"), "valid city")
  expect_error(city_local_date(list(latitude = 17, longitude = 78, timezone = "bad")), "timezone")
  expect_error(parse_api_json('{bad-json'), "malformed")
  expect_error(parse_api_json('{"error":true,"reason":"test"}'), "requested data")
  expect_error(parse_api_json('[]'), "malformed")
  expect_error(parse_api_json('https://example.invalid/weather.json'), "malformed")
  fixture_path <- tempfile(fileext = ".json")
  on.exit(unlink(fixture_path), add = TRUE)
  writeLines('{"unexpected_file_read":true}', fixture_path)
  expect_error(parse_api_json(fixture_path), "malformed")
  stopifnot(identical(weather_label(c(0, 63, 95, 97, NA, 999)),
                      c("Clear sky", "Moderate rain", "Thunderstorm", "Heavy thunderstorm", "Not available", "Unknown condition")))
  stopifnot(length(weather_label(numeric())) == 0L)

  daily_fixture <- list(time = c("2026-01-02", "2026-01-01"),
                        temperature_2m_min = c(20, 18), temperature_2m_max = c(30, 28),
                        temperature_2m_mean = list(NULL, 22.5), precipitation_sum = list(NULL, 4),
                        wind_speed_10m_max = c(12, -2), weather_code = c(2, 61))
  fixture <- list(timezone = "Asia/Kolkata", daily = daily_fixture,
                   current = list(time = "2026-01-01T12:00", temperature_2m = 28,
                                  relative_humidity_2m = 70, interval = 900))
  weather <- parse_weather(fixture)
  stopifnot(length(weather$current) == 10L, weather$current$temperature_2m == 28,
            is.na(weather$current$cloud_cover), inherits(weather$fetched_at, "POSIXct"),
            identical(weather$daily$temp_mean, c(22.5, 25)),
            inherits(weather$daily$date, "Date"), is.na(weather$daily$precipitation[2]),
            is.na(weather$daily$wind_max[1]), weather$daily$mean_method[2] == "Midpoint of daily min/max")
  broken <- fixture
  broken$daily$temperature_2m_min <- 20
  expect_error(parse_daily(broken), "incomplete")
  broken <- fixture
  broken$daily$time <- c("2026-01-01", "2026-01-01")
  expect_error(parse_daily(broken), "invalid daily dates")
  broken$daily$time <- c("not-a-date", "2026-01-01")
  expect_error(parse_daily(broken), "invalid daily dates")
  expect_error(parse_weather(list(daily = daily_fixture)), "Current weather")
  broken <- fixture
  broken$current$temperature_2m <- NULL
  expect_error(parse_weather(broken), "Current temperature")
  broken$current$temperature_2m <- 999
  expect_error(parse_weather(broken), "Current temperature")
  broken$current$temperature_2m <- TRUE
  expect_error(parse_weather(broken), "Current temperature")
  broken <- fixture
  broken$current$time <- "2026-02-30T12:00"
  expect_error(parse_weather(broken), "invalid local weather time")
  broken$current$time <- "2026-01-01T25:00"
  expect_error(parse_weather(broken), "invalid local weather time")
  broken <- fixture
  broken$timezone <- NULL
  expect_error(parse_weather(broken), "invalid local weather time")
  broken <- fixture
  broken$current$interval <- NULL
  broken$current$relative_humidity_2m <- 200
  broken$current$wind_speed_10m <- -1
  partial <- parse_weather(broken)
  stopifnot(is.null(partial$current$interval), is.na(partial$current$relative_humidity_2m),
            is.na(partial$current$wind_speed_10m))
  expect_error(parse_daily(list(daily = list(time = "2026-01-01"))), "unavailable")
  expect_error(validate_history_dates("2026-01-02", "2026-01-01", as.Date("2026-02-01")), "valid date")
  expect_error(validate_history_dates("2026-01-01", "2026-02-01", as.Date("2026-02-01")), "before today")
  expect_error(validate_history_dates("1939-01-01", "1939-01-02", as.Date("2026-02-01")), "1940")
  expect_error(fetch_model_history(cities, days = 2), "30 and 731")
  local_today <- city_local_date(cities, as.POSIXct("2026-01-01 20:00:00", tz = "UTC"))
  stopifnot(local_today == as.Date("2026-01-02"))

  clear_weather_cache()
  on.exit(clear_weather_cache(), add = TRUE)
  calls <- 0L
  response <- function(url, handle) {
    calls <<- calls + 1L
    if (calls == 1L) stop("simulated interruption")
    list(status_code = 200L, content = charToRaw('{"value":5}'))
  }
  endpoint <- "https://api.open-meteo.com/v1/forecast"
  request <- function(...) api_request_json(endpoint, list(latitude = 17), transport = response,
                                            sleep = function(seconds) NULL, ...)
  answer <- request()
  stopifnot(answer$value == 5L, calls == 2L, inherits(attr(answer, "fetched_at"), "POSIXct"))
  request()
  stopifnot(calls == 2L)
  request(force = TRUE)
  stopifnot(calls == 3L)
  attempts <- 0L
  bad_request <- function(url, handle) {
    attempts <<- attempts + 1L
    list(status_code = 400L, content = charToRaw('{}'))
  }
  expect_error(api_request_json(endpoint, list(latitude = 18), transport = bad_request,
                                sleep = function(seconds) NULL), "HTTP 400")
  stopifnot(attempts == 1L)
  invalid_json <- function(url, handle) list(status_code = 200L, content = charToRaw('oops'))
  expect_error(api_request_json(endpoint, list(latitude = 19), transport = invalid_json,
                                sleep = function(seconds) NULL), "malformed")
  rate_limited <- function(url, handle) list(status_code = 429L, content = charToRaw('{}'))
  expect_error(api_request_json(endpoint, list(latitude = 20), transport = rate_limited,
                                sleep = function(seconds) NULL), "too many requests")
  international <- function(url, handle) {
    list(status_code = 200L, content = charToRaw(enc2utf8('{"city":"Hyder\u0101b\u0101d"}')))
  }
  city_name <- api_request_json(endpoint, list(latitude = 21), transport = international)
  stopifnot(city_name$city == "Hyder\u0101b\u0101d")
  clear_weather_cache()
  now <- Sys.time()
  weather_cache_set("expired", list(value = 1), 1, now - 2)
  stopifnot(is.null(weather_cache_get("expired", now)))
  for (i in seq_len(.weather_cache_limit + 10L)) weather_cache_set(paste0("key", i), i, 100)
  stopifnot(length(ls(.weather_cache)) == .weather_cache_limit)
  message("PASS: API parsing, weather codes, validation, retries, and bounded TTL cache")
  invisible(TRUE)
}

if (sys.nframe() == 0L) run_api_tests()
