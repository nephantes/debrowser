# mod_qc_cards.R
# Phase E4 Task 2: always-on QC card modules.
# Each card consumes the pure helpers from R/fct_qc.R (library_depth_summary,
# detection_rate, mt_pct_per_sample, sample_distance_matrix). UI factories
# wrap the plot in de_card() with a download button; server factories take
# plain (non-reactive) data values from the caller.

# ---------------------------------------------------------------------------
# Card 1: Library depth
# ---------------------------------------------------------------------------

#' qcLibraryDepthUI
#'
#' UI factory for the library-depth QC card. Renders a `de_card` containing
#' a `plotly` bar of total counts per sample (with a CSV download button) and
#' a one-line caption explaining the 2-SD outlier flag.
#'
#' @param id character, namespace id
#' @return a `bslib::card` tagList
#' @examples
#' \dontrun{
#' qcLibraryDepthUI("libraryDepth")
#' }
#' @export
qcLibraryDepthUI <- function(id) {
  ns <- NS(id)
  de_card(
    title = "Library Depth",
    plotly::plotlyOutput(ns("plot"), height = "500px"),
    helpText(
      "Total counts per sample. Samples flagged red are >2 SD below the mean."
    ),
    download_id = ns("dl")
  )
}

#' debrowserqclibrarydepth
#'
#' Server factory for the library-depth QC card. Computes per-sample depth via
#' \code{\link{library_depth_summary}} and renders a horizontal `plotly` bar
#' colored by the optional `group_col`. Outliers (>2 SD from the mean depth)
#' are drawn with a red marker outline.
#'
#' @param id character, namespace id matching `qcLibraryDepthUI(id)`
#' @param counts numeric matrix or data.frame (rows = features,
#'   cols = samples); the module no-ops if NULL
#' @param meta optional metadata data.frame with a `samples` column
#' @param group_col optional name of a column in `meta` used to color bars
#' @return invisible(NULL); the module wires `output$plot` and `output$dl`
#' @examples
#' \dontrun{
#' debrowserqclibrarydepth("libraryDepth", counts, meta, "samples")
#' }
#' @export
debrowserqclibrarydepth <- function(id, counts = NULL, meta = NULL,
                                    group_col = NULL) {
  if (is.null(counts)) {
    return(invisible(NULL))
  }
  moduleServer(id, function(input, output, session) {
    df_react <- reactive({
      req(counts)
      library_depth_summary(counts, meta, group_col)
    })

    output$plot <- plotly::renderPlotly({
      df <- df_react()
      has_group <- !all(is.na(df$group))
      # Use the same factor order as the data so the y-axis matches input.
      df$sample <- factor(df$sample, levels = df$sample)
      line_col <- ifelse(df$is_outlier_2sd, "red", "rgba(0,0,0,0)")
      line_w   <- ifelse(df$is_outlier_2sd, 2, 0)

      p <- if (has_group) {
        plotly::plot_ly(
          df,
          x = ~depth,
          y = ~sample,
          color = ~group,
          type = "bar",
          orientation = "h",
          marker = list(line = list(color = line_col, width = line_w))
        )
      } else {
        plotly::plot_ly(
          df,
          x = ~depth,
          y = ~sample,
          type = "bar",
          orientation = "h",
          marker = list(
            color = "#4F81BD",
            line = list(color = line_col, width = line_w)
          )
        )
      }
      p <- plotly::layout(
        p,
        xaxis = list(title = "Total counts"),
        yaxis = list(title = "", autorange = "reversed"),
        margin = list(l = 120)
      )
      p$elementId <- NULL
      p
    })

    output$dl <- downloadHandler(
      filename = function() "library_depth.csv",
      content = function(file) {
        utils::write.csv(df_react(), file, row.names = FALSE)
      }
    )
  })
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Card 2: Detection rate
# ---------------------------------------------------------------------------

#' qcDetectionRateUI
#'
#' UI factory for the feature-detection-rate QC card. Renders a `de_card`
#' containing a `plotly` bar of detection percentage per sample plus a one-line
#' caption.
#'
#' @param id character, namespace id
#' @return a `bslib::card` tagList
#' @examples
#' \dontrun{
#' qcDetectionRateUI("detectionRate")
#' }
#' @export
qcDetectionRateUI <- function(id) {
  ns <- NS(id)
  de_card(
    title = "Feature Detection Rate",
    plotly::plotlyOutput(ns("plot"), height = "500px"),
    helpText(
      "Percentage of features with non-zero counts per sample."
    ),
    download_id = ns("dl")
  )
}

#' debrowserqcdetectionrate
#'
#' Server factory for the feature-detection-rate QC card. Computes
#' \code{\link{detection_rate}} and renders a horizontal `plotly` bar of
#' `detection_pct` per sample.
#'
#' @param id character, namespace id matching `qcDetectionRateUI(id)`
#' @param counts numeric matrix or data.frame (rows = features,
#'   cols = samples); the module no-ops if NULL
#' @return invisible(NULL); the module wires `output$plot` and `output$dl`
#' @examples
#' \dontrun{
#' debrowserqcdetectionrate("detectionRate", counts)
#' }
#' @export
debrowserqcdetectionrate <- function(id, counts = NULL) {
  if (is.null(counts)) {
    return(invisible(NULL))
  }
  moduleServer(id, function(input, output, session) {
    df_react <- reactive({
      req(counts)
      detection_rate(counts)
    })

    output$plot <- plotly::renderPlotly({
      df <- df_react()
      df$sample <- factor(df$sample, levels = df$sample)
      p <- plotly::plot_ly(
        df,
        x = ~detection_pct,
        y = ~sample,
        type = "bar",
        orientation = "h",
        marker = list(color = "#4F81BD")
      )
      p <- plotly::layout(
        p,
        xaxis = list(title = "Detection %", range = c(0, 100)),
        yaxis = list(title = "", autorange = "reversed"),
        margin = list(l = 120)
      )
      p$elementId <- NULL
      p
    })

    output$dl <- downloadHandler(
      filename = function() "detection_rate.csv",
      content = function(file) {
        utils::write.csv(df_react(), file, row.names = FALSE)
      }
    )
  })
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Card 3: % mitochondrial reads
# ---------------------------------------------------------------------------

#' qcMtPctUI
#'
#' UI factory for the mitochondrial-percentage QC card. The body is a
#' `uiOutput` so the server can switch between a plot and an empty-state alert
#' when no MT genes are detected.
#'
#' @param id character, namespace id
#' @return a `bslib::card` tagList
#' @examples
#' \dontrun{
#' qcMtPctUI("mtPct")
#' }
#' @export
qcMtPctUI <- function(id) {
  ns <- NS(id)
  de_card(
    title = "Mitochondrial Read %",
    uiOutput(ns("body")),
    download_id = ns("dl")
  )
}

#' debrowserqcmtpct
#'
#' Server factory for the mitochondrial-percentage QC card. Computes
#' \code{\link{mt_pct_per_sample}} and either renders a `plotly` bar with a
#' horizontal threshold line at `threshold_pct`, or an empty-state info alert
#' when no MT genes are detected.
#'
#' @param id character, namespace id matching `qcMtPctUI(id)`
#' @param counts numeric matrix or data.frame (rows = features,
#'   cols = samples); the module no-ops if NULL
#' @param threshold_pct numeric, the horizontal warning threshold drawn over
#'   the bar plot (default 5)
#' @return invisible(NULL); the module wires `output$body`, `output$plot`,
#'   and `output$dl`
#' @examples
#' \dontrun{
#' debrowserqcmtpct("mtPct", counts, threshold_pct = 5)
#' }
#' @export
debrowserqcmtpct <- function(id, counts = NULL, threshold_pct = 5) {
  if (is.null(counts)) {
    return(invisible(NULL))
  }
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    df_react <- reactive({
      req(counts)
      mt_pct_per_sample(counts)
    })

    output$body <- renderUI({
      df <- df_react()
      if (nrow(df) == 0) {
        div(
          class = "alert alert-info",
          paste0(
            "No mitochondrial gene IDs (^MT-/^mt-/Mt-) detected ",
            "in this dataset."
          )
        )
      } else {
        plotly::plotlyOutput(ns("plot"), height = "500px")
      }
    })

    output$plot <- plotly::renderPlotly({
      df <- df_react()
      req(nrow(df) > 0)
      df$sample <- factor(df$sample, levels = df$sample)
      p <- plotly::plot_ly(
        df,
        x = ~sample,
        y = ~mt_pct,
        type = "bar",
        marker = list(color = "#4F81BD")
      )
      p <- plotly::layout(
        p,
        xaxis = list(title = "", categoryorder = "array",
                     categoryarray = as.character(df$sample)),
        yaxis = list(title = "MT %"),
        shapes = list(
          list(
            type = "line",
            x0 = -0.5, x1 = nrow(df) - 0.5,
            y0 = threshold_pct, y1 = threshold_pct,
            xref = "x", yref = "y",
            line = list(color = "red", width = 2, dash = "dash")
          )
        )
      )
      p$elementId <- NULL
      p
    })

    output$dl <- downloadHandler(
      filename = function() "mt_pct.csv",
      content = function(file) {
        utils::write.csv(df_react(), file, row.names = FALSE)
      }
    )
  })
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Card 4: Sample distance heatmap
# ---------------------------------------------------------------------------

#' qcSampleDistUI
#'
#' UI factory for the sample-distance QC card. Renders a `de_card` containing
#' a `heatmaply` heatmap and a caption explaining the distance metric.
#'
#' @param id character, namespace id
#' @return a `bslib::card` tagList
#' @examples
#' \dontrun{
#' qcSampleDistUI("sampleDist")
#' }
#' @export
qcSampleDistUI <- function(id) {
  ns <- NS(id)
  de_card(
    title = "Sample Distance Heatmap",
    plotly::plotlyOutput(ns("plot"), height = "600px"),
    helpText(
      paste0(
        "Euclidean distance on VST-transformed counts. ",
        "Samples that cluster together are most similar."
      )
    ),
    download_id = ns("dl")
  )
}

#' debrowserqcsampledist
#'
#' Server factory for the sample-distance heatmap. Computes
#' \code{\link{sample_distance_matrix}} and renders it via
#' \code{heatmaply::heatmaply}.
#'
#' @param id character, namespace id matching `qcSampleDistUI(id)`
#' @param counts numeric matrix or data.frame (rows = features,
#'   cols = samples); the module no-ops if NULL
#' @return invisible(NULL); the module wires `output$plot` and `output$dl`
#' @examples
#' \dontrun{
#' debrowserqcsampledist("sampleDist", counts)
#' }
#' @export
debrowserqcsampledist <- function(id, counts = NULL) {
  if (is.null(counts)) {
    return(invisible(NULL))
  }
  moduleServer(id, function(input, output, session) {
    dist_react <- reactive({
      req(counts)
      sample_distance_matrix(counts)
    })

    output$plot <- plotly::renderPlotly({
      dist_mat <- dist_react()
      p <- heatmaply::heatmaply(
        dist_mat,
        Rowv = TRUE,
        Colv = TRUE,
        dendrogram = "both"
      )
      p$elementId <- NULL
      p
    })

    output$dl <- downloadHandler(
      filename = function() "sample_distance.csv",
      content = function(file) {
        utils::write.csv(dist_react(), file, row.names = TRUE)
      }
    )
  })
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Card 8: Mapping / rRNA stats (sidecar stub)
# ---------------------------------------------------------------------------

#' qcMappingStatsUI
#'
#' UI factory for the mapping/rRNA stats QC card. Empty-state stub: renders
#' an info block describing the optional sidecar TSV format and a disabled
#' file input. The upload handler is a follow-up; this round ships the
#' affordance only.
#'
#' @param id character, namespace id
#' @return a `bslib::card` tagList
#' @examples
#' \dontrun{
#' qcMappingStatsUI("mappingStats")
#' }
#' @export
qcMappingStatsUI <- function(id) {
  ns <- NS(id)
  de_card(
    title = "Mapping / rRNA Stats",
    div(
      class = "alert alert-info",
      tags$p(
        "Optional: upload a TSV with columns ",
        tags$code("sample"), ", ",
        tags$code("mapped_pct"), ", ",
        tags$code("rRNA_pct"),
        " to populate this card."
      ),
      tags$p(
        tags$small(
          "Mapping rate and rRNA contamination cannot be computed from",
          " the count matrix alone — they require alignment-time",
          " statistics (e.g. STAR / HISAT2 logs or Picard",
          " CollectRnaSeqMetrics output)."
        )
      )
    ),
    fileInput(
      ns("sidecar"),
      label = "Mapping stats TSV (handler not yet wired)",
      accept = c(".tsv", ".txt", "text/tab-separated-values")
    )
  )
}

#' debrowserqcmappingstats
#'
#' Server factory for the mapping/rRNA stats QC card. Stub only —
#' parses no upload, renders no plot. Reserved for a follow-up that wires
#' the actual sidecar handler when the format is finalised.
#'
#' @param id character, namespace id matching `qcMappingStatsUI(id)`
#' @return invisible(NULL); the module installs no observers in this round
#' @examples
#' \dontrun{
#' debrowserqcmappingstats("mappingStats")
#' }
#' @export
debrowserqcmappingstats <- function(id) {
  moduleServer(id, function(input, output, session) {
    invisible(NULL)
  })
  invisible(NULL)
}
