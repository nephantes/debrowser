# R/fct_condselect.R
#
# Pure helpers for the comparison-selection wizard. No Shiny dependency.
# Tested in tests/testthat/test-condselect-helpers.R and
# tests/testthat/test-condselect-validation.R.

.CONTROL_REGEX <- paste0(
  "(?i)^(",
  paste(c(
    "control", "ctrl", "wt", "wildtype", "wild_type",
    "vehicle", "dmso", "untreated", "mock", "ref",
    "naive", "baseline", "0h", "day0"
  ), collapse = "|"),
  ")$"
)

#' Infer the control-side level for a 2-level metadata column.
#'
#' Matches each level (case-insensitive, anchored) against a small list of
#' reference-shaped words. If exactly one level matches, returns it. Otherwise
#' falls back to alphabetical order so the result is always deterministic.
#'
#' @param levels character vector of metadata-column levels (>= 2 expected).
#' @return character(1) -- the level chosen as control.
#' @noRd
infer_control_level <- function(levels) {
  matches <- grepl(.CONTROL_REGEX, levels, perl = TRUE)
  if (sum(matches) == 1) {
    return(levels[matches])
  }
  sort(levels)[1]
}

#' Compute initial side labels for a comparison.
#'
#' Returns a named character(2) `c(treatment = ..., control = ...)`. When
#' a metadata column with two non-NA levels is supplied, the level names are
#' used directly. Otherwise falls back to the literal "Treatment" / "Control".
#'
#' @noRd
default_side_labels <- function(meta_column, treatment_level, control_level) {
  if (!is.na(meta_column) && !is.na(treatment_level) && !is.na(control_level)) {
    return(c(treatment = treatment_level, control = control_level))
  }
  c(treatment = "Treatment", control = "Control")
}

#' Halve a sample-name vector into default treatment / control halves.
#'
#' Replaces the legacy `getSampleNames(cnames, part)` and fixes its `1:0`
#' index-reversal quirk at length 1. The first half (length floor(n/2)) is
#' assigned to treatment, the rest to control. At n = 1 treatment is empty
#' and control gets the single sample.
#'
#' @param sample_names character vector of column names from the count matrix.
#' @return list with components `treatment` and `control`, or NULL on NULL input.
#' @noRd
halve_sample_names <- function(sample_names) {
  if (is.null(sample_names)) return(NULL)
  n <- length(sample_names)
  if (n == 0L) return(list(treatment = character(0), control = character(0)))
  cut <- floor(n / 2L)
  list(
    treatment = if (cut >= 1L) sample_names[seq_len(cut)] else character(0),
    control   = if (cut + 1L <= n) sample_names[(cut + 1L):n] else character(0)
  )
}

#' Extract the user-visible label vector from a comparison spec.
#'
#' This is the single source of truth that flows into `cond_names` for plot
#' legends, table column prefixes, etc.
#'
#' @noRd
compute_cond_names <- function(spec) {
  c(spec$treatment_label, spec$control_label)
}

