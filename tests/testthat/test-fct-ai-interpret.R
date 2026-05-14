test_that("ai_error() raises a classed condition with ai_error in class chain", {
  expect_error(
    ai_error("test message"),
    class = "ai_error"
  )
})

test_that("ai_error() passes through subclass", {
  expect_error(
    ai_error("auth failed", class = "ai_no_key"),
    class = "ai_no_key"
  )
  # And ai_no_key inherits ai_error
  err <- tryCatch(ai_error("auth", class = "ai_no_key"),
                  ai_error = function(e) e)
  expect_s3_class(err, "ai_error")
  expect_s3_class(err, "ai_no_key")
})

test_that("ai_error() recognizes all 5 spec subclasses", {
  for (sub in c("ai_no_key", "ai_rate_limit", "ai_network",
                "ai_invalid_response", "ai_disabled")) {
    err <- tryCatch(ai_error(sprintf("msg for %s", sub), class = sub),
                    ai_error = function(e) e)
    expect_s3_class(err, sub)
    expect_s3_class(err, "ai_error")
  }
})

.fixture_payload <- function() {
  list(
    genes = c("BRCA1", "TP53", "MYC", "EGFR", "KRAS",
              "PTEN", "RB1", "APC", "VHL", "NF1"),
    stats = data.frame(
      gene_id = c("BRCA1", "TP53", "MYC", "EGFR", "KRAS",
                  "PTEN", "RB1", "APC", "VHL", "NF1"),
      log2FoldChange = c(2.3, -1.8, 3.1, 1.5, -2.7, 1.1, -1.4, 2.0, -1.2, 1.7),
      padj           = c(0.001, 0.002, 0.0001, 0.01, 0.0005,
                         0.05, 0.03, 0.001, 0.04, 0.02)
    ),
    enrichment = list(
      term      = "DNA damage response",
      pvalue    = 1e-8,
      n_overlap = 10
    )
  )
}

test_that(".redact_payload symbols mode returns genes only", {
  red <- .redact_payload(.fixture_payload(), "symbols", top_n = 50L)
  expect_named(red, "genes")
  expect_equal(red$genes, .fixture_payload()$genes)
  expect_null(red$stats)
  expect_null(red$enrichment)
})

test_that(".redact_payload stats mode returns genes + stats, no enrichment", {
  red <- .redact_payload(.fixture_payload(), "stats", top_n = 50L)
  expect_named(red, c("genes", "stats"))
  expect_s3_class(red$stats, "data.frame")
  expect_true(all(c("gene_id", "log2FoldChange", "padj") %in% colnames(red$stats)))
  expect_null(red$enrichment)
})

test_that(".redact_payload stats_enrichment mode returns all three", {
  red <- .redact_payload(.fixture_payload(), "stats_enrichment", top_n = 50L)
  expect_named(red, c("genes", "stats", "enrichment"))
  expect_equal(red$enrichment$term, "DNA damage response")
})

test_that(".redact_payload caps genes at top_n and flags truncation", {
  red <- .redact_payload(.fixture_payload(), "symbols", top_n = 3L)
  expect_length(red$genes, 3L)
  expect_equal(red$genes, c("BRCA1", "TP53", "MYC"))
  expect_true(attr(red, "truncated"))
  expect_equal(attr(red, "n_total"), 10L)
})

test_that(".redact_payload caps stats rows at top_n in stats mode", {
  red <- .redact_payload(.fixture_payload(), "stats", top_n = 3L)
  expect_length(red$genes, 3L)
  expect_equal(nrow(red$stats), 3L)
})

test_that(".redact_payload errors on unknown privacy mode", {
  expect_error(
    .redact_payload(.fixture_payload(), "bogus", top_n = 50L),
    class = "ai_invalid_response"
  )
})

# --- .render_prompt tests ---

test_that(".render_prompt substitutes basic whisker slots", {
  testthat::skip_if_not_installed("whisker")
  tmp <- tempfile(fileext = ".md")
  on.exit(unlink(tmp), add = TRUE)
  writeLines("Hello {{name}}, you have {{n_items}} items.", tmp)
  out <- .render_prompt(tmp, list(name = "world", n_items = 3))
  expect_equal(out, "Hello world, you have 3 items.")
})

test_that(".render_prompt expands {{#cond}}...{{/cond}} when truthy", {
  testthat::skip_if_not_installed("whisker")
  tmp <- tempfile(fileext = ".md")
  on.exit(unlink(tmp), add = TRUE)
  writeLines("Start{{#has_stats}} stats{{/has_stats}} end.", tmp)
  expect_equal(
    .render_prompt(tmp, list(has_stats = TRUE)),
    "Start stats end."
  )
  expect_equal(
    .render_prompt(tmp, list(has_stats = FALSE)),
    "Start end."
  )
})

