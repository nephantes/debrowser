#' getGeneList
#'
#' Gathers the gene list to use for GOTerm analysis.
# "
#' @note \code{GOTerm}
#'
#' @export
#'
#' @note \code{getGeneList}
#' symobol to ENTREZ ID conversion
#' @param genes, gene list
#' @param org, orgranism for gene symbol entrez ID conversion
#' @param fromType, from Type
#' @param toType, to Type
#' @return ENTREZ ID list
#'
#' @examples
#' x <- getGeneList(c("OCLN", "ABCC2"))
#'
getGeneList <- function(
  genes = NULL, org = "org.Hs.eg.db",
  fromType = "SYMBOL", toType = c("ENTREZID")
) {
  # Get the entrez gene identifiers that are mapped to a gene symbol
  if (!requireNamespace(org, quietly = TRUE)) {
    showNotification(
      paste0("Please install ", org, " to use this function."),
      type = "error"
    )
    return(NULL)
  }

  mapped_genes <- bitr(genes,
    fromType = fromType,
    toType = toType,
    OrgDb = org
  )
  # genelist <- unique(as.vector(unlist(mapped_genes[toType])))
  genelist <- data.frame(mapped_genes)
  colnames(genelist) <- c(fromType, toType)
  genelist
}

#' getEntrezTable
#'
#' Gathers the entrezIds of the genes in given list and their data
# "
#' @note \code{GOTerm}
#'
#' @export
#'
#' @note \code{getEntrezTable}
#' symobol to ENTREZ ID conversion
#' @param genes, gene list
#' @param dat, data matrix
#' @param org, orgranism for gene symbol entrez ID conversion
#' @return table with the entrez IDs in the rownames
#'
#' @examples
#' x <- getEntrezTable()
#'
getEntrezTable <- function(genes = NULL, dat = NULL, org = "org.Hs.eg.db") {
  if (is.null(genes)) {
    return(NULL)
  }
  if (!requireNamespace(org, quietly = TRUE)) {
    showNotification(
      paste0("Please install ", org, " to use this function."),
      type = "error"
    )
    return(NULL)
  }
  # Fetch the AnnotationDb object directly from the package namespace --
  # `eval(parse(text = org))` only works if the org package is attached
  # to the search path. Suggests-status packages (e.g., org.Mm.eg.db)
  # aren't attached by requireNamespace alone.
  org_db <- getExportedValue(org, org)
  entrezIDs <- unlist(strsplit(genes, "/"))
  # Drop NA / empty entries -- otherwise `mapped_genes %in% NA` matches
  # every NA-mapped DE gene (no-overlap categories ended up showing
  # all unmapped DE genes in the modal).
  entrezIDs <- entrezIDs[!is.na(entrezIDs) & nzchar(entrezIDs)]
  empty_template <- cbind(
    mapped_genes = character(0),
    dat[integer(0), , drop = FALSE]
  )
  if (length(entrezIDs) == 0L) {
    return(data.frame(empty_template))
  }

  mapped_genes <- mapIds(org_db,
    keys = rownames(dat),
    column = "ENTREZID", keytype = "SYMBOL",
    multiVals = "first"
  )
  # Drop unmapped genes before the overlap test so an `entrezIDs`
  # that still contains a stray NA cannot pull NA-mapped rows in.
  mapped_genes <- mapped_genes[!is.na(mapped_genes)]
  mapped_genes <- mapped_genes[mapped_genes %in% entrezIDs]
  if (length(mapped_genes) == 0L) {
    return(data.frame(empty_template))
  }
  genelist <- cbind(mapped_genes, dat[names(mapped_genes), ])

  data.frame(genelist)
}

