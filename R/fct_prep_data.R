#' Apply DE filters and label Up/Down/NS/MV/GS rows.
#'
#' Pure function — no Shiny dependency. Re-normalizes the count columns,
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
