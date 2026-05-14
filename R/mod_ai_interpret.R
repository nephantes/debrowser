# R/mod_ai_interpret.R
#
# Phase E12.A - AI interpretation panel. aiInterpretUI() renders the
# panel card; aiInterpretServer() wires the question / privacy / Top-N /
# disclosure / Ask button / response. Reads the parent's payload reactive
# and the user's settings reactive; calls the pure ai_interpret() helper.
# No tests for this module (Shiny module is thin).
#
# Phase E12.B - widened signatures: aiInterpretUI gains questions= /
# payload_shape= ; aiInterpretServer gains payload_shape= /
# deterministic_methods_react= . Backward-compatible defaults preserve
# E12.A behavior. Response area swapped from textOutput+tags$pre to
# uiOutput+sanitized-markdown HTML.

#' AI interpretation panel UI.
#'
#' Renders a card with: question dropdown, privacy radio (hidden for
#' `draft_methods`), Top-N input, "What will be sent?" disclosure, Ask
#' button, and a sanitized-markdown response area. The card is meant
#' to be wrapped in a parent's conditionalPanel so it only renders
#' when settings are valid and analytical results exist.
#'
#' @param id Module ID.
#' @param questions Character vector of preset keys offered in the
#'   dropdown. Default `"summarize_geneset"` (E12.A behavior).
#'   Supported keys: `summarize_geneset`, `reconcile_enrichments`,
#'   `suggest_followup`, `draft_methods`.
#' @param payload_shape One of `"geneset"`, `"de_table"`,
#'   `"concordance"`. Drives slot building and per-shape privacy
#'   defaults. Default `"geneset"` (E12.A behavior).
#' @return tagList.
#' @examples
#' aiInterpretUI("ai_enrichment")
#' aiInterpretUI("ai_de",
#'               questions     = c("summarize_geneset", "suggest_followup",
#'                                 "draft_methods"),
#'               payload_shape = "de_table")
#' @export
aiInterpretUI <- function(id,
                          questions     = "summarize_geneset",
                          payload_shape = "geneset") {
  ns <- shiny::NS(id)
  # Friendly labels for the dropdown -- match the preset key vocabulary.
  all_labels <- c(
    "summarize_geneset"     = "Summarize this gene set's biology",
    "reconcile_enrichments" = "Reconcile this pathway across comparisons",
    "suggest_followup"      = "Suggest follow-up analyses and experiments",
    "draft_methods"         = "Polish the Methods paragraph"
  )
  q_labels  <- all_labels[questions]
  q_choices <- setNames(names(q_labels), unname(q_labels))

  shiny::tagList(
    shiny::tags$div(`data-shape` = payload_shape),  # for downstream introspection
    shiny::selectInput(ns("question"), "Question",
                       choices = q_choices,
                       selected = q_choices[[1]]),
    shiny::conditionalPanel(
      condition = sprintf("input['%s'] !== 'draft_methods'", ns("question")),
      shiny::radioButtons(ns("privacy"), "Privacy",
                         choices = c(
                           "Symbols"          = "symbols",
                           "+ Stats"          = "stats",
                           "+ Stats + Enrich" = "stats_enrichment"
                         ),
                         inline = TRUE,
                         selected = "symbols")
    ),
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
      shiny::uiOutput(ns("response"),
                      style = "max-height: 400px; overflow-y: auto;")
    )
  )
}

