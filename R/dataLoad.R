#' debrowserdataload
#'
#' Module to load count data and metadata
#'
#' @param id, namespace id
#' @param nextpagebutton, the name of the next page button after loading the data
#' @return main plot
#'
#' @return panel
#' @export
#'
#' @examples
#' \dontrun{
#' x <- debrowserdataload("load")
#' }
#'
debrowserdataload <- function(id, nextpagebutton = NULL) {
  moduleServer(id, function(input, output, session) {
  ldata <- reactiveValues(count = NULL, meta = NULL, data_source = NA_character_)
  loadeddata <- reactive({
    ret <- NULL
    if (!is.null(ldata$count)) {
      ldata$count <- ldata$count[, sapply(ldata$count, is.numeric)]
      ret <- list(count = ldata$count, meta = ldata$meta,
                  data_source = ldata$data_source)
    }
    return(ret)
  })
  output$dataloaded <- reactive({
    return(!is.null(loadeddata()))
  })
  outputOptions(output, "dataloaded",
    suspendWhenHidden = FALSE
  )
  observe({
    query <- parseQueryString(session$clientData$url_search)
    jsonobj <- query$jsonobject
    type <- ""
    if (!is.null(query$type)) {
      type <- query$type
    }

    # To test json load;
    # It accepts two parameters:
    # 1. jsonobject=https://debrowser.umassmed.edu/?jsonobject=https://umms.dolphinnext.com/pub/debrowser/advanced_demo_org.json
    # 2. meta=https://umms.dolphinnext.com/pub/debrowser/advanced_meta.json
    # The finished product of the link will look like this without metadata:
    #
    # https://127.0.0.1:3427/debrowser/R/?jsonobject=https://debrowser.umassmed.edu/?jsonobject=https://umms.dolphinnext.com/pub/debrowser/advanced_demo_org.json
    #
    #  With metadata
    #
    # http://127.0.0.1:3427/?jsonobject=https://debrowser.umassmed.edu/?jsonobject=https://umms.dolphinnext.com/pub/debrowser/advanced_demo_org.json&meta=https://umms.dolphinnext.com/pub/debrowser/advanced_meta.json
    #
    if (!is.null(jsonobj)) {
      if (type == "nojson") {
        ex <- strsplit(basename(jsonobj), split = "\\.")[[1]]
        if (ex[-1] == "tsv") {
          data <- read.delim(jsonobj)
        } else {
          data <- read.csv(jsonobj)
        }
      } else {
        raw <- RCurl::getURL(jsonobj,
          .opts = list(ssl.verifypeer = FALSE),
          crlf = TRUE
        )
        data <- fromJSON(raw, simplifyDataFrame = TRUE)
      }
      colnames(data) <- gsub("\\s+|\\.|\\-", "_", colnames(data))
      jsondata <- data.frame(data, stringsAsFactors = TRUE)

      rownames(jsondata) <- jsondata[, 1]
      jsondata <- jsondata[, c(3:ncol(jsondata))]
      jsondata[, c(1:ncol(jsondata))] <- sapply(
        jsondata[, c(1:ncol(jsondata))], as.numeric
      )
      jsondata <- jsondata[, sapply(jsondata, is.numeric)]

      metadatatable <- NULL
      jsonmet <- query$meta

      if (!is.null(jsonmet)) {
        if (type == "nojson") {
          ex <- strsplit(basename(jsonmet), split = "\\.")[[1]]
          if (ex[-1] == "tsv") {
            data <- read.delim(jsonmet)
          } else {
            data <- read.csv(jsonmet)
          }
        } else {
          raw <- RCurl::getURL(jsonmet,
            .opts = list(ssl.verifypeer = FALSE),
            crlf = TRUE
          )
          data <- fromJSON(raw, simplifyDataFrame = TRUE)
        }
        data[, 1] <- gsub("\\s+|\\.|\\-", "_", data[, 1])

        metadatatable <- data.frame(data,
          stringsAsFactors = TRUE
        )
        cnames <- names(jsondata)
        selectcols <- cnames[cnames %in% metadatatable[, 1]]
        ldata$count <- jsondata[, selectcols]
        print(dim(ldata$count))
      } else {
        ldata$count <- jsondata
        metadatatable <- make_default_metadata(jsondata)
      }
      ldata$meta <- metadatatable
      ldata$data_source <- "json"
      input$Filter
    }
  })
  observeEvent(input$demo, {
    demoEnv <- new.env()
    load(system.file("extdata", "demo", "demodata.Rda",
      package = "debrowser"
    ), envir = demoEnv)
    ldata$count <- demoEnv$demodata
    ldata$meta <- demoEnv$metadatatable
    ldata$data_source <- "demo1"
  })
  observeEvent(input$demo2, {
    demoEnv <- new.env()
    load(system.file("extdata", "demo", "demodata2.Rda",
      package = "debrowser"
    ), envir = demoEnv)
    ldata$count <- demoEnv$demodata
    ldata$meta <- demoEnv$metadatatable
    ldata$data_source <- "demo2"
  })

  # B2b: auto-detect separator on counts file change.
  # Also opens the "Show all options" accordion when detection fails.
  autoDetectFailed <- reactiveVal(FALSE)
  output$autoDetectFailed <- reactive(autoDetectFailed())
  outputOptions(output, "autoDetectFailed", suspendWhenHidden = FALSE)

  observeEvent(input$countdata, {
    f <- input$countdata
    if (is.null(f)) return()
    sep <- detect_separator(f$datapath)
    if (is.na(sep)) {
      autoDetectFailed(TRUE)
      bslib::accordion_panel_open(
        id = "advancedOptions",
        values = TRUE,
        session = session
      )
    } else {
      autoDetectFailed(FALSE)
      updateRadioButtons(session, "countdataSep", selected = sep)
    }
  }, ignoreInit = TRUE)

  observeEvent(input$metadata, {
    f <- input$metadata
    if (is.null(f)) return()
    # Metadata files typically have 1-2 numeric columns -- min_score = 1
    # so the helper isn't inert on the common case.
    sep <- detect_separator(f$datapath, min_score = 1L)
    if (!is.na(sep)) {
      updateRadioButtons(session, "metadataSep", selected = sep)
    }
  }, ignoreInit = TRUE)

  observeEvent(input$uploadFile, {
    if (is.null(input$countdata)) {
      return(NULL)
    }
    # B2b followup: re-detect the separator inside the upload handler.
    # Shiny's updateRadioButtons is queued client-side, so a fast click
    # on Upload right after picking a file can read input$countdataSep
    # before the auto-detect roundtrip completes. Falling back to the
    # radio only when detect can't decide preserves the user's manual
    # override path (Show all options + sep change after detect failed).
    detected_count <- detect_separator(input$countdata$datapath)
    count_sep <- if (!is.na(detected_count)) detected_count else input$countdataSep

    counttable <- tryCatch(
      {
        validate_count_upload(input$countdata$datapath, sep = count_sep)
        as.data.frame(
          read.delim(input$countdata$datapath,
            header = TRUE, sep = count_sep,
            row.names = 1, strip.white = TRUE
          )
        )
      },
      bad_separator = function(e) {
        de_notify_error(
          "Could not read the count file: only 1 column was detected. Try Tab or Comma in the separator radio buttons below."
        )
        NULL
      },
      duplicate_gene_ids = function(e) {
        de_notify_error(sprintf(
          "Count file has duplicate gene IDs in the first column: %s. Make each row unique before uploading.",
          paste0(e$dups, collapse = ", ")
        ))
        NULL
      },
      error = function(e) {
        de_notify_error(
          "Could not read the count file. Check the file is plain text (TSV, CSV, or TXT) and not corrupted."
        )
        NULL
      }
    )
    if (is.null(counttable)) return(NULL)
    colnames(counttable) <- gsub("\\s+|\\.|\\-", "_", colnames(counttable))
    counttable <- counttable[, sapply(counttable, is.numeric)]
    metadatatable <- c()
    if (!is.null(input$metadata$datapath)) {
      detected_meta <- detect_separator(input$metadata$datapath, min_score = 1L)
      meta_sep <- if (!is.na(detected_meta)) detected_meta else input$metadataSep
      metadatatable <- tryCatch(
        {
          validate_metadata_upload(
            input$metadata$datapath,
            count_cols = colnames(counttable),
            sep = meta_sep
          )
          mt <- as.data.frame(
            read.delim(input$metadata$datapath,
              header = TRUE, sep = meta_sep, strip.white = TRUE
            )
          )
          mt[, 1] <- gsub("\\s+|\\.|\\-", "_", mt[, 1])
          mt
        },
        bad_separator = function(e) {
          de_notify_error(
            "Could not read the metadata file: only 1 column was detected. Try Tab or Comma in the separator radio buttons."
          )
          NULL
        },
        column_mismatch = function(e) {
          de_notify_error(sprintf(
            "Metadata is missing rows for these count columns: %s. Add a row per sample, or remove the unmatched samples from the count file.",
            paste0(e$unmatched, collapse = ", ")
          ))
          NULL
        },
        error = function(e) {
          de_notify_error(
            "Could not read the metadata file. Check the file is plain text (TSV, CSV, or TXT) and not corrupted."
          )
          NULL
        }
      )
      if (is.null(metadatatable)) return(NULL)
      counttable <- counttable[, metadatatable[, 1]]
    } else {
      metadatatable <- make_default_metadata(counttable)
    }
    # Defensive guard: counttable should already be non-NULL here because
    # the count tryCatch at line ~208 returns early on parse failure. Kept
    # as a belt-and-suspenders for any future refactor that loses that
    # early return.
    if (is.null(counttable)) {
      de_notify_error(
        "Upload a count file before continuing. Use the Browse button to pick a TSV, CSV, or TXT file."
      )
      return(NULL)
    }
    ldata$count <- counttable
    ldata$meta <- metadatatable
    ldata$data_source <- "upload"
  })
  output$nextButton <- renderUI({
    actionButtonDE(nextpagebutton, label = nextpagebutton, styleclass = "primary")
  })
  output$countPreview <- renderTable({
    d <- loadeddata()
    if (is.null(d) || is.null(d$count)) return(NULL)
    cnt <- d$count
    n_rows <- min(5L, nrow(cnt))
    n_cols <- min(6L, ncol(cnt))
    cnt[seq_len(n_rows), seq_len(n_cols), drop = FALSE]
  }, rownames = TRUE, digits = 2)
  observe({
    getSampleDetails(output, "uploadSummary", "sampleDetails", loadeddata())
  })

  # B3.7 — stat strip pill: samples · genes · conditions
  output$statStrip <- renderUI({
    d <- loadeddata()
    if (is.null(d) || is.null(d$count)) return(NULL)
    n_samples <- ncol(d$count)
    n_genes   <- nrow(d$count)
    n_cond    <- if (!is.null(d$meta) && ncol(d$meta) >= 2) {
      length(unique(d$meta[, 2]))
    } else {
      NA
    }
    fmt <- function(x) format(x, big.mark = ",", scientific = FALSE)
    div(class = "de-stat-strip",
      span(span(class = "de-stat-dot",
                style = "background:var(--de-cyan)"),
           tags$b(fmt(n_samples)), " samples"),
      span(span(class = "de-stat-dot",
                style = "background:var(--de-violet)"),
           tags$b(fmt(n_genes)), " genes"),
      if (!is.na(n_cond)) {
        span(span(class = "de-stat-dot",
                  style = "background:var(--de-blue)"),
             tags$b(n_cond), " conditions")
      }
    )
  })

  # D2.3: module-level bookmark/restore for content-hash uploads.
  # The module's `ldata` reactiveValues holds count/meta/data_source;
  # serialize_load_state() round-trips them through content_hash_store
  # so bookmarks reference uploads by SHA, not file bytes.
  shiny::onBookmark(function(state) {
    if (is.null(ldata$count)) return()
    user_id <- shiny::isolate(current_user(session))
    if (is.na(user_id) || is.null(user_id)) user_id <- "local"
    con <- tryCatch(user_db_connect(), error = function(e) NULL)
    if (is.null(con)) return()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    store <- content_hash_store()
    tryCatch({
      state$values$load <- list(
        state = serialize_load_state(
          list(count = ldata$count, meta = ldata$meta,
               data_source = ldata$data_source),
          store, con, user_id
        )
      )
    },
    bookmark_unsupported = function(cond) {
      shiny::showNotification(
        cond$message,
        type = "warning",
        duration = 8
      )
      # Mark state so the user knows the bookmark is unusable.
      state$values$load <- list(state = list(data_source = "unsupported"))
    })
  })

  shiny::onRestore(function(state) {
    s <- state$values$load$state
    if (is.null(s)) return()
    store <- content_hash_store()
    paths <- restore_load_state(s, store)
    if (is.null(paths)) return()
    if (identical(paths$data_source, "upload")) {
      counttable <- as.data.frame(read.delim(
        paths$count_path, header = TRUE,
        sep = "\t", row.names = 1, strip.white = TRUE,
        check.names = FALSE
      ))
      metadatatable <- as.data.frame(read.delim(
        paths$meta_path, header = TRUE,
        sep = "\t", strip.white = TRUE
      ))
      ldata$count <- counttable
      ldata$meta  <- metadatatable
      ldata$data_source <- "upload"
    } else if (identical(paths$data_source, "demo1")) {
      demoEnv <- new.env()
      load(system.file("extdata", "demo", "demodata.Rda",
                       package = "debrowser"), envir = demoEnv)
      ldata$count <- demoEnv$demodata
      ldata$meta  <- demoEnv$metadatatable
      ldata$data_source <- "demo1"
    } else if (identical(paths$data_source, "demo2")) {
      demoEnv <- new.env()
      load(system.file("extdata", "demo", "demodata2.Rda",
                       package = "debrowser"), envir = demoEnv)
      ldata$count <- demoEnv$demodata
      ldata$meta  <- demoEnv$metadatatable
      ldata$data_source <- "demo2"
    }
    # data_source == "json": defer to the existing observe() in the
    # module; URL params are still in session$clientData and the json
    # branch will re-fire naturally.
  })

  list(load = loadeddata)
  })
}

