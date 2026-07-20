# inst/templates/report_helpers.R
#
# Phase E3.B - report helper functions consumed by the Rmd / Jupyter /
# .R reports emitted by R/fct_export_session.R. Functions are lifted
# verbatim from a reference DESeq2-Salmon report Rmd contributed by
# the user (Haania mouse PA/DMSO study, 2022). Aesthetic parity with
# that reference is the v1 correctness signal.
#
# Helpers loaded here:
#   count_distribution(counts, samples, min_counts_per_event, group_by)
#   all2all(data, cex)               + panel.hist + panel.cor
#   getNormalizedMatrix(M, method)
#   run_pca(input, ...)
#   pca_plot(pca, metadata, ...)
#   scree_plot(pca)
#   volcano_plot(deseq_res, ...)
#   ma_plot(deseq_res, ...)
#   heatmap_plot(df)
#   add_alias / add_highlights / call_significance / post_processing
#
# These run inside the rendered report's R session and depend on a few
# Suggests packages (DESeq2, edgeR, sva, gplots, ggplot2, ggrepel, dplyr,
# tidyr, scales, DT, htmltools, clusterProfiler::bitr). The emitted Rmd
# loads them via library() at the top.

quiet <- function(x) {
  sink(tempfile())
  on.exit(sink())
  invisible(force(x))
}

count_distribution <- function(counts, samples, min_counts_per_event, group_by) {
  options(scipen = 999)

  needed_colors <- nrow(samples %>% dplyr::distinct(!!rlang::sym(group_by)))
  colors <- c("#4682b4", "#000000", "#6d2578", "#DC6D00", "#1e6234",
              "#FFFF33", "#A65628", "#F781BF", "#999999")

  df <- as.data.frame(counts) %>%
    tibble::rownames_to_column("feature") %>%
    tidyr::pivot_longer(!feature, names_to = "sample_name",
                        values_to = "count") %>%
    dplyr::left_join(samples, by = "sample_name") %>%
    dplyr::group_by(feature, !!rlang::sym(group_by)) %>%
    dplyr::summarise(ave_count = mean(count), .groups = "drop") %>%
    dplyr::filter(ave_count > 0)

  ggplot2::ggplot(df,
                  ggplot2::aes(x = ave_count,
                               fill = as.factor(!!rlang::sym(group_by)))) +
    ggplot2::theme_classic() +
    ggplot2::theme(strip.background = ggplot2::element_blank(),
                   strip.text = ggplot2::element_blank()) +
    ggplot2::facet_wrap(stats::as.formula(paste("~", group_by)), ncol = 1) +
    ggplot2::scale_x_continuous(
      trans = "log10",
      breaks = c(.1, 1, 10, 100, 1000, 10000, 100000, 1000000),
      name = "Raw Counts") +
    ggplot2::scale_y_continuous(name = "Number of Features",
                                expand = c(0, 0)) +
    {if (needed_colors <= length(colors))
      ggplot2::scale_fill_manual(values = colors, name = "")} +
    ggplot2::geom_histogram(bins = 100) +
    ggplot2::geom_vline(xintercept = min_counts_per_event,
                        linetype = 2, color = "firebrick")
}

panel.hist <- function(x, ...) {
  usr <- graphics::par("usr")
  on.exit(graphics::par(usr))
  graphics::par(usr = c(usr[1:2], 0, 1.5))
  h <- graphics::hist(x, plot = FALSE)
  breaks <- h$breaks
  nb <- length(breaks)
  y <- h$counts
  y <- y / max(y)
  graphics::rect(breaks[-nb], 0, breaks[-1], y, col = "red", ...)
}

