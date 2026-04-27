# Shared helpers for debrowser tests.

#' Load the bundled Vernia demo dataset and metadata as a list.
load_demo <- function() {
  load(system.file("extdata", "demo", "demodata.Rda", package = "debrowser"))
  list(counts = demodata, meta = metadatatable)
}

#' Stable hash of a numeric matrix or data frame for snapshot tests.
#' Coerces to a numeric matrix, rounds to 6 dp to absorb FPU noise, then digests.
stable_hash <- function(x) {
  if (is.data.frame(x)) {
    x <- as.matrix(x[vapply(x, is.numeric, logical(1))])
  }
  x <- round(x, 6L)
  digest::digest(x, algo = "xxhash64")
}

#' The 6-column control/exper subset used in tests.
demo_columns <- c(
  "exper_rep1", "exper_rep2", "exper_rep3",
  "control_rep1", "control_rep2", "control_rep3"
)

#' Condition factor matching demo_columns: experimental samples = Treat,
#' control samples = Control. (The legacy test-deseq.R had this reversed.)
demo_conds <- factor(c("Treat", "Treat", "Treat", "Control", "Control", "Control"))
