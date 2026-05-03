# B4 catalogue test: lock the user-facing message format. Every Tier 1
# message must contain BOTH a problem clause and a fix clause.
#
# Module-level messages live in the source files; we keep their literal
# text here as a snapshot. If the source diverges, this test fails and
# we either update the snapshot here, or fix the source.

tier1_module_messages <- list(
  missing_count_upload = "Upload a count file before continuing. Use the Browse button to pick a TSV, CSV, or TXT file.",
  bad_separator_count = "Could not read the count file: only 1 column was detected. Try Tab or Comma in the separator radio buttons below.",
  bad_separator_meta = "Could not read the metadata file: only 1 column was detected. Try Tab or Comma in the separator radio buttons.",
  count_corrupt = "Could not read the count file. Check the file is plain text (TSV, CSV, or TXT) and not corrupted.",
  meta_corrupt = "Could not read the metadata file. Check the file is plain text (TSV, CSV, or TXT) and not corrupted.",
  combat_no_batch = "ComBat needs a batch field. Pick one in the Batch dropdown above before applying.",
  harman_no_fields = "Harman needs both a batch and a treatment field. Pick one for each in the dropdowns above.",
  deseq_too_few = "Cannot run DE analysis: each condition needs at least one sample. Go back to Condition Selection and add samples to the empty group."
)

test_that("Tier 1 module messages all contain a problem clause and a fix clause", {
  # Problem clauses: "Cannot", "Could not", "needs", "Upload"
  problem_pattern <- "Cannot |Could not |needs |Upload "
  # Fix clauses: imperative second sentence -- "Try", "Pick", "Use", "Go back",
  # "Add", "Make", "Check", "Confirm".
  fix_pattern <- "Try |Pick |Use |Go back |Add |Make |Check |Confirm "

  for (key in names(tier1_module_messages)) {
    msg <- tier1_module_messages[[key]]
    expect_match(msg, problem_pattern,
                 info = sprintf("Message %s lacks a problem clause: %s", key, msg))
    expect_match(msg, fix_pattern,
                 info = sprintf("Message %s lacks a fix clause: %s", key, msg))
    expect_false(grepl("!$", msg),
                 info = sprintf("Message %s ends with '!' (style violation): %s", key, msg))
    expect_false(grepl("^Error:|^Warning:", msg),
                 info = sprintf("Message %s starts with redundant prefix: %s", key, msg))
  }
})

test_that("Pure validators raise the documented classes", {
  # Belt-and-suspenders: also covered in test-fct-upload.R, but lock here.
  path <- tempfile(fileext = ".tsv")
  on.exit(unlink(path), add = TRUE)
  writeLines(c("a\tb", "g1\t1"), path)
  expect_error(validate_count_upload(path, sep = ","), class = "bad_separator")

  writeLines(c("g\ts1\ts2", "G1\t1\t2", "G1\t3\t4"), path)
  expect_error(validate_count_upload(path, sep = "\t"),
               class = "duplicate_gene_ids")

  writeLines(c("Sample\tCondition", "S1\tA"), path)
  expect_error(
    validate_metadata_upload(path, count_cols = c("S1", "S99"), sep = "\t"),
    class = "column_mismatch"
  )
})

test_that("Module messages exist verbatim in the source files", {
  # Snapshot guard: if a future copy-edit changes a message, this test
  # will catch the drift between the catalogue and the source.
  data_load <- paste(readLines("../../R/dataLoad.R"), collapse = "\n")
  batch <- paste(readLines("../../R/batcheffect.R"), collapse = "\n")
  deprogs <- paste(readLines("../../R/deprogs.R"), collapse = "\n")

  expect_true(grepl(tier1_module_messages$missing_count_upload, data_load, fixed = TRUE))
  expect_true(grepl(tier1_module_messages$bad_separator_count, data_load, fixed = TRUE))
  expect_true(grepl(tier1_module_messages$bad_separator_meta, data_load, fixed = TRUE))
  expect_true(grepl(tier1_module_messages$count_corrupt, data_load, fixed = TRUE))
  expect_true(grepl(tier1_module_messages$meta_corrupt, data_load, fixed = TRUE))
  expect_true(grepl(tier1_module_messages$combat_no_batch, batch, fixed = TRUE))
  expect_true(grepl(tier1_module_messages$harman_no_fields, batch, fixed = TRUE))
  expect_true(grepl(tier1_module_messages$deseq_too_few, deprogs, fixed = TRUE))
})

test_that("Empty-result messages flipped from error to info severity", {
  gopanel <- paste(readLines("../../R/gopanel.R"), collapse = "\n")
  goterm <- paste(readLines("../../R/GOterm.R"), collapse = "\n")
  # gopanel: GSEA empty-result must use de_notify_info, not type = "error".
  expect_match(gopanel, "de_notify_info\\(sprintf\\(\\s*\"No enriched terms at p")
  # GOterm: cluster empty-result must use de_notify_info.
  expect_match(goterm, "de_notify_info\\(sprintf\\(\\s*\"No enriched terms in any cluster")
  # GOterm: cluster no-mappable-IDs stays as a warning.
  expect_match(goterm, "de_notify_warning\\(sprintf\\(\\s*\"No gene IDs mapped to")
})