#' Serialize a comparison's DE method + params + covariates into the comma-
#' separated string that `R/fct_de_methods.R` and `R/deprogs.R` parse
#' positionally. Reproduces the legacy `prepDataContainer` format byte-for-byte.
#'
#' Schema by method:
#'   DESeq2: "DESeq2,<covariate>,<fitType>,<betaPrior>,<testType>,<shrinkage>"
#'   EdgeR:  "EdgeR,<covariate>,<edgeR_normfact>,<dispersion>,<edgeR_testType>"
#'   Limma:  "Limma,<covariate>,<limma_normfact>,<limma_fitType>,<normBetween>"
#'
#' Where `<covariate>` is the pipe-joined covariate column names, or the
#' literal string "NoCovariate" when empty (legacy convention).
#'
#' Empty-string covariates (length-1 `""` from a legacy reactive context) are
#' normalized away alongside `character(0)` to the literal `"NoCovariate"`.
#' Missing or `NULL` `method_params` fields produce a hard error rather than
#' silently dropping a field via `paste()`.
#'
#' @noRd
build_demethod_params_string <- function(de_method, method_params, covariates) {
  # Drop empty-string covariates so callers passing "" (legacy artifact of an
  # empty selectInput) get the "NoCovariate" sentinel just like length-0.
  covariates <- covariates[nzchar(covariates)]
  cov_str <- if (length(covariates) == 0L) {
    "NoCovariate"
  } else {
    paste(covariates, collapse = "|")
  }

  # Hard-fail on missing/NULL method_params fields so a downstream parser
  # off-by-one (paste() silently drops NULL) is impossible. Each branch
  # consumes a fixed-arity vector; missing fields = bug, not a recoverable case.
  require_fields <- function(params, fields) {
    missing_or_null <- vapply(
      fields,
      function(f) is.null(params[[f]]),
      logical(1)
    )
    if (any(missing_or_null)) {
      stop("build_demethod_params_string: missing method_params field(s) for ",
           sQuote(de_method), ": ",
           paste(fields[missing_or_null], collapse = ", "),
           call. = FALSE)
    }
  }

  switch(de_method,
    "DESeq2" = {
      require_fields(method_params, c("fitType", "betaPrior", "testType", "shrinkage"))
      paste(
        "DESeq2", cov_str,
        method_params$fitType, method_params$betaPrior,
        method_params$testType, method_params$shrinkage,
        sep = ","
      )
    },
    "EdgeR" = {
      require_fields(method_params, c("edgeR_normfact", "dispersion", "edgeR_testType"))
      paste(
        "EdgeR", cov_str,
        method_params$edgeR_normfact, method_params$dispersion,
        method_params$edgeR_testType,
        sep = ","
      )
    },
    "Limma" = {
      require_fields(method_params, c("limma_normfact", "limma_fitType", "normBetween"))
      paste(
        "Limma", cov_str,
        method_params$limma_normfact, method_params$limma_fitType,
        method_params$normBetween,
        sep = ","
      )
    },
    stop("build_demethod_params_string: unknown de_method: ",
         sQuote(de_method), call. = FALSE)
  )
}

.rec <- function(field, ok, message = NULL, severity = NULL) {
  stopifnot(is.logical(ok), length(ok) == 1L, !is.na(ok))
  if (is.null(severity)) {
    severity <- if (ok) "pass" else "error"
  }
  list(field = field, ok = ok, message = message, severity = severity)
}

# Treats character(1) without leading/trailing whitespace as non-blank.
# NULL, NA, length != 1, and pure-whitespace are all blank.
is_nonblank <- function(x) {
  length(x) == 1L && !is.na(x) && nzchar(trimws(x))
}

# Locate the column in metadata whose values contain all the named samples.
# Mirrors the convention used in R/deprogs.R::prepGroup so the validator and
# downstream DE machinery agree on which column is the sample-name column.
# Returns the column name, or NA_character_ if no column qualifies.
find_sample_column <- function(metadata, samples) {
  if (is.null(metadata) || ncol(metadata) == 0L || length(samples) == 0L) {
    return(NA_character_)
  }
  hit <- vapply(seq_len(ncol(metadata)), function(j) {
    col <- metadata[[j]]
    if (is.factor(col)) col <- as.character(col)
    sum(samples %in% col) == length(samples)
  }, logical(1))
  if (!any(hit)) return(NA_character_)
  colnames(metadata)[which(hit)[1]]
}

