#' debrowserdeanalysis
#'
#' Module to perform and visualize DE results.
#'
#' @param id, namespace id
#' @param data, a matrix that includes expression values
#' @param metadata, metadata
#' @param columns, columns
#' @param conds, conditions
#' @param params, de parameters
#' @return DE panel
#' @export
#'
#' @examples
#' \dontrun{
#' x <- debrowserdeanalysis("de")
#' }
#'
debrowserdeanalysis <- function(id, data = NULL, metadata = NULL,
                                columns = NULL, conds = NULL, params = NULL) {
  if (is.null(data)) {
    return(NULL)
  }
  moduleServer(id, function(input, output, session) {
    deres <- reactive({
      runDE(data, metadata, columns, conds, params)
    })
    prepDat <- reactive({
      applyFiltersNew(addDataCols(data, deres(), columns, conds), input)
    })
    observe({
      if (!is.null(input$legendradio)) {
        if (input$legendradio == "All") {
          dat <- prepDat()
        } else {
          dat <- prepDat()[prepDat()$Legend == input$legendradio, ]
        }
      } else {
        dat <- NULL
      }
      dat2 <- removeCols(c("ID", "x", "y", "Legend", "Size"), dat)
      getTableDetails(output, session, "DEResults", dat2, modal = FALSE)
    })
    list(dat = prepDat)
  })
}
#' getDEResultsUI
#' Creates a panel to visualize DE results
#'
#' @param id, namespace id
#' @return panel
#' @examples
#' x <- getDEResultsUI("batcheffect")
#'
#' @export
#'
getDEResultsUI <- function(id) {
  ns <- NS(id)
  list(
    fluidRow(
      bslib::card(
        bslib::card_header("DE Results"),
        fluidRow(
          column(
            12,
            uiOutput(ns("DEResults"))
          ),
          actionButtonDE("goMain", "Go to Main Plots", styleclass = "primary")
        )
      )
    )
  )
}

#' cutOffSelectionUI
#'
#' Gathers the cut off selection for DE analysis
#'
#' @param id, namespace id
#' @note \code{cutOffSelectionUI}
#' @return returns the left menu according to the selected tab;
#' @examples
#' x <- cutOffSelectionUI("cutoff")
#' @export
#'
cutOffSelectionUI <- function(id) {
  ns <- NS(id)
  list(
    getLegendRadio(id),
    textInput(ns("padj"), "padj value cut off", value = "0.01"),
    textInput(ns("foldChange"), "or foldChange", value = "2")
  )
}

#' applyFiltersNew
#'
#' Apply filters based on foldChange cutoff and padj value.
#' This function adds a "Legend" column with "Up", "Down" or
#' "NS" values for visualization.
#'
#' @param data, loaded dataset
#' @param input, input parameters
#' @return data
#' @export
#'
#' @examples
#' x <- applyFiltersNew()
#'
applyFiltersNew <- function(data = NULL, input = NULL) {
  if (is.null(data)) {
    return(NULL)
  }
  padj_cutoff <- as.numeric(input$padj)
  foldChange_cutoff <- as.numeric(input$foldChange)
  m <- data
  if (!("Legend" %in% names(m))) {
    m$Legend <- character(nrow(m))
    m$Legend <- "NS"
  }
  m$Legend[m$foldChange >= foldChange_cutoff &
    m$padj <= padj_cutoff] <- "Up"
  m$Legend[m$foldChange <= (1 / foldChange_cutoff) &
    m$padj <= padj_cutoff] <- "Down"
  return(m)
}


#' runDE
#'
#' Run DE algorithms on the selected parameters.  Output is
#' to be used for the interactive display.
#'
#' @param data, A matrix that includes all the expression raw counts,
#'     rownames has to be the gene, isoform or region names/IDs
#' @param metadata, metadata of the matrix of expression raw counts
#' @param columns, is a vector that includes the columns that are going
#'     to be analyzed. These columns has to match with the given data.
#' @param conds, experimental conditions. The order has to match
#'     with the column order
#' @param params, all params for the DE methods
#' @return de results
#'
#' @export
#'
#' @examples
#' x <- runDE()
#'
runDE <- function(data = NULL, metadata = NULL, columns = NULL, conds = NULL, params = NULL) {
  if (is.null(data)) {
    return(NULL)
  }
  de_res <- NULL
  if (startsWith(params[1], "DESeq2")) {
    de_res <- runDESeq2(data, metadata, columns, conds, params)
  } else if (startsWith(params[1], "EdgeR")) {
    de_res <- runEdgeR(data, metadata, columns, conds, params)
  } else if (startsWith(params[1], "Limma")) {
    de_res <- runLimma(data, metadata, columns, conds, params)
  }
  data.frame(de_res)
}

