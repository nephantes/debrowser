test_that("getEntrezTable() returns 0-row table when category geneID is NA", {
  # Regression: when input$gotable_rows_selected indexes past the current
  # enrichResult (e.g. stale selection across re-runs), genes was
  # NA_character_. `mapped_genes %in% NA` then matched every NA-mapped
  # DE gene and the modal showed "all DE genes" instead of empty.
  skip_if_not_installed("org.Hs.eg.db")

  de_dat <- data.frame(
    log2FoldChange = c(0.5, -0.3, 1.2, -0.8, 0.1),
    padj = c(0.01, 0.02, 0.03, 0.04, 0.05),
    row.names = c("TP53", "FAKE_A", "FAKE_B", "FAKE_C", "FAKE_D")
  )

  res <- getEntrezTable(NA_character_, de_dat, "org.Hs.eg.db")
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 0L)
})

test_that("getEntrezTable() returns 0-row table for no-overlap category", {
  skip_if_not_installed("org.Hs.eg.db")

  de_dat <- data.frame(
    log2FoldChange = c(0.5, -0.3),
    padj = c(0.01, 0.02),
    row.names = c("TP53", "BRCA1")
  )

  res <- getEntrezTable("99999/88888", de_dat, "org.Hs.eg.db")
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 0L)
})

test_that("getEntrezTable() returns the overlap subset when categories match", {
  skip_if_not_installed("org.Hs.eg.db")

  de_dat <- data.frame(
    log2FoldChange = c(0.5, -0.3, 1.2),
    padj = c(0.01, 0.02, 0.03),
    row.names = c("TP53", "BRCA1", "FAKE_X")
  )

  # 7157 = TP53 ENTREZ; 672 = BRCA1 ENTREZ
  res <- getEntrezTable("7157/672", de_dat, "org.Hs.eg.db")
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 2L)
  expect_setequal(rownames(res), c("TP53", "BRCA1"))
})

test_that("getEntrezTable() drops empty / NA segments from /-split geneID", {
  skip_if_not_installed("org.Hs.eg.db")

  de_dat <- data.frame(
    log2FoldChange = c(0.5, -0.3),
    padj = c(0.01, 0.02),
    row.names = c("TP53", "FAKE_X")
  )

  # Trailing / and stray empty segments shouldn't pull NA-mapped rows in.
  res <- getEntrezTable("7157//", de_dat, "org.Hs.eg.db")
  expect_equal(nrow(res), 1L)
  expect_equal(rownames(res), "TP53")
})
