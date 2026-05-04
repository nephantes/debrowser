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
#' Mounted in the page_navbar after `nav_spacer()`. Three items:
#'   - "R script"           downloads a runnable .R reproducibility script
#'   - "Rmd -> HTML"        renders an .Rmd to HTML (gated on rmarkdown)
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
      shiny::downloadLink(ns("download_rmd"), "Rmd -> HTML")
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
#' \donttest{
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
        shiny::tags$p(
          class = "small text-muted",
          "Select the text below and copy with Cmd/Ctrl+C, ",
          "or use the Download button to save as .txt."
        ),
        shiny::verbatimTextOutput(session$ns("methods_text_render"),
                                  placeholder = TRUE),
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

    invisible(NULL)
  })
}