#' getEntrezIds
#'
#' Gathers the gene list to use for GOTerm analysis.
# "
#' @note \code{GOTerm}
#'
#' @export
#'
#' @note \code{getEntrezIds}
#' symobol to ENTREZ ID conversion
#' @param genes, gene list with fold changes
#' @param org, orgranism for gene symbol entrez ID conversion
#' @return ENTREZ ID list
#'
#' @examples
#' x <- getEntrezIds()
#'
getEntrezIds <- function(genes = NULL, org = "org.Hs.eg.db") {
  if (is.null(genes)) {
    return(NULL)
  }
  if (!requireNamespace(org, quietly = TRUE)) {
    showNotification(
      paste0("Please install ", org, " to use this function."),
      type = "error"
    )
    return(NULL)
  }
  # Fetch the AnnotationDb object directly from the package namespace --
  # see getEntrezTable() for the rationale.
  org_db <- getExportedValue(org, org)
  allkeys <- AnnotationDbi::keys(org_db, keytype = "SYMBOL")

  mapped_genes <- mapIds(org_db,
    keys = rownames(genes),
    column = "ENTREZID", keytype = "SYMBOL",
    multiVals = "first"
  )
  mapped_genes <- mapped_genes[!is.na(mapped_genes)]
  genelist <- cbind(mapped_genes, names(mapped_genes), genes[names(mapped_genes), "log2FoldChange"])

  colnames(genelist) <- c("ENTREZID", "SYMBOL", "log2FoldChange")
  genelist <- data.frame(genelist)
  genelist$log2FoldChange <- as.numeric(as.character(genelist$log2FoldChange))
  rownames(genelist) <- genelist$ENTREZID
  genelist
}
#' getEnrichGO
#'
#' Gathers the Enriched GO Term analysis data to be used within the
#' GO Term plots.
#'
#' @note \code{getEnrichGO}
#' @param genelist, gene list
#' @param pvalueCutoff, p value cutoff
#' @param org, the organism used
#' @param ont, the ontology used
#' @return Enriched GO
#' @examples
#' x <- getEnrichGO()
#'
#' @export
#'
getEnrichGO <- function(
  genelist = NULL, pvalueCutoff = 0.01,
  org = "org.Hs.eg.db", ont = "CC"
) {
  if (is.null(genelist)) {
    return(NULL)
  }
  if (!requireNamespace(org, quietly = TRUE)) {
    showNotification(
      paste0("Please install ", org, " to use this function."),
      type = "error"
    )
    return(NULL)
  }
  res <- c()
  res$enrich_p <- clusterProfiler::enrichGO(
    gene = genelist, OrgDb = org,
    # res$enrich_p <- enrichGO(gene = genelist, organism = "human",
    ont = ont, pvalueCutoff = pvalueCutoff
  )

  res$p <- barplot(res$enrich_p,
    title = paste("Enrich GO", ont),
    font.size = 12
  )
  res$table <- NULL
  if (!is.null(nrow(res$enrich_p@result))) {
    res$table <- res$enrich_p@result[, c(
      "ID", "Description",
      "GeneRatio", "pvalue", "p.adjust", "qvalue"
    )]
  }
  return(res)
}

#' getEnrichKEGG
#'
#' Gathers the Enriched KEGG analysis data to be used within the
#' GO Term plots.
#'
#' @note \code{getEnrichKEGG}
#' @param genelist, gene list
#' @param org, the organism used
#' @param pvalueCutoff, the p value cutoff
#' @return Enriched KEGG
#' @examples
#' x <- getEnrichKEGG()
#' @export
#'
getEnrichKEGG <- function(
  genelist = NULL, pvalueCutoff = 0.01,
  org = "org.Hs.eg.db"
) {
  if (is.null(genelist)) {
    return(NULL)
  }
  res <- c()
  res$enrich_p <- enrichKEGG(
    gene = genelist, organism = getOrganism(org),
    pvalueCutoff = pvalueCutoff
  )
  res$p <- barplot(res$enrich_p,
    title =
      paste("KEGG Enrichment: p-value=", pvalueCutoff)
  )
  res$table <- NULL
  if (!is.null(nrow(res$enrich_p@result))) {
    res$table <- res$enrich_p@result[, c(
      "ID", "Description",
      "GeneRatio", "pvalue", "p.adjust", "qvalue"
    )]
  }
  return(res)
}

#' getGSEA
#'
#' Gathers the Enriched KEGG analysis data to be used within the
#' GO Term plots.
#'
#' @note \code{getGSEA}
#' @param org, the organism used
#' @param dataset, dataset
#' @param pvalueCutoff, the p value cutoff
#' @param sortfield, sort field for GSEA
#' @return GSEA
#' @examples
#' x <- getGSEA()
#' @export
#'
getGSEA <- function(dataset = NULL, pvalueCutoff = 0.01,
                    org = "org.Hs.eg.db", sortfield = "log2FoldChange") {
  if (is.null(dataset)) {
    return(NULL)
  }

  genelist <- getGeneList(rownames(dataset), org,
    fromType = "SYMBOL", toType = c("ENTREZID")
  )
  # symbol <- getGeneList(genelist, org,
  #    fromType = "ENTREZID",toType = c("SYMBOL") )
  dataset[is.na(dataset[, sortfield]), sortfield] <- 0
  data <- dataset[genelist$SYMBOL, c("ID", sortfield)]
  rownames(data) <- genelist$ENTREZID
  newdata <- data[order(-data[, sortfield]), ]
  newdatatmp <- newdata[, sortfield]
  names(newdatatmp) <- rownames(newdata)

  res <- c()
  OrgDb <- org
  if (is(OrgDb, "character")) {
    require(OrgDb, character.only = TRUE)
    OrgDb <- eval(parse(text = OrgDb))
  }
  res$enrich_p <- gseGO(
    geneList = newdatatmp, ont = "All", OrgDb = OrgDb, verbose = FALSE,
    pvalueCutoff = pvalueCutoff
  )

  res$table <- NULL
  if (nrow(res$enrich_p@result) > 0) {
    res$table <- res$enrich_p@result[, c(
      "ID", "Description",
      "setSize", "enrichmentScore", "pvalue", "p.adjust", "qvalue"
    )]
  }

  return(res)
}