panel.cor <- function(x, y, prefix = "rho=", cex.cor = 2, ...) {
  usr <- graphics::par("usr")
  on.exit(graphics::par(usr))
  graphics::par(usr = c(0, 1, 0, 1))
  r <- stats::cor.test(x, y, method = "spearman",
                       na.rm = TRUE, exact = FALSE)$estimate
  txt <- round(r, digits = 2)
  txt <- paste0(prefix, txt)
  graphics::text(0.5, 0.5, txt, cex = cex.cor)
}

all2all <- function(data, cex = 2) {
  pcor <- function(x, y, ...) panel.cor(x, y, cex.cor = cex)
  nr <- nrow(data)
  if (nr > 1000) nr <- 1000
  graphics::pairs(log10(data[1:nr, ]), cex = 0.25,
                  diag.panel = panel.hist, lower.panel = pcor)
}

getNormalizedMatrix <- function(M = NULL, method = "TMM") {
  if (is.null(M)) return(NULL)
  M[is.na(M)] <- 0
  norm <- M
  if (!(method == "none" || method == "MRN")) {
    norm.factors <- edgeR::calcNormFactors(M, method = method)
    norm <- edgeR::equalizeLibSizes(
      edgeR::DGEList(M, norm.factors = norm.factors)
    )$pseudo.counts
  } else if (method == "MRN") {
    columns <- colnames(M)
    conds <- columns
    coldata <- data.frame(group = conds, row.names = columns)
    M[, columns] <- apply(M[, columns], 2, function(x) as.integer(x))
    dds <- DESeq2::DESeqDataSetFromMatrix(
      countData = as.matrix(M), colData = coldata, design = ~group)
    dds <- DESeq2::estimateSizeFactors(dds)
    norm <- DESeq2::counts(dds, normalized = TRUE)
  }
  return(norm)
}

run_pca <- function(input, retx = TRUE, center = TRUE, scale = TRUE,
                    transformation = "Default", write_transform = FALSE) {
  # Defensive coercion: vst() and rlog() dispatch on object class via
  # sizeFactors(), which has no method for data.frame. The DEBrowser
  # demo and upload paths can deliver `corrected` as a data.frame, so
  # we always coerce to an integer matrix before downstream DESeq2
  # transforms. This is a no-op for callers who already pass a matrix.
  if (!is.matrix(input)) input <- as.matrix(input)
  if (!is.integer(input)) {
    input_int <- input
    storage.mode(input_int) <- "integer"
    if (!any(is.na(input_int))) input <- input_int
  }

  if (transformation == "None") {
    keep <- subset(input, apply(input, 1, stats::var, na.rm = TRUE) > 0)
    return(stats::prcomp(t(keep), retx = retx, center = center, scale. = scale))
  } else if (transformation == "vst" ||
             (transformation == "Default" && ncol(input) > 50)) {
    transformed <- DESeq2::vst(input)
    if (write_transform) {
      utils::write.table(
        as.data.frame(transformed) %>% tibble::rownames_to_column("feature"),
        file = "outputs/transformed_counts_vst.tsv",
        quote = FALSE, sep = "\t", row.names = FALSE)
    }
    return(stats::prcomp(t(transformed), retx = retx, center = center,
                         scale. = FALSE))
  } else {
    transformed <- DESeq2::rlog(input)
    if (write_transform) {
      utils::write.table(
        as.data.frame(transformed) %>% tibble::rownames_to_column("feature"),
        file = "outputs/transformed_counts_rlog.tsv",
        quote = FALSE, sep = "\t", row.names = FALSE)
    }
    return(stats::prcomp(t(transformed), retx = retx, center = center,
                         scale. = FALSE))
  }
}

