library(shiny)
library(bslib)
library(ggplot2)
for (module in c("utils", "weather_codes", "api", "analytics", "prediction")) {
  source(file.path("R", paste0(module, ".R")), local = TRUE)
}
options(shiny.sanitize.errors = TRUE)

metric <- function(label, value, detail = NULL) {
  tags$div(class = "metric", tags$div(class = "metric-label", label),
    tags$div(class = "metric-value", value), tags$div(class = "metric-detail", detail))
}
intro <- function(kicker, title, text) {
  tags$div(class = "section-intro", tags$div(class = "eyebrow", kicker), tags$h1(title), tags$p(text))
}
chart_card <- function(title, output, height = 320) {
  card(card_header(title), plotOutput(output, height = height, fill = FALSE), fill = FALSE)
}

ui <- page_navbar(
  title = tags$div(class = "brand", tags$span(class = "brand-mark", "W"), "WeatherPulse"),
  id = "page", window_title = "WeatherPulse | Weather analytics in R",
  fillable = FALSE,
  theme = bs_theme(version = 5, bg = "#f4f7f8", fg = "#142d38", primary = "#087f83",
    base_font = "system-ui", heading_font = "system-ui", border_radius = "0.7rem"),
  header = tags$head(tags$link(rel = "stylesheet", href = "styles.css")),
  sidebar = sidebar(width = 275, open = "desktop", title = "Your weather workspace",
    tags$div(class = "eyebrow", "LOCATION"),
    textInput("city_query", "Search a city", value = "Hyderabad", placeholder = "City name"),
    actionButton("search_city", "Search cities", class = "btn-outline-primary w-100"),
    selectInput("city_select", "Choose location", choices = character()),
    uiOutput("selected_location"),
    actionButton("refresh", "Refresh weather", class = "btn-primary w-100"),
    tags$hr(),
    tags$div(class = "source-badge", tags$span(class = "status-dot"), "Powered by Open-Meteo"),
    tags$p(class = "small muted", "Current / near-real-time weather. Refreshes every 5 minutes while your session is active."),
    tags$p(class = "small muted", "Explore a city, investigate its history, and evaluate an R statistical model."),
    tags$a(href = "https://open-meteo.com/", target = "_blank", rel = "noopener", "Data source & attribution ↗")
  ),
  nav_panel("Overview", value = "overview",
    intro("WEATHER AT A GLANCE", "A clearer view of your day.", "Real-Time Weather Analytics & Prediction Dashboard"),
    uiOutput("weather_status"), uiOutput("current_weather"),
    layout_columns(col_widths = c(8, 4),
      chart_card("The next seven days", "forecast_temperature"),
      chart_card("Daily precipitation", "forecast_rain")),
    card(card_header("Daily forecast details"), tableOutput("forecast_table"))
  ),
  nav_panel("Historical analytics", value = "history",
    intro("EXPLORE THE RECORD", "Patterns over time.", "Inspect daily weather estimates, seasonal changes, and rainfall for your selected city."),
    card(card_header("Choose a historical window"),
      layout_columns(col_widths = c(4, 4, 4),
        selectInput("history_days", "History length", choices = c("30 days" = 30, "90 days" = 90, "180 days" = 180, "365 days" = 365), selected = 90),
        dateInput("history_end", "End date", value = Sys.Date() - 6, max = Sys.Date() - 6),
        tags$div(class = "action-aligned", actionButton("analyze", "Analyze historical data", class = "btn-primary"))),
      tags$p(class = "small muted", "The archive window ends at least 6 days ago to allow for data availability. Missing values stay missing.")),
    uiOutput("history_summary"),
    layout_columns(col_widths = c(8, 4), chart_card("Daily temperature", "history_temperature"), chart_card("Daily precipitation", "history_rain")),
    uiOutput("monthly_container"),
    card(card_header("Your loaded dataset"), uiOutput("history_dataset_note"),
      downloadButton("download_history", "Download historical CSV"), tableOutput("history_preview"))
  ),
  nav_panel("Prediction", value = "prediction",
    intro("BUILT WITH BASE R", "From observations to estimates.", "Train and evaluate an educational statistical model for next-day mean temperature."),
    card(card_header("Train the R statistical model"),
      layout_columns(col_widths = c(6, 6),
        selectInput("model_days", "Training history", choices = c("180 days" = 180, "365 days" = 365), selected = 365),
        tags$div(class = "action-aligned", actionButton("train", "Train & evaluate model", class = "btn-primary"))),
      tags$p(class = "small muted", "Daily history combines archive estimates with recent completed days from Open-Meteo forecast-model history. The model predicts the day after the last completed day; the exact target date is shown below.")),
    uiOutput("prediction_summary"),
    chart_card("Chronological holdout: actual vs predicted", "prediction_plot", 370),
    card(card_header("How to interpret this model"),
      tags$p("Linear regression uses temperatures from the preceding 1, 2, and 3 days, the previous 7-day mean, and annual sine/cosine features. The first 80% of usable days train the evaluation model; the final 20% measure one-day-ahead performance."),
      tags$p("Holdout features use the actual preceding daily estimates, including earlier holdout days. This evaluates successive one-step predictions, not a multi-day forecast made at the start of the test period. A separate model is then refitted on all usable history for the displayed next-day estimate."),
      tags$p(class = "notice", "The local R model is an educational statistical model trained on historical weather patterns and should not be considered a professional meteorological forecasting system."))
  ),
  nav_panel("City comparison", value = "comparison",
    intro("A WIDER PERSPECTIVE", "Three cities. One view.", "Compare current weather across locations worldwide."),
    card(card_header("Find and confirm your cities"),
      layout_columns(col_widths = c(4, 4, 4),
        tags$div(textInput("compare_query_1", "City 1", "Hyderabad"), selectInput("compare_city_1", "Location 1", character())),
        tags$div(textInput("compare_query_2", "City 2", "London"), selectInput("compare_city_2", "Location 2", character())),
        tags$div(textInput("compare_query_3", "City 3 (optional)", "Tokyo"), selectInput("compare_city_3", "Location 3", character()))),
      tags$div(class = "button-row", actionButton("find_comparison", "Find cities", class = "btn-outline-primary"), actionButton("compare", "Compare weather", class = "btn-primary")),
      tags$p(class = "small muted", "Confirm the region and country for each match, then compare. Leave a city blank to omit it.")),
    uiOutput("comparison_note"),
    chart_card("Current temperature by city", "comparison_plot"),
    card(card_header("Current conditions side by side"), tableOutput("comparison_table"))
  ),
  nav_panel("Methodology", value = "about",
    intro("THE SCIENCE & THE SOFTWARE", "Transparent by design.", "Real-Time Weather Analytics and Prediction Dashboard using R"),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Objective & architecture"),
        tags$p("WeatherPulse demonstrates the analytics lifecycle: acquisition → validation → cleaning → transformation → exploration → prediction → evaluation → visualization."),
        tags$p("The Shiny interface calls modular R functions. curl retrieves JSON from Open-Meteo; jsonlite parses it. Base R prepares data and fits lm() regression. ggplot2 renders charts and bslib provides the responsive dashboard."),
        tags$p("API responses are cached temporarily in process memory. No database, permanent CSV history, or background collection service is required.")),
      card(card_header("Data & cleaning"),
        tags$p("Open-Meteo geocoding resolves city, administrative region, country, and coordinates. Forecast and current endpoints use city-local time. The historical archive supplies gridded reanalysis/model estimates, not a dedicated sensor at the selected coordinates."),
        tags$p("Dates are ordered, duplicates validated, and missing days preserved. Invalid weather measurements become missing. Where daily mean temperature is absent, the midpoint of daily minimum and maximum is used and labeled in the CSV."),
        tags$p("History includes daily temperature, precipitation, and maximum wind speed. Monthly charts appear only for sufficiently long datasets.")),
      card(card_header("Prediction & evaluation"),
        tags$p("Past-only lag and rolling features avoid using the target temperature. A chronological 80/20 split preserves time order; constant or redundant predictors are handled defensively."),
        tags$p("MAE is average absolute error in °C. RMSE is the square root of average squared error in °C and penalizes larger misses. R² compares squared error against variation in the holdout target; it may be negative and is N/A for a constant target."),
        tags$p("A persistence baseline predicts the previous day's mean. Comparing it with regression helps judge whether the added model complexity is useful.")),
      card(card_header("Scope & limitations"),
        tags$p("“Real-time” means fresh current data is requested on interaction and approximately every 5 minutes during an active session. A free shinyapps.io app can sleep when idle and does not collect data 24/7."),
        tags$p("Network failures and service limits can delay results. Model accuracy depends on city, season, history, and data completeness. Weather is complex; this linear model is for learning and is not suitable for safety-critical decisions."),
        tags$p("Future work could add richer lag features, rolling-origin validation, prediction intervals, and a broader comparison of lightweight statistical models."))),
    card(card_header("Sources & credits"), tags$p(
      tags$a(href = "https://open-meteo.com/", "Weather data by Open-Meteo"), " · ",
      tags$a(href = "https://creativecommons.org/licenses/by/4.0/", "Weather data: CC BY 4.0"), " · ",
      tags$a(href = "https://www.geonames.org/", "Geocoding data: GeoNames")),
      tags$p("Software: R, Shiny, bslib, ggplot2, curl, and jsonlite. Hosting: shinyapps.io with rsconnect."))
  ),
  footer = tags$footer(class = "app-footer", tags$span("WeatherPulse · An R analytics project"),
    tags$span("Weather data by ", tags$a(href = "https://open-meteo.com/", "Open-Meteo"), " · °C / mm / km/h"))
)

