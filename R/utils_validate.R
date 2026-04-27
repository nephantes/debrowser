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
