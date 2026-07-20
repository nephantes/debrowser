#' Apply DE filters and label Up/Down/NS/MV/GS rows.
#'
#' Pure function -- no Shiny dependency. Re-normalizes the count columns,
#' computes per-condition x/y log10 means, and labels each row by cutoff.
#'
#' @param filt_data data.frame with columns including `foldChange`, `padj`,
#'   plus all `cols`.
#' @param cols Character vector of sample column names.
#' @param conds Character vector of per-column condition labels (length ==
#'   length(cols)). Values look like "Cond1"/"Cond2"/...
#' @param params Named list with components:
#'   - `padj_cutoff` (numeric or numeric-string)
#'   - `fold_cutoff` (numeric or numeric-string)
#'   - `dataset` ("up"/"down"/"up+down"/"alldetected"/"selected"/
#'     "most-varied"/"comparisons"/"searched")
#'   - `compselect` (integer; default 1)
#'   - `norm_method` (forwarded to [normalize_counts()])
#'   - `geneset_area` (string of search terms; "" = none)
#'   - `method_tab` (UI tab id; geneset overlay only applies on "panel1")
#'   - `top_n`, `min_count` (only for `dataset == "most-varied"`)
#' @return data.frame with added `x`, `y`, `Legend`, `Size` columns; or NULL.
#' @examples
#' cols <- c("S1", "S2", "S3", "S4")
#' conds <- c("Cond1", "Cond1", "Cond2", "Cond2")
#' fd <- data.frame(
#'   S1 = c(100L, 5L), S2 = c(120L, 8L),
#'   S3 = c(10L, 200L), S4 = c(12L, 220L),
#'   foldChange = c(10, 0.05), padj = c(0.001, 0.001),
#'   row.names = c("GeneA", "GeneB")
#' )
#' params <- list(padj_cutoff = 0.05, fold_cutoff = 2, dataset = "up+down",
#'                compselect = 1, norm_method = "none")
#' apply_de_filters(fd, cols, conds, params)
#' @export
apply_de_filters <- function(filt_data, cols, conds, params = list()) {
  if (is.null(filt_data) || is.null(params$padj_cutoff) ||
    is.null(params$fold_cutoff)) {
    return(NULL)
  }

  compselect <- if (!is.null(params$compselect)) {
    as.integer(params$compselect)
  } else {
    1L
  }
  x <- paste0("Cond", 2 * compselect - 1)
  y <- paste0("Cond", 2 * compselect)

  norm_data <- normalize_counts(filt_data[, cols], method = params$norm_method)
  g <- data.frame(cbind(cols, conds))

  cols_x <- as.vector(g[g$conds == x, "cols"])
  filt_data$x <- if (length(cols_x) > 1L) {
    log10(rowMeans(norm_data[, cols_x]) + 0.1)
  } else {
    log10(norm_data[, cols_x] + 0.1)
  }

  cols_y <- as.vector(g[g$conds == y, "cols"])
  filt_data$y <- if (length(cols_y) > 1L) {
    log10(rowMeans(norm_data[, cols_y]) + 0.1)
  } else {
    log10(norm_data[, cols_y] + 0.1)
  }

  filt_data[, cols] <- norm_data

  padj_cutoff <- as.numeric(params$padj_cutoff)
  fold_cutoff <- as.numeric(params$fold_cutoff)

  m <- filt_data
  m$Legend <- "NS"
  m$Size <- "40"

  ds <- params$dataset
  if (ds %in% c("up", "up+down", "selected")) {
    m$Legend[m$foldChange >= fold_cutoff & m$padj <= padj_cutoff] <- "Up"
  }
  if (ds %in% c("down", "up+down", "selected")) {
    m$Legend[m$foldChange <= (1 / fold_cutoff) & m$padj <= padj_cutoff] <- "Down"
  }
  if (identical(ds, "most-varied") && !is.null(cols)) {
    most_varied <- get_most_varied(m, cols, params)
    m[rownames(most_varied), "Legend"] <- "MV"
  }
  if (!is.null(params$geneset_area) && params$geneset_area != "" &&
    identical(params$method_tab, "panel1")) {
    genelist <- getGeneSetData(m, c(params$geneset_area))
    m[rownames(genelist), "Legend"] <- "GS"
    m[rownames(genelist), "Size"] <- "100"
    tmp <- m["Legend" == "GS", ]
    tmp1 <- m["Legend" != "GS", ]
    m <- rbind(tmp1, tmp)
  }
  m
}

