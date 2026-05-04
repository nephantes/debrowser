# R/fct_methods_text.R
#
# Citation-rich per-step methods sentences (methods_sentences) and a
# paragraph-level assembler (methods_paragraph) consumed by emit_r_script()
# (header comment block) and emit_rmd() (Methods paragraph). Backed by
# .method_refs registry; per-call package versions resolved by
# .pkg_version_or_unknown(). Tested in tests/testthat/test-fct-methods-text.R.

#' Per-step methods sentences with inline citations and version stamps.
#'
#' Returns a named character vector with one entry per pipeline step
#' (`load, filter, batch, de, enrichment`). Each entry is one
#' English sentence (or NA if the step did not run, e.g. `batch$method ==
#' "none"`). Internal building block of [methods_paragraph()] which joins
#' the non-NA entries into a single manuscript-ready paragraph.
#'
#' @param blocks Output of [build_session_blocks()].
#' @return Named character vector of length 5.
#' @keywords internal
#' @noRd
methods_sentences <- function(blocks) {
  # --- load (intro + data) ---
  source_desc <- switch(blocks$load$source,
    "demo1"  = "the DEBrowser demo dataset (Vernia et al.)",
    "demo2"  = "the DEBrowser demo dataset (Donnard et al.)",
    "json"   = "a remote JSON URL",
    "upload" = "a user-uploaded TSV"
  )
  load_msg <- sprintf(
    paste0("Differential expression analysis was performed using ",
           "DEBrowser v%s (%s). ",
           "Raw counts (%s features x %d samples) were loaded from %s."),
    .pkg_version_or_unknown(.method_refs$debrowser$version_pkg),
    .method_refs$debrowser$cite,
    format(blocks$load$n_features, big.mark = ","),
    blocks$load$n_samples,
    source_desc
  )

  # --- filter ---
  filter_method_label <- switch(blocks$filter$method,
    "Max"  = sprintf("Max value < %s", blocks$filter$cutoff),
    "Mean" = sprintf("Mean value < %s", blocks$filter$cutoff),
    "CPM"  = sprintf("CPM < %s in fewer than %d samples",
                    blocks$filter$cutoff, blocks$filter$min_samples)
  )
  filter_msg <- sprintf(
    "Features were filtered using a %s cutoff (%s); %s of %s features retained.",
    blocks$filter$method, filter_method_label,
    format(blocks$filter$n_features_out, big.mark = ","),
    format(blocks$filter$n_features_in,  big.mark = ",")
  )

  # --- batch (NA when method=="none") ---
  batch_msg <- if (identical(blocks$batch$method, "none")) {
    NA_character_
  } else {
    key <- switch(blocks$batch$method,
      "Combat"    = "combat",
      "CombatSeq" = "combat_seq",
      "Harman"    = "harman"
    )
    entry <- .method_refs[[key]]
    treat_clause <- if (is.null(blocks$batch$treatment_column) ||
                        is.na(blocks$batch$treatment_column %||% NA)) {
      ""
    } else {
      sprintf(" and `%s` as the biological covariate",
              blocks$batch$treatment_column)
    }
    sprintf(
      "Batch effects were corrected with %s v%s (%s), using `%s` as the batch covariate%s.",
      entry$name, .pkg_version_or_unknown(entry$version_pkg), entry$cite,
      blocks$batch$batch_column, treat_clause
    )
  }

  # --- de (one sentence per comparison, joined with single spaces) ---
  de_lines <- vapply(seq_along(blocks$de), function(i) {
    d <- blocks$de[[i]]
    treat_label   <- gsub("`", "", d$treatment_label)
    control_label <- gsub("`", "", d$control_label)
    n_treat   <- length(d$treatment_samples)
    n_control <- length(d$control_samples)
    de_key <- switch(d$de_method,
      "DESeq2" = "deseq2",
      "EdgeR"  = "edger",
      "Limma"  = "limma"
    )
    entry <- .method_refs[[de_key]]
    param_str <- paste(sprintf("%s=%s", names(d$method_params),
                               unlist(d$method_params)), collapse = ", ")
    sprintf(
      paste0("`%s` (n=%d) versus `%s` (n=%d) was tested with %s v%s (%s) ",
             "using %s; %s features were significant at adjusted p-value < 0.05 ",
             "and |log2 fold change| > 1."),
      treat_label, n_treat, control_label, n_control,
      entry$name, .pkg_version_or_unknown(entry$version_pkg), entry$cite,
      param_str,
      format(d$n_sig_at_padj0.05_lfc1, big.mark = ",")
    )
  }, character(1))
  de_msg <- paste(de_lines, collapse = " ")

  # --- enrichment (NA when not loaded) ---
  enrichment_msg <- if (is.null(blocks$enrichment)) {
    NA_character_
  } else if (identical(blocks$enrichment$source, "msigdb")) {
    sub <- blocks$enrichment$msigdb$subcollection
    sub_part <- if (is.na(sub) || !nzchar(sub)) "" else sprintf(" / %s", sub)
    sprintf(
      paste0("Gene set enrichment analysis was performed with fgsea v%s (%s) ",
             "against the MSigDB %s %s%s collection v%s (%s) ",
             "(n=%d gene sets, default fgsea parameters)."),
      .pkg_version_or_unknown(.method_refs$fgsea$version_pkg),
      .method_refs$fgsea$cite,
      blocks$enrichment$msigdb$species,
      blocks$enrichment$msigdb$collection, sub_part,
      .pkg_version_or_unknown(.method_refs$msigdb$version_pkg),
      .method_refs$msigdb$cite,
      blocks$enrichment$n_pathways
    )
  } else {
    sprintf(
      paste0("Gene set enrichment analysis was performed with fgsea v%s (%s) ",
             "against the uploaded gene set file '%s' ",
             "(n=%d gene sets, default fgsea parameters)."),
      .pkg_version_or_unknown(.method_refs$fgsea$version_pkg),
      .method_refs$fgsea$cite,
      blocks$enrichment$manual_file %||% "uploaded.gmt",
      blocks$enrichment$n_pathways
    )
  }

  c(load = load_msg, filter = filter_msg, batch = batch_msg,
    de = de_msg, enrichment = enrichment_msg)
}