pca_plot <- function(pca, metadata, x = "PC1", y = "PC2", color_by = "",
                     shape_by = "", fill_by = "", alpha_by = "",
                     label_by = "", size = 4) {
  col_names <- names(metadata)
  metadata[, col_names] <- lapply(metadata[, col_names], factor)

  if (color_by == "NA") color_by <- ""
  if (shape_by == "NA") shape_by <- ""
  if (fill_by  == "NA") fill_by  <- ""
  if (alpha_by == "NA") alpha_by <- ""
  if (label_by == "NA") label_by <- ""

  if (color_by != "") {
    needed_colors <- nrow(metadata %>% dplyr::distinct(!!rlang::sym(color_by)))
  } else {
    needed_colors <- Inf
  }
  colors <- c("#b22222", "#4682b4", "#6d2578", "#DC6D00", "#1e6234",
              "#FFFF33", "#A65628", "#F781BF", "#999999")

  PoV <- data.frame(PoV = pca$sdev^2 / sum(pca$sdev^2) * 100) %>%
    dplyr::mutate(PC = paste0("PC", dplyr::row_number()))
  pca_results <- as.data.frame(pca$x) %>%
    tibble::rownames_to_column("sample_name") %>%
    dplyr::left_join(metadata, by = "sample_name")

  PoV_X <- round((PoV %>% dplyr::filter(PC == x))$PoV, 2)
  PoV_Y <- round((PoV %>% dplyr::filter(PC == y))$PoV, 2)

  ggplot2::ggplot(pca_results,
                  ggplot2::aes(x = !!rlang::sym(x),
                               y = !!rlang::sym(y),
                               color = !!rlang::sym(color_by),
                               shape = !!rlang::sym(shape_by),
                               fill  = !!rlang::sym(fill_by),
                               alpha = !!rlang::sym(alpha_by),
                               label = !!rlang::sym(label_by))) +
    ggplot2::theme_classic() +
    ggplot2::xlab(paste0(x, ": ", PoV_X, "%")) +
    ggplot2::ylab(paste0(y, ": ", PoV_Y, "%")) +
    {if (needed_colors <= length(colors))
      ggplot2::scale_color_manual(values = colors)} +
    ggplot2::geom_point(size = size) +
    {if (label_by != "")
      ggplot2::geom_label(label.size = NA, fill = NA, color = "black")}
}

scree_plot <- function(pca) {
  PoV <- data.frame(PoV = pca$sdev^2 / sum(pca$sdev^2) * 100) %>%
    dplyr::mutate(PC = dplyr::row_number()) %>%
    dplyr::mutate(Label = dplyr::case_when(
      PoV >= .01 ~ as.character(round(PoV, 2)),
      TRUE ~ "<.01"
    ))

  ggplot2::ggplot(PoV,
                  ggplot2::aes(x = PC, y = PoV, label = Label)) +
    ggplot2::theme_classic() +
    ggplot2::scale_x_continuous(breaks = seq(1, min(nrow(PoV), 20), 1),
                                limits = c(0, min(nrow(PoV), 20))) +
    ggplot2::scale_y_continuous(name = "Percent of Variation",
                                limits = c(0, 100), expand = c(0, 0)) +
    ggplot2::geom_bar(stat = "identity", fill = "black") +
    ggplot2::geom_label(fill = NA, label.size = NA, vjust = -.05)
}

add_alias <- function(df, add_alias = TRUE, fromType = "ENSEMBL",
                      toType = "SYMBOL", org = "org.Hs.eg.db") {
  if (add_alias) {
    mapped_names <- data.frame(clusterProfiler::bitr(
      df$feature, fromType = fromType, toType = toType, OrgDb = org))

    unique_from <- mapped_names %>%
      dplyr::group_by(!!rlang::sym(fromType)) %>%
      dplyr::summarise(count = dplyr::n()) %>%
      dplyr::filter(count == 1) %>%
      dplyr::select(-count)
    colnames(unique_from) <- c("alias")

    unique_to <- mapped_names %>%
      dplyr::group_by(!!rlang::sym(toType)) %>%
      dplyr::summarise(count = dplyr::n()) %>%
      dplyr::filter(count == 1) %>%
      dplyr::select(-count)
    colnames(unique_to) <- c("alias")

    one_to_one <- mapped_names %>%
      dplyr::filter(!!rlang::sym(toType) %in% unique_to$alias &
                    !!rlang::sym(fromType) %in% unique_from$alias)

    return(df %>%
      dplyr::left_join(one_to_one,
                       by = stats::setNames(fromType, "feature")) %>%
      dplyr::mutate(alias = dplyr::case_when(
        !is.na(!!rlang::sym(toType)) ~ !!rlang::sym(toType),
        TRUE ~ feature)) %>%
      dplyr::select(-!!rlang::sym(toType)))
  } else {
    return(df %>% dplyr::mutate(alias = feature))
  }
}