#' Compute the most-varied genes by coefficient of variation.
#'
#' @param datavar data.frame with sample columns.
#' @param cols Character vector of sample column names.
#' @param params Named list with `top_n` (int) and `min_count` (int).
#' @return data.frame of the top-N most-varied rows.
#' @examples
#' cols <- paste0("S", 1:6)
#' df <- as.data.frame(matrix(
#'   c(100, 200, 150, 80, 250, 130,
#'     40,  60,  55, 30,  70,  45,
#'     10,  10,  10, 10,  10,  10),
#'   nrow = 3, byrow = TRUE,
#'   dimnames = list(paste0("Gene", 1:3), cols)
#' ))
#' get_most_varied(df, cols, list(top_n = 2, min_count = 0))
#' @export
get_most_varied <- function(datavar, cols, params = list()) {
  if (is.null(datavar)) {
    return(NULL)
  }
  topn <- as.integer(as.numeric(params$top_n))
  min_count <- as.integer(as.numeric(params$min_count))
  filtvar <- datavar[rowSums(datavar[, cols]) > min_count, ]
  cv <- cbind(apply(filtvar, 1, function(x) {
    sd(x, na.rm = TRUE) / mean(x, na.rm = TRUE)
  }), 1)
  colnames(cv) <- c("coeff", "a")
  cvsort <- cv[order(cv[, 1], decreasing = TRUE), ]
  topindex <- min(nrow(cvsort), topn)
  data.frame(datavar[rownames(head(cvsort, topindex)), ])
}

#' Pick a subset of `rdata` based on the `dataset` filter param.
#'
#' @param rdata Filtered data.frame (typically the output of
#'   [apply_de_filters()]).
#' @param get_selected Optional; the user's lasso/click selection.
#' @param get_most_varied_data Optional; the most-varied subset to use when
#'   `dataset == "most-varied"`.
#' @param merged_comparison Optional; merged comparisons table.
#' @param params Named list with `dataset` and (optionally) `selected_plot`,
#'   `geneset_area`.
#' @return Subset data.frame.
#' @examples
#' rdata <- data.frame(
#'   foldChange = c(5, 0.1, 1.0),
#'   padj = c(0.01, 0.01, 0.5),
#'   Legend = c("Up", "Down", "NS"),
#'   row.names = c("GeneA", "GeneB", "GeneC")
#' )
#' select_dataset(rdata, params = list(dataset = "alldetected"))
#' @export
select_dataset <- function(rdata, get_selected = NULL,
                           get_most_varied_data = NULL,
                           merged_comparison = NULL, params = list()) {
  if (is.null(rdata)) {
    return(NULL)
  }
  ds <- params$dataset
  switch(ds,
    "up"           = getUp(rdata),
    "down"         = getDown(rdata),
    "up+down"      = getUpDown(rdata),
    "alldetected"  = rdata,
    "selected"     = if (!is.null(params$selected_plot)) get_selected else rdata,
    "most-varied"  = rdata[rownames(get_most_varied_data), ],
    "comparisons"  = merged_comparison,
    "searched"     = search_geneset(rdata, params),
    rdata
  )
}