#' dataLoadUI
#'
#' Creates a panel to upload the data
#'
#' @param id, namespace id
#' @return panel
#' @examples
#' x <- dataLoadUI("load")
#'
#' @export
#'
dataLoadUI <- function(id) {
  ns <- NS(id)
  list(
    # B3.7 — Page 1 (Upload) redesigned to match outputs/debrowser_redesign.html.
    # Pre-upload: INPUTS card with TWO drop tiles SIDE-BY-SIDE (mockup-style),
    # below it the "Show all options" accordion + action row.
    # Post-upload: stat strip + preview card + sample-design card + next-step CTAs.
    conditionalPanel(
      condition = paste0("!output['", ns("dataloaded"), "']"),
      bslib::card(
        bslib::card_header(
          class = "d-flex align-items-center",
          tags$span(class = "card-title", "Inputs"),
          tags$span(class = "ms-auto",
                    style = "font-size:10.5px; padding:2px 8px; border-radius:999px; border:1px solid var(--de-border-strong); color:var(--de-text-2);",
                    ".tsv · .csv · .txt · .csv.gz")
        ),
        bslib::card_body(
          # Two side-by-side drop tiles using mockup .drop structure
          div(class = "de-drop-grid",
              style = "display:grid; grid-template-columns: 1fr 1fr; gap:12px;",
            # Tile 1: Count Data (required)
            div(class = "de-drop",
              div(class = "de-drop-ic", HTML("&#10515;")),  # up arrow ⤳
              div(class = "de-drop-meta",
                div(class = "de-drop-title", "Count Data"),
                div(class = "de-drop-help",
                    "Genes/regions × samples · drag & drop or browse")
              ),
              div(class = "de-drop-input",
                fileInput(
                  ns("countdata"),
                  label = NULL,
                  accept = fileTypes(),
                  buttonLabel = "Browse",
                  placeholder = "No file"
                )
              )
            ),
            # Tile 2: Metadata (optional)
            div(class = "de-drop",
              div(class = "de-drop-ic", HTML("&#8862;")),  # square+dot ⌗
              div(class = "de-drop-meta",
                div(class = "de-drop-title",
                    "Metadata ",
                    tags$span(class = "de-drop-muted", "(optional)")),
                div(class = "de-drop-help",
                    "Sample table with conditions, batches, etc.")
              ),
              div(class = "de-drop-input",
                fileInput(
                  ns("metadata"),
                  label = NULL,
                  accept = fileTypes(),
                  buttonLabel = "Browse",
                  placeholder = "No file"
                )
              )
            )
          ),
          # Auto-detect failure caption
          conditionalPanel(
            condition = paste0("output['", ns("autoDetectFailed"), "']"),
            div(class = "de-detect-fail-caption",
                style = "margin-top:10px;",
                "Couldn't auto-detect the separator — pick it under Show all options.")
          ),
          # "Show all options" accordion
          div(style = "margin-top:14px;",
            bslib::accordion(
              id = ns("advancedOptions"),
              open = FALSE,
              bslib::accordion_panel(
                title = "Show all options",
                fluidRow(
                  column(6, sepRadio(id, "countdataSep")),
                  column(6, sepRadio(id, "metadataSep"))
                )
              )
            )
          ),
          # Action row: Upload (auto-width primary) + demo pills
          div(class = "de-action-row",
              style = "margin-top:14px; display:flex; align-items:center; gap:8px; flex-wrap:wrap;",
            actionButton(ns("uploadFile"), "Upload",
                         class = "btn btn-primary"),
            tags$span(class = "de-demo-caption",
                      style = "color:var(--de-text-2); font-style:italic; margin: 0 6px 0 4px;",
                      "or try a demo:"),
            actionButton(ns("demo"),  "Vernia et. al",
                         class = "btn btn-sm"),
            actionButton(ns("demo2"), "Donnard et. al",
                         class = "btn btn-sm")
          )
        )
      )
    ),
    # ------------ Post-upload ------------
    conditionalPanel(
      condition = paste0("output['", ns("dataloaded"), "']"),
      # B3.24 — Sticky workbar: stat strip on left, primary "Continue →
      # Filter" pill on the right. Always visible at the top of the
      # post-upload view so the next-step action never gets buried under
      # long tables.
      div(class = "de-data-workbar",
        uiOutput(ns("statStrip")),
        div(class = "spacer", style = "flex:1"),
        div(class = "de-data-workbar-actions",
            uiOutput(ns("nextButton"))
        )
      ),
      tags$div(style = "height:12px"),
      de_card(
        title = "Preview · count matrix",
        div(class = "de-compact-table",
            style = "overflow:auto; max-height: 280px;",
            tableOutput(ns("countPreview")))
      ),
      tags$div(style = "height:12px"),
      bslib::card(
        bslib::card_header("Sample design"),
        bslib::card_body(
          div(class = "de-compact-table",
              style = "overflow:auto; max-height: 320px;",
              DT::dataTableOutput(ns("sampleDetails")))
        )
      )
    )
  )
}

