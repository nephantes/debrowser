# R/fct_method_concordance.R
#
# Phase E11 — Statistical method concordance.
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
#' DESeq2's native return is a `DESeqResults` object — coerced via
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
#' object — caller (renderPlot) is responsible for printing.
#'
#' @inheritParams concordance_sets
#' @return Result of `UpSetR::upset()` (a list with class `"upset"`).
#'   When fewer than 2 methods produce non-empty sets, returns NULL
#'   (caller should render an empty-state instead).
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