#' clusterData
#'
#' Gathers the Cluster analysis data to be used within the
#' GO Term plots.
#'
#' @note \code{clusterData}
#' @param dat, the data to cluster
#' @return clustered data
#' @examples
#' mycluster <- clusterData()
#'
#' @export
#'
clusterData <- function(dat = NULL) {
  if (is.null(dat)) {
    return(NULL)
  }
  # dat is typically the filt_data subset returned by getDataForTables(),
  # which carries UI metadata (Legend/Size/x/y/ID) and DE-result columns
  # (foldChange/padj/pvalue/log2FoldChange and their *.condA.vs.condB
  # variants from merged comparisons) alongside the count columns. Strip
  # them so getNormalizedMatrix() sees only the numeric count matrix.
  drop_exact <- c(
    "ID", "x", "y", "Legend", "Size",
    "foldChange", "padj", "pvalue", "log2FoldChange"
  )
  drop_pat <- grepl(
    "^(foldChange|padj|pvalue|log2FoldChange)\\.", colnames(dat)
  )
  count_dat <- dat[, !(colnames(dat) %in% drop_exact) & !drop_pat, drop = FALSE]
  count_dat <- count_dat[, vapply(count_dat, is.numeric, logical(1)),
    drop = FALSE
  ]

  ret <- list()
  itemlabels <- rownames(count_dat)
  norm_data <- getNormalizedMatrix(count_dat)
  mydata <- na.omit(norm_data) # listwise deletion of missing
  mydata <- scale(mydata) # standardize variables

  wss <- (nrow(mydata) - 1) * sum(apply(mydata, 2, var))
  for (i in 2:15) wss[i] <- sum(kmeans(mydata, centers = i)$withinss)
  plot(1:15, wss,
    type = "b",
    xlab = "Number of Clusters",
    ylab = "Within groups sum of squares"
  )
  k <- 0
  for (i in 1:14) {
    if ((wss[i] / wss[i + 1]) > 1.2) {
      k <- k + 1
    }
  }
  # K-Means Cluster Analysis
  fit <- kmeans(mydata, k) # 5 cluster solution
  # get cluster means
  aggregate(mydata, by = list(fit$cluster), FUN = mean)
  # append cluster assignment
  mydata_cluster <- data.frame(mydata, fit$cluster)

  # distance <- dist(mydata, method = 'euclidean')
  # distance matrix fit <- hclust(distance,
  # method='ward.D2') plot(fit, cex = 0.1)
  # display dendogram groups <- cutree(fit, k=k) rect.hclust(fit,
  # k=k, border='red')
  return(mydata_cluster)
}

