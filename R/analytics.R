# Daily weather cleaning and aggregation. All calculations use observed values;
# unavailable measurements remain NA rather than becoming zero or invented data.

clean_history <- function(history) {
  if (!is.data.frame(history) || !"date" %in% names(history)) {
    stop("Historical data must contain a date column.", call. = FALSE)
  }
  if (nrow(history) == 0L) {
    stop("No historical weather observations were returned.", call. = FALSE)
  }

  result <- history
  result$date <- if (inherits(result$date, "Date")) {
    result$date
  } else {
    # An explicit format safely turns malformed text into missing dates.
    suppressWarnings(as.Date(as.character(result$date), format = "%Y-%m-%d"))
  }
  valid_dates <- !is.na(result$date) & is.finite(as.numeric(result$date))
  result <- result[valid_dates, , drop = FALSE]
  if (nrow(result) == 0L) {
    stop("Historical data contains no valid dates.", call. = FALSE)
  }

  numeric_columns <- c("temp_min", "temp_max", "temp_mean", "precipitation",
                       "wind_max", "weather_code")
  for (column in numeric_columns) {
    values <- if (column %in% names(result)) result[[column]] else rep(NA_real_, nrow(result))
    if (is.factor(values)) values <- as.character(values)
    values <- suppressWarnings(as.numeric(values))
    values[!is.finite(values)] <- NA_real_
    result[[column]] <- values
  }
  if (!"mean_method" %in% names(result)) {
    result$mean_method <- rep("Provided daily mean", nrow(result))
  } else {
    result$mean_method <- as.character(result$mean_method)
    unlabeled <- is.na(result$mean_method) | !nzchar(result$mean_method)
    result$mean_method[unlabeled] <- "Provided daily mean"
  }

  # Reject impossible measurements without discarding the other usable fields.
  for (column in c("temp_min", "temp_max", "temp_mean")) {
    impossible <- !is.na(result[[column]]) &
      (result[[column]] < -100 | result[[column]] > 70)
    result[[column]][impossible] <- NA_real_
  }
  inverted <- !is.na(result$temp_min) & !is.na(result$temp_max) &
    result$temp_min > result$temp_max
  result[inverted, c("temp_min", "temp_max", "temp_mean")] <- NA_real_
  outside_range <- !is.na(result$temp_mean) &
    ((!is.na(result$temp_min) & result$temp_mean < result$temp_min) |
       (!is.na(result$temp_max) & result$temp_mean > result$temp_max))
  result$temp_mean[outside_range] <- NA_real_
  use_midpoint <- is.na(result$temp_mean) &
    !is.na(result$temp_min) & !is.na(result$temp_max)
  result$mean_method[is.na(result$temp_mean)] <- "Unavailable"
  result$temp_mean[use_midpoint] <-
    (result$temp_min[use_midpoint] + result$temp_max[use_midpoint]) / 2
  result$mean_method[use_midpoint] <- "Midpoint of daily min/max"
  result$precipitation[!is.na(result$precipitation) & result$precipitation < 0] <- NA_real_
  result$wind_max[!is.na(result$wind_max) & result$wind_max < 0] <- NA_real_
  bad_code <- !is.na(result$weather_code) &
    (result$weather_code < 0 | result$weather_code > 99 |
       result$weather_code != floor(result$weather_code))
  result$weather_code[bad_code] <- NA_real_

  # In a repeated date, the last supplied record is the latest revision.
  duplicate_count <- sum(duplicated(result$date, fromLast = TRUE))
  result <- result[!duplicated(result$date, fromLast = TRUE), , drop = FALSE]
  provenance_columns <- intersect(c("mean_method", "source"), names(result))
  result <- result[order(result$date), c("date", numeric_columns, provenance_columns), drop = FALSE]
  rownames(result) <- NULL
  attr(result, "cleaning") <- list(
    invalid_date_rows = sum(!valid_dates),
    duplicate_date_rows = duplicate_count,
    midpoint_mean_rows = sum(use_midpoint)
  )
  result
}

weather_stat <- function(values, operation) {
  values <- values[is.finite(values)]
  if (!length(values)) return(NA_real_)
  operation(values)
}

summarize_history <- function(history) {
  data <- clean_history(history)
  wet <- which(is.finite(data$precipitation) & data$precipitation > 0)
  rainiest <- if (length(wet)) {
    data$date[wet[which.max(data$precipitation[wet])]]
  } else {
    as.Date(NA)
  }
  list(
    avg_temp = weather_stat(data$temp_mean, mean),
    highest_temp = weather_stat(data$temp_max, max),
    lowest_temp = weather_stat(data$temp_min, min),
    total_precipitation = weather_stat(data$precipitation, sum),
    rainiest_day = rainiest,
    rainiest_amount = weather_stat(data$precipitation, max),
    avg_wind = weather_stat(data$wind_max, mean),
    max_wind = weather_stat(data$wind_max, max),
    rainy_days = if (all(is.na(data$precipitation))) NA_integer_ else
      sum(data$precipitation > 0, na.rm = TRUE),
    n_days = nrow(data),
    temperature_days = sum(!is.na(data$temp_mean)),
    precipitation_days = sum(!is.na(data$precipitation)),
    wind_days = sum(!is.na(data$wind_max)),
    calendar_days = as.integer(max(data$date) - min(data$date)) + 1L,
    missing_calendar_days = as.integer(max(data$date) - min(data$date)) + 1L - nrow(data),
    precipitation_coverage = sum(!is.na(data$precipitation)) /
      (as.integer(max(data$date) - min(data$date)) + 1L),
    start_date = min(data$date),
    end_date = max(data$date)
  )
}

monthly_summary <- function(history) {
  data <- clean_history(history)
  groups <- split(seq_len(nrow(data)), format(data$date, "%Y-%m-01"))
  rows <- lapply(names(groups), function(month) {
    part <- data[groups[[month]], , drop = FALSE]
    data.frame(
      month = as.Date(month),
      avg_temp = weather_stat(part$temp_mean, mean),
      highest_temp = weather_stat(part$temp_max, max),
      lowest_temp = weather_stat(part$temp_min, min),
      total_precipitation = weather_stat(part$precipitation, sum),
      avg_wind = weather_stat(part$wind_max, mean),
      n_days = nrow(part),
      temperature_days = sum(!is.na(part$temp_mean)),
      precipitation_days = sum(!is.na(part$precipitation))
    )
  })
  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result
}
