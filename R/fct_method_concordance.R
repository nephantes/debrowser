# R/fct_method_concordance.R
#
# Phase E11 -- Statistical method concordance.
#
# Pure helpers consumed by R/mod_method_concordance.R. No Shiny calls;
# all error paths go through de_error() so callers can class-dispatch.

#' Run multiple DE methods on the same comparison.
#'
#' Wraps [run_de()] for each requested method and returns a named list
#' of per-method result data.frames keyed by `methods`. The returned
#' frames are normalized to a common shape:
#' `data.frame(ID, log2FoldChange, padj, pvalue, stat)` so downstream
#' helpers can join by `ID` without per-method special-casing.
#'
#' DESeq2's native return is a `DESeqResults` object -- coerced via
#' `as.data.frame()`. edgeR / limma already return data.frames.
#'
#' @param counts Numeric count matrix or data.frame (genes x samples).
#' @param metadata Sample metadata data.frame.
#' @param columns Character vector of sample column names to use.
#' @param conds Factor of conditions, length == length(columns).
#' @param methods Character vector of method names; subset of
#'   `c("DESeq2", "EdgeR", "Limma")`. Default all three.
#' @param params_per_method Optional named list keyed by method name
#'   whose values are the per-method `params` list passed to [run_de()].
#'   Missing methods get an empty list (defaults take over inside the
#'   per-method runner).
#' @return Named list of per-method data.frames with columns ID,
#'   log2FoldChange, padj, pvalue, stat. `length()` equals
#'   `length(methods)`. Methods that error out are dropped from the
#'   returned list and a warning is signalled (not an error) so partial
#'   results remain usable.
#' @examples
#' set.seed(42)
#' counts <- matrix(
#'   as.integer(abs(rnorm(60, mean = 100, sd = 30))),
#'   nrow = 10, ncol = 6,
#'   dimnames = list(paste0("G", 1:10), paste0("S", 1:6))
#' )
#' conds <- c("Cond1", "Cond1", "Cond1", "Cond2", "Cond2", "Cond2")
#' run_de_methods(counts, columns = colnames(counts), conds = conds,
#'                methods = c("EdgeR", "Limma"))
#' @export
run_de_methods <- function(counts, metadata = NULL, columns = NULL,
                           conds = NULL,
                           methods = c("DESeq2", "EdgeR", "Limma"),
                           params_per_method = list()) {
  de_assert_count_matrix(counts)
  if (length(methods) == 0L) {
    de_error("methods must be a non-empty character vector",
             class = "empty_input")
  }
  out <- list()
  for (m in methods) {
    p <- if (!is.null(params_per_method[[m]])) params_per_method[[m]] else list()
    res <- tryCatch(
      run_de(m, counts, metadata, columns, conds, p),
      error = function(e) {
        warning(sprintf("DE method '%s' failed: %s", m, conditionMessage(e)),
                call. = FALSE)
        NULL
      }
    )
    if (is.null(res)) next
    df <- as.data.frame(res)
    df$ID <- rownames(df)
    keep <- intersect(c("ID", "log2FoldChange", "padj", "pvalue", "stat"),
                      names(df))
    out[[m]] <- df[, keep, drop = FALSE]
  }
  out
}

#' Build per-method significant-gene sets.
#'
#' @param de_list Output of [run_de_methods()].
#' @param padj_cutoff Maximum padj for "significant" (default 0.05).
#' @param lfc_cutoff Minimum |log2FoldChange| for "significant"
#'   (default 0; pass 0.585 for |fold|>=1.5, 1 for |fold|>=2).
#' @return Named list of character vectors of significant gene IDs.
#'   Names match `names(de_list)`.
#' @examples
#' de_list <- list(
#'   EdgeR = data.frame(ID = paste0("G", 1:5),
#'     log2FoldChange = c(2, -1, 0, 3, -2),
#'     padj = c(0.01, 0.04, 0.5, 0.02, 0.03)),
#'   Limma = data.frame(ID = paste0("G", 1:5),
#'     log2FoldChange = c(1.8, -0.9, 0.1, 2.5, -1.8),
#'     padj = c(0.02, 0.03, 0.6, 0.01, 0.04))
#' )
#' concordance_sets(de_list, padj_cutoff = 0.05)
#' @export
concordance_sets <- function(de_list, padj_cutoff = 0.05, lfc_cutoff = 0) {
  if (length(de_list) == 0L) {
    de_error("de_list is empty", class = "empty_input")
  }
  lapply(de_list, function(df) {
    keep <- !is.na(df$padj) & df$padj <= padj_cutoff &
      !is.na(df$log2FoldChange) &
      abs(df$log2FoldChange) >= lfc_cutoff
    df$ID[keep]
  })
}

