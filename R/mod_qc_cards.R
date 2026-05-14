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
#' qcLibraryDepthUI("libraryDepth")
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
#' \donttest{
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
#' qcDetectionRateUI("detectionRate")
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
#' \donttest{
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
#' qcMtPctUI("mtPct")
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
#' \donttest{
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
            "No mitochondrial genes detected. The matcher accepts ",
            "the human (MT-ND1, MT-CO1) and mouse (mt-Nd1, mt-Co1) ",
            "canonical symbols, the dash-stripped Ensembl variants ",
            "(MTND1, mtNd1), and the prefix-stripped suffixes ",
            "(ND1, Nd1)."
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
#' qcSampleDistUI("sampleDist")
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

# Internal: rendered when a post-DE QC card (5/6/7) is asked to render but
# the active comparison has no fitted DESeqDataSet. This happens before the
# user clicks Start DE or when the DE method was not DESeq2. Keeps the card
# visible (so the sidebar selector behaviour matches cards 1-4) but tells
# the user what to do to populate it.
#' @noRd
qc_card_empty_state_no_dds <- function() {
  div(
    class = "alert alert-info",
    "This QC card requires a fitted DESeqDataSet. Run a DESeq2 ",
    "differential-expression analysis from the Condition Selection step ",
    "and then return to this tab."
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
#' \donttest{
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
      withProgress(message = "Drawing sample distance heatmap", style = "notification", value = 0.1, {
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
# Card 5: DESeq2 dispersion estimates (post-DE)
# ---------------------------------------------------------------------------

#' qcDispersionUI
#'
#' UI factory for the DESeq2 dispersion-estimates QC card. The body is a
#' `uiOutput` so the server can switch between the base-R dispersion plot
#' and an empty-state alert when no fitted `DESeqDataSet` is available.
#'
#' @param id character, namespace id
#' @return a `bslib::card` tagList
#' @examples
#' qcDispersionUI("dispersion")
#' @export
qcDispersionUI <- function(id) {
  ns <- NS(id)
  de_card(
    title = "Dispersion Estimates (DESeq2)",
    uiOutput(ns("body")),
    helpText(
      paste0(
        "Black: gene-wise estimates. Red: fitted trend. ",
        "Blue: final shrunken values used by Wald/LRT. ",
        "Outlier genes (circled) escape shrinkage."
      )
    ),
    download_id = NULL
  )
}

#' debrowserqcdispersion
#'
#' Server factory for the dispersion-estimates QC card. Wraps
#' \code{DESeq2::plotDispEsts(dds)} in `renderPlot` (base-R graphics, not
#' plotly). Renders an empty-state alert when `dds` is NULL (no DE run yet,
#' or method was not DESeq2).
#'
#' @param id character, namespace id matching `qcDispersionUI(id)`
#' @param dds A fitted `DESeqDataSet`, or NULL.
#' @return invisible(NULL); wires `output$body` and `output$plot`.
#' @examples
#' \donttest{
#' debrowserqcdispersion("dispersion", dds)
#' }
#' @export
debrowserqcdispersion <- function(id, dds = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    output$body <- renderUI({
      if (is.null(dds)) {
        qc_card_empty_state_no_dds()
      } else {
        plotOutput(ns("plot"), height = "500px")
      }
    })
    output$plot <- renderPlot({
      req(dds)
      withProgress(message = "Drawing dispersion plot", style = "notification", value = 0.1, {
        DESeq2::plotDispEsts(dds)
      })
    })
  })
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Card 6: Size factors vs library size (post-DE)
# ---------------------------------------------------------------------------

#' qcSizeFactorsUI
#'
#' UI factory for the size-factors-vs-library-size QC card. The body is a
#' `uiOutput` so the server can render the comparison plot or an empty-state
#' alert when no fitted `DESeqDataSet` is available.
#'
#' @param id character, namespace id
#' @return a `bslib::card` tagList
#' @examples
#' qcSizeFactorsUI("sizeFactors")
#' @export
qcSizeFactorsUI <- function(id) {
  ns <- NS(id)
  de_card(
    title = "Size Factors vs Library Size",
    uiOutput(ns("body")),
    helpText(
      paste0(
        "Per-sample DESeq2 size factor and raw library size, both rescaled ",
        "to [0, 1]. Spearman rho close to 1 confirms size factors track ",
        "depth without unexpected composition shifts."
      )
    ),
    download_id = ns("dl")
  )
}

#' debrowserqcsizefactors
#'
#' Server factory for the size-factors-vs-library-size QC card. Computes
#' \code{\link{size_factor_library_summary}} and renders two scaled bars per
#' sample plus the Spearman correlation in the subtitle.
#'
#' @param id character, namespace id matching `qcSizeFactorsUI(id)`
#' @param dds A fitted `DESeqDataSet`, or NULL.
#' @param selected_samples Optional character vector of sample names to
#'   show. NULL (default) shows every sample in the dds; otherwise only
#'   bars for samples whose name is in `selected_samples` are rendered
#'   (mirrors the QC sidebar's column-selector behaviour).
#' @return invisible(NULL); wires `output$body`, `output$plot`, and
#'   `output$dl`.
#' @examples
#' \donttest{
#' debrowserqcsizefactors("sizeFactors", dds)
#' }
#' @export
debrowserqcsizefactors <- function(id, dds = NULL,
                                   selected_samples = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    df_react <- reactive({
      req(dds)
      out <- size_factor_library_summary(dds)
      if (!is.null(selected_samples)) {
        out <- out[out$sample %in% selected_samples, , drop = FALSE]
      }
      out
    })
    output$body <- renderUI({
      if (is.null(dds)) {
        qc_card_empty_state_no_dds()
      } else {
        plotly::plotlyOutput(ns("plot"), height = "500px")
      }
    })
    output$plot <- plotly::renderPlotly({
      df <- df_react()
      df$sample <- factor(df$sample, levels = df$sample)
      rho <- attr(df, "spearman_rho")
      subtitle <- if (is.finite(rho)) {
        sprintf("Spearman rho = %.3f", rho)
      } else {
        "Spearman rho: n/a"
      }
      p <- plotly::plot_ly(df) |>
        plotly::add_bars(
          x = ~sample, y = ~sf_scaled,
          name = "Size factor (scaled)",
          marker = list(color = "#4F81BD"),
          hovertext = ~sprintf("size factor: %.3f", size_factor),
          hoverinfo = "text+name"
        ) |>
        plotly::add_bars(
          x = ~sample, y = ~lib_scaled,
          name = "Library size (scaled)",
          marker = list(color = "#C0504D"),
          hovertext = ~sprintf("library size: %s",
                               formatC(library_size, format = "d",
                                       big.mark = ",")),
          hoverinfo = "text+name"
        ) |>
        plotly::layout(
          barmode = "group",
          xaxis = list(title = "", categoryorder = "array",
                       categoryarray = as.character(df$sample)),
          yaxis = list(title = "Scaled value [0, 1]", range = c(0, 1.05)),
          legend = list(orientation = "h", x = 0, y = -0.15),
          annotations = list(list(
            text = subtitle, x = 1, y = 1.06, xref = "paper", yref = "paper",
            xanchor = "right", showarrow = FALSE
          ))
        )
      p$elementId <- NULL
      p
    })
    output$dl <- downloadHandler(
      filename = function() "size_factors_vs_library_size.csv",
      content = function(file) {
        df <- df_react()
        # Drop attributes for the CSV (keep them visible only in the UI).
        utils::write.csv(as.data.frame(df), file, row.names = FALSE)
      }
    )
  })
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Card 7: Cook's distance outlier counts (post-DE)
# ---------------------------------------------------------------------------

#' qcCooksUI
#'
#' UI factory for the Cook's-distance outlier-count QC card. The body is a
#' `uiOutput` so the server can switch between the bar plot and an
#' empty-state alert when no fitted `DESeqDataSet` is available.
#'
#' @param id character, namespace id
#' @return a `bslib::card` tagList
#' @examples
#' qcCooksUI("cooks")
#' @export
qcCooksUI <- function(id) {
  ns <- NS(id)
  de_card(
    title = "Cook's Outlier Counts",
    uiOutput(ns("body")),
    helpText(
      paste0(
        "Per-sample count of genes whose Cook's distance exceeds the ",
        "DESeq2 vignette threshold 4 / (n_samples - n_params). ",
        "Disproportionately high bars flag samples that drove DE calls."
      )
    ),
    download_id = ns("dl")
  )
}

#' debrowserqccooks
#'
#' Server factory for the Cook's-distance outlier-count QC card. Computes
#' \code{\link{cooks_outlier_summary}} and renders a vertical bar of
#' `n_high_cooks` per sample. Subtitle reports the active threshold.
#'
#' @param id character, namespace id matching `qcCooksUI(id)`
#' @param dds A fitted `DESeqDataSet`, or NULL.
#' @param selected_samples Optional character vector of sample names to
#'   show. NULL (default) shows every sample in the dds; otherwise only
#'   bars for samples whose name is in `selected_samples` are rendered
#'   (mirrors the QC sidebar's column-selector behaviour).
#' @return invisible(NULL); wires `output$body`, `output$plot`, and
#'   `output$dl`.
#' @examples
#' \donttest{
#' debrowserqccooks("cooks", dds)
#' }
#' @export
debrowserqccooks <- function(id, dds = NULL,
                             selected_samples = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    df_react <- reactive({
      req(dds)
      out <- cooks_outlier_summary(dds)
      thr <- attr(out, "threshold")
      if (!is.null(selected_samples)) {
        out <- out[out$sample %in% selected_samples, , drop = FALSE]
        attr(out, "threshold") <- thr
      }
      out
    })
    output$body <- renderUI({
      if (is.null(dds)) {
        qc_card_empty_state_no_dds()
      } else {
        plotly::plotlyOutput(ns("plot"), height = "500px")
      }
    })
    output$plot <- plotly::renderPlotly({
      withProgress(message = "Drawing Cook's distance plot", style = "notification", value = 0.1, {
        df <- df_react()
        df$sample <- factor(df$sample, levels = df$sample)
        thr <- attr(df, "threshold")
        subtitle <- if (is.finite(thr)) {
          sprintf("Threshold: %.3f", thr)
        } else {
          "Threshold: n/a"
        }
        p <- plotly::plot_ly(
          df, x = ~sample, y = ~n_high_cooks, type = "bar",
          marker = list(color = "#4F81BD"),
          hovertext = ~sprintf("%d / %d genes (%.2f%%)",
                               n_high_cooks, total_genes, high_cooks_pct),
          hoverinfo = "text"
        ) |>
          plotly::layout(
            xaxis = list(title = "", categoryorder = "array",
                         categoryarray = as.character(df$sample)),
            yaxis = list(title = "High-Cook genes"),
            annotations = list(list(
              text = subtitle, x = 1, y = 1.06, xref = "paper", yref = "paper",
              xanchor = "right", showarrow = FALSE
            ))
          )
        p$elementId <- NULL
        p
      })
    })
    output$dl <- downloadHandler(
      filename = function() "cooks_outliers.csv",
      content = function(file) {
        utils::write.csv(as.data.frame(df_react()), file, row.names = FALSE)
      }
    )
  })
  invisible(NULL)
}