server <- function(input, output, session) {
  state <- reactiveValues(cities = NULL, city = NULL, weather = NULL, weather_error = NULL,
    history = NULL, history_city = NULL, model = NULL, model_city = NULL,
    comparison_options = list(), comparison = NULL)
  friendly_error <- function(e) {
    msg <- conditionMessage(e)
    showNotification(msg, type = "error", duration = 12)
    invisible(NULL)
  }
  search_locations <- function() {
    tryCatch({
      matches <- geocode_city(input$city_query)
      if (!nrow(matches)) stop("No matching city found. Try a different spelling.")
      state$cities <- matches
      preferred <- which(matches$name == "Hyderabad" & matches$country == "India")
      index <- if (length(preferred) && tolower(trimws(input$city_query)) == "hyderabad") preferred[1] else 1L
      updateSelectInput(session, "city_select", choices = setNames(as.character(seq_len(nrow(matches))), matches$label), selected = as.character(index))
      state$city <- matches[index, , drop = FALSE]
    }, error = friendly_error)
  }
  observeEvent(input$city_query, { req(nzchar(input$city_query)); search_locations() }, once = TRUE)
  observeEvent(input$search_city, search_locations())
  observeEvent(input$city_select, {
    req(state$cities)
    index <- suppressWarnings(as.integer(input$city_select))
    if (length(index) == 1L && !is.na(index) && index >= 1 && index <= nrow(state$cities)) state$city <- state$cities[index, , drop = FALSE]
  })
  load_weather <- function(force = FALSE) {
    req(state$city)
    tryCatch({
      state$weather <- fetch_weather(state$city, force = force)
      state$weather_error <- NULL
    }, error = function(e) { state$weather_error <- conditionMessage(e); friendly_error(e) })
  }
  observeEvent(state$city, {
    state$weather <- NULL; state$history <- NULL; state$model <- NULL
    tryCatch({
      updateDateInput(session, "history_end", value = city_local_date(state$city) - 6, max = city_local_date(state$city) - 6)
      load_weather()
    }, error = friendly_error)
  })
  observeEvent(input$refresh, load_weather(force = TRUE))
  observe({ invalidateLater(300000, session); isolate({ if (!is.null(state$city)) load_weather() }) })
  output$selected_location <- renderUI({
    req(state$city)
    tags$div(class = "location-details", tags$strong(state$city$name), tags$p(state$city$country),
      tags$small(sprintf("%.3f°, %.3f°", state$city$latitude, state$city$longitude)),
      tags$small(state$city$timezone))
  })
  output$weather_status <- renderUI({
    if (!is.null(state$weather_error)) tags$div(class = "notice error-notice", role = "alert", state$weather_error,
      if (!is.null(state$weather)) " Showing the last successful update." else " Please refresh to retry.")
    else if (is.null(state$weather)) tags$div(class = "empty-state", "Choose a city to load real weather data.")
  })
  output$current_weather <- renderUI({
    req(state$weather, state$city)
    w <- state$weather; c <- w$current
    tagList(tags$div(class = "conditions-banner",
      tags$div(tags$div(class = "eyebrow", "CURRENT CONDITIONS"), tags$h2(state$city$label),
        tags$p(weather_label(c$weather_code))),
      tags$div(class = "update-note", tags$strong(paste("Local weather time:", gsub("T", " ", c$time))),
        tags$span(w$timezone), tags$span(paste("Last updated:", format(w$fetched_at, tz = w$timezone, format = "%d %b %Y, %H:%M"))))),
      tags$div(class = "metric-grid",
        metric("Temperature", format_value(c$temperature_2m, " °C"), "At 2 metres"),
        metric("Feels like", format_value(c$apparent_temperature, " °C"), "Apparent temperature"),
        metric("Humidity", format_value(c$relative_humidity_2m, "%", 0), "Relative humidity"),
        metric("Wind", format_value(c$wind_speed_10m, " km/h"), "At 10 metres"),
        metric("Precipitation", format_value(c$precipitation, " mm"), paste("Current interval:", if (is.null(c$interval)) "provider-defined" else paste(c$interval / 60, "min"))),
        metric("Pressure", format_value(c$pressure_msl, " hPa", 0), "At sea level"),
        metric("Cloud cover", format_value(c$cloud_cover, "%", 0), "Total cloud cover")))
  })
  output$forecast_temperature <- renderPlot({
    req(state$weather); d <- state$weather$daily
    ggplot(d, aes(date)) + geom_ribbon(aes(ymin = temp_min, ymax = temp_max), fill = "#d4ece9") +
      geom_line(aes(y = temp_max, colour = "Maximum"), linewidth = 1.1) + geom_point(aes(y = temp_max), colour = "#087f83", size = 2.5) +
      geom_line(aes(y = temp_min, colour = "Minimum"), linewidth = 1.1) +
      scale_colour_manual(values = c(Maximum = "#087f83", Minimum = "#7197b1")) +
      scale_x_date(date_labels = "%a\n%d %b", date_breaks = "1 day") + labs(x = NULL, y = "Temperature (°C)") + weather_theme()
  }, alt = "Seven-day forecast with daily minimum and maximum temperatures in degrees Celsius.")
  rain_plot <- function(d) ggplot(d, aes(date, precipitation)) + geom_col(fill = "#7197b1", width = 0.7) +
    labs(x = NULL, y = "Precipitation (mm)") + weather_theme()
  output$forecast_rain <- renderPlot({ req(state$weather); rain_plot(state$weather$daily) + scale_x_date(date_labels = "%a", date_breaks = "1 day") }, alt = "Forecast precipitation by day in millimetres.")
  output$forecast_table <- renderTable({
    req(state$weather); d <- state$weather$daily
    data.frame(Date = format(d$date, "%a, %d %b"), `Min (°C)` = d$temp_min, `Max (°C)` = d$temp_max,
      `Mean (°C)` = d$temp_mean, `Rain (mm)` = d$precipitation, Condition = weather_label(d$weather_code), check.names = FALSE)
  }, striped = TRUE, bordered = FALSE, digits = 1)
  observeEvent(input$analyze, {
    req(state$city)
    tryCatch(withProgress(message = "Loading historical weather", value = 0.2, {
      end <- as.Date(input$history_end); days <- as.integer(input$history_days)
      if (is.na(end) || end > city_local_date(state$city) - 6 || !days %in% c(30, 90, 180, 365)) stop("Choose a valid window ending at least 6 days ago.")
      h <- clean_history(fetch_history(state$city, end - days + 1, end))
      state$history <- h; state$history_city <- state$city
    }), error = friendly_error)
  })
  output$history_summary <- renderUI({
    if (is.null(state$history)) return(tags$div(class = "empty-state", "Choose a window and select Analyze historical data to begin."))
    s <- summarize_history(state$history)
    tagList(tags$p(class = "dataset-caption", paste(state$history_city$label, "·", min(state$history$date), "to", max(state$history$date))),
      tags$p(class = "small muted", paste("Coverage:", s$temperature_days, "temperature days and", s$precipitation_days, "precipitation days out of", s$calendar_days, "calendar days. Totals use available values only.")),
      tags$div(class = "metric-grid", metric("Average temperature", format_value(s$avg_temp, " °C")),
        metric("Highest temperature", format_value(s$highest_temp, " °C")), metric("Lowest temperature", format_value(s$lowest_temp, " °C")),
        metric("Total precipitation", format_value(s$total_precipitation, " mm")), metric("Rainy days", s$rainy_days, "Daily precipitation > 0 mm"),
        metric("Rainiest day", if (is.na(s$rainiest_day)) "N/A" else format(s$rainiest_day, "%d %b %Y")),
        metric("Average daily max wind", format_value(s$avg_wind, " km/h")), metric("Maximum wind", format_value(s$max_wind, " km/h"))))
  })
  output$history_temperature <- renderPlot({ req(state$history); d <- state$history
    ggplot(d, aes(date, temp_mean)) + geom_ribbon(aes(ymin = temp_min, ymax = temp_max), fill = "#d4ece9") +
      geom_line(colour = "#087f83", linewidth = 0.8) + labs(x = NULL, y = "Temperature (°C)", subtitle = "Mean temperature · shaded daily minimum–maximum range") + weather_theme()
  }, alt = "Historical mean temperature with daily minimum and maximum range.")
  output$history_rain <- renderPlot({ req(state$history); rain_plot(state$history) }, alt = "Historical daily precipitation in millimetres.")
  output$monthly_container <- renderUI({ req(state$history); if (nrow(state$history) >= 60) chart_card("Monthly rainfall totals", "monthly_plot") })
  output$monthly_plot <- renderPlot({ req(state$history); d <- monthly_summary(state$history)
    ggplot(d, aes(month, total_precipitation)) + geom_col(fill = "#087f83", width = 20) +
      scale_x_date(date_labels = "%b %Y", date_breaks = "1 month") + labs(x = NULL, y = "Precipitation (mm)", subtitle = "Totals cover loaded days only; first and last months may be partial.") + weather_theme()
  }, alt = "Monthly precipitation totals for the loaded date range.")
  output$history_dataset_note <- renderUI({ req(state$history); tags$p(paste(nrow(state$history), "daily rows. CSV includes units in column names, location, and data-source labels. Preview: latest 10 days.")) })
  output$history_preview <- renderTable({ req(state$history); d <- tail(state$history, 10)
    data.frame(Date = as.character(d$date), `Mean (°C)` = d$temp_mean, `Min (°C)` = d$temp_min, `Max (°C)` = d$temp_max, `Precipitation (mm)` = d$precipitation, `Max wind (km/h)` = d$wind_max, check.names = FALSE)
  }, digits = 1)
  output$download_history <- downloadHandler(
    filename = function() { req(state$history_city); paste0("weather_history_", safe_filename(state$history_city$name), "_", city_local_date(state$history_city), ".csv") },
    content = function(file) {
      req(state$history, state$history_city)
      d <- state$history
      names(d) <- sub("^temp_min$", "temperature_min_c", names(d)); names(d) <- sub("^temp_max$", "temperature_max_c", names(d))
      names(d) <- sub("^temp_mean$", "temperature_mean_c", names(d)); names(d) <- sub("^precipitation$", "precipitation_mm", names(d)); names(d) <- sub("^wind_max$", "wind_max_kmh", names(d))
      d$city <- state$history_city$label; d$latitude <- state$history_city$latitude; d$longitude <- state$history_city$longitude
      write.csv(d, file, row.names = FALSE, na = "", fileEncoding = "UTF-8")
    })
  observeEvent(input$train, {
    req(state$city)
    tryCatch(withProgress(message = "Training and evaluating the R model", value = 0.2, {
      h <- fetch_model_history(state$city, as.integer(input$model_days))
      m <- train_temperature_model(h)
      if (m$next_date != city_local_date(state$city)) stop("Recent completed days are unavailable. Please retry later to obtain a current model estimate.")
      state$model <- m; state$model_city <- state$city
    }), error = friendly_error)
  })
  output$prediction_summary <- renderUI({
    if (is.null(state$model)) return(tags$div(class = "empty-state", "Select Train & evaluate model to run a real linear regression in R."))
    m <- state$model; met <- m$metrics
    tagList(tags$p(class = "dataset-caption", paste(state$model_city$label, "·", m$n_train, "training days ·", m$n_test, "test days")),
      tags$div(class = "prediction-banner", tags$div(tags$div(class = "eyebrow", "R STATISTICAL MODEL PREDICTION"),
        tags$h2(format_value(m$next_prediction, " °C")), tags$p(paste("Mean temperature for", format(m$next_date, "%d %B %Y"))),
        tags$p(class = "small", paste("Next day after completed history ending", m$history_end_date, "— the target is today in the selected city.")))),
      tags$div(class = "metric-grid", metric("MAE", format_value(met$mae, " °C", 2), "Lower is better"),
        metric("RMSE", format_value(met$rmse, " °C", 2), "Penalizes larger errors"),
        metric("R²", format_value(met$r_squared, "", 3), "May be negative; N/A if undefined"),
        metric("Persistence baseline MAE", format_value(m$baseline_metrics$mae, " °C", 2), "Predict yesterday's mean")),
      tags$p(class = "small muted", "Evaluation metrics belong to the fixed training model. The displayed next-day estimate uses a separate refit on all usable days."))
  })
  output$prediction_plot <- renderPlot({ req(state$model); d <- state$model$test
    ggplot(d, aes(date)) + geom_line(aes(y = actual, colour = "Actual"), linewidth = 0.8) +
      geom_line(aes(y = predicted, colour = "R model"), linewidth = 0.8, linetype = "dashed") +
      scale_colour_manual(values = c(Actual = "#087f83", `R model` = "#be6b38")) + labs(x = NULL, y = "Mean temperature (°C)", subtitle = "Last 20% of usable dates · successive one-step predictions") + weather_theme()
  }, alt = "Actual and predicted daily mean temperatures on the chronological holdout data.")
  observeEvent(input$find_comparison, {
    options <- list()
    for (i in 1:3) {
      query <- trimws(input[[paste0("compare_query_", i)]])
      matches <- if (nzchar(query)) tryCatch(geocode_city(query), error = function(e) { friendly_error(e); NULL }) else NULL
      options[[as.character(i)]] <- matches
      choices <- if (is.null(matches) || !nrow(matches)) character() else setNames(as.character(seq_len(nrow(matches))), matches$label)
      updateSelectInput(session, paste0("compare_city_", i), choices = c("Omit city" = "", choices), selected = if (length(choices)) "1" else "")
    }
    state$comparison_options <- options
  })
  observeEvent(input$compare, {
    tryCatch(withProgress(message = "Comparing current conditions", value = 0.2, {
      rows <- list()
      for (i in 1:3) {
        choices <- state$comparison_options[[as.character(i)]]
        selected <- suppressWarnings(as.integer(input[[paste0("compare_city_", i)]]))
        if (is.null(choices) || length(selected) != 1 || is.na(selected) || selected < 1 || selected > nrow(choices)) next
        city <- choices[selected, , drop = FALSE]
        row <- tryCatch({ w <- fetch_weather(city); c <- w$current
          data.frame(city = city$label, temperature = c$temperature_2m, feels_like = c$apparent_temperature,
            humidity = c$relative_humidity_2m, wind = c$wind_speed_10m, precipitation = c$precipitation,
            condition = weather_label(c$weather_code), local_time = gsub("T", " ", c$time), timezone = w$timezone)
        }, error = function(e) { friendly_error(e); NULL })
        if (!is.null(row)) rows[[length(rows) + 1]] <- row
      }
      if (!length(rows)) stop("Find and select cities before comparing, or retry if the service is unavailable.")
      state$comparison <- unique(do.call(rbind, rows))
    }), error = friendly_error)
  })
  output$comparison_note <- renderUI({
    if (is.null(state$comparison)) tags$div(class = "empty-state", "Find cities, confirm your locations, then compare weather.")
    else tags$p(class = "dataset-caption", paste(nrow(state$comparison), "locations loaded. Conditions refer to each city's local weather time."))
  })
  output$comparison_plot <- renderPlot({ req(state$comparison); d <- state$comparison
    ggplot(d, aes(reorder(city, temperature), temperature)) + geom_col(fill = "#087f83", width = 0.5) + coord_flip() +
      geom_text(aes(label = paste0(round(temperature, 1), " °C")), hjust = -0.15, size = 4) +
      scale_y_continuous(expand = expansion(mult = c(0.1, 0.2))) + labs(x = NULL, y = "Current temperature (°C)") + weather_theme()
  }, alt = "Current temperatures for the selected comparison cities in degrees Celsius.")
  output$comparison_table <- renderTable({ req(state$comparison); d <- state$comparison
    names(d) <- c("Location", "Temp (°C)", "Feels like (°C)", "Humidity (%)", "Wind (km/h)", "Precipitation (mm)", "Condition", "Local weather time", "Timezone")
    d
  }, digits = 1, striped = TRUE)
}

shinyApp(ui, server)
