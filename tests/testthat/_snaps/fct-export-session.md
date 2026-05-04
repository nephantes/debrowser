# emit_r_script demo+DESeq2 minimal matches snapshot

    Code
      cat(emit_r_script(blocks), sep = "\n")
    Output
      # DEBrowser session export
      # Generated 2026-05-03 14:22:11 by debrowser 1.31.2
      # R version 4.4.2 (2024-10-31)
      #
      # Methods (auto-generated, refine before publication):
      # Differential expression analysis was performed using DEBrowser v1.31.2
      # (Kucukural et al., 2019). Raw counts (30,739 features x 6 samples) were
      # loaded from the DEBrowser demo dataset (Vernia et al.). Features were
      # filtered using a Max cutoff (Max value < 10); 18,000 of 30,739 features
      # retained. `exper` (n=3) versus `control` (n=3) was tested with DESeq2
      # v1.48.2 (Love et al., 2014) using fitType=parametric, betaPrior=FALSE,
      # testType=Wald, shrinkage=apeglm; 1,247 features were significant at
      # adjusted p-value < 0.05 and |log2 fold change| > 1.
      #
      # Frozen sessionInfo (at export time):
      # R version 4.4.2 (2024-10-31)
      # Platform: aarch64-apple-darwin20
      
      library(debrowser)
      
      # 1. Load counts and metadata --------------------------------------------------
      demo_env <- new.env()
      load(system.file("extdata", "demo", "demodata.Rda", package = "debrowser"), envir = demo_env)
      counts <- demo_env$demodata
      meta   <- demo_env$metadatatable
      
      # 2. Low-count filter ----------------------------------------------------------
      filtered <- filter_low_counts(counts, method = "max",  cutoff = 10)
      
      # 3. Batch correction ----------------------------------------------------------
      # (none configured)
      corrected <- filtered
      
      # 4. Differential expression ---------------------------------------------------
      # --- Comparison 1: exper vs control ---
      cols_1  <- c("exper_rep1", "exper_rep2", "exper_rep3", "control_rep1", "control_rep2", "control_rep3")
      conds_1 <- c("Cond1", "Cond1", "Cond1", "Cond2", "Cond2", "Cond2")
      de1 <- run_de(
        method = "DESeq2",
        counts = corrected, metadata = meta, columns = cols_1, conds = conds_1,
        params = list(covariates = "NoCovariate", fit_type   = "parametric", beta_prior = FALSE, test_type  = "Wald", shrinkage  = "apeglm"),
        return_dds = FALSE
      )
      
      # 6. Write per-comparison result tables ----------------------------------------
      dir.create("debrowser_results", showWarnings = FALSE)
      write.table(de1, "debrowser_results/results_exper_vs_control.tsv",
                  sep = "\t", quote = FALSE, col.names = NA)
      
      cat("Wrote 1 result files to debrowser_results/\n")
      
      # 7. Session info (run-time) ---------------------------------------------------
      sessionInfo()