#' fileUploadBox
#'
#' File upload module
#' @param id, namespace id
#' @param inputId, input file ID
#' @param label, label
#' @param helper, optional help-text string shown beneath the card title
#' @note \code{fileUploadBox}
#' @return radio control
#'
#' @examples
#'
#' x <- fileUploadBox("meta", "metadata", "Metadata")
#'
#' @export
#'
fileUploadBox <- function(id = NULL, inputId = NULL, label = NULL, helper = NULL) {
  ns <- NS(id)
  helptext <- if (is.null(helper)) {
    paste0("Upload your '", label, " File'")
  } else {
    helper
  }
  de_card(
    title = paste0(label, " File"),
    helpText(helptext),
    fileInput(
      inputId = ns(inputId),
      label = NULL,
      accept = fileTypes()
    )
  )
}

#' sepRadio
#'
#' Radio button for separators
#'
#' @param id, module id
#' @param name, name
#' @note \code{sepRadio}
#' @return radio control
#'
#' @examples
#'
#' x <- sepRadio("meta", "metadata")
#'
#' @export
#'
sepRadio <- function(id, name) {
  ns <- NS(id)
  radioButtons(
    inputId = ns(name),
    label = "Separator",
    choices = c(
      Comma = ",",
      Semicolon = ";",
      Tab = "\t"
    ),
    selected = "\t"
  )
}

