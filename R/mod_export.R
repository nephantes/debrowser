# R/mod_export.R
#
# Phase E3 - reproducibility export. Thin Shiny module exposing the
# navbar Export dropdown plus two downloadHandlers (.R script and
# .Rmd -> HTML render). Phase E9 added a third item, "Copy methods text",
# which opens a modal containing methods_paragraph() output plus a
# Download-as-.txt button. Pure helpers (build_session_blocks,
# emit_r_script, emit_rmd, methods_paragraph) live in
# R/fct_export_session.R and R/fct_methods_text.R.

#' Export menu UI -- navbar dropdown.
#'
#' Mounted in the page_navbar after `nav_spacer()`. Six items:
#'   - "R script"           downloads a runnable .R reproducibility script
#'   - "Rmd source"         (E3.B) downloads the raw .Rmd body, no render
#'   - "HTML"               renders an .Rmd to HTML (gated on rmarkdown)
#'   - "View HTML in tab"   (E3.B) renders + opens in a new browser tab
#'   - "Jupyter notebook"   (E3.B) downloads the same content as .ipynb
#'                          with R-kernel code cells
#'   - "Copy methods text"  opens a modal with a manuscript-ready paragraph
#'                          (E9) plus a "Download as .txt" button
#'
#' Items are disabled at the server level when DE has not yet been run; the
#' UI emits the disabled-attribute via output bindings.
#'
#' @param id Module ID.
#' @return bslib::nav_menu element.
#' @examples
#' exportMenuUI("demo")
#' @export
exportMenuUI <- function(id) {
  ns <- shiny::NS(id)
  bslib::nav_menu(
    title = "Export",
    align = "right",
    bslib::nav_item(
      shiny::downloadLink(ns("download_r"), "R script")
    ),
    bslib::nav_item(
      shiny::downloadLink(ns("download_rmd_src"), "Rmd source")
    ),
    bslib::nav_item(
      shiny::downloadLink(ns("download_rmd"), "HTML")
    ),
    bslib::nav_item(
      shiny::actionLink(ns("view_html_tab"), "View HTML in tab")
    ),
    bslib::nav_item(
      shiny::downloadLink(ns("download_ipynb"), "Jupyter notebook")
    ),
    bslib::nav_item(
      shiny::actionLink(ns("show_methods"), "Copy methods text")
    )
  )
}

