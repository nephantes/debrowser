#' Run DESeq2 on a count matrix.
#'
#' Pure function: takes plain R objects, returns a `DESeqResults` object.
#' No Shiny dependency. Errors are raised via [de_error()] with classes:
#'   - `too_few_columns`
#'   - `null_input`
#'
#' @param counts A numeric count matrix or data.frame (genes x samples).
#' @param metadata Sample metadata; first column is sample id.
#' @param columns Character vector of sample column names to use.
#' @param conds Factor of conditions, length == length(columns).
#' @param params Named list with components: covariates (character "|"-joined
#'   or "NoCovariate"), fit_type ("parametric"/"local"/"mean"), beta_prior
#'   (logical), test_type ("Wald"/"LRT"), shrinkage
#'   ("None"/"apeglm"/"ashr"/"normal").
#' @param return_dds Logical. If TRUE, return a list with components `res`
#'   (DESeqResults) and `dds` (the fitted DESeqDataSet), so downstream QC
#'   cards (Dispersion / SizeFactors / Cook's) can introspect the fit.
#'   Default FALSE preserves the legacy data.frame-shaped contract.
#' @return DESeqResults if `return_dds = FALSE`; otherwise
#'   `list(res = DESeqResults, dds = DESeqDataSet)`.
#' @examples
#' \donttest{
#' set.seed(42)
#' counts <- matrix(
#'   as.integer(abs(rnorm(60, mean = 100, sd = 30))),
#'   nrow = 10, ncol = 6,
#'   dimnames = list(paste0("G", 1:10), paste0("S", 1:6))
#' )
#' conds <- c("Cond1", "Cond1", "Cond1", "Cond2", "Cond2", "Cond2")
#' run_deseq2(counts, columns = colnames(counts), conds = conds,
#'            params = list(test_type = "Wald", shrinkage = "None"))
#' }
#' @export
run_deseq2 <- function(counts, metadata = NULL, columns = NULL, conds = NULL,
                       params = list(), return_dds = FALSE) {
  de_assert_count_matrix(counts)
  if (length(columns) < 3L) {
    de_error(
      paste0("DESeq2 requires at least 3 sample columns; got ", length(columns)),
      class = "too_few_columns"
    )
  }
  defaults <- list(
    covariates = "NoCovariate",
    fit_type   = "parametric",
    beta_prior = FALSE,
    test_type  = "LRT",
    shrinkage  = "apeglm"
  )
  params <- modifyList(defaults, params)

  data <- counts[, columns]
  data[, columns] <- apply(data[, columns], 2, as.integer)

  covariates <- strsplit(params$covariates, split = "\\|")[[1]]
  coldata <- prepGroup(conds, columns, metadata, covariates)

  if (!identical(covariates, "NoCovariate")) {
    dds_formula <- as.formula(
      paste0("~ group", paste0(" + covariate", seq_along(covariates), collapse = ""))
    )
    dds <- DESeq2::DESeqDataSetFromMatrix(
      countData = as.matrix(data), colData = coldata, design = dds_formula
    )
  } else {
    dds <- DESeq2::DESeqDataSetFromMatrix(
      countData = as.matrix(data), colData = coldata, design = ~group
    )
  }

  if (params$test_type == "LRT") {
    dds <- DESeq2::DESeq(
      dds,
      fitType   = params$fit_type,
      betaPrior = as.logical(params$beta_prior),
      test      = params$test_type,
      reduced   = ~1
    )
  } else {
    dds <- DESeq2::DESeq(
      dds,
      fitType   = params$fit_type,
      betaPrior = as.logical(params$beta_prior),
      test      = params$test_type
    )
  }

  coef_names <- colnames(coef(dds))
  group_name <- coef_names[grepl("group", coef_names)][1]
  res <- DESeq2::results(dds, name = group_name)

  if (params$shrinkage != "None") {
    if (params$shrinkage %in% c("apeglm", "ashr")) {
      require_pkg(params$shrinkage,
        feature = sprintf("LFC shrinkage (type='%s')", params$shrinkage)
      )
    }
    res <- DESeq2::lfcShrink(dds, coef = 2, res = res, type = params$shrinkage)
    if (params$test_type == "Wald") {
      colname <- names(dds@rowRanges@elementMetadata)[
        grepl(
          paste0(params$test_type, "Statistic_group"),
          names(dds@rowRanges@elementMetadata)
        )
      ]
    } else {
      colname <- paste0(params$test_type, "Statistic")
    }
    stat <- dds@rowRanges@elementMetadata[colname]
    res <- cbind(res, stat)
    colnames(res)[colnames(res) == colname] <- "stat"
  }
  if (isTRUE(return_dds)) {
    return(list(res = res, dds = dds))
  }
  res
}