#' Compose all validation predicates for a comparison spec.
#'
#' Returns a list of validation records (one per check that produced a
#' result). Records are `list(field, ok, message, severity)`. Fields:
#' "treatment_samples", "control_samples", "samples_disjoint",
#' "treatment_label", "control_label", "meta_levels", "level_distinct",
#' "covariate_<name>".
#'
#' @noRd
validate_comparison <- function(spec, metadata) {
  records <- list()

  # Error-severity predicates.
  if (length(spec$treatment_samples) >= 1) {
    records[[length(records) + 1]] <- .rec("treatment_samples", TRUE)
  } else {
    records[[length(records) + 1]] <- .rec("treatment_samples", FALSE,
         "Treatment side has no samples selected.", "error")
  }

  if (length(spec$control_samples) >= 1) {
    records[[length(records) + 1]] <- .rec("control_samples", TRUE)
  } else {
    records[[length(records) + 1]] <- .rec("control_samples", FALSE,
         "Control side has no samples selected.", "error")
  }

  overlap <- intersect(spec$treatment_samples, spec$control_samples)
  if (length(overlap) == 0) {
    records[[length(records) + 1]] <- .rec("samples_disjoint", TRUE)
  } else {
    records[[length(records) + 1]] <- .rec("samples_disjoint", FALSE,
         paste0("Sample(s) appear on both sides: ",
                paste(overlap, collapse = ", "), "."), "error")
  }

  if (is_nonblank(spec$treatment_label)) {
    records[[length(records) + 1]] <- .rec("treatment_label", TRUE)
  } else {
    records[[length(records) + 1]] <- .rec("treatment_label", FALSE,
         "Treatment label is empty.", "error")
  }

  if (is_nonblank(spec$control_label)) {
    records[[length(records) + 1]] <- .rec("control_label", TRUE)
  } else {
    records[[length(records) + 1]] <- .rec("control_label", FALSE,
         "Control label is empty.", "error")
  }

  # Meta-path-only predicates.
  if (!is.na(spec$meta_column) && spec$meta_column %in% colnames(metadata)) {
    col <- metadata[[spec$meta_column]]
    if (is.factor(col)) col <- as.character(col)
    levels_present <- unique(col)
    levels_present <- levels_present[!is.na(levels_present) & nzchar(levels_present)]

    if (length(levels_present) >= 2) {
      records[[length(records) + 1]] <- .rec("meta_levels", TRUE)
    } else {
      records[[length(records) + 1]] <- .rec("meta_levels", FALSE,
           paste0("Metadata column `", spec$meta_column,
                  "` has fewer than 2 distinct levels."), "error")
    }

    if (!is.na(spec$treatment_level) && !is.na(spec$control_level)) {
      if (spec$treatment_level != spec$control_level) {
        records[[length(records) + 1]] <- .rec("level_distinct", TRUE)
      } else {
        records[[length(records) + 1]] <- .rec("level_distinct", FALSE,
             "Treatment and Control must be different levels.", "error")
      }
    }
  }

  # Covariate predicates (severity = warning, advisory only -- except an
  # unknown column name, which is a hard configuration error).
  selected_samples <- c(spec$treatment_samples, spec$control_samples)
  treatment_marker <- c(rep("Treat", length(spec$treatment_samples)),
                       rep("Control", length(spec$control_samples)))
  sample_col <- find_sample_column(metadata, selected_samples)

  for (cov in spec$covariates) {
    if (!cov %in% colnames(metadata)) {
      records[[length(records) + 1]] <- .rec(
        paste0("covariate_", cov), FALSE,
        paste0("Covariate `", cov, "` is not a column of the metadata."),
        "error"
      )
      next
    }

    msg <- NULL

    # 1. Equal to meta column?
    if (!is.na(spec$meta_column) && cov == spec$meta_column) {
      msg <- paste0("Covariate `", cov, "` is the comparison column itself.")
    }

    # 2. NA in selected samples?
    if (is.null(msg)) {
      if (is.na(sample_col)) {
        # Can't locate the sample-name column at all; nothing more to check
        # for this covariate without that anchor.
        msg <- paste0("Covariate `", cov,
                      "` cannot be evaluated (no metadata column matches the ",
                      "selected sample names).")
      } else {
        cov_vals <- metadata[[cov]][match(selected_samples, metadata[[sample_col]])]
        if (is.factor(cov_vals)) cov_vals <- as.character(cov_vals)
        if (any(is.na(cov_vals))) {
          msg <- paste0("Covariate `", cov, "` has NA in selected samples.")
        } else if (length(unique(cov_vals)) < 2) {
          # 3. < 2 unique values?
          msg <- paste0("Covariate `", cov,
                        "` has fewer than 2 distinct values in selected samples.")
        } else {
          # 4. Confounded? (each level of cov should appear in both sides)
          ct <- table(cov_vals, treatment_marker)
          if (any(ct == 0)) {
            msg <- paste0("Covariate `", cov,
                          "` is confounded with treatment (some levels appear ",
                          "on only one side).")
          }
        }
      }
    }

    if (!is.null(msg)) {
      records[[length(records) + 1]] <- .rec(
        paste0("covariate_", cov), FALSE, msg, "warning"
      )
    }
  }

  records
}
