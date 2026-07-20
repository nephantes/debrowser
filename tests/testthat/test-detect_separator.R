# tests/testthat/test-detect_separator.R

write_fixture <- function(text, ext = "tsv", gzip = FALSE) {
  path <- tempfile(fileext = paste0(".", ext, if (gzip) ".gz" else ""))
  if (gzip) {
    con <- gzfile(path, "wb")
    writeBin(charToRaw(text), con)
    close(con)
  } else {
    writeBin(charToRaw(text), path)
  }
  path
}

# 4 cols * 6 rows of data is well above the score >= 3 threshold.
counts_tsv <- paste(
  "gene\ts1\ts2\ts3\ts4",
  "A\t10\t12\t9\t11",
  "B\t20\t22\t19\t21",
  "C\t30\t32\t29\t31",
  "D\t40\t42\t39\t41",
  "E\t50\t52\t49\t51",
  sep = "\n"
)
counts_csv <- gsub("\t", ",", counts_tsv)
counts_ssv <- gsub("\t", ";", counts_tsv)

test_that("detect_separator picks tab on a clean .tsv", {
  path <- write_fixture(counts_tsv, "tsv")
  expect_equal(detect_separator(path), "\t")
})

test_that("detect_separator picks comma on a clean .csv", {
  path <- write_fixture(counts_csv, "csv")
  expect_equal(detect_separator(path), ",")
})

test_that("detect_separator picks semicolon on a clean .csv with ; delimiter", {
  path <- write_fixture(counts_ssv, "csv")
  expect_equal(detect_separator(path), ";")
})

test_that("detect_separator handles BOM-prefixed UTF-8 files", {
  bom <- rawToChar(as.raw(c(0xEF, 0xBB, 0xBF)))
  path <- write_fixture(paste0(bom, counts_tsv), "tsv")
  expect_equal(detect_separator(path), "\t")
})

test_that("detect_separator decompresses .gz before sniffing", {
  path <- write_fixture(counts_csv, "csv", gzip = TRUE)
  expect_equal(detect_separator(path), ",")
})

test_that("detect_separator picks tab when CSV-like content is wrapped in tab columns", {
  # Quoted commas inside a TSV: tab still wins because the tab split
  # produces 5 numeric-rich columns; the comma split produces ragged
  # columns that don't parse as numeric.
  rows <- c(
    "gene\ts1\ts2\ts3\ts4",
    "A,1\t10\t12\t9\t11",
    "B,2\t20\t22\t19\t21",
    "C,3\t30\t32\t29\t31",
    "D,4\t40\t42\t39\t41",
    "E,5\t50\t52\t49\t51"
  )
  path <- write_fixture(paste(rows, collapse = "\n"), "tsv")
  expect_equal(detect_separator(path), "\t")
})

test_that("detect_separator returns NA on a 1-numeric-column file (score < 3)", {
  rows <- c("gene\tcount", "A\t1", "B\t2", "C\t3")
  path <- write_fixture(paste(rows, collapse = "\n"), "tsv")
  expect_true(is.na(detect_separator(path)))
})

test_that("detect_separator picks tab on a 1-numeric-column file with min_score = 1", {
  # Metadata files typically have only 1-2 numeric columns. With the
  # default min_score = 3 they fail to detect; with min_score = 1 the
  # helper still picks the right delimiter.
  rows <- c("sample\tbatch", "A\t1", "B\t2", "C\t3")
  path <- write_fixture(paste(rows, collapse = "\n"), "tsv")
  expect_equal(detect_separator(path, min_score = 1L), "\t")
})

test_that("detect_separator returns NA on a malformed/empty file", {
  path <- write_fixture("", "tsv")
  expect_true(is.na(detect_separator(path)))
})

test_that("detect_separator picks ; on a comma-decimal European CSV", {
  # Numeric parse fails under ',' delimiter (decimals become column
  # boundaries); ';' delimiter yields cleanly numeric columns.
  rows <- c(
    "gene;s1;s2;s3;s4",
    "A;1,5;2,5;3,5;4,5",
    "B;10,1;11,2;12,3;13,4",
    "C;20,1;21,2;22,3;23,4",
    "D;30,1;31,2;32,3;33,4",
    "E;40,1;41,2;42,3;43,4"
  )
  path <- write_fixture(paste(rows, collapse = "\n"), "csv")
  expect_equal(detect_separator(path), ";")
})

test_that("detect_separator tie-breaks tab > comma > semicolon when scores match", {
  # Construct a fixture where tab and comma both yield 3 numeric columns.
  # Tab should win on the tie-break.
  rows <- c(
    "gene\ts1,s2\ts3\ts4",
    "A\t10,11\t9\t11",
    "B\t20,21\t19\t21",
    "C\t30,31\t29\t31",
    "D\t40,41\t39\t41",
    "E\t50,51\t49\t51"
  )
  path <- write_fixture(paste(rows, collapse = "\n"), "tsv")
  expect_equal(detect_separator(path), "\t")
})

test_that("detect_separator returns NA when sample_lines is too low to score", {
  # sample_lines = 1 gives the helper only the header line; with < 2 lines
  # the scorer can't compute column scores, so NA is returned.
  path <- write_fixture(counts_tsv, "tsv")
  expect_true(is.na(detect_separator(path, sample_lines = 1)))
})
