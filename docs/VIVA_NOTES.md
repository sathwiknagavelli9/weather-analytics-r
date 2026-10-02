# WeatherPulse: viva notes

**Project:** Real-Time Weather Analytics and Prediction Dashboard using R

## 1. What does this project do?

WeatherPulse retrieves real weather data, displays current conditions and a provider forecast, analyzes historical daily weather, compares cities, and runs an educational R regression model for next-day mean temperature. It also reports holdout errors and supports CSV downloads.

## 2. Why did you choose R?

R provides statistical modelling, numerical data handling, and plotting in one language. Base R includes linear regression, so this project can remain lightweight and its calculations are easy to inspect.

## 3. Why did you choose Shiny?

Shiny lets an R program become an interactive web application. Inputs such as city selection and date ranges connect directly to R calculations and visual outputs without requiring a separate application framework.

## 4. What is an API?

An application programming interface lets one program request data or services from another system. Here, the application sends an HTTP request with coordinates and weather variables, and Open-Meteo returns structured weather data.

## 5. Why use Open-Meteo?

Its public services support geocoding, current weather, forecasts, and historical weather without an application API key. We attribute the provider and keep its forecast separate from our R model. Its products are model-based and reanalysis data, not readings from sensors installed by this project.

## 6. What is JSON, and how is it used?

JSON is a structured text format containing objects, arrays, numbers, strings, and other simple values. Open-Meteo returns JSON. The curl package retrieves the response and jsonlite converts it into structures that R can process.

## 7. How do you resolve a city name?

The geocoding service returns candidate locations with coordinates, country, and administrative details. The user selects the correct result, which prevents confusion between cities with the same name. Weather requests then use its latitude and longitude.

For city comparison, enter up to three names, click **Find cities**, confirm the matching locations, and click **Compare weather**.

## 8. What is data cleaning in this project?

It includes validating response structure, parsing dates, checking numerical values, sorting daily records, and handling missing or duplicate records. Missing weather values are not silently replaced with zero. Rows without enough valid preceding temperatures cannot be used for model training.

## 9. What if daily mean temperature is unavailable?

When both daily maximum and minimum are usable, their midpoint can be used: `(maximum + minimum) / 2`. This is an approximation and is identified as such. It is not necessarily equal to the true average across all hours of the day.

## 10. What are lag features?

A lag is a value from an earlier time. To predict a target day's temperature, lag 1 uses the previous day's mean, lag 2 uses the value from two days earlier, and lag 3 uses the value from three days earlier. They capture short-term persistence without using the target day's temperature.

## 11. Why use a seven-day mean and sine/cosine terms?

The preceding seven-day mean summarizes recent conditions and reduces the influence of one unusual day. Sine and cosine of the target date's day of year represent the annual seasonal cycle smoothly. Only the preceding seven days enter the rolling mean.

## 12. What is linear regression?

Linear regression estimates a target as an intercept plus a weighted sum of predictors. R's `lm()` chooses coefficients by minimizing squared errors on the training data. “Linear” refers to the model's relationship with its coefficients, not a claim that all weather behavior is simple.

## 13. Why use a chronological 80/20 split instead of a random split?

We train on earlier usable dates and test on later dates to preserve the time direction of forecasting. Random splitting mixes earlier and later periods and can make a time-series evaluation harder to interpret. Roughly 80% is for fitting and 20% is held out for checking errors.

## 14. Is the holdout a multi-day forecast?

No. Each test day uses actual provider temperatures from previous days. A previous test day's actual value can become a later test day's lag. This evaluates one-day-ahead predictions; it is not a recursive forecast that repeatedly uses its own predicted values. It is also retrospective and does not recreate the exact data releases available at each historical date.

## 15. What is MAE?

Mean absolute error is `mean(abs(actual - predicted))`. It measures the average size of an error without considering its direction. For temperature it is expressed in °C, and lower values indicate smaller errors on the evaluated data.

## 16. What is RMSE?

Root mean squared error is `sqrt(mean((actual - predicted)^2))`. It is also expressed in °C. Squaring gives larger errors more influence, so RMSE is useful when large misses are especially important.

## 17. What is R², and can it be negative?