#' Run edgeR on a count matrix.
#'
#' @inheritParams run_deseq2
#' @param params Named list with components: covariates, norm_fact
#'   ("TMM"/"RLE"/"upperquartile"/"none"), dispersion (numeric or character
#'   "common"/"trended"/"tagwise"/"auto"), test_type ("exactTest"/"glmLRT").
#' @return data.frame with columns log2FoldChange, pvalue, padj, stat.
#' @examples
#' set.seed(42)
#' counts <- matrix(
#'   as.integer(abs(rnorm(60, mean = 100, sd = 30))),
#'   nrow = 10, ncol = 6,
#'   dimnames = list(paste0("G", 1:10), paste0("S", 1:6))
#' )
#' conds <- c("Cond1", "Cond1", "Cond1", "Cond2", "Cond2", "Cond2")
#' run_edger(counts, columns = colnames(counts), conds = conds)
#' @export
run_edger <- function(counts, metadata = NULL, columns = NULL, conds = NULL,
                      params = list()) {
  de_assert_count_matrix(counts)
  defaults <- list(
    covariates = "NoCovariate",
    norm_fact  = "TMM",
    dispersion = "0",
    test_type  = "exactTest"
  )
  params <- modifyList(defaults, params)

  data <- counts[, columns]
  data[, columns] <- apply(data[, columns], 2, as.integer)
  covariates <- strsplit(params$covariates, split = "\\|")[[1]]

  dispersion <- params$dispersion
  if (!is.na(dispersion) &&
    !(dispersion %in% c("common", "trended", "tagwise", "auto"))) {
    dispersion <- as.numeric(dispersion)
  }

  conds <- factor(conds)
  filtd <- data
  d <- edgeR::DGEList(counts = filtd, group = conds)
  d <- edgeR::calcNormFactors(d, method = params$norm_fact)

  cnum <- summary(conds)[levels(conds)[1]]
  tnum <- summary(conds)[levels(conds)[2]]
  des <- c(rep(1, cnum), rep(2, tnum))
  if (cnum == 1 && tnum == 1 &&
    (dispersion %in% c("common", "trended", "tagwise", "auto") ||
      identical(dispersion, 0))) {
    de_error(
      paste(
        "edgeR cannot use 'common'/'trended'/'tagwise'/'auto' dispersion",
        "or 0 with 1 replicate per condition.",
        "Provide a numeric dispersion."
      ),
      class = "bad_dispersion"
    )
  }

  if (!identical(covariates, "NoCovariate")) {
    des_formula <- as.formula(
      paste0("~ des", paste0(" + covariate", seq_along(covariates), collapse = ""))
    )
    model_data <- data.frame(des = des)
    sample_col_ind <- which(apply(metadata, 2, function(x) sum(x %in% columns) == length(columns)))
    sample_col <- colnames(metadata)[sample_col_ind]
    cov_metadata <- metadata[match(columns, metadata[, sample_col]), covariates, drop = FALSE]
    for (i in seq_along(covariates)) {
      model_data[[paste0("covariate", i)]] <- factor(cov_metadata[, i])
    }
    design <- model.matrix(des_formula, data = model_data)
  } else {
    design <- model.matrix(~des)
  }

  d <- edgeR::estimateDisp(d, design)
  if (params$test_type == "exactTest") {
    de_com <- if (identical(dispersion, 0)) {
      edgeR::exactTest(d)
    } else {
      edgeR::exactTest(d, dispersion = dispersion)
    }
    # Pass `sort.by = "none"` so the table stays aligned with the input gene
    # order. Without this, topTags would sort by FDR and the subsequent
    # `rownames(res) <- rownames(filtd)` would attach values to the wrong
    # genes (a long-standing bug).
    de_com$table <- edgeR::topTags(de_com, n = nrow(de_com$table),
                                   sort.by = "none")$table
    colnames(de_com$table)[colnames(de_com$table) == "FDR"] <- "stat"
  } else {
    fit <- if (identical(dispersion, 0)) {
      edgeR::glmFit(d, design)
    } else {
      edgeR::glmFit(d, design, dispersion = dispersion)
    }
    de_com <- edgeR::glmLRT(fit, coef = 2)
    colnames(de_com$table)[colnames(de_com$table) == "LR"] <- "stat"
  }

  options(digits = 4)
  padj <- p.adjust(de_com$table$PValue, method = "BH")
  # edgeR's `logFC` is log2-fold-change by default (per `?exactTest` /
  # `?glmLRT`). The legacy `/ log(2)` divided by ~0.693, inflating reported
  # log2FoldChange by ~44% and the derived linear `foldChange = 2^...` by
  # even more. Fixed: use `logFC` directly so all three DE methods produce
  # consistent log2-scale fold changes that downstream filters can compare.
  # D2.5 fix Issue 5: include `baseMean` so EdgeR results plug into the
  # same Rmd report template (MA plot x-axis, formatRound) and DEBrowser
  # MA / scatter plots that DESeq2 results do. edgeR's `logCPM` is the
  # natural per-gene mean-expression metric; we use 2^logCPM to put it
  # on a comparable linear scale to DESeq2's normalized-count baseMean.
  base_mean <- if (!is.null(de_com$table$logCPM)) {
    2 ^ de_com$table$logCPM
  } else {
    rowMeans(filtd)
  }
  res <- data.frame(
    baseMean       = base_mean,
    log2FoldChange = de_com$table$logFC,
    pvalue         = de_com$table$PValue,
    padj           = padj,
    stat           = de_com$table$stat
  )
  rownames(res) <- rownames(filtd)
  res
}

