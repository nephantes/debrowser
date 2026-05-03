# Tests for the pure QC helpers in R/fct_qc.R.

test_that("flag_outliers_2sd flags a single 10 in a sea of 1s", {
  expect_identical(
    flag_outliers_2sd(c(1, 1, 1, 1, 1, 10)),
    c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE)
  )
})

test_that("flag_outliers_2sd returns all FALSE on zero-variance input", {
  expect_identical(
    flag_outliers_2sd(c(1, 1, 1, 1)),
    rep(FALSE, 4)
  )
})

test_that("flag_outliers_2sd returns empty logical on empty input", {
  out <- flag_outliers_2sd(numeric(0))
  expect_type(out, "logical")
  expect_length(out, 0)
})

test_that("flag_outliers_2sd treats NA positions as FALSE and still flags an extreme value", {
  # NA at position 1 must be FALSE; the trailing 10 sits >2sd from the mean
  # of the non-NA values (mean ~2.5, sd ~3.67, 2sd ~7.35; |10-2.5|=7.5).
  out <- flag_outliers_2sd(c(NA, 1, 1, 1, 1, 1, 10))
  expect_length(out, 7)
  expect_false(out[1])
  expect_true(out[7])
})

test_that("flag_outliers_2sd returns FALSE for a length-1 vector", {
  expect_identical(flag_outliers_2sd(42), FALSE)
})

test_that("library_depth_summary on demo (no meta) has 6 rows, NA group, depth==colSums", {
  d <- load_demo()
  out <- library_depth_summary(d$counts)
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 6L)
  expect_named(out, c("sample", "depth", "group", "is_outlier_2sd"))
  expect_identical(out$sample, colnames(d$counts))
  expect_equal(out$depth, as.numeric(colSums(d$counts)))
  expect_true(all(is.na(out$group)))
  expect_type(out$is_outlier_2sd, "logical")
})

test_that("library_depth_summary attaches group from meta when group_col is supplied", {
  d <- load_demo()
  out <- library_depth_summary(d$counts, d$meta, "treatment")
  expect_equal(nrow(out), 6L)
  idx <- match(out$sample, d$meta$samples)
  expect_identical(out$group, as.character(d$meta$treatment[idx]))
})

test_that("library_depth_summary raises qc_input_error on length mismatch", {
  d <- load_demo()
  bad_meta <- d$meta[1:3, ]
  expect_error(
    library_depth_summary(d$counts, bad_meta, "treatment"),
    class = "qc_input_error"
  )
})

test_that("library_depth_summary rejects non-matrix input with qc_input_error", {
  expect_error(library_depth_summary("nope"), class = "qc_input_error")
  expect_error(library_depth_summary(list(a = 1)), class = "qc_input_error")
})

test_that("detection_rate on demo: total_features==30739, pct in [0,100]", {
  d <- load_demo()
  out <- detection_rate(d$counts)
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 6L)
  expect_named(out, c("sample", "n_detected", "total_features", "detection_pct"))
  expect_true(all(out$total_features == 30739L))
  expect_true(all(out$detection_pct >= 0 & out$detection_pct <= 100))
  expect_true(all(out$n_detected >= 0))
})

test_that("detection_rate respects the threshold argument", {
  m <- matrix(c(0, 1, 5, 0, 10, 0), nrow = 3,
              dimnames = list(NULL, c("a", "b")))
  # threshold=0: a has 2 detected, b has 1
  out0 <- detection_rate(m, threshold = 0)
  expect_equal(out0$n_detected, c(2, 1))
  # threshold=4: a has 1 (the 5), b has 1 (the 10)
  out4 <- detection_rate(m, threshold = 4)
  expect_equal(out4$n_detected, c(1, 1))
})

test_that("mt_pct_per_sample returns zero rows when no rownames match", {
  d <- load_demo()
  # The demo data does contain `Cytb` (cytochrome b, prefix-stripped) so the
  # default pattern picks it up. To assert the empty-state, drop the matched
  # rows first.
  pat <- debrowser:::mt_default_pattern()
  cnt_no_mt <- d$counts[!grepl(pat, rownames(d$counts)), , drop = FALSE]
  out <- mt_pct_per_sample(cnt_no_mt)
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 0L)
  expect_named(out, c("sample", "mt_count", "total", "mt_pct"))
})

test_that("mt_pct_per_sample picks up the demo's prefix-stripped Cytb row", {
  d <- load_demo()
  out <- mt_pct_per_sample(d$counts)
  expect_equal(nrow(out), 6L)
  # Cytb is the only matching row in the Vernia demo.
  cytb_counts <- as.numeric(d$counts["Cytb", ])
  expect_equal(out$mt_count, cytb_counts)
})