#' fileTypes
#'
#' Returns fileTypes that are going to be used in creating fileUpload UI
#'
#' @note \code{fileTypes}
#' @return file types
#'
#' @examples
#' x <- fileTypes()
#'
#' @export
#'
fileTypes <- function() {
  c(
    "text/tab-separated-values",
    "text/csv",
    "text/comma-separated-values",
    "text/tab-separated-values",
    ".txt",
    ".csv",
    ".tsv"
  )
}

#' checkCountData
#'
#' Returns if there is a problem in the count data.
#'
#' @note \code{checkCountData}
#' @param input, inputs
#' @param sep, optional override for the field separator; defaults to
#'   `input$countdataSep` when NULL
#' @return error if there is a problem about the loaded data
#
#' @examples
#' x <- checkCountData()
#'
#' @export
#'
checkCountData <- function(input = NULL, sep = NULL) {
  # B4 (2026-05-02): kept as a shim around validate_count_upload() for
  # any external/programmatic caller. The Shiny upload observer no
  # longer routes through this function.
  if (is.null(input$countdata$datapath)) {
    return(NULL)
  }
  if (is.null(sep)) sep <- input$countdataSep
  tryCatch(
    {
      validate_count_upload(input$countdata$datapath, sep = sep)
      "success"
    },
    bad_separator = function(e) {
      "Error: Please check if you chose the right separator!"
    },
    duplicate_gene_ids = function(e) {
      paste0(
        "Error: There are duplicate gene IDs in the rownames. (",
        paste0(e$dups, collapse = ","), ")"
      )
    },
    error = function(err) paste0("Error(Count file):", toString(err)),
    warning = function(war) paste0("Warning(Count file):", toString(war))
  )
}