add_highlights <- function(df, to_highlight) {
  df %>% dplyr::mutate(Highlighted = dplyr::case_when(
    (alias %in% to_highlight | feature %in% to_highlight) ~ TRUE,
    TRUE ~ FALSE
  ))
}

call_significance <- function(df, padj_significance_cutoff,
                              fc_significance_cutoff, padj_floor,
                              fc_ceiling, num_labeled, apply_shrinkage) {
  labels <- df %>%
    dplyr::filter(padj < padj_significance_cutoff &
                  abs(log2FoldChange) > fc_significance_cutoff) %>%
    dplyr::arrange(-abs(log2FoldChange)) %>%
    dplyr::mutate(Rank = dplyr::row_number()) %>%
    dplyr::filter(Rank <= num_labeled) %>%
    dplyr::select(feature)

  if (apply_shrinkage) {
    df <- df %>%
      dplyr::mutate(Direction = dplyr::case_when(
        padj < padj_significance_cutoff &
          log2FoldChange_shrink >  fc_significance_cutoff ~ "Upregulated",
        padj < padj_significance_cutoff &
          log2FoldChange_shrink < -fc_significance_cutoff ~ "Downregulated",
        TRUE ~ "No Change")) %>%
      dplyr::mutate(log2FoldChange_shrink = dplyr::case_when(
        log2FoldChange_shrink < 0 &
          abs(log2FoldChange_shrink) > fc_ceiling ~ -fc_ceiling,
        log2FoldChange_shrink > 0 &
          abs(log2FoldChange_shrink) > fc_ceiling ~  fc_ceiling,
        TRUE ~ log2FoldChange_shrink))
  } else {
    df <- df %>%
      dplyr::mutate(Direction = dplyr::case_when(
        padj < padj_significance_cutoff &
          log2FoldChange >  fc_significance_cutoff ~ "Upregulated",
        padj < padj_significance_cutoff &
          log2FoldChange < -fc_significance_cutoff ~ "Downregulated",
        TRUE ~ "No Change"))
  }

  df <- df %>%
    dplyr::mutate(Direction = factor(Direction,
      levels = c("Upregulated", "No Change", "Downregulated"))) %>%
    dplyr::mutate(Significant = dplyr::case_when(
      Direction == "No Change" ~ "Non-Significant",
      TRUE ~ "Significant")) %>%
    dplyr::mutate(padj = dplyr::case_when(
      padj < padj_floor ~ padj_floor,
      TRUE ~ padj)) %>%
    dplyr::mutate(log2FoldChange = dplyr::case_when(
      log2FoldChange < 0 & abs(log2FoldChange) > fc_ceiling ~ -fc_ceiling,
      log2FoldChange > 0 & abs(log2FoldChange) > fc_ceiling ~  fc_ceiling,
      TRUE ~ log2FoldChange)) %>%
    dplyr::mutate(Label = dplyr::case_when(
      ((Significant == "Significant" & feature %in% labels$feature) |
        Highlighted == TRUE) ~ alias)) %>%
    dplyr::mutate(Group = dplyr::case_when(
      Highlighted == TRUE  & Direction == "Upregulated"   ~ "Upregulated_Highlighted",
      Highlighted == TRUE  & Direction == "No Change"     ~ "NoChange_Highlighted",
      Highlighted == TRUE  & Direction == "Downregulated" ~ "Downregulated_Highlighted",
      Highlighted == FALSE & Direction == "Upregulated"   ~ "Upregulated",
      Highlighted == FALSE & Direction == "No Change"     ~ "No Change",
      Highlighted == FALSE & Direction == "Downregulated" ~ "Downregulated"
    ))
  return(df)
}