#' compareClust
#'
#' Compares the clustered data to be displayed within the GO Term
#' plots.
#'
#' @note \code{compareClust}
#' @param dat, data to compare clusters
#' @param ont, the ontology to use
#' @param org, the organism used
#' @param fun, fun
#' @param title, title of the comparison
#' @param pvalueCutoff, pvalueCutoff
#' @return compared cluster
#' @examples
#' x <- compareClust()
#'
#' @export
#'
compareClust <- function(
  dat = NULL, ont = "CC", org = "org.Hs.eg.db",
  fun = "enrichGO", title = "Ontology Distribution Comparison",
  pvalueCutoff = 0.01
) {
  if (is.null(dat)) {
    return(NULL)
  }
  if (!requireNamespace(org, quietly = TRUE)) {
    showNotification(
      paste0("Please install ", org, " to use this function."),
      type = "error"
    )
    return(NULL)
  }
  res <- c()
  genecluster <- list()
  k <- max(dat$fit.cluster)
  for (i in 1:k) {
    clgenes <- rownames(dat[dat$fit.cluster == i, ])
    # getGeneList() returns a data.frame(SYMBOL, ENTREZID).
    # compareCluster() expects a list of character gene-ID vectors.
    entrez_ids <- unique(as.character(getGeneList(clgenes, org)$ENTREZID))
    entrez_ids <- entrez_ids[!is.na(entrez_ids) & nzchar(entrez_ids)]
    if (length(entrez_ids) == 0L) next
    genecluster[[paste0("X", i)]] <- entrez_ids
  }
  if (length(genecluster) == 0L) {
    showNotification(
      "No mappable gene IDs in any cluster - check organism selection.",
      type = "warning"
    )
    return(NULL)
  }
  res$table <- NULL
  title <- paste(fun, title)
  if (fun == "enrichKEGG") {
    xx <- compareCluster(genecluster,
      fun = fun,
      organism = getOrganism(org),
      pvalueCutoff = pvalueCutoff
    )
  } else if (fun == "enrichDO") {
    if (!requireNamespace("DOSE", quietly = TRUE)) {
      showNotification(
        "Please install DOSE to use this function.",
        type = "error"
      )
      return(NULL)
    }
    xx <- compareCluster(genecluster,
      fun = fun,
      pvalueCutoff = pvalueCutoff
    )
  } else {
    title <- paste(ont, title)
    xx <- compareCluster(genecluster,
      fun = fun,
      ont = ont, OrgDb = org, pvalueCutoff = pvalueCutoff
    )
  }
  if (is.null(xx) || is.null(xx@compareClusterResult) ||
    nrow(xx@compareClusterResult) == 0L) {
    showNotification(
      "No enrichment found for any cluster at this p-value cutoff.",
      type = "warning"
    )
    return(NULL)
  }
  res$table <- xx@compareClusterResult[
    ,
    c(
      "Cluster", "ID", "Description", "GeneRatio", "BgRatio",
      "pvalue", "p.adjust", "qvalue"
    )
  ]
  require_pkg("enrichplot", feature = "GO/KEGG dotplot")
  res$p <- enrichplot::dotplot(xx, title = title)
  res
}
#' getEnrichDO
#'
#' Gathers the Enriched DO Term analysis data to be used within the
#' GO Term plots.
#'
#' @note \code{getEnrichDO}
#' @param genelist, gene list
#' @param pvalueCutoff, the p value cutoff
#' @return enriched DO
#' @examples
#' x <- getEnrichDO()
#' @export
#'
getEnrichDO <- function(genelist = NULL, pvalueCutoff = 0.01) {
  if (is.null(genelist)) {
    return(NULL)
  }
  require_pkg("DOSE", feature = "Disease Ontology enrichment")
  res <- c()
  res$enrich_p <- DOSE::enrichDO(
    gene = genelist, ont = "DO",
    pvalueCutoff = pvalueCutoff
  )

  res$p <- barplot(res$enrich_p, title = "Enrich DO", font.size = 12)
  res$table <- NULL
  if (!is.null(nrow(res$enrich_p@result))) {
    res$table <- res$enrich_p@result[, c(
      "ID", "Description",
      "GeneRatio", "pvalue", "p.adjust", "qvalue"
    )]
  }
  res
}

#' drawKEGG
#'
#' draw KEGG patwhay with expression values
#'
#' @note \code{drawKEGG}
#' @param input, input
#' @param dat, expression matrix
#' @param pid, pathway id
#' @return enriched DO
#' @examples
#' x <- drawKEGG()
#' @export
#'
drawKEGG <- function(input = NULL, dat = NULL, pid = NULL) {
  if (is.null(dat) && is.null(pid)) {
    return(NULL)
  }
  tryCatch({
    if (requireNamespace("pathview", quietly = TRUE)) {
      # pathview::pathview() references its unexported lazy-data
      # object `bods` directly. With pathview in Suggests,
      # requireNamespace alone does not auto-load lazy-data -- the
      # package must be attached to the search path. Cheap and
      # idempotent: only attach if not already attached.
      if (!"package:pathview" %in% search()) {
        suppressPackageStartupMessages(attachNamespace("pathview"))
      }
      org <- input$organism
      genedata <- getEntrezIds(dat[[1]], org)
      foldChangeData <- data.frame(genedata$log2FoldChange)
      rownames(foldChangeData) <- rownames(genedata)
      pathview::pathview(
        gene.data = foldChangeData,
        pathway.id = pid,
        species = substr(pid, 0, 3),
        gene.idtype = "entrez",
        out.suffix = "b.2layer", kegg.native = TRUE
      )

      unlink(paste0(pid, ".png"))
      unlink(paste0(pid, ".xml"))
    }
  })
}