#' checkMetaData
#'
#' Returns if there is a problem in the count data.
#'
#' @note \code{checkMetaData}
#' @param input, input
#' @param counttable, counttable
#' @param sep, optional override for the field separator; defaults to
#'   `input$metadataSep` when NULL
#' @return error if there is a problem about the loaded data
#
#' @examples
#' x <- checkMetaData()
#'
#' @export
#'
checkMetaData <- function(input = NULL, counttable = NULL, sep = NULL) {
  # B4 (2026-05-02): kept as a shim around validate_metadata_upload()
  # for any external/programmatic caller. The Shiny upload observer no
  # longer routes through this function.
  #
  # BEHAVIORAL CHANGE since B3.5: the legacy `setdiff(meta, count)`
  # direction (metadata rows with no count column) was changed to
  # `setdiff(count, meta)` (count columns with no metadata row). The
  # new direction catches a real silent bug — the legacy code returned
  # "success" when count columns lacked metadata rows, then later
  # silently dropped those samples via `counttable[, metadatatable[, 1]]`.
  # The error string format ("Colnames doesn't match with the metada
  # table(...)") is preserved for any consumer that string-matches the
  # prefix; only the names listed inside the parens differ.
  if (is.null(counttable) || is.null(input$metadata$datapath)) {
    return(NULL)
  }
  if (is.null(sep)) sep <- input$metadataSep
  tryCatch(
    {
      validate_metadata_upload(
        input$metadata$datapath,
        count_cols = colnames(counttable),
        sep = sep
      )
      "success"
    },
    bad_separator = function(e) {
      "Error: Please check if you chose the right separator!"
    },
    column_mismatch = function(e) {
      paste0(
        "Colnames doesn't match with the metada table(",
        paste0(e$unmatched, sep = ",", collapse = " "), ")"
      )
    },
    error = function(err) paste0("Error(Matadata file):", toString(err)),
    warning = function(war) paste0("Warning(Matadata file):", toString(war))
  )
}