post_processing <- function(deseq_res, padj_significance_cutoff,
                            fc_significance_cutoff, num_labeled, highlighted,
                            add_alias = TRUE, fromType = "ENSEMBL",
                            toType = "SYMBOL", org = "org.Hs.eg.db",
                            apply_shrinkage = FALSE,
                            padj_floor = 0, fc_ceiling = Inf) {
  post <- add_alias(deseq_res, add_alias = add_alias,
                    fromType = fromType, toType = toType, org = org)
  post <- add_highlights(post, highlighted)
  post <- call_significance(post, padj_significance_cutoff,
                            fc_significance_cutoff, padj_floor,
                            fc_ceiling, num_labeled, apply_shrinkage)
  return(post)
}

volcano_plot <- function(deseq_res, X = "log2FoldChange", padj_cutoff = .05,
                         fc_cutoff = 1, padj_floor = 0, fc_ceiling = Inf,
                         num_labeled = Inf,
                         upregulated_color = "firebrick",
                         noChange_color = "grey",
                         downregulated_color = "steelblue",
                         upregulated_highlight_color = "#1e6234",
                         noChange_highlight_color = "black",
                         downregulated_highlight_color = "#1e6234",
                         upregulated_alpha = 1,
                         noChange_alpha = .3,
                         downregulated_alpha = 1,
                         upregulated_highlight_alpha = 1,
                         noChange_highlight_alpha = 1,
                         downregulated_highlight_alpha = 1,
                         upregulated_size = 2,
                         noChange_size = 1,
                         downregulated_size = 2,
                         upregulated_highlight_size = 2,
                         noChange_highlight_size = 2,
                         downregulated_highlight_size = 2,
                         fc_markers = TRUE, fc_marker_color = "grey",
                         center_marker = TRUE, center_marker_color = "black",
                         padj_marker = TRUE, padj_marker_color = "grey",
                         display_upregulated_count = TRUE,
                         display_downregulated_count = TRUE,
                         display_noChange_count = FALSE) {
  colors <- c("Upregulated" = upregulated_color,
              "No Change" = noChange_color,
              "Downregulated" = downregulated_color,
              "Upregulated_Highlighted" = upregulated_highlight_color,
              "NoChange_Highlighted" = noChange_highlight_color,
              "Downregulated_Highlighted" = downregulated_highlight_color)
  alphas <- c("Upregulated" = upregulated_alpha,
              "No Change" = noChange_alpha,
              "Downregulated" = downregulated_alpha,
              "Upregulated_Highlighted" = upregulated_highlight_alpha,
              "NoChange_Highlighted" = noChange_highlight_alpha,
              "Downregulated_Highlighted" = downregulated_highlight_alpha)
  sizes <- c("Upregulated" = upregulated_size,
             "No Change" = noChange_size,
             "Downregulated" = downregulated_size,
             "Upregulated_Highlighted" = upregulated_highlight_size,
             "NoChange_Highlighted" = noChange_highlight_size,
             "Downregulated_Highlighted" = downregulated_highlight_size)

  upregulated_count   <- nrow(deseq_res %>% dplyr::filter(Direction == "Upregulated"))
  noChange_count      <- nrow(deseq_res %>% dplyr::filter(Direction == "No Change"))
  downregulated_count <- nrow(deseq_res %>% dplyr::filter(Direction == "Downregulated"))

  ggplot2::ggplot(deseq_res,
                  ggplot2::aes(x = !!rlang::sym(X), y = padj,
                               color = Group, alpha = Group, size = Group,
                               label = Label)) +
    ggplot2::theme_classic() +
    ggplot2::theme(legend.position = "none") +
    ggplot2::scale_x_continuous(name = "Fold Change (log2)") +
    ggplot2::scale_y_continuous(
      trans = c("log10", "reverse"), name = "Significance",
      labels = scales::trans_format("log10", scales::math_format(10^.x))) +
    ggplot2::scale_color_manual(values = colors) +
    ggplot2::scale_alpha_manual(values = alphas) +
    ggplot2::scale_size_manual(values = sizes) +
    ggplot2::geom_point() +
    {if (fc_markers) ggplot2::geom_vline(xintercept = fc_cutoff,
        linetype = 2, color = fc_marker_color)} +
    {if (center_marker) ggplot2::geom_vline(xintercept = 0,
        linetype = 2, color = center_marker_color)} +
    {if (fc_markers) ggplot2::geom_vline(xintercept = -fc_cutoff,
        linetype = 2, color = fc_marker_color)} +
    {if (padj_marker) ggplot2::geom_hline(yintercept = padj_cutoff,
        linetype = 2, color = padj_marker_color)} +
    {if (display_upregulated_count) ggplot2::annotate(
        "text", x = Inf, y = 0, hjust = 1, vjust = 1,
        color = upregulated_color,
        label = paste0("Upregulated: ", upregulated_count))} +
    {if (display_downregulated_count) ggplot2::annotate(
        "text", x = -Inf, y = 0, hjust = -.01, vjust = 1,
        color = downregulated_color,
        label = paste0("Downregulated: ", downregulated_count))} +
    {if (display_noChange_count) ggplot2::annotate(
        "text", x = 0, y = 0, vjust = 1,
        color = noChange_color,
        label = paste0("No Change: ", noChange_count))} +
    ggrepel::geom_label_repel(label.size = NA, fill = NA, na.rm = TRUE,
                              max.overlaps = 50, max.time = 5)
}