# emit_r_script upload+CPM+Combat+2xDESeq2+MSigDB matches snapshot

    Code
      cat(emit_r_script(blocks), sep = "\n")
    Output
      # DEBrowser session export
      # Generated 2026-05-03 14:22:11 by debrowser 1.31.2
      # R version 4.4.2 (2024-10-31)
      #
      # Methods (auto-generated, refine before publication):
      # Differential expression analysis was performed using DEBrowser v1.31.2
      # (Kucukural et al., 2019). Raw counts (32,451 features x 12 samples) were
      # loaded from a user-uploaded TSV. Features were filtered using a CPM cutoff
      # (CPM < 1 in fewer than 11 samples); 28,104 of 32,451 features retained.
      # Batch effects were corrected with ComBat v3.56.0 (Johnson et al., 2007),
      # using `batch` as the batch covariate and `condition` as the biological
      # covariate. `treated` (n=3) versus `control` (n=3) was tested with DESeq2
      # v1.48.2 (Love et al., 2014) using fitType=parametric, betaPrior=FALSE,
      # testType=Wald, shrinkage=apeglm; 1,247 features were significant at
      # adjusted p-value < 0.05 and |log2 fold change| > 1. `high_dose` (n=3)
      # versus `control` (n=3) was tested with DESeq2 v1.48.2 (Love et al., 2014)
      # using fitType=parametric, betaPrior=FALSE, testType=Wald, shrinkage=apeglm;
      # 892 features were significant at adjusted p-value < 0.05 and |log2 fold
      # change| > 1. Gene set enrichment analysis was performed with fgsea v1.34.2
      # (Korotkevich et al., 2021) against the MSigDB Homo sapiens H collection
      # v26.1.0 (Liberzon et al., 2015) (n=50 gene sets, default fgsea parameters).
      #
      # Frozen sessionInfo (at export time):
      # R version 4.4.2 (2024-10-31)
      # Platform: aarch64-apple-darwin20
      
      library(debrowser)
      
      # 1. Load counts and metadata --------------------------------------------------
      # original upload: counts='my_counts.tsv', meta='my_meta.tsv'
      # EDIT THIS PATH to point at your local copy of the file:
      counts <- read.table("YOUR_COUNTS.tsv", sep = "\t", header = TRUE,
                           row.names = 1, check.names = FALSE)
      meta   <- read.table("YOUR_META.tsv",   sep = "\t", header = TRUE,
                           row.names = 1, check.names = FALSE)
      
      # 2. Low-count filter ----------------------------------------------------------
      filtered <- filter_low_counts(counts, method = "cpm",  cutoff = 1, min_samples = 11)
      
      # 3. Batch correction ----------------------------------------------------------
      corrected <- apply_batch_correction(
        filtered, meta,
        method = "Combat", batch_col = "batch", treatment_col = "condition"
      )
      
      # 4. Differential expression ---------------------------------------------------
      # --- Comparison 1: treated vs control ---
      cols_1  <- c("S1", "S2", "S3", "S4", "S5", "S6")
      conds_1 <- c("Cond1", "Cond1", "Cond1", "Cond2", "Cond2", "Cond2")
      de1 <- run_de(
        method = "DESeq2",
        counts = corrected, metadata = meta, columns = cols_1, conds = conds_1,
        params = list(covariates = "NoCovariate", fit_type   = "parametric", beta_prior = FALSE, test_type  = "Wald", shrinkage  = "apeglm"),
        return_dds = FALSE
      )
      
      # --- Comparison 2: high_dose vs control ---
      cols_2  <- c("S7", "S8", "S9", "S4", "S5", "S6")
      conds_2 <- c("Cond3", "Cond3", "Cond3", "Cond4", "Cond4", "Cond4")
      de2 <- run_de(
        method = "DESeq2",
        counts = corrected, metadata = meta, columns = cols_2, conds = conds_2,
        params = list(covariates = "NoCovariate", fit_type   = "parametric", beta_prior = FALSE, test_type  = "Wald", shrinkage  = "apeglm"),
        return_dds = FALSE
      )
      
      # 5. Enrichment (GSEA) ---------------------------------------------------------
      pathways <- msigdb_pathways(species = "Homo sapiens", collection = "H", subcollection = NULL)
      gsea_1 <- run_gsea(de1, pathways = pathways)
      gsea_2 <- run_gsea(de2, pathways = pathways)
      
      # 6. Write per-comparison result tables ----------------------------------------
      dir.create("debrowser_results", showWarnings = FALSE)
      write.table(de1, "debrowser_results/results_treated_vs_control.tsv",
                  sep = "\t", quote = FALSE, col.names = NA)
      write.table(de2, "debrowser_results/results_high_dose_vs_control.tsv",
                  sep = "\t", quote = FALSE, col.names = NA)
      write.table(gsea_1, "debrowser_results/gsea_treated_vs_control.tsv",
                  sep = "\t", quote = FALSE, row.names = FALSE)
      write.table(gsea_2, "debrowser_results/gsea_high_dose_vs_control.tsv",
                  sep = "\t", quote = FALSE, row.names = FALSE)
      
      cat("Wrote 4 result files to debrowser_results/\n")
      
      # 7. Session info (run-time) ---------------------------------------------------
      sessionInfo()

