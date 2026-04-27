#' applyFilters
#'
#' Applies filters based on user selected parameters to be
#' displayed within the DEBrowser.
#'
#' @param filt_data, loaded dataset
#' @param cols, selected samples
#' @param conds, seleced conditions
#' @param input, input parameters
#' @return data
#' @export
#'
#' @examples
#' x <- applyFilters()
#'
applyFilters <- function(filt_data = NULL, cols = NULL, conds = NULL,
                         input = NULL) {
  apply_de_filters(filt_data, cols, conds, filter_params_from_input(input))
}
#' getSelectedDatasetInput
#'
#' Gathers the user selected dataset output to be displayed.
#'
#' @param rdata, filtered dataset
#' @param getSelected, selected data
#' @param getMostVaried, most varied data
#' @param mergedComparison, merged comparison data
#' @param input, input parameters
#' @return data
#' @export
#'
#' @examples
#' x <- getSelectedDatasetInput()
#'
getSelectedDatasetInput <- function(rdata = NULL, getSelected = NULL,
                                    getMostVaried = NULL,
                                    mergedComparison = NULL,
                                    input = NULL) {
  select_dataset(
    rdata,
    get_selected         = getSelected,
    get_most_varied_data = getMostVaried,
    merged_comparison    = mergedComparison,
    params               = filter_params_from_input(input)
  )
}


#' getMostVariedList
#'
#' Calculates the most varied genes to be used for specific plots
#' within the DEBrowser.
#'
#' @param datavar, loaded dataset
#' @param cols, selected columns
#' @param input, input
#' @return data
#' @export
#'
#' @examples
#' x <- getMostVariedList()
#'
getMostVariedList <- function(datavar = NULL, cols = NULL, input = NULL) {
  get_most_varied(datavar, cols, filter_params_from_input(input))
}


#' getSearchData
#'
#' search the geneset in the tables and return it
#'
#' @param dat, table data
#' @param input, input params
#' @return data
#' @export
#'
#' @examples
#' x <- getSearchData()
#'
getSearchData <- function(dat = NULL, input = NULL) {
  search_geneset(dat, filter_params_from_input(input))
}

#' getGeneSetData
#'
#' Gathers the specified gene set list to be used within the
#' DEBrowser.
#'
#' @param data, loaded dataset
#' @param geneset, given gene set
#' @return data
#' @export
#'
#' @examples
#' x <- getGeneSetData()
#'
getGeneSetData <- function(data = NULL, geneset = NULL) {
  if (is.null(data)) {
    return(NULL)
  }

  geneset1 <- unique(unlist(strsplit(geneset, split = "[:;, \t\n\t]")))
  geneset2 <- geneset1[geneset1 != ""]
  if (length(geneset2) > 3) {
    geneset2 <- paste0("^", geneset2, "$")
  }

  dat1 <- as.data.frame(data)
  if (!("ID" %in% names(dat1))) {
    dat2 <- addID(dat1)
  } else {
    dat2 <- dat1
  }

  dat2$ID <- factor(as.character(dat2$ID))

  geneset4 <- unique(as.vector(unlist(lapply(
    toupper(geneset2),
    function(x) {
      sapply(
        dat2[(grepl(x, toupper(dat2[, "ID"]))), "ID"],
        as.character
      )
    }
  ))))
  retset <- data.frame(dat2[geneset4, ])
  retset
}

#' getUp
#' get up regulated data
#'
#' @param filt_data, filt_data
#' @return data
#' @export
#'
#' @examples
#' x <- getUp()
#'
getUp <- function(filt_data = NULL) {
  if (is.null(filt_data)) {
    return(NULL)
  }
  filt_data[
    filt_data[, "Legend"] == "Up" |
      filt_data[, "Legend"] == "GS",
  ]
}
#' getDown
#' get down regulated data
#'
#' @param filt_data, filt_data
#' @return data
#' @export
#'
#' @examples
#' x <- getDown()
#'
getDown <- function(filt_data = NULL) {
  if (is.null(filt_data)) {
    return(NULL)
  }
  filt_data[
    filt_data[, "Legend"] == "Down" |
      filt_data[, "Legend"] == "GS",
  ]
}

#' getUpDown
#' get up+down regulated data
#'
#' @param filt_data, filt_data
#' @return data
#' @export
#'
#' @examples
#' x <- getUpDown()
#'
getUpDown <- function(filt_data = NULL) {
  if (is.null(filt_data)) {
    return(NULL)
  }
  filt_data[
    filt_data[, "Legend"] == "Up" |
      filt_data[, "Legend"] == "Down" |
      filt_data[, "Legend"] == "GS",
  ]
}

#' getDataForTables
#' get data to fill up tables tab
#'

