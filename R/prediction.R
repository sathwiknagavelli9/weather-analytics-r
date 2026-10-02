# Educational next-day regression using base R. No future temperatures enter a
# feature. Holdout errors are one-step errors with prior observed lags, not an
# unattended multi-day forecast. A separate full-history fit predicts next_date.

temperature_daily_grid <- function(history) {
  data <- clean_history(history)
  span <- as.integer(max(data$date) - min(data$date)) + 1L
  if (!is.finite(span) || span > 36600L) {
    stop("The historical date range is too large to model safely.", call. = FALSE)
  }
  dates <- seq(min(data$date), max(data$date), by = "day")
  data.frame(date = dates, temp_mean = data$temp_mean[match(dates, data$date)])
}

temperature_features_from_grid <- function(grid) {
  n <- nrow(grid)
  shifted <- function(k) {
    if (n <= k) return(rep(NA_real_, n))
    c(rep(NA_real_, k), grid$temp_mean[seq_len(n - k)])
  }
  previous_seven <- rep(NA_real_, n)
  if (n >= 8L) {
    for (i in seq.int(8L, n)) {
      values <- grid$temp_mean[seq.int(i - 7L, i - 1L)]
      if (all(is.finite(values))) previous_seven[i] <- mean(values)
    }
  }
  day_of_year <- as.integer(format(grid$date, "%j"))
  data.frame(
    date = grid$date,
    temp_mean = grid$temp_mean,
    lag_1_temperature = shifted(1L),
    lag_2_temperature = shifted(2L),
    lag_3_temperature = shifted(3L),
    rolling_mean_7 = previous_seven,
    day_of_year = day_of_year,
    season_sin = sin(2 * pi * day_of_year / 365.25),
    season_cos = cos(2 * pi * day_of_year / 365.25)
  )
}

create_temperature_features <- function(history) {
  temperature_features_from_grid(temperature_daily_grid(history))
}

model_metrics <- function(actual, predicted) {
  if (!is.numeric(actual) || !is.numeric(predicted) ||
      length(actual) != length(predicted)) {
    stop("Model evaluation requires matching numeric observations and predictions.", call. = FALSE)
  }
  valid <- is.finite(actual) & is.finite(predicted)
  if (!any(valid)) {
    stop("No valid observations are available to evaluate the model.", call. = FALSE)
  }
  actual <- actual[valid]
  predicted <- predicted[valid]
  errors <- actual - predicted
  total_variation <- sum((actual - mean(actual))^2)
  has_variation <- length(actual) > 1L &&
    total_variation > .Machine$double.eps * max(1, sum(actual^2))
  list(
    mae = mean(abs(errors)),
    rmse = sqrt(mean(errors^2)),
    r_squared = if (has_variation) 1 - sum(errors^2) / total_variation else NA_real_,
    n = length(actual)
  )
}

fit_temperature_regression <- function(data, candidates) {
  if (length(unique(data$temp_mean)) < 2L || stats::sd(data$temp_mean) < 1e-8) {
    stop("Temperature history has too little variation to train a meaningful regression.", call. = FALSE)
  }
  varying <- candidates[vapply(data[candidates], function(x) {
    length(unique(x)) > 1L && is.finite(stats::sd(x)) && stats::sd(x) > 1e-8
  }, logical(1))]
  if (!length(varying)) {
    stop("There are no usable varying predictors in this historical period.", call. = FALSE)
  }
  # Select an independent predictor set on the training data alone. This makes
  # redundant lags and seasonal terms safe without fitting aliased coefficients.
  design <- stats::model.matrix(stats::reformulate(varying), data = data)
  decomposition <- qr(design, tol = 1e-7)
  independent <- colnames(design)[decomposition$pivot[seq_len(decomposition$rank)]]
  selected <- varying[varying %in% independent]
  if (!length(selected)) {
    stop("The historical predictors cannot support a stable regression.", call. = FALSE)
  }
  fit <- tryCatch(
    stats::lm(stats::reformulate(selected, response = "temp_mean"), data = data,
              na.action = stats::na.fail),
    error = function(e) stop("The statistical model could not be fitted to this history.", call. = FALSE)
  )
  if (fit$rank != length(stats::coef(fit)) || any(!is.finite(stats::coef(fit)))) {
    stop("The historical data produced an unstable regression. Try a longer period.", call. = FALSE)
  }
  list(model = fit, features = selected, dropped = setdiff(candidates, selected))
}

