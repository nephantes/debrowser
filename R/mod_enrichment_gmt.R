# R/mod_enrichment_gmt.R
#
# Gene-set source picker for the consolidated Enrichment tab. Two
# sources:
#   * "Upload .gmt"  - manual file upload (auto-loads on file pick)
#   * "MSigDB"       - msigdbr-backed species/collection picker
#                      (loads on explicit "Load gene sets" click)
# Both branches populate a reactiveVal keyed off the picker's state, so
# the loaded pathways are observable immediately (status text updates on
# load) and the parent server's startGO action just consumes whatever
# is in the val without waiting on a lazy chain.

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
  unique_codes <- unique(cols$gs_collection)
  labels <- vapply(unique_codes, function(code) {
    nm <- unique(cols$gs_collection_name[cols$gs_collection == code])
    nm <- nm[nzchar(nm)]
    if (!length(nm)) return(code)
    nm[1]
  }, character(1))
  setNames(unique_codes, labels)
}

#' UI for the gene-set source picker (Enrichment tab sidebar).
#'
#' Two sources: manual `.gmt` upload (auto-loads on file pick) and
#' MSigDB (loads on explicit "Load gene sets" click). A status line
#' below the picker reports how many gene sets are currently loaded so
#' the user has immediate feedback before pressing Submit.
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
    ),
    shiny::uiOutput(ns("status"))
  )
}

#' Server for the gene-set source picker.
#'
#' Returns a reactive that yields a named list of gene-symbol vectors -
#' the same shape \code{\link{gmt_to_pathways}} produces - or NULL until
#' the user has loaded a source.
#'
#' Both branches populate an internal reactiveVal so the load step is
#' observable independently of any downstream consumer (the previous
#' eventReactive design was lazy and didn't fire until Submit). A small
#' status output reports load success / failure / set count next to the
#' picker.
#'
#' @param id Module ID.
#' @return Reactive expression yielding the parsed pathways list.
#' @export
enrichmentGmtServer <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    pathways_val <- shiny::reactiveVal(NULL)
    status_val   <- shiny::reactiveVal(NULL)

    # Manual upload: auto-load on file pick.
    shiny::observeEvent(input$manual_gmt, {
      shiny::req(input$gmt_source == "manual", input$manual_gmt)
      tryCatch({
        pw <- gmt_to_pathways(input$manual_gmt$datapath)
        pathways_val(pw)
        status_val(list(
          ok = TRUE,
          msg = sprintf("Loaded %d gene sets from %s",
                        length(pw),
                        input$manual_gmt$name %||% ".gmt")
        ))
      }, error = function(e) {
        pathways_val(NULL)
        status_val(list(ok = FALSE,
                        msg = sprintf("Could not parse .gmt: %s",
                                      conditionMessage(e))))
      })
    })

    # MSigDB: load on explicit click. observeEvent fires regardless of
    # whether anything downstream is currently watching, so the user
    # gets feedback the moment the click happens.
    shiny::observeEvent(input$msigdb_load, {
      shiny::req(input$msigdb_species, input$msigdb_collection)
      sub <- if (nzchar(trimws(input$msigdb_subcollection %||% ""))) {
        trimws(input$msigdb_subcollection)
      } else {
        NULL
      }
      tryCatch({
        pw <- shiny::withProgress(
          message = "Fetching MSigDB gene sets",
          detail  = sprintf("%s / %s%s", input$msigdb_species,
                            input$msigdb_collection,
                            if (is.null(sub)) "" else paste0(" / ", sub)),
          value   = 0.5,
          msigdb_pathways(species       = input$msigdb_species,
                          collection    = input$msigdb_collection,
                          subcollection = sub)
        )
        pathways_val(pw)
        status_val(list(
          ok = TRUE,
          msg = sprintf(
            "Loaded %d gene sets - MSigDB %s / %s%s",
            length(pw), input$msigdb_species,
            input$msigdb_collection,
            if (is.null(sub)) "" else paste0(" / ", sub)
          )
        ))
      }, error = function(e) {
        pathways_val(NULL)
        status_val(list(ok = FALSE,
                        msg = sprintf("MSigDB load failed: %s",
                                      conditionMessage(e))))
      })
    })

    # Reset stored pathways when the user switches source so the
    # status line doesn't lie about which source is loaded.
    shiny::observeEvent(input$gmt_source, {
      pathways_val(NULL)
      status_val(NULL)
    }, ignoreInit = TRUE)

    output$status <- shiny::renderUI({
      st <- status_val()
      if (is.null(st)) {
        shiny::div(
          class = "small text-muted mt-2",
          "No gene sets loaded yet."
        )
      } else if (isTRUE(st$ok)) {
        shiny::div(
          class = "small text-success mt-2",
          shiny::icon("check-circle"), " ", st$msg
        )
      } else {
        shiny::div(
          class = "small text-danger mt-2",
          shiny::icon("circle-exclamation"), " ", st$msg
        )
      }
    })

    shiny::reactive({ pathways_val() })
  })
}

# Internal NULL-coalescing helper.
#' @noRd
`%||%` <- function(a, b) if (is.null(a)) b else a