#' @param input, input parameters
#' @param init_data, initial dataset
#' @param filt_data, filt_data
#' @param selected, selected genes
#' @param getMostVaried, most varied genes
#' @param mergedComp, merged comparison set
#' @param explainedData, pca gene set
#' @return data
#' @export
#'
#' @examples
#' x <- getDataForTables()
#'
getDataForTables <- function(
  input = NULL, init_data = NULL,
  filt_data = NULL, selected = NULL,
  getMostVaried = NULL, mergedComp = NULL,
  explainedData = NULL
) {
  if (is.null(init_data)) {
    return(NULL)
  }
  if (is.null(filt_data)) filt_data <- init_data
  pastr <- "padj"
  fcstr <- "foldChange"
  dat <- NULL
  if (input$dataset == "alldetected") {
    dat <- getSearchData(filt_data, input)
  } else if (input$dataset == "up+down") {
    if (!is.null(filt_data)) {
      dat <- getSearchData(getUpDown(filt_data), input)
    }
  } else if (input$dataset == "up") {
    if (!is.null(filt_data)) {
      dat <- getSearchData(getUp(filt_data), input)
    }
  } else if (input$dataset == "down") {
    if (!is.null(filt_data)) {
      dat <- getSearchData(getDown(filt_data), input)
    }
  } else if (input$dataset == "selected") {
    dat <- getSearchData(selected, input)
  } else if (input$dataset == "most-varied") {
    if (!is.null(filt_data)) {
      d <- filt_data[rownames(getMostVaried), ]
    } else {
      d <- init_data[rownames(getMostVaried), ]
    }
    dat <- getSearchData(d, input)
  } else if (input$dataset == "comparisons") {
    if (is.null(mergedComp)) {
      return(NULL)
    }
    fcstr <- colnames(mergedComp)[grepl("foldChange", colnames(mergedComp))]
    pastr <- colnames(mergedComp)[grepl("padj", colnames(mergedComp))]
    dat <- getSearchData(mergedComp, input)
  } else if (input$dataset == "searched") {
    dat <- getSearchData(init_data, input)
  }
  list(dat, pastr, fcstr)
}


#' getMergedComparison
#'
#' Gathers the merged comparison data to be used within the
#' DEBrowser.
#' @param dc, data container
#' @param nc, the number of comparisons
#' @param input, input params
#' @return data
#' @export
#'
#' @examples
#' x <- getMergedComparison()
#'
getMergedComparison <- function(dc = NULL, nc = NULL, input = NULL) {
  if (is.null(dc)) {
    return(NULL)
  }
  mergeresults <- c()
  mergedata <- c()
  allsamples <- c()
  for (ni in seq(1:nc)) {
    tmp <- dc[[ni]]$init_data[, c("foldChange", "padj")]

    samples <- dc[[ni]]$cols
    cond_names <- dc[[ni]]$cond_names
    tt <- paste0(cond_names[1], ".vs.", cond_names[2])
    # tt <- paste0("C", (2*ni-1),".vs.C",(2*ni))
    fctt <- paste0("foldChange.", tt)
    patt <- paste0("padj.", tt)
    colnames(tmp) <- c(fctt, patt)
    if (ni == 1) {
      allsamples <- samples
      mergeresults <- tmp
      mergedata <- dc[[ni]]$init_data[, samples]
    } else {
      mergeresults[, fctt] <- character(nrow(tmp))
      mergeresults[, patt] <- character(nrow(tmp))
      mergeresults[rownames(tmp), c(fctt, patt)] <- tmp[, c(fctt, patt)]
      mergeresults[rownames(tmp), patt] <- tmp[, patt]
      mergeresults[is.na(mergeresults[, fctt]), fctt] <- 1
      mergeresults[is.na(mergeresults[, patt]), patt] <- 1
      remaining_samples <- dc[[ni]]$cols[!(samples %in% colnames(mergedata))]
      allsamples <- unique(c(allsamples, remaining_samples))
      mergedata <- cbind(mergedata, dc[[ni]]$init_data[, remaining_samples])
      colnames(mergedata) <- allsamples
    }
  }
  mergedata[, allsamples] <- getNormalizedMatrix(mergedata[, allsamples], input$norm_method)
  cbind(mergedata, mergeresults)
}

#' applyFiltersToMergedComparison
#'
#' Gathers the merged comparison data to be used within the
#' DEBrowser.
#'
#' @param dc, all data
#' @param nc, the number of comparisons
#' @param input, input params
#' @return data
#' @export
#'
#' @examples
#' x <- applyFiltersToMergedComparison()
#'
applyFiltersToMergedComparison <- function(
  dc = NULL,
  nc = NULL, input = NULL
) {
  if (is.null(dc)) {
    return(NULL)
  }
  merged <- getMergedComparison(dc, nc, input)
  padj_cutoff <- as.numeric(input$padj)
  foldChange_cutoff <- as.numeric(input$foldChange)
  if (is.null(merged$Legend)) {
    merged$Legend <- character(nrow(merged))
    merged$Legend <- "NS"
  }
  for (ni in seq(1:nc)) {
    cond_names <- dc[[ni]]$cond_names
    tt <- paste0(cond_names[1], ".vs.", cond_names[2])
    # tt <- paste0("C", (2*ni-1),".vs.C",(2*ni))
    merged[which(as.numeric(merged[, c(paste0("foldChange.", tt))]) >=
      foldChange_cutoff & as.numeric(merged[, c(paste0("padj.", tt))]) <=
      padj_cutoff), "Legend"] <- "Sig"
    merged[which(as.numeric(merged[, c(paste0("foldChange.", tt))]) <=
      1 / foldChange_cutoff & as.numeric(merged[, c(paste0("padj.", tt))]) <=
      padj_cutoff), "Legend"] <- "Sig"
  }
  merged
}

#' removeCols
#'
#' remove unnecessary columns
#'
#' @param cols, columns that are going to be removed from data frame
#' @param dat, data
#' @return data
#' @export
#'
#' @examples
#' x <- removeCols()
#'
removeCols <- function(cols = NULL, dat = NULL) {
  if (is.null(dat)) {
    return(NULL)
  }
  for (colnum in seq(1:length(cols))) {
    if (cols[colnum] %in% colnames(dat)) {
      dat[, cols[colnum]] <- NULL
    }
  }
  dat
}
