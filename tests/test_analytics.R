source(file.path("R", "analytics.R"))

analytics_fixture <- data.frame(
  date = c("2025-02-01", "2025-01-30", "2025-01-31", "2025-01-31", "invalid"),
  temp_min = c(10, 12, 13, 14, 10),
  temp_max = c(20, 22, 23, 24, 20),
  temp_mean = c(NA, 17, 18, 19, 15),
  precipitation = c(0, 3, 4, 5, 6),
  wind_max = c(8, 10, 12, 14, 16)
)
analytics_fixture$mean_method <- c("Unavailable", rep("API daily mean", 4))
analytics_fixture$source <- "Open-Meteo archive"
cleaned <- clean_history(analytics_fixture)
stopifnot(
  nrow(cleaned) == 3L,
  inherits(cleaned$date, "Date"),
  identical(as.character(cleaned$date), c("2025-01-30", "2025-01-31", "2025-02-01")),
  identical(cleaned$temp_mean, c(17, 19, 15)),
  attr(cleaned, "cleaning")$duplicate_date_rows == 1L,
  attr(cleaned, "cleaning")$invalid_date_rows == 1L,
  identical(cleaned$source, rep("Open-Meteo archive", 3)),
  cleaned$mean_method[3] == "Midpoint of daily min/max"
)
summary_result <- summarize_history(cleaned)
stopifnot(
  summary_result$avg_temp == 17,
  summary_result$highest_temp == 24,
  summary_result$lowest_temp == 10,
  summary_result$total_precipitation == 8,
  summary_result$rainiest_day == as.Date("2025-01-31"),
  summary_result$rainy_days == 2L,
  summary_result$max_wind == 14
)
gap_summary <- summarize_history(cleaned[-2, ])
stopifnot(gap_summary$calendar_days == 3L, gap_summary$missing_calendar_days == 1L,
          gap_summary$precipitation_days == 2L, gap_summary$precipitation_coverage == 2 / 3)
monthly_result <- monthly_summary(cleaned)
stopifnot(
  nrow(monthly_result) == 2L,
  monthly_result$avg_temp[1] == 18,
  monthly_result$total_precipitation[1] == 8,
  monthly_result$n_days[1] == 2L,
  inherits(monthly_result$month, "Date")
)

missing_fixture <- data.frame(date = as.Date("2025-01-01") + 0:2,
                              temp_mean = c(NA, Inf, NaN),
                              precipitation = c(NA, -1, Inf), wind_max = -1)
missing_summary <- summarize_history(missing_fixture)
stopifnot(is.na(missing_summary$avg_temp), is.na(missing_summary$total_precipitation),
          is.na(missing_summary$rainiest_day), is.na(missing_summary$rainy_days),
          is.na(missing_summary$max_wind), missing_summary$temperature_days == 0)
invalid_range <- clean_history(data.frame(date = as.Date("2025-01-01"),
                                          temp_min = 30, temp_max = 20, temp_mean = 25))
stopifnot(all(is.na(invalid_range[c("temp_min", "temp_max", "temp_mean")])) )
dry_fixture <- data.frame(date = as.Date("2025-01-01"), temp_mean = 15, precipitation = 0)
stopifnot(is.na(summarize_history(dry_fixture)$rainiest_day),
          summarize_history(dry_fixture)$total_precipitation == 0,
          inherits(try(clean_history(data.frame(date = "invalid")), silent = TRUE), "try-error"),
          inherits(try(clean_history(data.frame(x = 1)), silent = TRUE), "try-error"),
          inherits(try(clean_history(data.frame(date = as.Date(character()))), silent = TRUE), "try-error"))
cat("PASS: historical cleaning, missing values, daily and monthly summaries\n")
