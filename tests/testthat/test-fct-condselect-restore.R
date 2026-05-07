make_spec_entry <- function(label = "treatment", control = "control") {
  list(
    meta_column       = "condition",
    treatment_level   = "A",
    control_level     = "B",
    treatment_samples = c("s1", "s2"),
    control_samples   = c("s3", "s4"),
    treatment_label   = label,
    control_label     = control,
    de_method         = "DESeq2",
    method_params     = list(fitType = "parametric",
                             betaPrior = FALSE,
                             testType  = "LRT",
                             shrinkage = "apeglm"),
    covariates        = c("batch")
  )
}

test_that("restore_comparisons_spec: empty spec returns empty list", {
  expect_equal(restore_comparisons_spec(list()), list())
  expect_equal(restore_comparisons_spec(NULL), list())
})

# D2.5 fix: condSelectServer's `initial_spec` parameter populates the
# wizard from a saved spec at module mount time, regardless of whether
# Shiny's bookmark-restore window is still active. This is the path
# the deServer auto-replay observer uses (it mounts condSelectServer
# AFTER session-restore has finished, so the module's onRestore is a
# no-op there).
test_that("condSelectServer applies initial_spec at mount", {
  skip_if_not_installed("shiny")
  counts <- matrix(as.integer(c(100, 200, 10, 12, 40, 60, 50, 70)),
                   nrow = 2, dimnames = list(c("G1", "G2"),
                                             paste0("S", 1:4)))
  meta <- data.frame(Sample = paste0("S", 1:4),
                     condition = c("A", "A", "B", "B"),
                     stringsAsFactors = FALSE)
  spec <- list(make_spec_entry("treat", "ctrl"))

  shiny::testServer(
    condSelectServer,
    args = list(data = counts, metadata = meta, initial_spec = spec),
    {
      # n_comparisons synced from the restored set (length(spec) = 1)
      expect_equal(n_comparisons(), 1L)
      # spec snapshot from the module reflects the populated values,
      # not the empty NA defaults from new_comparison(1L)
      out <- comparisons_spec()
      expect_length(out, 1L)
      expect_equal(out[[1]]$meta_column, "condition")
      expect_equal(out[[1]]$treatment_level, "A")
      expect_equal(out[[1]]$control_level, "B")
      expect_equal(out[[1]]$treatment_label, "treat")
      expect_equal(out[[1]]$control_label, "ctrl")
    }
  )
})

test_that("condSelectServer multi-comparison initial_spec installs cards 2..N", {
  skip_if_not_installed("shiny")
  counts <- matrix(as.integer(c(100, 200, 10, 12, 40, 60, 50, 70)),
                   nrow = 2, dimnames = list(c("G1", "G2"),
                                             paste0("S", 1:4)))
  meta <- data.frame(Sample = paste0("S", 1:4),
                     condition = c("A", "A", "B", "B"),
                     stringsAsFactors = FALSE)
  spec <- list(
    make_spec_entry("a", "b"),
    make_spec_entry("c", "d"),
    make_spec_entry("e", "f")
  )

  shiny::testServer(
    condSelectServer,
    args = list(data = counts, metadata = meta, initial_spec = spec),
    {
      expect_equal(n_comparisons(), 3L)
      out <- comparisons_spec()
      expect_length(out, 3L)
      expect_equal(out[[1]]$treatment_label, "a")
      expect_equal(out[[2]]$treatment_label, "c")
      expect_equal(out[[3]]$treatment_label, "e")
    }
  )
})

test_that("condSelectServer NULL/empty initial_spec falls back to default card 1", {
  skip_if_not_installed("shiny")
  counts <- matrix(as.integer(c(1L, 2L, 3L, 4L)),
                   nrow = 1, dimnames = list("G", paste0("S", 1:4)))
  meta <- data.frame(Sample = paste0("S", 1:4),
                     condition = c("A", "A", "B", "B"))

  shiny::testServer(
    condSelectServer,
    args = list(data = counts, metadata = meta, initial_spec = NULL),
    {
      # Default: 1 empty card
      expect_equal(n_comparisons(), 1L)
      out <- comparisons_spec()
      expect_length(out, 1L)
      # NA defaults
      expect_true(is.na(out[[1]]$meta_column) ||
                  identical(out[[1]]$meta_column, NA_character_))
    }
  )

  shiny::testServer(
    condSelectServer,
    args = list(data = counts, metadata = meta, initial_spec = list()),
    {
      expect_equal(n_comparisons(), 1L)
    }
  )
})

test_that("restore_comparisons_spec: round-trip preserves all 10 fields", {
  spec <- list(make_spec_entry("treat", "ctrl"))
  out <- restore_comparisons_spec(spec)
  expect_length(out, 1L)
  expect_equal(names(out), "1")
  rv1 <- out[[1]]
  expect_equal(rv1$meta_column,       "condition")
  expect_equal(rv1$treatment_level,   "A")
  expect_equal(rv1$control_level,     "B")
  expect_equal(rv1$treatment_samples, c("s1", "s2"))
  expect_equal(rv1$control_samples,   c("s3", "s4"))
  expect_equal(rv1$treatment_label,   "treat")
  expect_equal(rv1$control_label,     "ctrl")
  expect_equal(rv1$de_method,         "DESeq2")
  expect_equal(rv1$method_params$fitType, "parametric")
  expect_equal(rv1$covariates,        c("batch"))
})

test_that("restore_comparisons_spec: multiple comparisons get sequential keys", {
  spec <- list(
    make_spec_entry("a", "b"),
    make_spec_entry("c", "d"),
    make_spec_entry("e", "f")
  )
  out <- restore_comparisons_spec(spec)
  expect_length(out, 3L)
  expect_equal(names(out), c("1", "2", "3"))
  expect_equal(out[["1"]]$treatment_label, "a")
  expect_equal(out[["2"]]$treatment_label, "c")
  expect_equal(out[["3"]]$treatment_label, "e")
})

test_that("restore_comparisons_spec: missing fields default to safe values", {
  partial <- list(
    treatment_label = "x", control_label = "y",
    treatment_samples = c("s1")
    # other fields missing
  )
  out <- restore_comparisons_spec(list(partial))
  rv1 <- out[[1]]
  expect_true(is.na(rv1$meta_column))
  expect_equal(rv1$de_method, "DESeq2")
  expect_equal(rv1$control_samples, character(0))
  expect_true(is.list(rv1$method_params))
})
