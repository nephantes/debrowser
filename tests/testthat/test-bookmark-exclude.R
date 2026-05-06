# Regression: serialize a fake bookmark state with sensitive content
# pretending to be input fields, run redact_for_bookmark, and assert
# nothing recognizably-secret survives.
test_that("redact_for_bookmark blocks well-known secret patterns", {
  fake_state <- list(
    `ai_settings-api_key`   = "sk-anth-abcdef1234567890",
    `ai_settings-master_switch` = TRUE,
    `ai_settings-provider`  = "anthropic",
    `ai_enrichment-response_text` = "(should not be bookmarked)",
    api_key_other = "should-also-go",
    SOME_API_KEY  = "should-also-go-2",
    foo = "kept",
    bar = 42
  )
  redacted <- redact_for_bookmark(fake_state)
  serialized <- paste(capture.output(dput(redacted)), collapse = " ")

  # No secret values should appear after redaction
  expect_false(grepl("sk-anth-abcdef1234567890", serialized, fixed = TRUE))
  expect_false(grepl("should not be bookmarked", serialized, fixed = TRUE))
  expect_false(grepl("should-also-go", serialized, fixed = TRUE))
  expect_false(grepl("should-also-go-2", serialized, fixed = TRUE))

  # Non-sensitive values are preserved
  expect_equal(redacted$foo, "kept")
  expect_equal(redacted$bar, 42)
})

# Verifies the centralized list of excluded inputs covers the documented
# AI / file-input / button surface. This is a DESIGN INVARIANT test.
test_that("expected setBookmarkExclude entries are present in server.R", {
  # Resolve server.R from the source tree (we're running under devtools::test
  # which sets the cwd to the tests/testthat dir).
  here <- testthat::test_path("..", "..", "R", "server.R")
  if (!file.exists(here)) {
    # Try installed-package path as a fallback
    here <- system.file("R", "server.R", package = "debrowser")
  }
  if (!file.exists(here) || nchar(here) == 0) {
    skip("server.R not in expected path")
  }
  src <- readLines(here)
  text <- paste(src, collapse = "\n")
  # IDs audited 2026-05-06 against actual ns() calls in each module.
  required <- c(
    "ai_settings-api_key",
    "ai_settings-enabled",
    "ai_enrichment-ask",
    "load-countdata",
    "load-metadata",
    "fgsea_gmt-manual_gmt",
    "load-uploadFile",
    "lcf-submitLCF",
    "batcheffect-submitBatchEffect",
    "cs-startDE"
  )
  for (r in required) {
    expect_true(grepl(r, text, fixed = TRUE),
                info = sprintf("setBookmarkExclude must include '%s'", r))
  }
})
