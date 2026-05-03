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
  out <- mt_pct_per_sample(d$counts)
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 0L)
  expect_named(out, c("sample", "mt_count", "total", "mt_pct"))
})

test_that("mt_pct_per_sample computes per-sample MT percentage correctly", {
  m <- matrix(
    c(2, 8, 10, 90,    # MT-X
      1, 9, 5, 95,     # ACTB
      3, 7, 0, 100,    # GAPDH
      4, 6, 20, 80),   # B2M
    nrow = 4, byrow = TRUE,
    dimnames = list(
      c("MT-X", "ACTB", "GAPDH", "B2M"),
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