#' AI interpretation panel server.
#'
#' @param id Module ID (matches [aiInterpretUI()]).
#' @param payload_react Reactive expression returning the payload list
#'   per shape:
#'   * `geneset` shape: `list(genes, stats, enrichment, context_mode)`
#'   * `de_table` shape: `list(comparison_label, genes, stats,
#'     n_total_de, cutoffs)`
#'   * `concordance` shape: `list(comparison_labels, concordance_table,
#'     per_comparison_top, cutoffs)`
#'   May return NULL; Ask is disabled in that case.
#' @param settings_react Reactive expression yielding the current AI
#'   settings list (from `aiSettingsServer`).
#' @param payload_shape One of `"geneset"`, `"de_table"`, `"concordance"`.
#'   Must match the shape passed to `aiInterpretUI(id, ..., payload_shape)`.
#'   Default `"geneset"`.
#' @param deterministic_methods_react Optional reactive expression
#'   yielding a chr(1) Methods paragraph (e.g. from `methods_paragraph()`).
#'   Required for the `draft_methods` preset; ignored otherwise.
#' @return invisible(NULL).
#' @export
aiInterpretServer <- function(id, payload_react, settings_react,
                              payload_shape = "geneset",
                              deterministic_methods_react = NULL) {
  shiny::moduleServer(id, function(input, output, session) {

    # Per-shape privacy defaults (overrides settings' default_privacy).
    shape_default_privacy <- switch(payload_shape,
                                    "geneset"     = NULL,  # use settings
                                    "de_table"    = "stats",
                                    "concordance" = "stats",
                                    NULL)
    shiny::observe({
      s <- settings_react()
      sel <- shape_default_privacy %||% s$default_privacy %||% "symbols"
      shiny::updateRadioButtons(session, "privacy", selected = sel)
    }, priority = 100)

    # Dynamic question dropdown filtering per (shape, payload).
    shiny::observe({
      p <- tryCatch(payload_react(), error = function(e) NULL)
      choices <- .applicable_questions(payload_shape, p)
      all_labels <- c(
        "summarize_geneset"     = "Summarize this gene set's biology",
        "reconcile_enrichments" = "Reconcile this pathway across comparisons",
        "suggest_followup"      = "Suggest follow-up analyses and experiments",
        "draft_methods"         = "Polish the Methods paragraph"
      )
      keep <- intersect(choices, names(all_labels))
      if (length(keep) == 0L) return()
      labeled <- setNames(keep, unname(all_labels[keep]))
      shiny::updateSelectInput(session, "question", choices = labeled)
    })

    prompt_preview_text <- shiny::reactive({
      tryCatch({
        p <- payload_react()
        if (identical(input$question, "draft_methods")) {
          txt <- if (is.null(deterministic_methods_react)) NULL else
                   deterministic_methods_react()
          if (is.null(txt) || !nzchar(txt)) {
            return("(no methods paragraph available -- run DE first)")
          }
          # Inject the deterministic text as a synthetic payload field
          # for ai_interpret's draft_methods path; this matches what
          # the Ask handler does below.
          if (is.null(p)) p <- list()
          p$shape <- "draft_methods_text"
          p$deterministic_methods <- txt
          template_file <- system.file("templates",
                                       "ai_draft_methods.md",
                                       package = "debrowser")
          if (!file.exists(template_file)) return("(template missing)")
          slots <- .slots_draft_methods(p)
          return(.render_prompt(template_file, slots))
        }
        if (is.null(p) ||
            (identical(payload_shape, "geneset")     && length(p$genes) == 0L) ||
            (identical(payload_shape, "de_table")    && length(p$genes) == 0L) ||
            (identical(payload_shape, "concordance") && length(p$comparison_labels) < 2L)) {
          return("(payload not ready)")
        }
        template_dir <- system.file("templates", package = "debrowser")
        template_file <- file.path(template_dir,
                                   sprintf("ai_%s.md", input$question))
        if (!file.exists(template_file)) return("(template missing)")

        if (identical(input$question, "summarize_geneset")) {
          redacted <- .redact_payload(p, input$privacy %||% "symbols",
                                      top_n = as.integer(input$top_n %||% 50L))
          slots <- .slots_summarize_geneset(
            redacted,
            isTRUE(attr(redacted, "truncated")),
            attr(redacted, "n_total")
          )
        } else if (identical(input$question, "reconcile_enrichments")) {
          slots <- .slots_reconcile_enrichments(p)
        } else if (identical(input$question, "suggest_followup")) {
          redacted <- .redact_payload(p, input$privacy %||% "symbols",
                                      top_n = as.integer(input$top_n %||% 50L))
          slots <- .slots_suggest_followup(p, redacted)
        } else {
          return("(unknown question)")
        }
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

    response_rv <- shiny::reactiveVal("")

    output$response <- shiny::renderUI({
      txt <- response_rv()
      if (!nzchar(txt)) return(NULL)
      if (identical(txt, "(thinking...)")) {
        return(shiny::tags$em("thinking..."))
      }
      rendered <- tryCatch(
        .render_markdown_sanitized(txt),
        error = function(e) {
          shiny::showNotification(
            "Could not render markdown; showing plain text.",
            type = "warning", duration = 6
          )
          sprintf("<pre>%s</pre>", htmltools::htmlEscape(txt))
        }
      )
      htmltools::HTML(rendered)
    })

    shiny::observeEvent(input$ask, {
      p <- payload_react()
      s <- settings_react()
      if (!.has_required_credentials(s)) {
        shiny::showNotification(
          "Configure a provider in Settings - AI Assistant.",
          type = "warning"
        )
        return()
      }
      q <- input$question

      # draft_methods needs the deterministic methods text injected.
      if (identical(q, "draft_methods")) {
        txt <- if (is.null(deterministic_methods_react)) NULL else
                 deterministic_methods_react()
        if (is.null(txt) || !nzchar(txt)) {
          shiny::showNotification(
            "Run DE first -- no Methods paragraph yet.",
            type = "warning"
          )
          return()
        }
        if (is.null(p)) p <- list()
        p$shape <- "draft_methods_text"
        p$deterministic_methods <- txt
      } else {
        if (is.null(p)) {
          shiny::showNotification("No payload available.", type = "warning")
          return()
        }
      }

      key <- if (s$provider == "ollama") NULL else ai_key_get(s$provider)
      response_rv("(thinking...)")
      tryCatch({
        chat <- ai_chat(s$provider, s$model, api_key = key)
        out  <- ai_interpret(
          question      = q,
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

# Local null-coalescing operator. Keep at bottom of file.
`%||%` <- function(a, b) if (is.null(a)) b else a