#' Export menu server -- wires download handlers from a state reactive.
#'
#' @param id Module ID (matches [exportMenuUI()]).
#' @param state_react reactive expression returning the plain-list state
#'   snapshot consumed by [build_session_blocks()]. May return NULL when
#'   no DE has run yet; both download handlers no-op (showNotification) in
#'   that case.
#' @return Invisibly NULL.
#' @examples
#' \dontrun{
#'   shiny::shinyApp(
#'     ui = bslib::page_navbar(exportMenuUI("exp")),
#'     server = function(input, output, session) {
#'       exportMenuServer("exp", shiny::reactive(NULL))
#'     }
#'   )
#' }
#' @export
exportMenuServer <- function(id, state_react) {
  shiny::moduleServer(id, function(input, output, session) {

    .guard <- function() {
      st <- state_react()
      if (is.null(st)) {
        shiny::showNotification(
          "Run a DE analysis before exporting.",
          type = "warning"
        )
        return(NULL)
      }
      st
    }

    output$download_r <- shiny::downloadHandler(
      filename = function() {
        sprintf("debrowser_session_%s.R",
                format(Sys.time(), "%Y%m%d_%H%M%S"))
      },
      content = function(file) {
        st <- .guard()
        if (is.null(st)) {
          writeLines("# Run DE first.", file); return(invisible(NULL))
        }
        blocks <- build_session_blocks(st)
        writeLines(emit_r_script(blocks), file)
      }
    )

    output$download_rmd <- shiny::downloadHandler(
      filename = function() {
        sprintf("debrowser_session_%s.html",
                format(Sys.time(), "%Y%m%d_%H%M%S"))
      },
      content = function(file) {
        st <- .guard()
        if (is.null(st)) {
          writeLines("Run DE first.", file); return(invisible(NULL))
        }
        if (!requireNamespace("rmarkdown", quietly = TRUE)) {
          shiny::showNotification(
            "Install the 'rmarkdown' package to enable HTML export.",
            type = "error"
          )
          writeLines("rmarkdown not installed.", file)
          return(invisible(NULL))
        }
        blocks <- build_session_blocks(st)
        rmd_lines <- emit_rmd(blocks)
        rmd_path  <- tempfile(fileext = ".Rmd")
        on.exit(unlink(rmd_path), add = TRUE)
        writeLines(rmd_lines, rmd_path)
        tryCatch({
          rmarkdown::render(
            input         = rmd_path,
            output_file   = file,
            output_format = "html_document",
            quiet         = TRUE,
            envir         = new.env(parent = globalenv())
          )
        }, error = function(e) {
          shiny::showNotification(
            sprintf("HTML render failed: %s. Downloading raw .Rmd instead.",
                    conditionMessage(e)),
            type = "error",
            duration = 10
          )
          writeLines(rmd_lines, file)
        })
      }
    )

    # Phase E9: Copy methods text -- opens a modal showing the paragraph
    # in selectable preformatted text, plus a Download as .txt button.
    # Idiomatic Shiny: outputs are defined at module init; the click
    # observer only updates the reactiveVal that feeds the output.
    methods_text_rv <- shiny::reactiveVal(NULL)
    output$methods_text_render <- shiny::renderText({
      shiny::req(methods_text_rv())
    })

    shiny::observeEvent(input$show_methods, {
      st <- .guard()
      if (is.null(st)) return()
      blocks <- build_session_blocks(st)
      methods_text_rv(methods_paragraph(blocks))

      shiny::showModal(shiny::modalDialog(
        title = "Methods text",
        size  = "l",
        shiny::tags$style(shiny::HTML(
          ".de-methods-text-wrap pre {
             min-height: 280px;
             max-height: 60vh;
             white-space: pre-wrap;
             word-wrap: break-word;
             overflow-y: auto;
             font-size: 0.9rem;
             padding: 0.75rem;
           }"
        )),
        shiny::tags$p(
          class = "small text-muted",
          "Select the text below and copy with Cmd/Ctrl+C, ",
          "or use the Download button to save as .txt."
        ),
        shiny::div(
          class = "de-methods-text-wrap",
          shiny::verbatimTextOutput(session$ns("methods_text_render"),
                                    placeholder = TRUE)
        ),
        easyClose = TRUE,
        footer = shiny::tagList(
          shiny::downloadButton(session$ns("download_methods_txt"),
                                "Download as .txt",
                                class = "btn-primary"),
          shiny::modalButton("Close")
        )
      ))
    })

    output$download_methods_txt <- shiny::downloadHandler(
      filename = function() {
        sprintf("debrowser_methods_%s.txt",
                format(Sys.time(), "%Y%m%d_%H%M%S"))
      },
      content = function(file) {
        st <- .guard()
        if (is.null(st)) {
          writeLines("Run DE first.", file); return(invisible(NULL))
        }
        blocks    <- build_session_blocks(st)
        paragraph <- methods_paragraph(blocks)
        writeLines(paragraph, file)
      }
    )

    # ---- Phase E3.B: Download Rmd source -----------------------------------
    # Writes the raw .Rmd body (no render). User can open in RStudio,
    # edit, and Knit on their own machine.
    output$download_rmd_src <- shiny::downloadHandler(
      filename = function() {
        sprintf("debrowser_session_%s.Rmd",
                format(Sys.time(), "%Y%m%d_%H%M%S"))
      },
      content = function(file) {
        st <- .guard()
        if (is.null(st)) {
          writeLines("# Run DE first.", file); return(invisible(NULL))
        }
        blocks <- build_session_blocks(st)
        writeLines(emit_rmd(blocks), file)
      }
    )

    # ---- Phase E3.B: View HTML in tab ---------------------------------------
    # On click: render the Rmd to a tempdir, register that dir as a Shiny
    # resource path, then send a custom message to the client to
    # window.open() the rendered HTML in a new tab. The custom-message
    # handler is registered once at module init via tags$script().
    shiny::observeEvent(input$view_html_tab, {
      st <- .guard()
      if (is.null(st)) return()
      if (!requireNamespace("rmarkdown", quietly = TRUE)) {
        shiny::showNotification(
          "Install the 'rmarkdown' package to enable HTML view.",
          type = "error"
        )
        return()
      }
      blocks <- build_session_blocks(st)
      rmd_lines <- emit_rmd(blocks)

      html_dir <- file.path(tempdir(), "debrowser_reports")
      if (!dir.exists(html_dir)) dir.create(html_dir, recursive = TRUE)
      shiny::addResourcePath("debrowser_reports", html_dir)

      ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
      rmd_path  <- tempfile(fileext = ".Rmd")
      on.exit(unlink(rmd_path), add = TRUE)
      writeLines(rmd_lines, rmd_path)

      html_file <- file.path(html_dir, sprintf("report_%s.html", ts))
      shiny::showNotification(
        "Rendering report... this may take up to a minute.",
        type = "message", duration = 5
      )

      tryCatch({
        rmarkdown::render(
          input         = rmd_path,
          output_file   = html_file,
          output_format = "html_document",
          quiet         = TRUE,
          envir         = new.env(parent = globalenv())
        )
        url <- sprintf("debrowser_reports/%s", basename(html_file))
        session$sendCustomMessage(
          "debrowser_open_tab", list(url = url)
        )
      }, error = function(e) {
        shiny::showNotification(
          sprintf("HTML render failed: %s", conditionMessage(e)),
          type = "error", duration = 10
        )
      })
    })

    # ---- Phase E3.B: Download Jupyter notebook ------------------------------
    output$download_ipynb <- shiny::downloadHandler(
      filename = function() {
        sprintf("debrowser_session_%s.ipynb",
                format(Sys.time(), "%Y%m%d_%H%M%S"))
      },
      content = function(file) {
        st <- .guard()
        if (is.null(st)) {
          writeLines('{"cells":[{"cell_type":"markdown","source":["Run DE first."]}],"nbformat":4,"nbformat_minor":5}',
                     file)
          return(invisible(NULL))
        }
        blocks <- build_session_blocks(st)
        writeLines(emit_ipynb(blocks), file)
      }
    )

    invisible(NULL)
  })
}
