source(file.path("R", "analytics.R"))
source(file.path("R", "prediction.R"))

set.seed(27)
model_dates <- as.Date("2024-01-01") + 0:364
model_temperatures <- 23 + 7 * sin(2 * pi * (seq_along(model_dates) - 40) / 365.25) +
  as.numeric(stats::arima.sim(list(ar = 0.5), n = length(model_dates), sd = 0.7))
model_fixture <- data.frame(date = model_dates, temp_mean = model_temperatures)
features <- create_temperature_features(model_fixture)
stopifnot(
  all(is.na(features$rolling_mean_7[1:7])),
  features$lag_1_temperature[8] == model_temperatures[7],
  features$lag_2_temperature[8] == model_temperatures[6],
  features$lag_3_temperature[8] == model_temperatures[5],
  features$rolling_mean_7[8] == mean(model_temperatures[1:7])
)

# A missing calendar date must be a missing lag, not yesterday by row position.
with_gap <- create_temperature_features(model_fixture[-20, ])
stopifnot(nrow(with_gap) == nrow(model_fixture), is.na(with_gap$temp_mean[20]),
          is.na(with_gap$lag_1_temperature[21]), is.na(with_gap$rolling_mean_7[27]),
          is.finite(with_gap$rolling_mean_7[28]))
shuffled <- create_temperature_features(model_fixture[rev(seq_len(nrow(model_fixture))), ])
stopifnot(identical(shuffled, features))

evaluation <- model_metrics(c(1, 2, 3), c(2, 2, 1))
stopifnot(evaluation$mae == 1, abs(evaluation$rmse - sqrt(5 / 3)) < 1e-12,
          evaluation$r_squared == -1.5,
          is.na(model_metrics(c(2, 2, 2), c(1, 2, 3))$r_squared),
          model_metrics(c(NA, 1, 2), c(5, 2, 2))$mae == 0.5)

trained <- train_temperature_model(model_fixture)
stopifnot(
  is.finite(trained$next_prediction), trained$next_date == max(model_dates) + 1,
  trained$n_train == floor(0.8 * (365 - 7)), trained$n_test == 72,
  trained$training_end_date < min(trained$test$date),
  all(is.finite(trained$test$predicted)),
  trained$metrics$mae >= 0, trained$metrics$rmse >= trained$metrics$mae,
  is.finite(trained$metrics$r_squared),
  trained$baseline_metrics$n == trained$n_test,
  length(stats::residuals(trained$model)) == trained$n_train,
  length(stats::residuals(trained$refit_model)) == trained$n_total
)

# Changing holdout targets cannot change the training fit or first holdout
# prediction. It may change later one-step predictions through observed lags.
changed_holdout <- model_fixture
changed_holdout$temp_mean[changed_holdout$date > trained$training_end_date] <-
  changed_holdout$temp_mean[changed_holdout$date > trained$training_end_date] + 2
changed_fit <- train_temperature_model(changed_holdout)
stopifnot(identical(stats::coef(trained$model), stats::coef(changed_fit$model)),
          trained$test$predicted[1] == changed_fit$test$predicted[1],
          trained$test$predicted[2] != changed_fit$test$predicted[2])

expect_model_error <- function(expression, pattern) {
  error <- tryCatch({ force(expression); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error)))
}
expect_model_error(train_temperature_model(model_fixture[1:40, ]), "At least")
constant_fixture <- data.frame(date = model_dates, temp_mean = rep(20, length(model_dates)))
expect_model_error(train_temperature_model(constant_fixture), "variation")
stale_tail <- model_fixture
stale_tail$temp_mean[nrow(stale_tail)] <- NA_real_
expect_model_error(train_temperature_model(stale_tail), "final seven consecutive")
expect_model_error(train_temperature_model(model_fixture[-(nrow(model_fixture) - 2), ]), "final seven consecutive")
expect_model_error(model_metrics(c(NA_real_, NA_real_), c(1, 2)), "No valid")
expect_model_error(model_metrics(1:3, 1:2), "matching numeric")

# A trend creates exactly dependent lags; independent-column selection keeps
# valid regression coefficients while explicitly reporting discarded features.
trend_fixture <- data.frame(date = model_dates, temp_mean = 10 + seq_along(model_dates) / 50)
trend_fit <- train_temperature_model(trend_fixture)
stopifnot(is.finite(trend_fit$next_prediction), length(trend_fit$dropped_features) > 0L,
          !anyNA(stats::coef(trend_fit$model)))
cat("PASS: calendar lags, no-leakage holdout, metrics, regression and defensive errors\n")
