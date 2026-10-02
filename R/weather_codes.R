# WMO interpretation codes used by Open-Meteo:
# https://open-meteo.com/en/docs#weathervariables
weather_label <- function(code) {
  labels <- c(
    `0` = "Clear sky", `1` = "Mainly clear", `2` = "Partly cloudy",
    `3` = "Overcast", `45` = "Fog", `48` = "Freezing fog",
    `51` = "Light drizzle", `53` = "Moderate drizzle", `55` = "Dense drizzle",
    `56` = "Light freezing drizzle", `57` = "Dense freezing drizzle",
    `61` = "Light rain", `63` = "Moderate rain", `65` = "Heavy rain",
    `66` = "Light freezing rain", `67` = "Heavy freezing rain",
    `71` = "Light snow", `73` = "Moderate snow", `75` = "Heavy snow",
    `77` = "Snow grains", `80` = "Light rain showers",
    `81` = "Moderate rain showers", `82` = "Heavy rain showers",
    `85` = "Light snow showers", `86` = "Heavy snow showers",
    `95` = "Thunderstorm", `96` = "Thunderstorm with light hail",
    `97` = "Heavy thunderstorm", `99` = "Thunderstorm with heavy hail"
  )
  values <- suppressWarnings(as.numeric(as.character(code)))
  result <- unname(labels[as.character(values)])
  result[is.na(result)] <- "Unknown condition"
  result[is.na(values)] <- "Not available"
  result
}