# emit_rmd minimal demo matches snapshot

    Code
      cat(emit_rmd(blocks), sep = "\n")
    Output
      ---
      title: "DEBrowser session report"
      date: "2026-05-03 14:22:11"
      output:
        html_document:
          toc: true
          toc_float: true
          theme: cosmo
      ---
      
      ```{r setup, include = FALSE}
      knitr::opts_chunk$set(eval = FALSE, echo = TRUE)
      library(debrowser)
      ```
      
      ## Methods
      
      This report was generated by **DEBrowser 1.31.2** under R version 4.4.2 (2024-10-31).
      
      Differential expression analysis was performed using DEBrowser v1.31.2 (Kucukural et al., 2019). Raw counts (30,739 features x 6 samples) were loaded from the DEBrowser demo dataset (Vernia et al.). Features were filtered using a Max cutoff (Max value < 10); 18,000 of 30,739 features retained. `exper` (n=3) versus `control` (n=3) was tested with DESeq2 v1.48.2 (Love et al., 2014) using fitType=parametric, betaPrior=FALSE, testType=Wald, shrinkage=apeglm; 1,247 features were significant at adjusted p-value < 0.05 and |log2 fold change| > 1.
      
      > *This narrative is auto-generated. Edit before publication; cite
      > DEBrowser (Kucukural et al., 2019) and the underlying tools
      > (DESeq2 -- Love et al., 2014; fgsea -- Korotkevich et al., 2021;
      > MSigDB -- Liberzon et al., 2015).*
      
      ## Pipeline
      
      ### 1. Load counts and metadata
      
      ```{r load}
      demo_env <- new.env()
      load(system.file("extdata", "demo", "demodata.Rda", package = "debrowser"), envir = demo_env)
      counts <- demo_env$demodata
      meta   <- demo_env$metadatatable
      ```
      
      ### 2. Low-count filter
      
      ```{r filter}
      filtered <- filter_low_counts(counts, method = "max",  cutoff = 10)
      ```
      
      ### 3. Batch correction
      
      *No batch correction was applied.*
      
      ### 4. Differential expression
      
      #### Comparison 1: exper vs control
      
      ```{r de1}
      cols_1  <- c("exper_rep1", "exper_rep2", "exper_rep3", "control_rep1", "control_rep2", "control_rep3")
      conds_1 <- c("Cond1", "Cond1", "Cond1", "Cond2", "Cond2", "Cond2")
      de1 <- run_de(
        method = "DESeq2",
        counts = corrected, metadata = meta, columns = cols_1, conds = conds_1,
        params = list(covariates = "NoCovariate", fit_type   = "parametric", beta_prior = FALSE, test_type  = "Wald", shrinkage  = "apeglm"),
        return_dds = FALSE
      )
      ```
      
      ## Session info
      
      ```{r sessioninfo, eval = TRUE, echo = FALSE}
      sessionInfo()
      ```

