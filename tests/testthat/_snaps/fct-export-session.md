# emit_r_script demo+DESeq2 minimal matches snapshot

    Code
      cat(emit_r_script(blocks), sep = "\n")
    Output
      # DEBrowser session export
      # Generated 2026-05-03 14:22:11 by debrowser 1.31.2
      # R version 4.4.2 (2024-10-31)
      #
      # Methods (E9-lite -- auto-generated, refine before publication):
      # - Counts loaded from DEBrowser demo dataset 'Vernia et al.' (32451 features x 12 samples).
      # - Low-count features removed using filter (Max value < 10); 28104 of 32451 features retained.
      # - Comparison 1: 'treated' vs 'control' tested with DESeq2 (fitType=parametric, betaPrior=FALSE, testType=Wald, shrinkage=apeglm); 1247 features significant at padj<0.05, |log2FC|>1.
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
      # --- Comparison 1: treated vs control ---
      cols_1  <- c("S1", "S2", "S3", "S4", "S5", "S6")
      conds_1 <- c("Cond1", "Cond1", "Cond1", "Cond2", "Cond2", "Cond2")
      de1 <- run_de(
        method = "DESeq2",
        counts = corrected, metadata = meta, columns = cols_1, conds = conds_1,
        params = c("DESeq2", "NoCovariate", "parametric", "FALSE", "Wald", "apeglm"),
        return_dds = FALSE
      )$res
      
      # 6. Write per-comparison result tables ----------------------------------------
      dir.create("debrowser_results", showWarnings = FALSE)
      write.table(de1, "debrowser_results/results_treated_vs_control.tsv",
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
      # Methods (E9-lite -- auto-generated, refine before publication):
      # - Counts loaded from uploaded file 'my_counts.tsv' (32451 features x 12 samples).
      # - Low-count features removed using filter (CPM < 1 in fewer than 11 samples); 28104 of 32451 features retained.
      # - Batch effects corrected with ComBat (sva package), batch column 'batch', treatment column 'condition'.
      # - Comparison 1: 'treated' vs 'control' tested with DESeq2 (fitType=parametric, betaPrior=FALSE, testType=Wald, shrinkage=apeglm); 1247 features significant at padj<0.05, |log2FC|>1. Comparison 2: 'high_dose' vs 'control' tested with DESeq2 (fitType=parametric, betaPrior=FALSE, testType=Wald, shrinkage=apeglm); 892 features significant at padj<0.05, |log2FC|>1.
      # - Gene set enrichment performed with fgsea against MSigDB Homo sapiens / H (50 gene sets).
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
        params = c("DESeq2", "NoCovariate", "parametric", "FALSE", "Wald", "apeglm"),
        return_dds = FALSE
      )$res
      
      # --- Comparison 2: high_dose vs control ---
      cols_2  <- c("S7", "S8", "S9", "S4", "S5", "S6")
      conds_2 <- c("Cond3", "Cond3", "Cond3", "Cond4", "Cond4", "Cond4")
      de2 <- run_de(
        method = "DESeq2",
        counts = corrected, metadata = meta, columns = cols_2, conds = conds_2,
        params = c("DESeq2", "NoCovariate", "parametric", "FALSE", "Wald", "apeglm"),
        return_dds = FALSE
      )$res
      
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