ma_plot <- function(deseq_res, Y = "log2FoldChange", padj_cutoff = .05,
                    fc_cutoff = 1, padj_floor = 0, fc_ceiling = Inf,
                    num_labeled = Inf,
                    upregulated_color = "firebrick",
                    noChange_color = "grey",
                    downregulated_color = "steelblue",
                    upregulated_highlight_color = "#1e6234",
                    noChange_highlight_color = "black",
                    downregulated_highlight_color = "#1e6234",
                    upregulated_alpha = 1,
                    noChange_alpha = .3,
                    downregulated_alpha = 1,
                    upregulated_highlight_alpha = 1,
                    noChange_highlight_alpha = 1,
                    downregulated_highlight_alpha = 1,
                    upregulated_size = 2,
                    noChange_size = 1,
                    downregulated_size = 2,
                    upregulated_highlight_size = 2,
                    noChange_highlight_size = 2,
                    downregulated_highlight_size = 2,
                    fc_markers = TRUE, fc_marker_color = "grey",
                    center_marker = TRUE, center_marker_color = "black",
                    display_upregulated_count = TRUE,
                    display_downregulated_count = TRUE,
                    display_noChange_count = FALSE) {
  options(scipen = 999)
  colors <- c("Upregulated" = upregulated_color,
              "No Change" = noChange_color,
              "Downregulated" = downregulated_color,
              "Upregulated_Highlighted" = upregulated_highlight_color,
              "NoChange_Highlighted" = noChange_highlight_color,
              "Downregulated_Highlighted" = downregulated_highlight_color)
  alphas <- c("Upregulated" = upregulated_alpha,
              "No Change" = noChange_alpha,
              "Downregulated" = downregulated_alpha,
              "Upregulated_Highlighted" = upregulated_highlight_alpha,
              "NoChange_Highlighted" = noChange_highlight_alpha,
              "Downregulated_Highlighted" = downregulated_highlight_alpha)
  sizes <- c("Upregulated" = upregulated_size,
             "No Change" = noChange_size,
             "Downregulated" = downregulated_size,
             "Upregulated_Highlighted" = upregulated_highlight_size,
             "NoChange_Highlighted" = noChange_highlight_size,
             "Downregulated_Highlighted" = downregulated_highlight_size)

  upregulated_count   <- nrow(deseq_res %>% dplyr::filter(Direction == "Upregulated"))
  noChange_count      <- nrow(deseq_res %>% dplyr::filter(Direction == "No Change"))
  downregulated_count <- nrow(deseq_res %>% dplyr::filter(Direction == "Downregulated"))

  ggplot2::ggplot(deseq_res,
                  ggplot2::aes(x = baseMean, y = !!rlang::sym(Y),
                               color = Group, alpha = Group, size = Group,
                               label = Label)) +
    ggplot2::theme_classic() +
    ggplot2::theme(legend.position = "none") +
    ggplot2::scale_x_continuous(trans = "log10", name = "Expression") +
    ggplot2::scale_y_continuous(name = "Fold Change (log2)") +
    ggplot2::scale_color_manual(values = colors) +
    ggplot2::scale_alpha_manual(values = alphas) +
    ggplot2::scale_size_manual(values = sizes) +
    ggplot2::geom_point() +
    {if (fc_markers) ggplot2::geom_hline(yintercept = fc_cutoff,
        linetype = 2, color = fc_marker_color)} +
    {if (center_marker) ggplot2::geom_hline(yintercept = 0,
        linetype = 2, color = center_marker_color)} +
    {if (fc_markers) ggplot2::geom_hline(yintercept = -fc_cutoff,
        linetype = 2, color = fc_marker_color)} +
    {if (display_upregulated_count) ggplot2::annotate(
        "text", x = Inf, y = Inf, hjust = 1, vjust = 1,
        color = upregulated_color,
        label = paste0("Upregulated: ", upregulated_count))} +
    {if (display_downregulated_count) ggplot2::annotate(
        "text", x = Inf, y = -Inf, hjust = 1, vjust = -1,
        color = downregulated_color,
        label = paste0("Downregulated: ", downregulated_count))} +
    {if (display_noChange_count) ggplot2::annotate(
        "text", x = Inf, y = fc_cutoff, hjust = 1, vjust = 1.2,
        color = noChange_color,
        label = paste0("No Change: ", noChange_count))} +
    ggrepel::geom_label_repel(label.size = NA, fill = NA, na.rm = TRUE,
                              max.overlaps = 50, max.time = 5)
}