#' runDESeq2
#'
#' Run DESeq2 algorithm on the selected conditions.  Output is
#' to be used for the interactive display.
#'
#' @param data, A matrix that includes all the expression raw counts,
#'     rownames has to be the gene, isoform or region names/IDs
#' @param metadata, metadata of the matrix of expression raw counts
#' @param columns, is a vector that includes the columns that are going
#'     to be analyzed. These columns has to match with the given data.
#' @param conds, experimental conditions. The order has to match
#'     with the column order
#' @param params, fitType: either "parametric", "local", or "mean" for the type
#'     of fitting of dispersions to the mean intensity.
#'     See estimateDispersions for description.
#'  betaPrior: whether or not to put a zero-mean normal prior
#'     on the non-intercept coefficients See nbinomWaldTest for
#'     description of the calculation of the beta prior. By default,
#'     the beta prior is used only for the Wald test, but can also be
#'     specified for the likelihood ratio test.
#' testType: either "Wald" or "LRT", which will then use either
#'     Wald significance tests (defined by nbinomWaldTest), or the
#'     likelihood ratio test on the difference in deviance between a
#'     full and reduced model formula (defined by nbinomLRT)
#' shrinkage: Adds shrunken log2 fold changes (LFC) and SE to a results
#'     table from DESeq run without LFC shrinkage. For consistency with
#'     results, the column name lfcSE is used here although what is
#'     returned is a posterior SD. Three shrinkage estimators for
#'     LFC are available via type (see the vignette for more details
#'     on the estimators). The apeglm publication demonstrates that
#'     'apeglm' and 'ashr' outperform the original 'normal' shrinkage
#'     estimator.
#' @return deseq2 results
#'
#' @export
#'
#' @examples
#' x <- runDESeq2()
#'
runDESeq2 <- function(data = NULL, metadata = NULL, columns = NULL,
                      conds = NULL, params = NULL) {
  if (is.null(data)) {
    return(NULL)
  }
  if (length(params) < 3) {
    params <- strsplit(params, ",")[[1]]
  }
  pure_params <- list(
    covariates = if (!is.null(params[2])) params[2] else "NoCovariate",
    fit_type   = if (!is.null(params[3])) params[3] else "parametric",
    beta_prior = if (!is.null(params[4])) as.logical(params[4]) else FALSE,
    test_type  = if (!is.null(params[5])) params[5] else "Wald",
    shrinkage  = if (!is.null(params[6])) params[6] else "None"
  )
  tryCatch(
    run_deseq2(data, metadata, columns, conds, pure_params),
    too_few_columns = function(e) {
      showNotification(conditionMessage(e), type = "error")
      NULL
    }
  )
}

#' runEdgeR
#'
#' Run EdgeR algorithm on the selected conditions.  Output is
#' to be used for the interactive display.
#'
#' @param data, A matrix that includes all the expression raw counts,
#'     rownames has to be the gene, isoform or region names/IDs
#' @param metadata, metadata of the matrix of expression raw counts
#' @param columns, is a vector that includes the columns that are going
#'     to be analyzed. These columns has to match with the given data.
#' @param conds, experimental conditions. The order has to match
#'     with the column order
#' @param params, normfact: Calculate normalization factors to scale the raw
#'     library sizes. Values can be "TMM","RLE","upperquartile","none".
#' dispersion: either a numeric vector of dispersions or a character
#'     string indicating that dispersions should be taken from the data
#'     object. If a numeric vector, then can be either of length one or
#'     of length equal to the number of genes. Allowable character
#'     values are "common", "trended", "tagwise" or "auto".
#'     Default behavior ("auto" is to use most complex dispersions
#'     found in data object.
#' testType: exactTest or glmLRT. exactTest: Computes p-values for differential
#'     abundance for each gene between two digital libraries, conditioning
#'     on the total count for each gene. The counts in each group as a
#'     proportion of the whole are assumed to follow a binomial distribution.
#'     glmLRT: Fit a negative binomial generalized log-linear model to the read
#'     counts for each gene. Conduct genewise statistical tests for a given
#'     coefficient or coefficient contrast.
#' @return edgeR results
#'
#' @export
#'
#' @examples
#' x <- runEdgeR()
#'
runEdgeR <- function(data = NULL, metadata = NULL, columns = NULL,
                     conds = NULL, params = NULL) {
  if (is.null(data)) {
    return(NULL)
  }
  if (length(params) < 3) {
    params <- strsplit(params, ",")[[1]]
  }
  pure_params <- list(
    covariates = if (!is.null(params[2])) params[2] else "NoCovariate",
    norm_fact  = if (!is.null(params[3])) params[3] else "TMM",
    dispersion = if (!is.null(params[4])) params[4] else "0",
    test_type  = if (!is.null(params[5])) params[5] else "exactTest"
  )
  tryCatch(
    run_edger(data, metadata, columns, conds, pure_params),
    bad_dispersion = function(e) {
      showNotification(conditionMessage(e), type = "error")
      NULL
    }
  )
}

