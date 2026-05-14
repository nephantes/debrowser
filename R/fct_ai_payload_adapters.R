# R/fct_ai_payload_adapters.R
#
# Phase E12.B - per-shape payload adapters consumed by server.R AI
# panel reactives. Pure helpers; return NULL when inputs are
# insufficient.

# Local id-column sniffer. Mirrors the closure of the same name in
# server.R -- kept local here so this file's helpers are self-contained
# and unit-testable without booting the Shiny server.
.fgsea_id_col <- function(de) {
  if ("ID"   %in% names(de)) return("ID")
  if ("gene" %in% names(de)) return("gene")
  NA_character_
}

# Local %||% to avoid loading the entire mod_enrichment_gmt copy.
# Same definition as elsewhere in R/.
`%||%` <- function(a, b) if (is.null(a)) b else a

#' Build a `geneset` shape payload.
#'
#' Used by the Enrichment-tab AI mount across all 6 enrichment modes.
#' The caller is responsible for resolving `genes` from the selected
#' term (leading-edge for fgseaGSEA / core_enrichment for legacy GSEA /
#' getEntrezTable for the other 4 modes).
#'
#' @param genes chr. Symbols.
#' @param primary_de data.frame|NULL. Primary DE result; rows used for
#'   the stats slice when `genes` are matched.
#' @param term list|NULL. `list(term, pvalue, n_overlap)` for the
#'   selected enrichment term.
#' @param context_mode chr(1). UI hint, e.g. "enrichGO" / "fgseaGSEA".
#' @return list or NULL.
#' @keywords internal
#' @noRd
.build_geneset_payload <- function(genes, primary_de, term, context_mode) {
  if (is.null(genes) || length(genes) == 0L) return(NULL)
  stats <- NULL
  if (!is.null(primary_de) && is.data.frame(primary_de) &&
      nrow(primary_de) > 0L) {
    id_col <- .fgsea_id_col(primary_de)
    if (!is.na(id_col)) {
      keep <- as.character(primary_de[[id_col]]) %in% genes
      if (any(keep)) {
        stats <- data.frame(
          gene_id        = as.character(primary_de[[id_col]][keep]),
          log2FoldChange = primary_de$log2FoldChange[keep],
          padj           = primary_de$padj[keep],
          stringsAsFactors = FALSE
        )
      }
    }
  }
  list(
    shape        = "geneset",
    genes        = genes,
    stats        = stats,
    enrichment   = term,
    context_mode = context_mode
  )
}

#' Build a `de_table` shape payload (DE Analysis tab mount).
#'
#' @param filt_data data.frame. Filtered DE result (post-cutoff).
#' @param comparison_label chr(1). e.g. "Treat vs Ctrl".
#' @param top_n integer(1).
#' @param cutoffs list. `list(padj, lfc)`.
#' @return list or NULL.
#' @keywords internal
#' @noRd
.build_de_payload <- function(filt_data, comparison_label, top_n, cutoffs) {
  if (is.null(filt_data) || !is.data.frame(filt_data) ||
      nrow(filt_data) == 0L) return(NULL)
  id_col <- .fgsea_id_col(filt_data)
  if (is.na(id_col)) return(NULL)
  ord <- order(filt_data$padj, na.last = TRUE)
  top <- filt_data[ord, , drop = FALSE]
  top <- top[seq_len(min(top_n, nrow(top))), , drop = FALSE]
  list(
    shape            = "de_table",
    comparison_label = comparison_label,
    genes            = as.character(top[[id_col]]),
    stats            = data.frame(
      gene_id        = as.character(top[[id_col]]),
      log2FoldChange = top$log2FoldChange,
      padj           = top$padj,
      stringsAsFactors = FALSE
    ),
    n_total_de       = nrow(filt_data),
    cutoffs          = cutoffs
  )
}

#' Build a `concordance` shape payload (Concordance tab mount).
#'
#' @param de_results_list list of data.frame, named by comparison label.
#'   Each df has ID / log2FoldChange / padj.
#' @param concordance_table data.frame. Output of concordance_summary().
#' @param top_n integer(1).
#' @param cutoffs list. `list(padj, lfc)`.
#' @return list or NULL.
#' @keywords internal
#' @noRd
.build_concordance_payload <- function(de_results_list, concordance_table,
                                       top_n, cutoffs) {
  if (is.null(de_results_list) || length(de_results_list) < 2L) {
    return(NULL)
  }
  per <- lapply(de_results_list, function(df) {
    keep <- !is.na(df$padj) & df$padj <= cutoffs$padj &
            abs(df$log2FoldChange) >= (cutoffs$lfc %||% 0)
    sub <- df[keep, , drop = FALSE]
    if (nrow(sub) == 0L) return(sub)
    ord <- order(sub$padj, na.last = TRUE)
    sub <- sub[ord, , drop = FALSE]
    sub[seq_len(min(top_n, nrow(sub))), , drop = FALSE]
  })
  list(
    shape              = "concordance",
    comparison_labels  = names(de_results_list),
    concordance_table  = concordance_table,
    per_comparison_top = per,
    cutoffs            = cutoffs
  )
}

#' Filter the question dropdown choices for a given (shape, payload).
#'
#' Implements the matrix in spec section 5. The Enrichment-tab
#' `reconcile_enrichments` gating (needs NES across comparisons) is
#' triggered when `payload$enrichment$nes_across` is non-NULL --
#' server.R sets that attribute when the fgsea NES matrix has >=2
#' columns. Concordance `reconcile_enrichments` gating is triggered
#' when `payload$pathways_for_reconcile` is non-empty.
#'
#' @param shape chr(1). "geneset" | "de_table" | "concordance".
#' @param payload list|NULL. Current payload reactive value.
#' @return character vector of preset keys.
#' @keywords internal
#' @noRd
.applicable_questions <- function(shape, payload) {
  base <- switch(
    shape,
    "geneset"     = "summarize_geneset",
    "de_table"    = c("summarize_geneset", "suggest_followup", "draft_methods"),
    "concordance" = c("suggest_followup", "draft_methods"),
    character(0)
  )
  # Gate reconcile_enrichments
  if (shape == "geneset") {
    nes <- payload$enrichment$nes_across
    if (!is.null(nes) && NCOL(nes) >= 2L) {
      base <- c(base, "reconcile_enrichments")
    }
  }
  if (shape == "concordance") {
    p <- payload$pathways_for_reconcile
    if (!is.null(p) && length(p) > 0L) {
      base <- c(base, "reconcile_enrichments")
    }
  }
  base
}