test_that(".render_prompt errors on missing template file", {
  expect_error(
    .render_prompt("/nonexistent/path/template.md", list()),
    class = "ai_invalid_response"
  )
})

# --- .map_provider_error tests ---

test_that(".map_provider_error maps 401 / unauthorized to ai_no_key", {
  e <- simpleError("HTTP 401: Unauthorized \u2014 invalid API key")
  expect_error(.map_provider_error(e), class = "ai_no_key")
})

test_that(".map_provider_error maps 429 / rate limit to ai_rate_limit", {
  e <- simpleError("HTTP 429: Too Many Requests \u2014 rate limit exceeded")
  expect_error(.map_provider_error(e), class = "ai_rate_limit")
})

test_that(".map_provider_error maps connection errors to ai_network", {
  e <- simpleError("Could not resolve host: api.anthropic.com")
  expect_error(.map_provider_error(e), class = "ai_network")
})

test_that(".map_provider_error maps unknown errors to ai_invalid_response", {
  e <- simpleError("something completely unexpected happened")
  expect_error(.map_provider_error(e), class = "ai_invalid_response")
})

# --- ai_interpret tests with stub chat object ---

# Stub chat object: emits canned response, or raises if `raise` is non-null.
.make_stub_chat <- function(response = "Stubbed response.", raise = NULL) {
  list(chat = function(text) {
    if (!is.null(raise)) stop(raise)
    response
  })
}

# Real on-disk template for ai_interpret. Tests that depend on it skip
# when the template fixture is missing \u2014 defensive against E12.A.1 not
# yet running.
.summarize_template_path <- function() {
  system.file("templates", "ai_summarize_geneset.md",
              package = "debrowser", mustWork = FALSE)
}

test_that("ai_interpret returns chat response on happy path", {
  testthat::skip_if_not_installed("whisker")
  if (!nzchar(.summarize_template_path())) {
    skip("ai_summarize_geneset.md template not installed")
  }
  stub <- .make_stub_chat("This gene set is enriched in DNA damage response.")
  out <- ai_interpret(
    question      = "summarize_geneset",
    payload       = .fixture_payload(),
    privacy_mode  = "symbols",
    provider_chat = stub,
    top_n         = 10L
  )
  expect_equal(out, "This gene set is enriched in DNA damage response.")
})

test_that("ai_interpret raises ai_invalid_response on unknown question key", {
  stub <- .make_stub_chat()
  expect_error(
    ai_interpret(
      question      = "bogus_preset",
      payload       = .fixture_payload(),
      privacy_mode  = "symbols",
      provider_chat = stub
    ),
    class = "ai_invalid_response"
  )
})

test_that("ai_interpret raises ai_no_key when chat throws auth error", {
  testthat::skip_if_not_installed("whisker")
  if (!nzchar(.summarize_template_path())) skip("template not installed")
  stub <- .make_stub_chat(raise = "HTTP 401: Unauthorized")
  expect_error(
    ai_interpret("summarize_geneset", .fixture_payload(), "symbols", stub),
    class = "ai_no_key"
  )
})

test_that("ai_interpret raises ai_rate_limit when chat throws 429", {
  testthat::skip_if_not_installed("whisker")
  if (!nzchar(.summarize_template_path())) skip("template not installed")
  stub <- .make_stub_chat(raise = "HTTP 429: rate limit exceeded")
  expect_error(
    ai_interpret("summarize_geneset", .fixture_payload(), "symbols", stub),
    class = "ai_rate_limit"
  )
})

test_that("ai_interpret raises ai_network when chat throws connection error", {
  testthat::skip_if_not_installed("whisker")
  if (!nzchar(.summarize_template_path())) skip("template not installed")
  stub <- .make_stub_chat(raise = "Could not resolve host: api.anthropic.com")
  expect_error(
    ai_interpret("summarize_geneset", .fixture_payload(), "symbols", stub),
    class = "ai_network"
  )
})

test_that("ai_interpret stats mode includes effect-size context in prompt", {
  testthat::skip_if_not_installed("whisker")
  if (!nzchar(.summarize_template_path())) skip("template not installed")
  # Capture the prompt text by stubbing chat to return its input
  captured <- new.env()
  stub <- list(chat = function(text) { captured$prompt <- text; "OK" })
  ai_interpret("summarize_geneset", .fixture_payload(),
               "stats", stub, top_n = 50L)
  expect_match(captured$prompt, "Effect-size context")
})

test_that("ai_interpret symbols mode does NOT include effect-size context", {
  testthat::skip_if_not_installed("whisker")
  if (!nzchar(.summarize_template_path())) skip("template not installed")
  captured <- new.env()
  stub <- list(chat = function(text) { captured$prompt <- text; "OK" })
  ai_interpret("summarize_geneset", .fixture_payload(),
               "symbols", stub, top_n = 50L)
  expect_no_match(captured$prompt, "Effect-size context")
})