test_that("mt_pct_per_sample computes per-sample MT percentage correctly", {
  m <- matrix(
    c(2, 8, 10, 90,    # MT-ND1
      1, 9, 5, 95,     # ACTB
      3, 7, 0, 100,    # GAPDH
      4, 6, 20, 80),   # B2M
    nrow = 4, byrow = TRUE,
    dimnames = list(
      c("MT-ND1", "ACTB", "GAPDH", "B2M"),
      c("s1", "s2", "s3", "s4")
    )
  )
  out <- mt_pct_per_sample(m)
  expect_equal(nrow(out), 4L)
  expect_identical(out$sample, colnames(m))
  expect_equal(out$mt_count, c(2, 8, 10, 90))
  expect_equal(out$total, as.numeric(colSums(m)))
  expect_equal(out$mt_pct, 100 * c(2, 8, 10, 90) / as.numeric(colSums(m)))
})

test_that("mt_pct_per_sample matches mouse MGI symbols with the dash", {
  m <- matrix(c(5, 10, 1, 99, 2, 98), nrow = 3, byrow = TRUE,
              dimnames = list(c("mt-Nd1", "Actb", "Gapdh"), c("s1", "s2")))
  out <- mt_pct_per_sample(m)
  expect_equal(out$mt_count, c(5, 10))
})

test_that("mt_pct_per_sample matches mouse symbols without the dash", {
  m <- matrix(c(7, 14, 1, 99), nrow = 2, byrow = TRUE,
              dimnames = list(c("mtNd1", "Actb"), c("s1", "s2")))
  out <- mt_pct_per_sample(m)
  expect_equal(out$mt_count, c(7, 14))
})

test_that("mt_pct_per_sample matches Ensembl all-caps no-dash form", {
  m <- matrix(c(3, 6, 9, 91), nrow = 2, byrow = TRUE,
              dimnames = list(c("MTND1", "ACTB"), c("s1", "s2")))
  out <- mt_pct_per_sample(m)
  expect_equal(out$mt_count, c(3, 6))
})

test_that("mt_pct_per_sample matches prefix-stripped suffixes", {
  m <- matrix(c(1, 2, 3, 4, 5, 6), nrow = 3, byrow = TRUE,
              dimnames = list(c("Nd1", "ND1", "Actb"), c("s1", "s2")))
  out <- mt_pct_per_sample(m)
  # both Nd1 (mouse) and ND1 (human) count as MT
  expect_equal(out$mt_count, c(1 + 3, 2 + 4))
})

test_that("mt_pct_per_sample does NOT match nuclear genes that share a prefix", {
  m <- matrix(c(100, 100, 100, 100, 100, 100, 100, 100), nrow = 4, byrow = TRUE,
              dimnames = list(
                c("Mtor", "Mthfr", "Atp6v0a1", "MTHFD1"),
                c("s1", "s2")
              ))
  out <- mt_pct_per_sample(m)
  expect_equal(nrow(out), 0L)
})

test_that("mt_pct_per_sample respects an explicit override pattern", {
  m <- matrix(c(1, 2, 3, 4), nrow = 2, byrow = TRUE,
              dimnames = list(c("custom-1", "custom-2"), c("s1", "s2")))
  out <- mt_pct_per_sample(m, pattern = "^custom-")
  expect_equal(nrow(out), 2L)
  expect_equal(out$mt_count, c(1 + 3, 2 + 4))
})

test_that("sample_distance_matrix on demo: symmetric, 6x6, diag=0, dimnames match", {
  d <- load_demo()
  dm <- sample_distance_matrix(d$counts)
  expect_true(is.matrix(dm))
  expect_equal(dim(dm), c(6L, 6L))
  expect_true(isSymmetric(dm))
  expect_equal(unname(diag(dm)), rep(0, 6L))
  expect_identical(rownames(dm), colnames(d$counts))
  expect_identical(colnames(dm), colnames(d$counts))
  expect_true(all(dm >= 0))
})

test_that("sample_distance_matrix falls back to log2 path on tiny input", {
  # 5 rows < 30 -> uses varianceStabilizingTransformation; if it can't, log2
  m <- matrix(rpois(15, lambda = 5), nrow = 5,
              dimnames = list(NULL, c("a", "b", "c")))
  dm <- sample_distance_matrix(m)
  expect_equal(dim(dm), c(3L, 3L))
  expect_equal(unname(diag(dm)), rep(0, 3L))
  expect_true(isSymmetric(dm))
})

# ---------------------------------------------------------------------------
# E4.5 helpers: size_factor_library_summary, cooks_outlier_summary
# ---------------------------------------------------------------------------