#' Run limma-voom on a count matrix.
#'
#' @inheritParams run_deseq2
#' @param params Named list: covariates, norm_fact, fit_type ("ls"/"robust"),
#'   norm_bet ("none"/"scale"/"quantile"/...).
#' @return data.frame with columns log2FoldChange, pvalue, padj, stat.
#' @examples
#' set.seed(42)
#' counts <- matrix(
#'   as.integer(abs(rnorm(60, mean = 100, sd = 30))),
#'   nrow = 10, ncol = 6,
#'   dimnames = list(paste0("G", 1:10), paste0("S", 1:6))
#' )
#' conds <- c("Cond1", "Cond1", "Cond1", "Cond2", "Cond2", "Cond2")
#' run_limma(counts, columns = colnames(counts), conds = conds)
#' @export
run_limma <- function(counts, metadata = NULL, columns = NULL, conds = NULL,
                      params = list()) {
  de_assert_count_matrix(counts)
  defaults <- list(
    covariates = "NoCovariate",
    norm_fact  = "TMM",
    fit_type   = "ls",
    norm_bet   = "none"
  )
  params <- modifyList(defaults, params)

  data <- counts[, columns]
  data[, columns] <- apply(data[, columns], 2, as.integer)
  conds <- factor(conds)
  covariates <- strsplit(params$covariates, split = "\\|")[[1]]

  cnum <- summary(conds)[levels(conds)[1]]
  tnum <- summary(conds)[levels(conds)[2]]
  filtd <- data
  des <- factor(c(rep(levels(conds)[1], cnum), rep(levels(conds)[2], tnum)))

  # Note: legacy code did `names(filtd) <- des` which produced the
  # "Repeated column names found in count matrix" warning. We intentionally
  # do NOT do that here -- the names are unused downstream and removing the
  # rename does not change result values (verified by snapshot equality).

  if (!identical(covariates, "NoCovariate")) {
    design <- cbind(Grp1 = 1, Grp2vs1 = des)
    sample_col_ind <- which(apply(metadata, 2, function(x) sum(x %in% columns) == length(columns)))
    sample_col <- colnames(metadata)[sample_col_ind]
    cov_metadata <- metadata[match(columns, metadata[, sample_col]), covariates, drop = FALSE]
    for (i in seq_along(covariates)) {
      design <- cbind(design, factor(cov_metadata[, i]))
      colnames(design)[length(colnames(design))] <- paste0("covariate", i)
    }
  } else {
    design <- cbind(Grp1 = 1, Grp2vs1 = des)
  }

  dge <- edgeR::DGEList(counts = filtd, group = des)
  dge <- edgeR::calcNormFactors(dge, method = params$norm_fact, samples = columns)
  v <- limma::voom(dge, design = design, normalize.method = params$norm_bet, plot = FALSE)
  fit <- limma::lmFit(v, design = design)
  fit <- limma::eBayes(fit)

  options(digits = 4)
  tab <- limma::topTable(fit, coef = 2, number = dim(fit)[1], genelist = fit$genes$NAME)
  # D2.5 fix Issue 5: include `baseMean` so Limma results have parity
  # with DESeq2's column set in the Rmd report (MA plot x-axis,
  # formatRound). limma's `AveExpr` is mean log2-expression after voom
  # normalization; we use 2^AveExpr to put it on a linear scale.
  base_mean <- if (!is.null(tab$AveExpr)) {
    2 ^ tab$AveExpr
  } else {
    rowMeans(filtd)
  }
  res <- data.frame(
    baseMean       = base_mean,
    log2FoldChange = tab$logFC,
    pvalue         = tab$P.Value,
    padj           = tab$adj.P.Val,
    stat           = tab$t
  )
  rownames(res) <- rownames(tab)
  res
}

