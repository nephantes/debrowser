# R/mod_ai_interpret.R
#
# Phase E12.A - AI interpretation panel. aiInterpretUI() renders the
# panel card; aiInterpretServer() wires the question / privacy / Top-N /
# disclosure / Ask button / response. Reads the parent's payload reactive
# and the user's settings reactive; calls the pure ai_interpret() helper.
# No tests for this module (Shiny module is thin).

#' AI interpretation panel UI.
#'
#' Renders a card with: question dropdown (only one preset in v1),
#' privacy radio, Top-N input, "What will be sent" disclosure, Ask
#' button, and response area. The card is meant to be wrapped in a
#' parent's conditionalPanel so it only renders when settings are valid
#' and analytical results exist.
#'
#' @param id Module ID.
#' @return tagList.
#' @export
aiInterpretUI <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::selectInput(ns("question"), "Question",
                       choices = c("Summarize this gene set's biology" = "summarize_geneset"),
                       selected = "summarize_geneset"),
    shiny::radioButtons(ns("privacy"), "Privacy",
                       choices = c(
                         "Symbols"          = "symbols",
                         "+ Stats"          = "stats",
                         "+ Stats + Enrich" = "stats_enrichment"
                       ),
                       inline = TRUE,
                       selected = "symbols"),
    shiny::numericInput(ns("top_n"), "Top-N genes (cap)",
                        value = 50L, min = 1L, max = 500L, step = 1L),
    shiny::tags$details(
      shiny::tags$summary("What will be sent?"),
      shiny::verbatimTextOutput(ns("prompt_preview"), placeholder = TRUE),
      shiny::tags$p(class = "small text-muted",
                    shiny::textOutput(ns("char_count"), inline = TRUE))
    ),
    shiny::actionButton(ns("ask"), "Ask AI",
                        class = "btn-primary"),
    shiny::tags$div(
      class = "ai-response mt-3",
      shiny::tags$pre(shiny::textOutput(ns("response")),
                      style = "white-space: pre-wrap; max-height: 400px; overflow-y: auto;")
    )
  )
}

#' AI interpretation panel server.
#'
#' @param id Module ID (matches [aiInterpretUI()]).
#' @param payload_react reactive expression returning the payload list:
#'   `list(genes = chr, stats = data.frame|NULL, enrichment = list|NULL)`.
#'   May return NULL when no selection exists; Ask is disabled in that case.
#' @param settings_react reactive expression yielding the current AI
#'   settings list (from `aiSettingsServer`).
#' @return invisible(NULL).
#' @export
aiInterpretServer <- function(id, payload_react, settings_react) {
  shiny::moduleServer(id, function(input, output, session) {

    # Initialize privacy radio from settings on first session
    shiny::observe({
      s <- settings_react()
      shiny::updateRadioButtons(session, "privacy",
                                selected = s$default_privacy %||% "symbols")
    }, priority = 100)

    # Live prompt preview (rebuilt on input changes / payload changes).
    # Wrap the entire body — including payload_react() — in tryCatch so
    # an upstream error (e.g. a stale row selection raising "subscript
    # out of bounds") returns a friendly placeholder rather than
    # crashing this output and the dependent char_count.
    prompt_preview_text <- shiny::reactive({
      tryCatch({
        p <- payload_react()
        if (is.null(p) || length(p$genes) == 0L) {
          return("(no genes selected)")
        }
        # Build the same prompt ai_interpret() would build, without dispatching.
        template_dir <- system.file("templates", package = "debrowser")
        template_file <- file.path(template_dir,
                                   sprintf("ai_%s.md", input$question))
        if (!file.exists(template_file)) return("(template missing)")
        redacted <- .redact_payload(p, input$privacy %||% "symbols",
                                    top_n = as.integer(input$top_n %||% 50L))
        slots <- list(
          n_genes = length(redacted$genes),
          n_total = attr(redacted, "n_total"),
          truncated = isTRUE(attr(redacted, "truncated")),
          gene_list = paste(redacted$genes, collapse = ", "),
          has_stats = !is.null(redacted$stats),
          stats_table = if (is.null(redacted$stats)) "" else
            .format_stats_table(redacted$stats),
          has_enrichment = !is.null(redacted$enrichment),
          enrichment_summary = if (is.null(redacted$enrichment)) "" else
            sprintf("Term: %s; p-value: %g; overlap: %d genes.",
                    redacted$enrichment$term,
                    redacted$enrichment$pvalue,
                    redacted$enrichment$n_overlap)
        )
        .render_prompt(template_file, slots)
      }, error = function(e) sprintf("(could not render preview: %s)",
                                     conditionMessage(e)))
    })

    output$prompt_preview <- shiny::renderText({ prompt_preview_text() })

    output$char_count <- shiny::renderText({
      txt <- tryCatch(prompt_preview_text(),
                      error = function(e) NA_character_)
      if (is.null(txt) || !is.character(txt) || is.na(txt)) {
        return("0 characters will be sent.")
      }
      sprintf("%d characters will be sent.", nchar(txt))
    })

    # Response state
    response_rv <- shiny::reactiveVal("")

    output$response <- shiny::renderText({ response_rv() })

    shiny::observeEvent(input$ask, {
      p <- payload_react()
      if (is.null(p) || length(p$genes) == 0L) {
        shiny::showNotification("No genes to summarize.", type = "warning")
        return()
      }
      s <- settings_react()
      if (!.has_required_credentials(s)) {
        shiny::showNotification(
          "Configure a provider in Settings - AI Assistant.", type = "warning"
        )
        return()
      }
      key <- if (s$provider == "ollama") NULL else ai_key_get(s$provider)
      response_rv("(thinking...)")
      tryCatch({
        chat <- ai_chat(s$provider, s$model, api_key = key)
        out  <- ai_interpret(
          question      = input$question,
          payload       = p,
          privacy_mode  = input$privacy %||% "symbols",
          provider_chat = chat,
          top_n         = as.integer(input$top_n %||% 50L)
        )
        response_rv(out)
      }, ai_no_key = function(e) {
        response_rv(""); shiny::showNotification(
          "Auth failed. Check the API key in Settings.",
          type = "error", duration = 10
        )
      }, ai_network = function(e) {
        response_rv(""); shiny::showNotification(
          "Network error reaching provider.", type = "error", duration = 10
        )
      }, ai_rate_limit = function(e) {
        response_rv(""); shiny::showNotification(
          "Rate limited. Try again in a moment.",
          type = "warning", duration = 10
        )
      }, ai_invalid_response = function(e) {
        response_rv(""); shiny::showNotification(
          sprintf("Provider returned an unexpected response: %s",
                  conditionMessage(e)),
          type = "error", duration = 10
        )
      }, error = function(e) {
        response_rv(""); shiny::showNotification(
          sprintf("AI request failed: %s", conditionMessage(e)),
          type = "error", duration = 10
        )
      })
    })

    invisible(NULL)
  })
}