#' runLimma
#'
#' Run Limma algorithm on the selected conditions.  Output is
#' to be used for the interactive display.
#'
#' @param data, A matrix that includes all the expression raw counts,
#'     rownames has to be the gene, isoform or region names/IDs
#' @param metadata, metadata of the matrix of expression raw counts
#' @param columns, is a vector that includes the columns that are going
#'     to be analyzed. These columns has to match with the given data.
#' @param conds, experimental conditions. The order has to match
#'     with the column order
#' @param params, normfact: Calculate normalization factors to scale the raw
#'     library sizes. Values can be "TMM","RLE","upperquartile","none".
#' fitType, fitting method; "ls" for least squares or "robust"
#'     for robust regression
#' normBet: Normalizes expression intensities so that the
#'     intensities or log-ratios have similar distributions across a set of arrays.
#' @return Limma results
#'
#' @export
#'
#' @examples
#' x <- runLimma()
#'
runLimma <- function(data = NULL, metadata = NULL, columns = NULL,
                     conds = NULL, params = NULL) {
  if (is.null(data)) {
    return(NULL)
  }
  if (length(params) < 3) {
    params <- strsplit(params, ",")[[1]]
  }
  pure_params <- list(
    covariates = if (!is.null(params[2])) params[2] else "NoCovariate",
    norm_fact  = if (!is.null(params[3])) params[3] else "TMM",
    fit_type   = if (!is.null(params[4])) params[4] else "ls",
    norm_bet   = if (!is.null(params[5])) params[5] else "none"
  )
  run_limma(data, metadata, columns, conds, pure_params)
}

#' prepGroup
#'
#' prepare group table
#'
#' @param cols, columns
#' @param conds, inputconds
#' @param metadata, metadata
#' @param covariates, covariates
#' @return data
#' @export
#'
#' @examples
#' x <- prepGroup()
#'
prepGroup <- function(conds = NULL, cols = NULL, metadata = NULL, covariates = NULL) {
  if (is.null(conds) || is.null(cols)) {
    return(NULL)
  }
  coldata <- data.frame(cbind(cols, conds))
  coldata$conds <- factor(coldata$conds)
  colnames_coldata <- c("libname", "group")
  if (!is.null(covariates)) {
    if (covariates != "NoCovariate") {
      sample_column_ind <- which(apply(metadata, 2, function(x) sum(x %in% cols) == length(cols)))
      sample_column <- colnames(metadata)[sample_column_ind]
      covariates <- metadata[match(cols, metadata[, sample_column]), covariates, drop = FALSE]
      for (i in 1:ncol(covariates)) {
        cur_covariate <- covariates[, i]
        cur_covariate <- factor(cur_covariate)
        coldata <- data.frame(cbind(coldata, cur_covariate))
        colnames_coldata <- c(colnames_coldata, paste0("covariate", i))
      }
    }
  }
  colnames(coldata) <- colnames_coldata
  coldata
}

#' addDataCols
#'
#' add aditional data columns to de results
#'
#' @param data, loaded dataset
#' @param de_res, de results
#' @param cols, columns
#' @param conds, inputconds
#' @return data
#' @export
#'
#' @examples
#' x <- addDataCols()
#'
addDataCols <- function(data = NULL, de_res = NULL, cols = NULL, conds = NULL) {
  if (is.null(data) || (nrow(de_res) == 0 && ncol(de_res) == 0)) {
    return(NULL)
  }
  norm_data <- data[, cols]

  coldata <- prepGroup(conds, cols)

  mean_cond_first <- getMean(norm_data, as.vector(coldata[coldata$group == levels(coldata$group)[1], "libname"]))
  mean_cond_second <- getMean(norm_data, as.vector(coldata[coldata$group == levels(coldata$group)[2], "libname"]))

  m <- cbind(
    rownames(de_res), norm_data[rownames(de_res), cols],
    log10(unlist(mean_cond_second) + 1),
    log10(unlist(mean_cond_first) + 1),
    de_res[
      rownames(de_res),
      c("padj", "log2FoldChange", "pvalue", "stat")
    ],
    2^de_res[
      rownames(de_res),
      "log2FoldChange"
    ],
    -1 * log10(de_res[rownames(de_res), "padj"])
  )
  colnames(m) <- c(
    "ID", cols, "x", "y",
    "padj", "log2FoldChange", "pvalue", "stat",
    "foldChange", "log10padj"
  )
  m <- as.data.frame(m)
  m$padj[is.na(m[paste0("padj")])] <- 1
  m$pvalue[is.na(m[paste0("pvalue")])] <- 1
  m
}

#' getMean
#'
#' Gathers the mean for selected condition.
#'
#' @param data, dataset
#' @param selcols, input cols
#' @return data
#' @export
#'
#' @examples
#' x <- getMean()
#'
getMean <- function(data = NULL, selcols = NULL) {
  if (is.null(data)) {
    return(NULL)
  }
  mean_cond <- NULL
  if (length(selcols) > 1) {
    mean_cond <- list(rowMeans(data[, selcols]))
  } else {
    mean_cond <- list(data[selcols])
  }
  mean_cond
}

#' getLegendRadio
#'
#' Radio buttons for the types in the legend
#' @param id, namespace id
#' @note \code{getLegendRadio}
#' @return radio control
#'
#' @examples
#'
#' x <- getLegendRadio("deprog")
#'
#' @export
#'
getLegendRadio <- function(id) {
  ns <- NS(id)
  types <- c("Up", "Down", "NS", "All")
  radioButtons(
    inputId = ns("legendradio"),
    label = "Data Type:",
    choices = types
  )
}