checked_temperature_prediction <- function(model, data) {
  predictions <- tryCatch(
    as.numeric(stats::predict(model, newdata = data)),
    error = function(e) stop("The model could not produce a valid temperature prediction.", call. = FALSE)
  )
  if (length(predictions) != nrow(data) || any(!is.finite(predictions)) ||
      any(predictions < -100 | predictions > 70)) {
    stop("The model produced implausible temperatures. Try a different historical period.", call. = FALSE)
  }
  predictions
}

train_temperature_model <- function(history, min_rows = 90L) {
  if (length(min_rows) != 1L || !is.numeric(min_rows) || is.na(min_rows) ||
      !is.finite(min_rows) || min_rows < 30L) {
    stop("The minimum model sample size must be at least 30 observations.", call. = FALSE)
  }
  grid <- temperature_daily_grid(history)
  features <- temperature_features_from_grid(grid)
  candidates <- c("lag_1_temperature", "lag_2_temperature", "lag_3_temperature",
                  "rolling_mean_7", "season_sin", "season_cos")
  eligible <- stats::complete.cases(features[c("temp_mean", candidates)])
  usable <- features[eligible, , drop = FALSE]
  if (nrow(usable) < min_rows) {
    stop(sprintf("At least %d complete daily model rows are needed after creating lag features; %d are available. Load 180 to 365 days of history.",
                 as.integer(min_rows), nrow(usable)), call. = FALSE)
  }
  if (nrow(grid) < 7L || any(!is.finite(utils::tail(grid$temp_mean, 7L)))) {
    stop("A next-day prediction needs valid temperatures for the final seven consecutive calendar days. Refresh the history or select a complete date range.", call. = FALSE)
  }

  n_train <- floor(0.8 * nrow(usable))
  train <- usable[seq_len(n_train), , drop = FALSE]
  test <- usable[seq.int(n_train + 1L, nrow(usable)), , drop = FALSE]
  evaluation_fit <- fit_temperature_regression(train, candidates)
  predicted <- checked_temperature_prediction(evaluation_fit$model, test)
  metrics <- model_metrics(test$temp_mean, predicted)
  baseline_metrics <- model_metrics(test$temp_mean, test$lag_1_temperature)

  next_date <- max(grid$date) + 1L
  extended <- rbind(grid, data.frame(date = next_date, temp_mean = NA_real_))
  next_features <- utils::tail(temperature_features_from_grid(extended), 1L)
  # Holdout metrics above remain untouched by this production refit. Apply the
  # predictor set selected from the training split to all eligible observations.
  final_fit <- fit_temperature_regression(usable, evaluation_fit$features)
  next_prediction <- checked_temperature_prediction(final_fit$model, next_features)

  list(
    next_prediction = unname(next_prediction),
    next_date = next_date,
    metrics = metrics,
    baseline_metrics = baseline_metrics,
    n_train = nrow(train),
    n_test = nrow(test),
    n_total = nrow(usable),
    n_excluded = nrow(features) - nrow(usable),
    test = data.frame(date = test$date, actual = test$temp_mean,
                      predicted = predicted, persistence = test$lag_1_temperature),
    model = evaluation_fit$model,
    refit_model = final_fit$model,
    features_used = evaluation_fit$features,
    dropped_features = evaluation_fit$dropped,
    training_end_date = max(train$date),
    history_end_date = max(grid$date),
    next_features = next_features,
    interpretation = paste("Chronological 80/20 holdout; one-step predictions use prior observed",
                           "temperatures. Reported metrics use the training-only fit.",
                           "A separate fit on all eligible rows predicts the day after the",
                           "loaded history ends, which may differ from tomorrow.")
  )
}