heatmap_plot <- function(df) {
  norm <- getNormalizedMatrix(df, method = "TMM")
  ld <- log2(norm + .1)
  cldt <- scale(t(ld), center = TRUE, scale = TRUE)
  cld <- t(cldt)

  if (nrow(cld) > 1) {
    gplots::heatmap.2(cld, Rowv = TRUE, dendrogram = "column", Colv = TRUE,
                     col = gplots::bluered(256),
                     labRow = NA, density.info = "none", trace = "none",
                     cexCol = .8,
                     hclust = function(x) stats::hclust(x, method = "complete"),
                     distfun = function(x) stats::as.dist((1 - stats::cor(t(x))) / 2))
  } else {
    x <- as.data.frame(cld) %>%
      tibble::rownames_to_column("Feature") %>%
      tidyr::pivot_longer(!Feature, names_to = "Sample", values_to = "Value")

    ggplot2::ggplot(x,
                    ggplot2::aes(x = Sample, y = Feature, fill = Value)) +
      ggplot2::theme_classic() +
      ggplot2::theme(axis.line = ggplot2::element_blank(),
                     axis.ticks = ggplot2::element_blank()) +
      ggplot2::scale_fill_gradient(low = "#0000FF", high = "#FF0000") +
      ggplot2::geom_tile()
  }
}
