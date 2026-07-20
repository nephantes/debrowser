utils::globalVariables(c("samples", "x", "y", "textName",
                         # Phase E1: ggplot2 NSE in enrichmentNesHeatmapServer.
                         ".data", "NES", "Label",
                         # Phase E11: ggplot2 NSE in plot_method_scatter.
                         "log2FC1", "log2FC2",
                         # Phase E11.11: ggplot2 NSE in plot_de_direction_bar
                         # and plot_de_pairwise_heatmap.
                         "comparison", "count", "direction",
                         "Group1", "Group2", "DEGs"))

# Install the compact DT layout as the package's global default. DT
# merges this with any per-call `options = list(...)`. The four call
# sites that previously passed `dom = "Blfrtip"` now pass
# `dom = .dt_dom_compact` directly; every other DT call in the app
# (mod_enrichment, mod_comparison_concordance, fgsea_results_table,
# sample-details panel) inherits this default and gets the same
# one-row-of-controls + compact-pagination layout for free.
.onLoad <- function(libname, pkgname) {
  current <- getOption("DT.options", default = list())
  if (is.null(current$dom)) {
    current$dom <- .dt_dom_compact
    options(DT.options = current)
  }
  # Register the package's static assets path BEFORE shinymanager's
  # secure_app wraps the request handler. The login screen renders
  # ahead of deUI, so deUI's own addResourcePath() runs too late for
  # head_auth scripts (legal/*.html links, remember_me.js, etc.) to
  # resolve. Calling it here at package-load time means every request
  # -- including the auth screen -- can resolve `www/...` URLs.
  if (requireNamespace("shiny", quietly = TRUE)) {
    www_dir <- system.file("extdata", "www", package = pkgname)
    if (nzchar(www_dir) && dir.exists(www_dir)) {
      tryCatch(shiny::addResourcePath("www", www_dir),
               error = function(e) NULL)
    }
  }
}
