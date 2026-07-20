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
      vapply(
        dat2[(grepl(x, toupper(dat2[, "ID"]))), "ID"],
        as.character,
        character(1)
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
getDataForTables <- function(input = NULL, init_data = NULL,
                             filt_data = NULL, selected = NULL,
                             getMostVaried = NULL, mergedComp = NULL,
                             explainedData = NULL) {
  get_table_data(
    init_data            = init_data,
    filt_data            = filt_data,
    selected             = selected,
    get_most_varied_data = getMostVaried,
    merged_comp          = mergedComp,
    explained_data       = explainedData,
    params               = filter_params_from_input(input)
  )
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
  merge_comparisons(dc, nc, filter_params_from_input(input))
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
applyFiltersToMergedComparison <- function(dc = NULL, nc = NULL,
                                           input = NULL) {
  apply_merged_filters(dc, nc, filter_params_from_input(input))
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
  for (colnum in seq_along(cols)) {
    if (cols[colnum] %in% colnames(dat)) {
      dat[, cols[colnum]] <- NULL
    }
  }
  dat
}
