# R/fct_gsea.R
#
# Pure analytical core for the Enrichment tab (Phase E1). Reference
# architecture (run_gsea shape, gmt picker layout, NES heatmap card)
# adapted from gsea-explorer (https://github.com/nephantes/gsea-explorer,
# Via Scientific). License attribution lives in NEWS.md.

#' Read a GMT file into a named list of gene-symbol vectors.
#'
#' Thin wrapper around \code{fgsea::gmtPathways()} that adds an explicit
#' file-existence check (raising classed \code{de_error}) and a
#' \code{require_pkg("fgsea")} gate so callers without `fgsea` installed
#' see a friendly install message rather than a stack trace.
#'
#' @param path Path to a `.gmt` file (tab-separated, columns: name, url,
#'   gene1, gene2, ...).
#' @return Named list, names = pathway names, elements = character vectors
#'   of gene symbols (or whatever ID the GMT uses).
#' @examples
#' \dontrun{
#' p <- system.file("extdata", "test-gmt", "hallmark-mini.gmt",
#'                  package = "debrowser")
#' gmt_to_pathways(p)
#' }
#' @export
gmt_to_pathways <- function(path) {
  if (!file.exists(path)) {
    de_error(
      sprintf("GMT file not found: %s", path),
      class = "missing_file",
      path  = path
    )
  }
  require_pkg("fgsea", feature = "GSEA")
  fgsea::gmtPathways(path)
}

#' Run pre-ranked GSEA on a DE result table.
#'
#' Pure function: takes a DE table (one row per gene with an effect-size
#' column) and a named list of pathways, returns a tidy data.frame of
#' enrichment scores ordered by descending |NES|. No Shiny calls.
#'
#' Symbols in `de_table[[id_col]]` are matched against the gene IDs in
#' `pathways` directly — caller is responsible for ID-space consistency
#' (typically both SYMBOL or both ENTREZID).
#'
#' @param de_table data.frame with at minimum `id_col` (gene ID) and
#'   `stat_col` (numeric effect size, e.g. log2 fold change).
#' @param pathways Named list, output of \code{\link{gmt_to_pathways}} or
#'   built from `msigdbr` (Phase E2).
#' @param min_size,max_size Pathway-size filter passed to `fgsea::fgsea`.
#' @param n_perm Permutations for `fgsea::fgsea` `nPermSimple` arg.
#' @param seed RNG seed for reproducibility.
#' @param stat_col Column in `de_table` providing the ranking statistic.
#' @param id_col Column in `de_table` providing the gene ID matching
#'   `pathways`.
#' @return data.frame with columns `pathway`, `size`, `NES`, `padj`,
#'   `pval`, `leading_edge` (last is a list-column of character vectors),
#'   ordered by descending `|NES|`.
#' @examples
#' \dontrun{
#' p <- gmt_to_pathways(system.file("extdata", "test-gmt",
#'                                  "hallmark-mini.gmt",
#'                                  package = "debrowser"))
#' de <- data.frame(gene = c("PGK1", "PDK1"),
#'                  log2FoldChange = c(3, 2.5))
#' run_gsea(de, p)
#' }
#' @export
run_gsea <- function(de_table,
                     pathways,
                     min_size = 15L,
                     max_size = 500L,
                     n_perm   = 1000L,
                     seed     = 1L,
                     stat_col = "log2FoldChange",
                     id_col   = "gene") {
  require_pkg("fgsea", feature = "GSEA")

  if (!stat_col %in% names(de_table)) {
    de_error(
      sprintf("DE table is missing column '%s'", stat_col),
      class = "missing_column", column = stat_col
    )
  }
  if (!id_col %in% names(de_table)) {
    de_error(
      sprintf("DE table is missing column '%s'", id_col),
      class = "missing_column", column = id_col
    )
  }

  stats <- de_table[[stat_col]]
  names(stats) <- as.character(de_table[[id_col]])
  stats <- stats[is.finite(stats)]
  stats <- sort(stats, decreasing = TRUE)

  set.seed(seed)
  res <- fgsea::fgsea(
    pathways    = pathways,
    stats       = stats,
    eps         = 0,
    minSize     = min_size,
    maxSize     = max_size,
    nPermSimple = n_perm
  )

  out <- data.frame(
    pathway      = as.character(res$pathway),
    size         = as.integer(res$size),
    NES          = as.numeric(res$NES),
    padj         = as.numeric(res$padj),
    pval         = as.numeric(res$pval),
    stringsAsFactors = FALSE
  )
  out$leading_edge <- res$leadingEdge
  out <- out[order(-abs(out$NES)), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' Reshape per-comparison GSEA results for the NES heatmap.
#'
#' Used by \code{\link{enrichmentNesHeatmapServer}} to render a tile plot
#' of NES across pathways (rows) by comparisons (columns).
#'
#' @param results_by_comparison Named list of \code{\link{run_gsea}}
#'   outputs. Names become column labels in the heatmap.
#' @param sig_only Logical; if TRUE, retain only pathways significant in
#'   at least one comparison.
#' @param sig_threshold padj cutoff used when `sig_only = TRUE`.
#' @return data.frame with columns `pathway`, `comparison`, `NES`, `padj`.
#' @examples
#' \dontrun{
#' nes_heatmap_data(list(c1 = run_gsea(de1, paths),
#'                       c2 = run_gsea(de2, paths)))
#' }
#' @export
nes_heatmap_data <- function(results_by_comparison,
                             sig_only      = FALSE,
                             sig_threshold = 0.05) {
  if (!length(results_by_comparison)) {
    de_error("results_by_comparison is empty", class = "empty_input")
  }

  long <- do.call(rbind, lapply(names(results_by_comparison), function(nm) {
    df <- results_by_comparison[[nm]]
    data.frame(
      pathway    = df$pathway,
      comparison = nm,
      NES        = df$NES,
      padj       = df$padj,
      stringsAsFactors = FALSE
    )
  }))

  if (sig_only) {
    sig_pw <- unique(long$pathway[long$padj < sig_threshold])
    long <- long[long$pathway %in% sig_pw, , drop = FALSE]
  }
  rownames(long) <- NULL
  long
}