#' Dispatch a DE run by method name.
#'
#' @param method One of "DESeq2", "EdgeR", "Limma".
#' @inheritParams run_deseq2
#' @param return_dds Logical. Forwarded to [run_deseq2()] for the DESeq2
#'   branch; ignored for edgeR/limma. When TRUE for DESeq2 the function
#'   returns `list(res, dds)`; for non-DESeq2 methods the standard
#'   per-method result object is wrapped to `list(res = <obj>, dds = NULL)`
#'   so downstream code can pattern-match a single shape.
#' @return Method-specific result object.
#' @examples
#' set.seed(42)
#' counts <- matrix(
#'   as.integer(abs(rnorm(60, mean = 100, sd = 30))),
#'   nrow = 10, ncol = 6,
#'   dimnames = list(paste0("G", 1:10), paste0("S", 1:6))
#' )
#' conds <- c("Cond1", "Cond1", "Cond1", "Cond2", "Cond2", "Cond2")
#' run_de("EdgeR", counts, columns = colnames(counts), conds = conds)
#' @export
run_de <- function(method, counts, metadata = NULL, columns = NULL,
                   conds = NULL, params = list(), return_dds = FALSE) {
  if (isTRUE(return_dds)) {
    return(switch(method,
      "DESeq2" = run_deseq2(counts, metadata, columns, conds, params,
                            return_dds = TRUE),
      "EdgeR"  = list(res = run_edger(counts, metadata, columns, conds, params),
                      dds = NULL),
      "Limma"  = list(res = run_limma(counts, metadata, columns, conds, params),
                      dds = NULL),
      de_error(
        paste0("Unknown DE method: ", method),
        class = "unknown_de_method"
      )
    ))
  }
  switch(method,
    "DESeq2" = run_deseq2(counts, metadata, columns, conds, params),
    "EdgeR"  = run_edger(counts, metadata, columns, conds, params),
    "Limma"  = run_limma(counts, metadata, columns, conds, params),
    de_error(
      paste0("Unknown DE method: ", method),
      class = "unknown_de_method"
    )
  )
}
