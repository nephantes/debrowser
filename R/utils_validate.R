#' Raise a structured DEBrowser error.
#'
#' All errors raised by the `fct_*` pure functions go through this helper so
#' callers (tests, scripts, Shiny modules) can dispatch on the error class
#' rather than parsing message strings.
#'
#' @param message Human-readable error message.
#' @param class Optional character vector of additional classes to prepend
#'   to the condition's class list. Always inherits from
#'   `"debrowser_error"`.
#' @param ... Extra named fields stored on the condition for caller use.
#' @return Nothing — always raises.
#' @export
#' @examples
#' tryCatch(de_error("bad input"), error = function(e) e$message)
de_error <- function(message, class = character(), ...) {
  cond <- structure(
    class = c(class, "debrowser_error", "error", "condition"),
    list(message = message, call = sys.call(-1), ...)
  )
  stop(cond)
}

#' Validate that x is a non-empty numeric count matrix.
#'
#' Raises `de_error()` with one of: `"null_input"`, `"empty_matrix"`,
#' `"non_numeric"`. Otherwise returns `x` invisibly.
#'
#' @param x Object to validate.
#' @return `x` (invisibly) if valid.
#' @export
de_assert_count_matrix <- function(x) {
  if (is.null(x)) {
    de_error("count matrix is NULL", class = "null_input")
  }
  if (length(x) == 0L ||
    (is.matrix(x) && (nrow(x) == 0L || ncol(x) == 0L))) {
    de_error("count matrix is empty", class = "empty_matrix")
  }
  m <- if (is.data.frame(x)) as.matrix(x) else x
  if (!is.numeric(m)) {
    de_error("count matrix is not numeric", class = "non_numeric")
  }
  invisible(x)
}

#' Translate a Shiny `input` reactive into a structured filter-params list.
#'
#' All A3b pure functions accept a named list of filter parameters. This
#' helper bridges Shiny modules to those functions in a single place so the
#' field-name mapping is documented and centralised.
#'
#' @param input A Shiny input reactive (or a plain list with the same
#'   fields).
#' @return Named list with components: padj_cutoff, fold_cutoff, dataset,
#'   compselect, norm_method, geneset_area, method_tab, min_count, top_n,
#'   selected_plot.
#' @export
filter_params_from_input <- function(input) {
  list(
    padj_cutoff   = input$padj,
    fold_cutoff   = input$foldChange,
    dataset       = input$dataset,
    compselect    = input$compselect,
    norm_method   = input$norm_method,
    geneset_area  = input$genesetarea,
    method_tab    = input$methodtabs,
    min_count     = input$mincount,
    top_n         = input$topn,
    selected_plot = input$selectedplot
  )
}