# Internal helper: build a small fitted DESeqDataSet for the helpers' tests.
# Filters low-count rows so DESeq()'s dispersion fit doesn't choke on a
# corner-case 5x4 input. Uses run_deseq2(return_dds = TRUE).
.qc_test_dds <- function() {
  skip_if_not_installed("DESeq2")
  set.seed(11L)
  m <- matrix(
    rpois(80L, lambda = 30L), nrow = 20L,
    dimnames = list(paste0("g", 1:20), paste0("s", 1:4))
  )
  meta <- data.frame(samples = paste0("s", 1:4), stringsAsFactors = FALSE)
  conds <- factor(c("Treat", "Treat", "Control", "Control"))
  out <- run_deseq2(
    counts = m, metadata = meta,
    columns = paste0("s", 1:4), conds = conds,
    params = list(
      covariates = "NoCovariate", fit_type = "parametric",
      beta_prior = FALSE, test_type = "Wald", shrinkage = "None"
    ),
    return_dds = TRUE
  )
  out$dds
}

test_that("run_deseq2(return_dds=TRUE) returns list(res, dds) with a fitted dds", {
  skip_if_not_installed("DESeq2")
  dds <- .qc_test_dds()
  expect_s4_class(dds, "DESeqDataSet")
  # DESeq() populates size factors and the cooks assay.
  expect_false(is.null(DESeq2::sizeFactors(dds)))
  expect_true("cooks" %in% names(SummarizedExperiment::assays(dds)))
})

test_that("size_factor_library_summary returns one row per sample with rho attached", {
  skip_if_not_installed("DESeq2")
  dds <- .qc_test_dds()
  out <- size_factor_library_summary(dds)
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 4L)
  expect_named(out, c("sample", "size_factor", "library_size",
                      "sf_scaled", "lib_scaled"))
  # sf_scaled / lib_scaled in [0, 1] with at least one row at exactly 1.
  expect_true(all(out$sf_scaled  >= 0 & out$sf_scaled  <= 1))
  expect_true(all(out$lib_scaled >= 0 & out$lib_scaled <= 1))
  expect_true(any(out$sf_scaled  == 1))
  expect_true(any(out$lib_scaled == 1))
  rho <- attr(out, "spearman_rho")
  expect_type(rho, "double")
  expect_length(rho, 1L)
  expect_true(is.finite(rho))
  # library_size matches DESeq2::counts colSums.
  expect_equal(out$library_size, as.numeric(colSums(DESeq2::counts(dds))))
})

test_that("size_factor_library_summary errors on NULL dds", {
  expect_error(size_factor_library_summary(NULL), class = "qc_input_error")
})

test_that("cooks_outlier_summary returns one row per sample with threshold attached", {
  skip_if_not_installed("DESeq2")
  dds <- .qc_test_dds()
  out <- cooks_outlier_summary(dds)
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 4L)
  expect_named(out, c("sample", "n_high_cooks", "total_genes",
                      "high_cooks_pct"))
  # All 4 samples produced from the same DESeqDataSet have the same total
  # gene count.
  expect_true(all(out$total_genes == out$total_genes[1]))
  # Counts and percentages line up.
  expect_equal(out$high_cooks_pct,
               100 * out$n_high_cooks / out$total_genes)
  thr <- attr(out, "threshold")
  expect_type(thr, "double")
  expect_length(thr, 1L)
  expect_true(is.finite(thr) && thr > 0)
})

test_that("cooks_outlier_summary respects an explicit threshold override", {
  skip_if_not_installed("DESeq2")
  dds <- .qc_test_dds()
  cooks_mat <- SummarizedExperiment::assays(dds)[["cooks"]]
  expected <- as.integer(colSums(cooks_mat > 0.5, na.rm = TRUE))
  out <- cooks_outlier_summary(dds, threshold = 0.5)
  expect_equal(out$n_high_cooks, expected)
  expect_identical(attr(out, "threshold"), 0.5)
})

test_that("cooks_outlier_summary errors on NULL dds", {
  expect_error(cooks_outlier_summary(NULL), class = "qc_input_error")
})

test_that("cooks_outlier_summary errors when the cooks assay is absent", {
  skip_if_not_installed("DESeq2")
  # Build a DESeqDataSet but skip DESeq() so 'cooks' is never populated.
  m <- matrix(rpois(30L, lambda = 10L), nrow = 5L,
              dimnames = list(paste0("g", 1:5), paste0("s", 1:6)))
  coldat <- data.frame(group = factor(c("A","A","A","B","B","B")))
  dds <- DESeq2::DESeqDataSetFromMatrix(m, colData = coldat, design = ~group)
  expect_error(cooks_outlier_summary(dds), class = "qc_input_error")
})
