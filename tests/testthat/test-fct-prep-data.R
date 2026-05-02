test_that("apply_de_filters() labels Up/Down/NS for the demo DE result", {
  skip_on_cran()

  demo <- load_demo()
  data <- demo$counts[, demo_columns]
  data <- data[rowSums(data) > 10, ]

  set.seed(1L)
  de <- run_deseq2(
    counts   = data,
    metadata = demo$meta,
    columns  = demo_columns,
    conds    = demo_conds,
    params   = list(covariates = "NoCovariate", test_type = "Wald", shrinkage = "None")
  )
  de <- as.data.frame(de)
  de$foldChange <- 2^de$log2FoldChange
  de$padj[is.na(de$padj)] <- 1
  de$ID <- rownames(de)
  # The applyFilters() pipeline expects sample columns on the input frame.
  for (col in demo_columns) de[[col]] <- data[rownames(de), col]

  out <- apply_de_filters(
    filt_data = de,
    cols      = demo_columns,
    conds     = c(rep("Cond1", 3), rep("Cond2", 3)),
    params    = list(
      padj_cutoff  = 0.05,
      fold_cutoff  = 2,
      dataset      = "up+down",
      compselect   = 1,
      norm_method  = "TMM",
      geneset_area = "",
      method_tab   = "panel1"
    )
  )

  expect_true("Legend" %in% colnames(out))
  expect_true(all(out$Legend %in% c("Up", "Down", "NS")))

  counts <- as.list(table(out$Legend))
  expect_snapshot_value(counts, style = "json2")
})

test_that("apply_de_filters() returns NULL for missing data", {
  expect_null(apply_de_filters(NULL, NULL, NULL, params = list()))
})

test_that("select_dataset() routes by dataset name", {
  rdata <- data.frame(
    ID     = c("a", "b", "c", "d"),
    Legend = c("Up", "Down", "Up", "NS"),
    stringsAsFactors = FALSE
  )
  rownames(rdata) <- rdata$ID

  expect_equal(
    nrow(select_dataset(rdata, params = list(dataset = "up"))),
    2L
  )
  expect_equal(
    nrow(select_dataset(rdata, params = list(dataset = "down"))),
    1L
  )
  expect_equal(
    nrow(select_dataset(rdata, params = list(dataset = "alldetected"))),
    4L
  )
  expect_equal(
    rownames(select_dataset(
      rdata,
      get_selected = rdata[1:2, ],
      params = list(dataset = "selected", selected_plot = "anything")
    )),
    c("a", "b")
  )
})

test_that("search_geneset() returns NULL when input is NULL", {
  expect_null(search_geneset(NULL, params = list(geneset_area = "BRCA1")))
})

test_that("merge_comparisons() returns NULL for empty input", {
  expect_null(merge_comparisons(NULL, 0L, params = list()))
})

test_that("get_table_data() returns (data, padj_col, fold_col) tuple", {
  init <- data.frame(
    ID = c("g1", "g2"),
    foldChange = c(3, 0.5),
    padj = c(0.001, 0.5),
    Legend = c("Up", "NS"),
    row.names = c("g1", "g2")
  )

  res <- get_table_data(
    init_data = init,
    filt_data = init,
    selected = NULL,
    get_most_varied_data = NULL,
    merged_comp = NULL,
    params = list(dataset = "alldetected", geneset_area = "")
  )
  expect_length(res, 3L)
  expect_equal(res[[2]], "padj")
  expect_equal(res[[3]], "foldChange")
  expect_equal(nrow(res[[1]]), 2L)

  res_up <- get_table_data(
    init_data = init,
    filt_data = init,
    selected = NULL,
    get_most_varied_data = NULL,
    merged_comp = NULL,
    params = list(dataset = "up", geneset_area = "")
  )
  expect_equal(nrow(res_up[[1]]), 1L)
})

test_that("get_table_data() returns NULL with no init_data", {
  expect_null(get_table_data(NULL))
})

test_that("apply_merged_filters() labels rows Sig where any comparison crosses cutoffs", {
  fake_dc <- list(
    list(
      cols = c("s1", "s2"),
      cond_names = c("A", "B"),
      init_data = data.frame(
        foldChange = c(3, 0.1, 1.0),
        padj       = c(0.001, 0.001, 0.5),
        s1 = c(10, 20, 30), s2 = c(11, 22, 33),
        row.names = c("g1", "g2", "g3")
      )
    )
  )
  out <- apply_merged_filters(fake_dc, 1L,
    params = list(padj_cutoff = 0.05, fold_cutoff = 2, norm_method = "none")
  )
  expect_true("Legend" %in% colnames(out))
  expect_equal(out$Legend, c("Sig", "Sig", "NS"))
})

test_that("apply_de_filters() with fold_cutoff = log2fc_to_fold(1) matches fold_cutoff = 2", {
  filt_data <- data.frame(
    foldChange = c(3, 0.1, 1.0, 2.5),
    padj       = c(0.001, 0.001, 0.5, 0.001),
    s1 = c(10, 20, 30, 40),
    s2 = c(11, 22, 33, 44),
    s3 = c(12, 24, 36, 48),
    s4 = c(13, 26, 39, 52),
    row.names = c("g1", "g2", "g3", "g4")
  )
  base_params <- list(
    padj_cutoff = 0.05, fold_cutoff = 2,
    dataset = "up+down", norm_method = "none"
  )
  via_log2fc_params <- modifyList(
    base_params, list(fold_cutoff = log2fc_to_fold(1))
  )

  out_base <- apply_de_filters(
    filt_data,
    cols   = c("s1", "s2", "s3", "s4"),
    conds  = c("Cond1", "Cond1", "Cond2", "Cond2"),
    params = base_params
  )
  out_via <- apply_de_filters(
    filt_data,
    cols   = c("s1", "s2", "s3", "s4"),
    conds  = c("Cond1", "Cond1", "Cond2", "Cond2"),
    params = via_log2fc_params
  )

  expect_equal(out_via$Legend, out_base$Legend)
  # Sanity: with this fixture both Up and Down labels appear.
  expect_true(any(out_via$Legend == "Up"))
  expect_true(any(out_via$Legend == "Down"))
})

test_that("apply_merged_filters() with fold_cutoff = log2fc_to_fold(1) matches fold_cutoff = 2", {
  fake_dc <- list(
    list(
      cols = c("s1", "s2"),
      cond_names = c("A", "B"),
      init_data = data.frame(
        foldChange = c(3, 0.1, 1.0),
        padj       = c(0.001, 0.001, 0.5),
        s1 = c(10, 20, 30), s2 = c(11, 22, 33),
        row.names = c("g1", "g2", "g3")
      )
    )
  )

  base <- apply_merged_filters(fake_dc, 1L,
    params = list(padj_cutoff = 0.05, fold_cutoff = 2, norm_method = "none")
  )
  via_log2fc <- apply_merged_filters(fake_dc, 1L,
    params = list(padj_cutoff = 0.05,
                  fold_cutoff = log2fc_to_fold(1),
                  norm_method = "none")
  )

  expect_equal(via_log2fc$Legend, base$Legend)
  # Sanity: with this fixture the labels are non-trivial (not all NS).
  expect_true(any(via_log2fc$Legend == "Sig"))
})
