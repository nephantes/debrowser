# R/fct_ai_markdown.R
#
# Phase E12.B - sanitized markdown rendering pipeline for LLM responses.
#
# Pipeline (spec section 6.1):
#   1. commonmark::markdown_html(text, extensions = FALSE)
#   2. xml2::read_html(paste0("<div>", html, "</div>"))
#   3. Walk tree; keep allow-list tags; strip others; drop all
#      attributes except `class` on <code>; drop <img> / <script> /
#      <style> / <iframe> entirely.
#   4. Serialize and unwrap.
#
# Defensive contract: NEVER raises. Internal failures fall back to
# htmltools::htmlEscape(input) wrapped in <pre>.

#' Allow-list of HTML tags retained by the markdown sanitizer.
#' @keywords internal
#' @noRd
.ai_md_allow_list <- function() {
  c("p", "br",
    "strong", "em",
    "ul", "ol", "li",
    "h1", "h2", "h3", "h4", "h5", "h6",
    "code", "pre",
    "blockquote",
    "hr")
}

#' Render LLM markdown response to sanitized HTML.
#'
#' Strict allow-list. Drops links (keeping text), images, scripts,
#' styles, iframes, and all attributes except `class` on `<code>`.
#' Never raises: any internal failure returns the input as escaped
#' plain text wrapped in `<pre>`.
#'
#' @param markdown_text chr(1). LLM response.
#' @param allow_list chr. Tag names to keep. Default `.ai_md_allow_list()`.
#' @return chr(1). HTML safe to wrap in `htmltools::HTML()`.
#' @keywords internal
#' @noRd
.render_markdown_sanitized <- function(markdown_text,
                                       allow_list = .ai_md_allow_list()) {
  if (!is.character(markdown_text) || length(markdown_text) != 1L) {
    return("")
  }
  if (!nzchar(trimws(markdown_text))) {
    return("")
  }

  result <- tryCatch({
    require_pkg("commonmark", "AI features")
    require_pkg("xml2",       "AI features")
    html <- commonmark::markdown_html(markdown_text,
                                      extensions = FALSE,
                                      smart      = FALSE)
    doc <- xml2::read_html(paste0("<div id='ai-root'>", html, "</div>"))
    root <- xml2::xml_find_first(doc, "//div[@id='ai-root']")
    .ai_sanitize_node(root, allow_list)
    inner <- paste(vapply(xml2::xml_children(root),
                          function(n) as.character(n),
                          character(1)), collapse = "")
    inner
  }, error = function(e) {
    sprintf("<pre>%s</pre>", htmltools::htmlEscape(markdown_text))
  })

  if (!is.character(result) || length(result) != 1L || is.na(result)) {
    return(sprintf("<pre>%s</pre>", htmltools::htmlEscape(markdown_text)))
  }
  result
}

#' Recursive in-place node sanitizer.
#'
#' Walks children of `node`. For each child:
#'   - if tag in allow_list: keep node, strip attributes, recurse;
#'   - if tag == "a": replace with the child's text content (link discarded);
#'   - if tag in c("img", "script", "style", "iframe"): remove node;
#'   - any other tag: replace with the child's text content (tag stripped).
#'
#' For kept nodes, attributes are scrubbed except `class` on `<code>`.
#'
#' @param node An xml2 node.
#' @param allow_list chr.
#' @return invisible NULL. Mutates `node` in place via xml2.
#' @keywords internal
#' @noRd
.ai_sanitize_node <- function(node, allow_list) {
  drop_tags <- c("img", "script", "style", "iframe")
  for (child in xml2::xml_children(node)) {
    tag <- xml2::xml_name(child)
    if (tag %in% drop_tags) {
      xml2::xml_remove(child)
      next
    }
    if (tag %in% allow_list) {
      # Strip every attribute except `class` on <code>.
      attrs <- xml2::xml_attrs(child)
      if (length(attrs) > 0L) {
        for (an in names(attrs)) {
          keep <- identical(tag, "code") && identical(an, "class")
          if (!keep) xml2::xml_attr(child, an) <- NULL
        }
      }
      .ai_sanitize_node(child, allow_list)
      next
    }
    # Unknown / disallowed tag: replace with text content.
    txt <- xml2::xml_text(child)
    # Insert text node before child, then remove child.
    text_node <- xml2::read_xml(paste0("<span>",
                                       htmltools::htmlEscape(txt),
                                       "</span>"))
    xml2::xml_add_sibling(child,
                          xml2::xml_find_first(text_node, "."),
                          .where = "before")
    xml2::xml_remove(child)
  }
  invisible(NULL)
}
