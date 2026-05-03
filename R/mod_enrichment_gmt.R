# R/mod_enrichment_gmt.R
#
# Gene-set source picker for the Enrichment tab. Two sources in E2:
#   * "Upload .gmt"  — manual file upload (E1)
#   * "MSigDB"       — msigdbr-backed species/collection picker (E2)
# Both branches return the same named-list-of-character-vectors shape so
# the downstream Enrichment server is source-agnostic.

# Internal: fetch the msigdbr species list with a fallback when the
# package isn't installed (the picker will simply offer Homo sapiens
# and Mus musculus, the two species DEBrowser already supports
# elsewhere). Only called inside the UI factory; safe to swallow the
# install-prompt because the GMT-source server reraises via require_pkg
# on submit.
#' @noRd
.msigdb_species_choices <- function() {
  if (!requireNamespace("msigdbr", quietly = TRUE)) {
    return(c("Homo sapiens", "Mus musculus"))
  }
  spp <- tryCatch(msigdbr::msigdbr_species()$species_name,
                  error = function(e) NULL)
  if (is.null(spp) || !length(spp)) {
    return(c("Homo sapiens", "Mus musculus"))
  }
  sort(unique(spp))
}

# Internal: list MSigDB top-level collection codes labelled with their
# canonical names (Hallmark / Curated / Ontology / etc.). Falls back to
# the canonical 9-collection list when msigdbr is unavailable.
#' @noRd
.msigdb_collection_choices <- function() {
  fallback <- c(
    "Hallmark"          = "H",
    "Positional"        = "C1",
    "Curated"           = "C2",
    "Regulatory targets" = "C3",
    "Computational"     = "C4",
    "Ontology"          = "C5",
    "Oncogenic"         = "C6",
    "Immunologic"       = "C7",
    "Cell type"         = "C8"
  )
  if (!requireNamespace("msigdbr", quietly = TRUE)) {
    return(fallback)
  }
  cols <- tryCatch(msigdbr::msigdbr_collections(),
                   error = function(e) NULL)
  if (is.null(cols) || !nrow(cols)) return(fallback)
  # Use the human-readable collection name when available; fall back to
  # the bare code so users see something either way.
  unique_codes <- unique(cols$gs_collection)
  labels <- vapply(unique_codes, function(code) {
    nm <- unique(cols$gs_collection_name[cols$gs_collection == code])
    nm <- nm[nzchar(nm)]
    if (!length(nm)) return(code)
    nm[1]
  }, character(1))
  setNames(unique_codes, labels)
}

#' UI for the gene-set source picker (Enrichment-tab sidebar).
#'
#' E2 ships two sources: manual `.gmt` upload and MSigDB (via
#' `msigdbr`). The picker is a single integration point so callers stay
#' oblivious to which source is active.
#'
#' @param id Module ID.
#' @return Shiny tagList for inclusion in a `bslib::accordion_panel`.
#' @export
enrichmentGmtUI <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::selectizeInput(
      ns("gmt_source"), "Gene-set source:",
      choices = c(
        "Upload .gmt" = "manual",
        "MSigDB"      = "msigdb"
      )
    ),
    shiny::conditionalPanel(
      condition = sprintf("input['%s'] == 'manual'", ns("gmt_source")),
      shiny::fileInput(ns("manual_gmt"), ".gmt file:",
                       accept = c(".gmt", "text/plain"))
    ),
    shiny::conditionalPanel(
      condition = sprintf("input['%s'] == 'msigdb'", ns("gmt_source")),
      shiny::selectizeInput(
        ns("msigdb_species"), "Species:",
        choices  = .msigdb_species_choices(),
        selected = "Homo sapiens"
      ),
      shiny::selectizeInput(
        ns("msigdb_collection"), "Collection:",
        choices  = .msigdb_collection_choices(),
        selected = "H"
      ),
      shiny::textInput(
        ns("msigdb_subcollection"),
        "Subcollection (optional, e.g. CP:KEGG, GO:BP):",
        value = ""
      ),
      shiny::actionButton(ns("msigdb_load"), "Load gene sets",
                          class = "btn-primary btn-sm")
    )
  )
}

#' Server for the gene-set source picker.
#'
#' Returns a reactive that yields a named list of gene-symbol vectors —
#' the same shape \code{\link{gmt_to_pathways}} produces — or NULL until
#' the user has supplied a source.
#'
#' For the MSigDB branch the fetch is gated on the "Load gene sets"
#' action button so the user controls when (and whether) the (potentially
#' large) msigdbr query runs. The result is cached in a reactiveVal
#' keyed on (species, collection, subcollection) so re-clicking with the
#' same inputs does not re-query msigdbr.
#'
#' @param id Module ID.
#' @return Reactive expression yielding the parsed pathways list.
#' @export
enrichmentGmtServer <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    # E2: in-session memoisation for the MSigDB branch. The cache is
    # scoped to this module instance so each user session gets its own;
    # collisions across users are impossible.
    msigdb_cache <- shiny::reactiveValues(key = NULL, value = NULL)
    msigdb_loaded <- shiny::eventReactive(input$msigdb_load, {
      shiny::req(input$msigdb_species, input$msigdb_collection)
      sub <- if (nzchar(trimws(input$msigdb_subcollection))) {
        trimws(input$msigdb_subcollection)
      } else {
        NULL
      }
      key <- paste(input$msigdb_species, input$msigdb_collection,
                   sub %||% "", sep = "|")
      if (!is.null(msigdb_cache$key) && identical(msigdb_cache$key, key)) {
        return(msigdb_cache$value)
      }
      pw <- shiny::withProgress(
        message = "Fetching MSigDB gene sets",
        detail = sprintf("%s / %s%s", input$msigdb_species,
                         input$msigdb_collection,
                         if (is.null(sub)) "" else paste0(" / ", sub)),
        value = 0.5,
        msigdb_pathways(species = input$msigdb_species,
                        collection = input$msigdb_collection,
                        subcollection = sub)
      )
      msigdb_cache$key <- key
      msigdb_cache$value <- pw
      pw
    }, ignoreNULL = TRUE)

    shiny::reactive({
      shiny::req(input$gmt_source)
      if (input$gmt_source == "manual") {
        shiny::req(input$manual_gmt)
        gmt_to_pathways(input$manual_gmt$datapath)
      } else if (input$gmt_source == "msigdb") {
        msigdb_loaded()
      } else {
        NULL
      }
    })
  })
}

# Internal NULL-coalescing helper (Shiny 1.7 ships its own %||% but we
# keep a private one to avoid cross-package operator-export weirdness in
# CHECK).
#' @noRd
`%||%` <- function(a, b) if (is.null(a)) b else a
