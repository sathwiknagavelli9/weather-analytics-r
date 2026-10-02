# Small presentation helpers; missing data is never replaced by a weather value.
format_value <- function(x, unit = "", digits = 1) {
  if (is.null(x) || length(x) != 1L || !is.numeric(x) || !is.finite(x)) return("N/A")
  paste0(formatC(x, format = "f", digits = digits), unit)
}
safe_filename <- function(x) {
  x <- tolower(gsub("[^A-Za-z0-9]+", "_", x))
  gsub("^_+|_+$", "", x)
}
weather_theme <- function() {
  ggplot2::theme_minimal(base_size = 12) + ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold", colour = "#142D38", size = 14),
    plot.subtitle = ggplot2::element_text(colour = "#536B73", margin = ggplot2::margin(b = 14)),
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major.x = ggplot2::element_blank(),
    axis.title = ggplot2::element_text(colour = "#536B73"),
    plot.margin = ggplot2::margin(16, 16, 12, 12),
    legend.position = "bottom", legend.title = ggplot2::element_blank())
}
