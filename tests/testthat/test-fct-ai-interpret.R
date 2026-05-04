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