#' Search a data.frame's `ID` column for a gene-set list.
#'
#' @param dat data.frame with an `ID` column (or first column treated as ID).
#' @param params Named list with `geneset_area` (string of search terms).
#' @return Filtered data.frame; or `dat` unchanged if `geneset_area` is empty.
#' @examples
#' dat <- data.frame(
#'   ID = c("BRCA1", "TP53", "MYC"),
#'   padj = c(0.01, 0.02, 0.5),
#'   stringsAsFactors = FALSE
#' )
#' # Empty search returns all rows:
#' search_geneset(dat, params = list(geneset_area = ""))
#' @export
search_geneset <- function(dat, params = list()) {
  if (is.null(dat)) {
    return(NULL)
  }
  if (is.null(params$geneset_area) || params$geneset_area == "") {
    return(dat)
  }
  getGeneSetData(dat, c(params$geneset_area))
}

#' Merge per-comparison DE results into one wide table.
#'
#' Pure version of `getMergedComparison()`. The legacy version reads
#' `input$norm_method`; this takes the same value off `params`.
#'
#' @param dc List of per-comparison containers (each has `init_data`, `cols`,
#'   `cond_names`).
#' @param nc Number of comparisons.
#' @param params Named list with `norm_method`.
#' @return Merged data.frame (samples + per-comparison foldChange/padj cols).
#' @examples
#' init1 <- data.frame(
#'   S1 = c(100L, 40L), S2 = c(200L, 60L),
#'   S3 = c(10L, 150L), S4 = c(12L, 160L),
#'   foldChange = c(10, 0.25), padj = c(0.01, 0.01),
#'   row.names = c("GeneA", "GeneB")
#' )
#' dc <- list(list(
#'   init_data = init1,
#'   cols = c("S1", "S2", "S3", "S4"),
#'   cond_names = c("Treat", "Ctrl")
#' ))
#' merge_comparisons(dc, nc = 1, params = list(norm_method = "none"))
#' @export
merge_comparisons <- function(dc, nc, params = list()) {
  if (is.null(dc)) {
    return(NULL)
  }
  mergeresults <- c()
  mergedata <- c()
  allsamples <- c()
  for (ni in seq(1, nc)) {
    tmp <- dc[[ni]]$init_data[, c("foldChange", "padj")]
    samples <- dc[[ni]]$cols
    cond_names <- dc[[ni]]$cond_names
    tt <- paste0(cond_names[1], ".vs.", cond_names[2])
    fctt <- paste0("foldChange.", tt)
    patt <- paste0("padj.", tt)
    colnames(tmp) <- c(fctt, patt)
    if (ni == 1L) {
      allsamples <- samples
      mergeresults <- tmp
      mergedata <- dc[[ni]]$init_data[, samples]
    } else {
      mergeresults[, fctt] <- character(nrow(tmp))
      mergeresults[, patt] <- character(nrow(tmp))
      mergeresults[rownames(tmp), c(fctt, patt)] <- tmp[, c(fctt, patt)]
      mergeresults[is.na(mergeresults[, fctt]), fctt] <- 1
      mergeresults[is.na(mergeresults[, patt]), patt] <- 1
      remaining <- dc[[ni]]$cols[!(samples %in% colnames(mergedata))]
      allsamples <- unique(c(allsamples, remaining))
      mergedata <- cbind(mergedata, dc[[ni]]$init_data[, remaining])
      colnames(mergedata) <- allsamples
    }
  }
  mergedata[, allsamples] <- normalize_counts(
    mergedata[, allsamples],
    method = params$norm_method
  )
  cbind(mergedata, mergeresults)
}

