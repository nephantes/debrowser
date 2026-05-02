test_that("validate_count_upload accepts a well-formed TSV", {
  path <- tempfile(fileext = ".tsv")
  on.exit(unlink(path), add = TRUE)
  writeLines(c(
    "gene\tS1\tS2\tS3",
    "G1\t10\t20\t30",
    "G2\t5\t6\t7"
  ), path)
  expect_silent(validate_count_upload(path, sep = "\t"))
})

test_that("validate_count_upload raises bad_separator on single-column read", {
  path <- tempfile(fileext = ".tsv")
  on.exit(unlink(path), add = TRUE)
  # File is tab-separated but caller passes comma -> read sees 1 column.
  writeLines(c(
    "gene\tS1\tS2",
    "G1\t10\t20"
  ), path)
  expect_error(
    validate_count_upload(path, sep = ","),
    class = "bad_separator"
  )
})

test_that("validate_count_upload raises duplicate_gene_ids and lists offenders", {
  path <- tempfile(fileext = ".tsv")
  on.exit(unlink(path), add = TRUE)
  writeLines(c(
    "gene\tS1\tS2",
    "G1\t10\t20",
    "G1\t11\t21",
    "G2\t5\t6",
    "G2\t7\t8"
  ), path)
  err <- tryCatch(
    validate_count_upload(path, sep = "\t"),
    error = identity
  )
  expect_s3_class(err, "duplicate_gene_ids")
  expect_setequal(err$dups, c("G1", "G2"))
})