Here, holdout R² is `1 - squared_error / total_variation`. It compares predictions with the mean of the actual test values and can be negative when the model performs worse than that reference. It is not an accuracy percentage. If actual test values have no meaningful variation, the application shows N/A.

## 18. How is the final next-day prediction produced?

After evaluating the training-only model, the application refits on all eligible completed-day data. It builds the next target date's features from the latest valid history and checks the prediction. If the last complete day is yesterday, the next-day target is today in that city's timezone; the displayed date is authoritative.

## 19. How does our model differ from Open-Meteo's forecast?

Our model is a small statistical regression fitted in R using past daily temperatures and seasonal features. Open-Meteo supplies forecasts from external weather modelling systems. The dashboard labels their origins separately, and their values should only be directly compared when target dates match.

## 20. What does “real-time” mean here?

It means current / near-real-time data is requested when a user interacts with the application and approximately every five minutes while a session is active. It does not mean second-by-second sensor readings or permanent background collection when the application is idle.

## 21. What is reactive programming?

Reactive programming updates dependent outputs when relevant inputs or data change. In Shiny, a city selection can update weather displays. Expensive operations such as historical acquisition and model training are tied to explicit buttons so editing an input does not repeatedly trigger them.

## 22. What happens when an API request or model fails?

The API layer uses timeouts, status checks, JSON validation, and retries for eligible temporary failures. The interface shows a friendly message and never invents weather values. Insufficient history or an invalid model fit is reported within the affected feature so the rest of the dashboard remains usable.

## 23. Why is caching useful, and why is there no database?

Caching lets repeated requests reuse recently fetched data, reducing latency and API traffic. The cache is temporary memory and is rebuilt after restart. Historical data comes from Open-Meteo when needed, so a persistent database is unnecessary for this project and cannot be assumed on a free hosted filesystem.

## 24. How is the application tested and deployed?

Base R tests check parsing, transformations, features, metrics, and defensive cases. Shiny's `testServer()` tests the reactive server and actual CSV handler with deterministic service substitutes. A smoke test uses real Open-Meteo requests. Local HTTP checks and browser checks cover startup and visible interactions. rsconnect publishes the app to shinyapps.io using existing local authentication; source control must contain no authentication secrets. A deployment is verified by checking its public app and data access after publishing.

The local checks passed, including a browser-downloaded 90-row CSV, city search and comparison, model execution, unknown-city recovery, and desktop/mobile layouts. The source was pushed to the public [GitHub repository](https://github.com/sathwiknagavelli9/weather-analytics-r), and the [hosted application](https://sathwik-nagavelli.shinyapps.io/weather-analytics-r/) was verified on 2 October 2026 with HTTP 200, real current/forecast data, and successful R model execution.

## 25. What are the limitations and possible improvements?

The regression is educational, depends on provider data, and can miss nonlinear weather changes and extremes. Recent and archive records may come from different data products. One holdout period does not prove reliability everywhere, and the project is not a distributed big-data platform. Improvements include rolling-origin evaluation across seasons, validated extra predictors, and calibrated uncertainty intervals, assessed against the included previous-day persistence baseline.

## Short demonstration introduction

“WeatherPulse is an R/Shiny weather analytics project using real Open-Meteo data. It demonstrates acquisition, cleaning, visualization, and statistical prediction. I can search worldwide cities, study historical patterns, compare current weather, and train our own next-day mean-temperature regression. The model uses earlier temperatures and seasonal features, and its errors are evaluated on later dates. The provider forecast and our educational R model are clearly distinguished.”

## Reporting results accurately

Use the metrics currently produced by the selected city and historical window. State the location, data dates, target date, and usable train/test counts with MAE, RMSE, and R². Do not memorize an illustrative score or describe R² as “percent accuracy.” Mention that holdout predictions use actual prior temperatures and that provider history is not an independent local sensor dataset.

An actual Hyderabad smoke-test run on **2 October 2026** used daily history from **2 October 2025 through 1 October 2026**, with **286 training and 72 testing rows**. The regression achieved **MAE 0.699 °C, RMSE 0.913 °C, and R² 0.461**. The previous-day persistence baseline achieved **MAE 0.725 °C and RMSE 0.914 °C**. The final refit estimated **28.78 °C** for **2 October 2026**. Explain that these are measured results for one run and that the prediction date was today locally because the most recent completed data ended yesterday.