# --- Phase E9: citation registry + version helper -----------------------------

# Maps method-key -> {name, version_pkg, cite}. Method-keys are the lowercase
# stable keys used by methods_sentences() to look up registry entries; they are
# distinct from the UI-side strings ("DESeq2", "Combat", etc.) which carry case.
# See spec: docs/superpowers/specs/2026-05-04-phase-e9-methods-paragraph-design.md
#' @noRd
.method_refs <- list(
  debrowser   = list(name = "DEBrowser",  version_pkg = "debrowser",
                     cite = "Kucukural et al., 2019"),
  deseq2      = list(name = "DESeq2",     version_pkg = "DESeq2",
                     cite = "Love et al., 2014"),
  edger       = list(name = "edgeR",      version_pkg = "edgeR",
                     cite = "Robinson et al., 2010"),
  limma       = list(name = "limma",      version_pkg = "limma",
                     cite = "Ritchie et al., 2015"),
  combat      = list(name = "ComBat",     version_pkg = "sva",
                     cite = "Johnson et al., 2007"),
  combat_seq  = list(name = "ComBat-seq", version_pkg = "sva",
                     cite = "Zhang et al., 2020"),
  harman      = list(name = "Harman",     version_pkg = "Harman",
                     cite = "Oytam et al., 2016"),
  fgsea       = list(name = "fgsea",      version_pkg = "fgsea",
                     cite = "Korotkevich et al., 2021"),
  msigdb      = list(name = "MSigDB",     version_pkg = "msigdbr",
                     cite = "Liberzon et al., 2015")
)

# Package-level tracker for missing-package notification dedup. Persists
# across Shiny sessions within the same R process (created at module load,
# never cleared). Suitable for the single-session-per-process pattern most
# DEBrowser users follow (local app, typical Shiny Server). In multi-session
# deployments (shinyapps.io etc.), a second user would not see a notification
# for a package that user 1 already triggered the warning for; acceptable
# trade-off vs. duplicating the warning N times for the same missing package
# during one paragraph build.
#' @noRd
.missing_pkg_warned <- new.env(parent = emptyenv())

#' @noRd
.notify_missing_pkg_once <- function(pkg) {
  if (!is.null(.missing_pkg_warned[[pkg]])) return(invisible(NULL))
  .missing_pkg_warned[[pkg]] <- TRUE
  if (requireNamespace("shiny", quietly = TRUE) &&
      !is.null(shiny::getDefaultReactiveDomain())) {
    shiny::showNotification(
      sprintf(
        "Methods text export: could not query version for package '%s'. Citation will read '(version unknown)'.",
        pkg
      ),
      type = "warning"
    )
  }
  invisible(NULL)
}

#' @noRd
.pkg_version_or_unknown <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    .notify_missing_pkg_once(pkg)
    return("(version unknown)")
  }
  as.character(utils::packageVersion(pkg))
}

# Internal NULL-coalescing helper. Duplicated in mod_enrichment_gmt.R and
# mod_comparison_concordance.R; lift to R/utils_validate.R when R 4.4 is
# the package floor (R 4.4+ has it natively as `%||%`).
#' @noRd
`%||%` <- function(a, b) if (is.null(a)) b else a
