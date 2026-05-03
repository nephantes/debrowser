# R/prep_data_container.R
#
# Extracted and rewritten from R/condSelect.R. The new signature is
#   prepDataContainer(data, metadata, comparisons_spec)
# where `comparisons_spec` is a list of per-comparison spec lists (see
# R/mod_condselect.R / docs/superpowers/specs/2026-04-29-...md). The legacy
# 4-arg signature was `prepDataContainer(data, counter, input, meta)`.

# Build the deterministic spec-derived inputs for one comparison.
#
# Pure helper extracted so the spec -> (cols, conds, cond_names,
# demethod_params) mapping is unit-testable without a Shiny session or
# DESeq2. `prepDataContainer` consumes the result and runs DE on top.
#
# `comparison_idx` (1-based) is the comparison's slot in the wizard. The
# `conds` vector uses globally-numbered codes (`Cond1/Cond2` for slot 1,
# `Cond3/Cond4` for slot 2, ...) to match the legacy contract that
# `R/fct_prep_data.R::apply_de_filters` consumes via
# `paste0("Cond", 2 * compselect - 1)` and `paste0("Cond", 2 * compselect)`.
prep_comparison_inputs <- function(spec, comparison_idx = 1L) {
  cols <- c(spec$treatment_samples, spec$control_samples)
  conds <- c(
    rep(paste0("Cond", 2L * comparison_idx - 1L), length(spec$treatment_samples)),
    rep(paste0("Cond", 2L * comparison_idx),     length(spec$control_samples))
  )
  cond_names <- compute_cond_names(spec)
  demethod_params <- build_demethod_params_string(
    spec$de_method, spec$method_params, spec$covariates
  )
  list(
    cols = cols,
    conds = conds,
    cond_names = cond_names,
    demethod_params = demethod_params
  )
}

#' Run DE per comparison and return the downstream `dclist` payload.
#'
#' @param data count matrix (rows = features, cols = samples).
#' @param metadata sample-metadata data.frame; first column is the sample id.
#' @param comparisons_spec list of per-comparison spec lists with components
#'   `treatment_samples`, `control_samples`, `treatment_label`,
#'   `control_label`, `de_method`, `method_params`, `covariates`,
#'   `meta_column` (NA_character_ when manual mode).
#' @return list of length `length(comparisons_spec)` with components
#'   `conds`, `cols`, `cond_names`, `init_data`, `demethod_params`, `dds`
#'   per comparison. `dds` is the fitted `DESeqDataSet` for DESeq2 runs and
#'   NULL for edgeR/limma. Returns NULL if no comparison produced usable
#'   results.
#' @export
prepDataContainer <- function(data, metadata, comparisons_spec) {
  if (is.null(data) || length(comparisons_spec) == 0L) {
    return(NULL)
  }

  dclist <- list()
  n <- length(comparisons_spec)

  for (i in seq_len(n)) {
    inputs <- prep_comparison_inputs(comparisons_spec[[i]], comparison_idx = i)

    shiny::withProgress(
      message = "Running DE Algorithms",
      detail = inputs$demethod_params,
      value = 0,
      {
        initd <- debrowserdeanalysis(
          paste0("DEResults", i),
          data = data, metadata = metadata,
          columns = inputs$cols, conds = inputs$conds,
          params = unlist(strsplit(inputs$demethod_params, ","))
        )
        if (!is.null(initd$dat()) && nrow(initd$dat()) > 1L) {
          dds_val <- tryCatch(initd$dds(), error = function(e) NULL)
          dclist[[i]] <- list(
            conds = inputs$conds, cols = inputs$cols,
            cond_names = inputs$cond_names,
            init_data = initd$dat(),
            demethod_params = inputs$demethod_params,
            dds = dds_val
          )
        }
        shiny::incProgress(1 / n)
      }
    )
  }

  if (length(dclist) < 1L) return(NULL)
  dclist
}