# emit_rmd full session matches snapshot

    Code
      cat(emit_rmd(blocks), sep = "\n")
    Output
      ---
      title: "DEBrowser session report"
      date: "2026-05-03 14:22:11"
      output:
        html_document:
          toc: true
          toc_float: true
          theme: cosmo
      ---
      
      ```{r setup, include = FALSE}
      knitr::opts_chunk$set(eval = FALSE, echo = TRUE)
      library(debrowser)
      ```
      
      ## Methods
      
      This report was generated by **DEBrowser 1.31.2** under R version 4.4.2 (2024-10-31).
      
      Differential expression analysis was performed using DEBrowser v1.31.2 (Kucukural et al., 2019). Raw counts (32,451 features x 12 samples) were loaded from a user-uploaded TSV. Features were filtered using a CPM cutoff (CPM < 1 in fewer than 11 samples); 28,104 of 32,451 features retained. Batch effects were corrected with ComBat v3.56.0 (Johnson et al., 2007), using `batch` as the batch covariate and `condition` as the biological covariate. `treated` (n=3) versus `control` (n=3) was tested with DESeq2 v1.48.2 (Love et al., 2014) using fitType=parametric, betaPrior=FALSE, testType=Wald, shrinkage=apeglm; 1,247 features were significant at adjusted p-value < 0.05 and |log2 fold change| > 1. `high_dose` (n=3) versus `control` (n=3) was tested with DESeq2 v1.48.2 (Love et al., 2014) using fitType=parametric, betaPrior=FALSE, testType=Wald, shrinkage=apeglm; 892 features were significant at adjusted p-value < 0.05 and |log2 fold change| > 1. Gene set enrichment analysis was performed with fgsea v1.34.2 (Korotkevich et al., 2021) against the MSigDB Homo sapiens H collection v26.1.0 (Liberzon et al., 2015) (n=50 gene sets, default fgsea parameters).
      
      > *This narrative is auto-generated. Edit before publication; cite
      > DEBrowser (Kucukural et al., 2019) and the underlying tools
      > (DESeq2 -- Love et al., 2014; fgsea -- Korotkevich et al., 2021;
      > MSigDB -- Liberzon et al., 2015).*
      
      ## Pipeline
      
      ### 1. Load counts and metadata
      
      Original upload: counts=`my_counts.tsv`, meta=`my_meta.tsv`. Edit the paths below.
      
      ```{r load}
      counts <- read.table("YOUR_COUNTS.tsv", sep = "\t", header = TRUE,
                           row.names = 1, check.names = FALSE)
      meta   <- read.table("YOUR_META.tsv",   sep = "\t", header = TRUE,
                           row.names = 1, check.names = FALSE)
      ```
      
      ### 2. Low-count filter
      
      ```{r filter}
      filtered <- filter_low_counts(counts, method = "cpm",  cutoff = 1, min_samples = 11)
      ```
      
      ### 3. Batch correction
      
      ```{r batch}
      corrected <- apply_batch_correction(
        filtered, meta,
        method = "Combat", batch_col = "batch", treatment_col = "condition"
      )
      ```
      
      ### 4. Differential expression
      
      #### Comparison 1: treated vs control
      
      ```{r de1}
      cols_1  <- c("S1", "S2", "S3", "S4", "S5", "S6")
      conds_1 <- c("Cond1", "Cond1", "Cond1", "Cond2", "Cond2", "Cond2")
      de1 <- run_de(
        method = "DESeq2",
        counts = corrected, metadata = meta, columns = cols_1, conds = conds_1,
        params = list(covariates = "NoCovariate", fit_type   = "parametric", beta_prior = FALSE, test_type  = "Wald", shrinkage  = "apeglm"),
        return_dds = FALSE
      )
      ```
      
      #### Comparison 2: high_dose vs control
      
      ```{r de2}
      cols_2  <- c("S7", "S8", "S9", "S4", "S5", "S6")
      conds_2 <- c("Cond3", "Cond3", "Cond3", "Cond4", "Cond4", "Cond4")
      de2 <- run_de(
        method = "DESeq2",
        counts = corrected, metadata = meta, columns = cols_2, conds = conds_2,
        params = list(covariates = "NoCovariate", fit_type   = "parametric", beta_prior = FALSE, test_type  = "Wald", shrinkage  = "apeglm"),
        return_dds = FALSE
      )
      ```
      
      ### 5. Enrichment (GSEA)
      
      ```{r enrichment}
      pathways <- msigdb_pathways(species = "Homo sapiens", collection = "H", subcollection = NULL)
      gsea_1 <- run_gsea(de1, pathways = pathways)
      gsea_2 <- run_gsea(de2, pathways = pathways)
      ```
      
      ## Session info
      
      ```{r sessioninfo, eval = TRUE, echo = FALSE}
      sessionInfo()
      ```