#' Pairwise concordance summary across DE methods.
#'
#' For each unordered pair of methods, computes set sizes, intersection
#' size, Jaccard index, and Spearman correlation of log2FoldChange over
#' the set of genes present in both per-method tables (excluding NAs).
#'
#' @inheritParams concordance_sets
#' @return data.frame with one row per pair, columns:
#'   `method1`, `method2`, `n_method1`, `n_method2`, `n_overlap`,
#'   `jaccard`, `spearman_lfc`, `n_genes_compared`. Empty data.frame
#'   (zero rows) when fewer than 2 methods are present.
#' @examples
#' de_list <- list(
#'   EdgeR = data.frame(ID = paste0("G", 1:5),
#'     log2FoldChange = c(2, -1, 0, 3, -2),
#'     padj = c(0.01, 0.04, 0.5, 0.02, 0.03)),
#'   Limma = data.frame(ID = paste0("G", 1:5),
#'     log2FoldChange = c(1.8, -0.9, 0.1, 2.5, -1.8),
#'     padj = c(0.02, 0.03, 0.6, 0.01, 0.04))
#' )
#' concordance_summary(de_list, padj_cutoff = 0.05)
#' @export
concordance_summary <- function(de_list, padj_cutoff = 0.05,
                                lfc_cutoff = 0) {
  empty <- data.frame(
    method1 = character(), method2 = character(),
    n_method1 = integer(), n_method2 = integer(),
    n_overlap = integer(), jaccard = numeric(),
    spearman_lfc = numeric(), n_genes_compared = integer(),
    stringsAsFactors = FALSE
  )
  if (length(de_list) < 2L) return(empty)
  sets <- concordance_sets(de_list, padj_cutoff, lfc_cutoff)
  nms <- names(de_list)
  pairs <- utils::combn(nms, 2L, simplify = FALSE)
  rows <- lapply(pairs, function(p) {
    a <- p[[1]]; b <- p[[2]]
    sa <- sets[[a]]; sb <- sets[[b]]
    inter <- intersect(sa, sb)
    uni <- union(sa, sb)
    jac <- if (length(uni) == 0L) NA_real_ else length(inter) / length(uni)
    da <- de_list[[a]]; db <- de_list[[b]]
    common <- intersect(da$ID, db$ID)
    la <- da$log2FoldChange[match(common, da$ID)]
    lb <- db$log2FoldChange[match(common, db$ID)]
    ok <- is.finite(la) & is.finite(lb)
    rho <- if (sum(ok) >= 3L) {
      suppressWarnings(stats::cor(la[ok], lb[ok], method = "spearman"))
    } else {
      NA_real_
    }
    data.frame(
      method1 = a, method2 = b,
      n_method1 = length(sa), n_method2 = length(sb),
      n_overlap = length(inter),
      jaccard = jac,
      spearman_lfc = rho,
      n_genes_compared = sum(ok),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, c(list(empty), rows))
}

#' UpSet plot of DE-gene overlap across methods.
#'
#' Gated by `require_pkg("UpSetR")`. Returns the `UpSetR::upset()`
#' object -- caller (renderPlot) is responsible for printing.
#'
#' @inheritParams concordance_sets
#' @return Result of `UpSetR::upset()` (a list with class `"upset"`).
#'   When fewer than 2 methods produce non-empty sets, returns NULL
#'   (caller should render an empty-state instead).
#' @examples
#' if (requireNamespace("UpSetR", quietly = TRUE)) {
#'   de_list <- list(
#'     EdgeR = data.frame(ID = paste0("G", 1:5),
#'       log2FoldChange = c(2, -1, 0, 3, -2),
#'       padj = c(0.01, 0.04, 0.5, 0.02, 0.03)),
#'     Limma = data.frame(ID = paste0("G", 1:5),
#'       log2FoldChange = c(1.8, -0.9, 0.1, 2.5, -1.8),
#'       padj = c(0.02, 0.03, 0.6, 0.01, 0.04))
#'   )
#'   plot_method_upset(de_list)
#' }
#' @export
plot_method_upset <- function(de_list, padj_cutoff = 0.05,
                              lfc_cutoff = 0) {
  require_pkg("UpSetR", feature = "Method-concordance UpSet plot")
  sets <- concordance_sets(de_list, padj_cutoff, lfc_cutoff)
  sets <- sets[vapply(sets, length, integer(1)) > 0L]
  if (length(sets) < 2L) return(NULL)
  UpSetR::upset(
    UpSetR::fromList(sets),
    nsets = length(sets),
    order.by = "freq",
    sets.bar.color = "#3c7eb8",
    main.bar.color = "#444444",
    text.scale = 1.2
  )
}

#' Pairwise log2FC scatter between two named entries of a DE list.
#'
#' Joins the two per-entry tables on gene ID and renders a scatter of
#' log2FoldChange (id1 on x, id2 on y). Spearman rho appears in the
#' subtitle. The y=x reference line is drawn dashed.
#'
#' Generic across "DE list dimensions": entries can be DE methods on the
#' same comparison, OR comparisons on the same method, OR any other
#' axis as long as each named entry contains a `data.frame(ID,
#' log2FoldChange, ...)`.
#'
#' @param de_list Named list of DE result data.frames (each with at
#'   minimum `ID` and `log2FoldChange` columns).
#' @param id1,id2 Names present in `names(de_list)` to put on x and y.
#' @return ggplot object.
#' @examples
#' de_list <- list(
#'   EdgeR = data.frame(ID = paste0("G", 1:5),
#'     log2FoldChange = c(2, -1, 0, 3, -2),
#'     padj = c(0.01, 0.04, 0.5, 0.02, 0.03)),
#'   Limma = data.frame(ID = paste0("G", 1:5),
#'     log2FoldChange = c(1.8, -0.9, 0.1, 2.5, -1.8),
#'     padj = c(0.02, 0.03, 0.6, 0.01, 0.04))
#' )
#' plot_method_scatter(de_list, id1 = "EdgeR", id2 = "Limma")
#' @export
plot_method_scatter <- function(de_list, id1, id2) {
  if (!all(c(id1, id2) %in% names(de_list))) {
    de_error(
      sprintf("Names not in de_list: %s",
              paste(setdiff(c(id1, id2), names(de_list)),
                    collapse = ", ")),
      class = "unknown_de_method"
    )
  }
  d1 <- de_list[[id1]]
  d2 <- de_list[[id2]]
  common <- intersect(d1$ID, d2$ID)
  if (length(common) == 0L) {
    de_error("No common genes between the two entries.",
             class = "empty_input")
  }
  df <- data.frame(
    ID = common,
    log2FC1 = d1$log2FoldChange[match(common, d1$ID)],
    log2FC2 = d2$log2FoldChange[match(common, d2$ID)],
    stringsAsFactors = FALSE
  )
  df <- df[is.finite(df$log2FC1) & is.finite(df$log2FC2), , drop = FALSE]
  rho <- if (nrow(df) >= 3L) {
    suppressWarnings(stats::cor(df$log2FC1, df$log2FC2, method = "spearman"))
  } else {
    NA_real_
  }
  subtitle <- if (is.finite(rho)) {
    sprintf("Spearman rho = %.3f  (n = %d)", rho, nrow(df))
  } else {
    sprintf("Spearman rho = NA  (n = %d)", nrow(df))
  }
  ggplot2::ggplot(df,
                  ggplot2::aes(x = log2FC1, y = log2FC2)) +
    ggplot2::geom_point(alpha = 0.4, size = 0.8) +
    ggplot2::geom_abline(slope = 1, intercept = 0,
                         linetype = "dashed", color = "grey40") +
    ggplot2::geom_hline(yintercept = 0, color = "grey80") +
    ggplot2::geom_vline(xintercept = 0, color = "grey80") +
    ggplot2::labs(
      x = sprintf("%s log2FC", id1),
      y = sprintf("%s log2FC", id2),
      title = sprintf("%s vs %s", id1, id2),
      subtitle = subtitle
    ) +
    ggplot2::theme_classic()
}

#' Build unique display labels for a list of comparisons.
#'
#' Each comparison contributes a label "<treatment> vs <control>" derived
#' from its `cond_names` field. When two comparisons collide on the
#' same label, suffixes " (1)", " (2)", ... are appended in input order
#' so `names()` of the final list stays unique. Comparisons missing
#' `cond_names` fall back to "comparison_<index>".
#'
#' @param comparisons List of per-comparison entries (typically `dc()`
#'   from server.R or `comparisons_spec()`); each entry should have a
#'   `cond_names` character vector of length >= 2 (treatment first).
#' @return Character vector of length `length(comparisons)`. Empty
#'   character vector when input is empty.
#' @examples
#' comparisons <- list(
#'   list(cond_names = c("Treat", "Ctrl")),
#'   list(cond_names = c("Drug", "Vehicle"))
#' )
#' comparison_labels(comparisons)
#' @export
comparison_labels <- function(comparisons) {
  if (length(comparisons) == 0L) return(character(0))
  base <- vapply(seq_along(comparisons), function(i) {
    cn <- comparisons[[i]]$cond_names
    if (!is.null(cn) && length(cn) >= 2L) {
      paste(cn[1], "vs", cn[2])
    } else {
      paste0("comparison_", i)
    }
  }, character(1))
  out <- base
  for (lbl in unique(base)) {
    idx <- which(base == lbl)
    if (length(idx) > 1L) {
      out[idx] <- paste0(lbl, " (", seq_along(idx), ")")
    }
  }
  out
}

#' Per-entry up / down / total significant gene counts.
#'
#' Counts significant genes per entry of a named DE-results list at the
#' given padj / |log2FoldChange| cutoffs. Up = significant + log2FC > 0;
#' Down = significant + log2FC < 0. NA padj / NA log2FoldChange are
#' treated as not-significant.
#'
#' @param de_list Named list of DE result data.frames; each must
#'   contain `padj` and `log2FoldChange` columns.
#' @param padj_cutoff Maximum padj for "significant" (default 0.05).
#' @param lfc_cutoff Minimum |log2FoldChange| for "significant"
#'   (default 0).
#' @return data.frame with columns `comparison`, `n_up`, `n_down`,
#'   `n_sig` (= `n_up + n_down`). One row per entry of `de_list`,
#'   in input order.
#' @examples
#' de_list <- list(
#'   comp1 = data.frame(
#'     log2FoldChange = c(2, -1, 0, 3, -2),
#'     padj = c(0.01, 0.04, 0.5, 0.02, 0.03)
#'   ),
#'   comp2 = data.frame(
#'     log2FoldChange = c(1.5, -0.8, 0.2, 2.1, -1.5),
#'     padj = c(0.02, 0.03, 0.6, 0.01, 0.04)
#'   )
#' )
#' de_direction_summary(de_list, padj_cutoff = 0.05)
#' @export
de_direction_summary <- function(de_list, padj_cutoff = 0.05,
                                 lfc_cutoff = 0) {
  if (length(de_list) == 0L) {
    de_error("de_list is empty", class = "empty_input")
  }
  do.call(rbind, lapply(seq_along(de_list), function(i) {
    df <- de_list[[i]]
    sig <- !is.na(df$padj) & df$padj <= padj_cutoff &
      !is.na(df$log2FoldChange) &
      abs(df$log2FoldChange) >= lfc_cutoff
    n_up   <- sum(sig & df$log2FoldChange > 0, na.rm = TRUE)
    n_down <- sum(sig & df$log2FoldChange < 0, na.rm = TRUE)
    data.frame(
      comparison = names(de_list)[i],
      n_up       = n_up,
      n_down     = n_down,
      n_sig      = n_up + n_down,
      stringsAsFactors = FALSE
    )
  }))
}

#' Horizontal bar plot of up / down DEG counts per comparison.
#'
#' Up bars (red) extend right; down bars (blue) extend left from the
#' zero line. Comparisons are ordered top-to-bottom by total DEG count.
#'
#' @param summary data.frame as returned by [de_direction_summary()];
#'   must contain `comparison`, `n_up`, `n_down`, `n_sig`.
#' @param subtitle Optional subtitle (typically a cutoff label like
#'   "Threshold: padj <= 0.05").
#' @return ggplot object.
#' @examples
#' summary <- data.frame(
#'   comparison = c("Treat vs Ctrl", "Drug vs Vehicle"),
#'   n_up   = c(120L, 45L),
#'   n_down = c(80L,  30L),
#'   n_sig  = c(200L, 75L),
#'   stringsAsFactors = FALSE
#' )
#' plot_de_direction_bar(summary, subtitle = "padj <= 0.05")
#' @export
plot_de_direction_bar <- function(summary, subtitle = NULL) {
  if (is.null(summary) || nrow(summary) == 0L) {
    de_error("summary is empty", class = "empty_input")
  }
  ord <- summary$comparison[order(summary$n_sig, decreasing = TRUE)]
  long <- data.frame(
    comparison = rep(summary$comparison, 2L),
    direction  = rep(c("Up-regulated", "Down-regulated"),
                     each = nrow(summary)),
    count      = c(summary$n_up, -summary$n_down),
    stringsAsFactors = FALSE
  )
  long$comparison <- factor(long$comparison, levels = rev(ord))
  ggplot2::ggplot(long,
                  ggplot2::aes(x = comparison, y = count,
                               fill = direction)) +
    ggplot2::geom_bar(stat = "identity", width = 0.7) +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(
      values = c("Up-regulated"   = "#e74c3c",
                 "Down-regulated" = "#3498db"),
      name = "Direction"
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      axis.text.y = ggplot2::element_text(size = 10),
      legend.position = "bottom",
      panel.grid.major.y = ggplot2::element_blank()
    ) +
    ggplot2::labs(
      title    = "Differential Gene Expression by Comparison",
      subtitle = subtitle,
      x        = "Comparison",
      y        = "Number of DEGs"
    ) +
    ggplot2::geom_hline(yintercept = 0, color = "#000000",
                        linewidth = 0.5)
}

#' Symmetric pairwise heatmap of significant DEG counts between groups.
#'
#' Builds a `groups x groups` symmetric matrix (diagonal NA) where each
#' off-diagonal cell shows the number of significant DEGs in the
#' comparison between those two groups. Group identities come from
#' `cond_names` of `comparisons`; sig counts come from `summary`,
#' matched on `comparison_labels(comparisons)`. When the same group
#' pair appears in multiple comparisons, the last seen wins.
#'
#' @param summary data.frame as returned by [de_direction_summary()].
#' @param comparisons List of comparison spec/dc-style entries with
#'   `cond_names` (treatment, control) used as group labels. Length and
#'   order should mirror the `de_list` that produced `summary`.
#' @param subtitle Optional subtitle (typically a cutoff label).
#' @return ggplot object.
#' @examples
#' summary_df <- data.frame(
#'   comparison = c("Treat vs Ctrl", "Drug vs Vehicle"),
#'   n_up   = c(120L, 45L),
#'   n_down = c(80L,  30L),
#'   n_sig  = c(200L, 75L),
#'   stringsAsFactors = FALSE
#' )
#' comparisons <- list(
#'   list(cond_names = c("Treat", "Ctrl")),
#'   list(cond_names = c("Drug", "Vehicle"))
#' )
#' plot_de_pairwise_heatmap(summary_df, comparisons)
#' @export
plot_de_pairwise_heatmap <- function(summary, comparisons,
                                     subtitle = NULL) {
  if (is.null(summary) || nrow(summary) == 0L) {
    de_error("summary is empty", class = "empty_input")
  }
  if (length(comparisons) == 0L) {
    de_error("comparisons is empty", class = "empty_input")
  }
  labels <- comparison_labels(comparisons)
  pairs <- lapply(comparisons, function(x) {
    cn <- x$cond_names
    if (is.null(cn) || length(cn) < 2L) return(NULL)
    c(cn[1], cn[2])
  })
  ok <- !vapply(pairs, is.null, logical(1))
  if (sum(ok) == 0L) {
    de_error("no comparisons with cond_names",
             class = "empty_input")
  }
  groups <- unique(unlist(pairs[ok]))
  m <- matrix(NA_real_, nrow = length(groups), ncol = length(groups),
              dimnames = list(groups, groups))
  for (i in which(ok)) {
    cnt <- summary$n_sig[match(labels[i], summary$comparison)]
    if (is.na(cnt)) next
    g1 <- pairs[[i]][1]
    g2 <- pairs[[i]][2]
    m[g1, g2] <- cnt
    m[g2, g1] <- cnt
  }
  long <- data.frame(
    Group1 = rep(rownames(m), times = ncol(m)),
    Group2 = rep(colnames(m), each  = nrow(m)),
    DEGs   = as.vector(m),
    stringsAsFactors = FALSE
  )
  long <- long[!is.na(long$DEGs), , drop = FALSE]
  if (nrow(long) == 0L) {
    de_error("no group-pair counts to plot",
             class = "empty_input")
  }
  ggplot2::ggplot(long,
                  ggplot2::aes(x = Group2, y = Group1, fill = DEGs)) +
    ggplot2::geom_tile(color = "white", linewidth = 1) +
    ggplot2::geom_text(ggplot2::aes(label = as.integer(DEGs)),
                       color = "#000000", size = 4,
                       fontface = "bold") +
    ggplot2::scale_fill_gradient(
      low      = "#ffffff",
      high     = "#1f77b4",
      name     = "Significant\nDEGs",
      na.value = "#f0f0f0"
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, vjust = 1),
      axis.text.y = ggplot2::element_text(size = 10),
      axis.title  = ggplot2::element_blank(),
      panel.grid  = ggplot2::element_blank(),
      plot.title  = ggplot2::element_text(face = "bold", size = 12)
    ) +
    ggplot2::labs(
      title    = "Pairwise DEG Comparison Heatmap",
      subtitle = subtitle
    ) +
    ggplot2::coord_fixed()
}