#' Apply Up/Down cutoffs across a merged-comparisons table.
#'
#' Pure version of `applyFiltersToMergedComparison()`.
#'
#' @inheritParams merge_comparisons
#' @return Merged data.frame with a `Legend` column (`"Sig"` / `"NS"`).
#' @examples
#' init1 <- data.frame(
#'   S1 = c(100L, 40L), S2 = c(200L, 60L),
#'   S3 = c(10L, 150L), S4 = c(12L, 160L),
#'   foldChange = c(10, 0.25), padj = c(0.01, 0.01),
#'   row.names = c("GeneA", "GeneB")
#' )
#' dc <- list(list(
#'   init_data = init1,
#'   cols = c("S1", "S2", "S3", "S4"),
#'   cond_names = c("Treat", "Ctrl")
#' ))
#' params <- list(norm_method = "none", padj_cutoff = 0.05, fold_cutoff = 2)
#' apply_merged_filters(dc, nc = 1, params = params)
#' @export
apply_merged_filters <- function(dc, nc, params = list()) {
  if (is.null(dc)) {
    return(NULL)
  }
  merged <- merge_comparisons(dc, nc, params)
  padj_cutoff <- as.numeric(params$padj_cutoff)
  fold_cutoff <- as.numeric(params$fold_cutoff)
  if (is.null(merged$Legend)) {
    merged$Legend <- "NS"
  }
  for (ni in seq(1, nc)) {
    cond_names <- dc[[ni]]$cond_names
    tt <- paste0(cond_names[1], ".vs.", cond_names[2])
    fctt <- paste0("foldChange.", tt)
    patt <- paste0("padj.", tt)
    up <- as.numeric(merged[, fctt]) >= fold_cutoff &
      as.numeric(merged[, patt]) <= padj_cutoff
    down <- as.numeric(merged[, fctt]) <= 1 / fold_cutoff &
      as.numeric(merged[, patt]) <= padj_cutoff
    merged$Legend[which(up | down)] <- "Sig"
  }
  merged
}

#' Build the (data, padj_colname, fold_colname) tuple for the Tables tab.
#'
#' Pure version of `getDataForTables()`.
#'
#' @param init_data Initial DE result.
#' @param filt_data Filtered DE result; defaults to `init_data` if NULL.
#' @param selected Genes the user lasso-selected (used when
#'   `dataset == "selected"`).
#' @param get_most_varied_data Most-varied subset (used when
#'   `dataset == "most-varied"`).
#' @param merged_comp Merged comparisons table.
#' @param explained_data Unused; preserved for legacy signature parity.
#' @param params Named list with `dataset`, `geneset_area`.
#' @return list(data, padj_colname, fold_colname).
#' @examples
#' init_data <- data.frame(
#'   foldChange = c(5, 0.1, 1.0), padj = c(0.01, 0.01, 0.5),
#'   Legend = c("Up", "Down", "NS"),
#'   row.names = c("GeneA", "GeneB", "GeneC")
#' )
#' result <- get_table_data(
#'   init_data = init_data,
#'   params = list(dataset = "alldetected", geneset_area = "")
#' )
#' result[[1]]  # the data.frame
#' @export
get_table_data <- function(init_data = NULL, filt_data = NULL,
                           selected = NULL, get_most_varied_data = NULL,
                           merged_comp = NULL, explained_data = NULL,
                           params = list()) {
  if (is.null(init_data)) {
    return(NULL)
  }
  if (is.null(filt_data)) filt_data <- init_data
  pastr <- "padj"
  fcstr <- "foldChange"
  ds <- params$dataset
  dat <- switch(ds,
    "alldetected"  = search_geneset(filt_data, params),
    "up+down"      = search_geneset(getUpDown(filt_data), params),
    "up"           = search_geneset(getUp(filt_data), params),
    "down"         = search_geneset(getDown(filt_data), params),
    "selected"     = search_geneset(selected, params),
    "most-varied"  = {
      d <- if (!is.null(filt_data)) {
        filt_data[rownames(get_most_varied_data), ]
      } else {
        init_data[rownames(get_most_varied_data), ]
      }
      search_geneset(d, params)
    },
    "comparisons"  = {
      if (is.null(merged_comp)) {
        return(NULL)
      }
      fcstr <- colnames(merged_comp)[grepl("foldChange", colnames(merged_comp))]
      pastr <- colnames(merged_comp)[grepl("padj", colnames(merged_comp))]
      search_geneset(merged_comp, params)
    },
    "searched"     = search_geneset(init_data, params),
    NULL
  )
  list(dat, pastr, fcstr)
}
