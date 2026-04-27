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
#' @return DESeqResults
#' @export
run_deseq2 <- function(counts, metadata = NULL, columns = NULL, conds = NULL,
                       params = list()) {
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
    test_type  = "Wald",
    shrinkage  = "None"
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
  res
}
