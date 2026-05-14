# R/mod_ai_settings.R
#
# Phase E12.A - Settings nav_menu + modal. aiSettingsUI() returns the
# navbar nav_menu element; aiSettingsServer() handles the modal form
# (provider, model, key, default privacy). No tests for this module
# (Shiny module is thin; pure helpers in fct_ai_settings.R carry the load).

#' Settings nav_menu UI (mounted in the navbar).
#'
#' Returns a `bslib::nav_menu` titled "Settings" with one item: "AI Assistant".
#' Clicking the item opens a modal handled by [aiSettingsServer()].
#'
#' @param id Module ID.
#' @return bslib::nav_menu element.
#' @examples
#' aiSettingsUI("ai")
#' @export
aiSettingsUI <- function(id) {
  ns <- shiny::NS(id)
  # CSP-safe: emit data-debrowser-input. account_dropdown.js attaches
  # a document-level click delegate that reads the attribute and
  # fires Shiny.setInputValue. The previous javascript: href was
  # blocked by Shiny's default CSP, so the click went nowhere.
  bslib::nav_menu(
    title = "Settings",
    align = "right",
    bslib::nav_item(
      shiny::tags$ul(
        class = "de-account-menu",
        shiny::tags$li(
          shiny::tags$a(
            href = "#",
            `data-debrowser-input` = ns("open_ai_modal"),
            class = "dropdown-item de-account-item",
            style = "color: #0f172a; cursor: pointer;",
            shiny::icon("robot"), " AI Assistant"
          )
        )
      )
    )
  )
}

#' Settings server -- opens the AI configuration modal on click.
#'
#' @param id Module ID (matches [aiSettingsUI()]).
#' @return shiny::reactive yielding the current settings list. Parent
#'   modules should consume this to gate the AI panel mount.
#' @export
aiSettingsServer <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {

    # Live settings reactive backed by ai_settings_load(). Refreshed on
    # successful Save.
    settings_rv <- shiny::reactiveVal(ai_settings_load())

    # Cached models per provider (cleared by Refresh).
    models_cache <- shiny::reactiveValues()

    # --- Modal open + initial form population ---
    shiny::observeEvent(input$open_ai_modal, {
      s <- settings_rv()
      shiny::showModal(shiny::modalDialog(
        title = "AI Settings",
        size = "l",
        shiny::checkboxInput(session$ns("enabled"),
                             "Enable AI features",
                             value = isTRUE(s$enabled)),
        shiny::selectInput(session$ns("provider"), "Provider",
                           choices = c("(select)" = "",
                                       "Anthropic" = "anthropic",
                                       "OpenAI"    = "openai",
                                       "Ollama (local)" = "ollama"),
                           selected = s$provider %||% ""),
        shiny::uiOutput(session$ns("model_picker")),
        shiny::uiOutput(session$ns("key_input")),
        shiny::radioButtons(session$ns("default_privacy"),
                            "Default privacy mode",
                            choices = c(
                              "Symbols only (recommended; most private)" = "symbols",
                              "+ Stats (log2FC, padj)"                   = "stats",
                              "+ Stats + local enrichment"               = "stats_enrichment"
                            ),
                            selected = s$default_privacy),
        shiny::tags$details(
          shiny::tags$summary("What's actually sent?"),
          shiny::tags$p(class = "small text-muted",
            "Symbols only: just gene symbols. Stats: also log2FoldChange ",
            "and adjusted p-value per gene. Stats + enrichment: also the ",
            "term name, p-value, and overlap count of the selected pathway. ",
            "API keys are stored encrypted in your OS keychain via the ",
            "keyring package and never written to disk in plaintext.")
        ),
        easyClose = TRUE,
        footer = shiny::tagList(
          shiny::actionButton(session$ns("test_provider"), "Test",
                              class = "btn-secondary"),
          shiny::modalButton("Cancel"),
          shiny::actionButton(session$ns("save_settings"), "Save",
                              class = "btn-primary")
        )
      ))
    })

    # --- Dynamic model picker ---
    output$model_picker <- shiny::renderUI({
      prov <- input$provider
      if (!nzchar(prov %||% "")) {
        return(shiny::tags$p(class = "text-muted",
                             "Select a provider first."))
      }
      key <- if (prov == "ollama") NULL else ai_key_get(prov)
      models <- models_cache[[prov]]
      if (is.null(models)) {
        models <- list_models(prov, api_key = key)
        models_cache[[prov]] <- models
      }
      cur_model <- settings_rv()$model
      # Guard against cur_model being NULL/empty: NULL %in% chr returns
      # logical(0) and breaks if(); pick the first available model in
      # that case.
      selected_model <- if (length(cur_model) == 1L && cur_model %in% models) {
        cur_model
      } else {
        models[1L]
      }
      shiny::tagList(
        shiny::selectInput(session$ns("model"), "Model",
                           choices = models,
                           selected = selected_model),
        shiny::actionLink(session$ns("refresh_models"), "Refresh models")
      )
    })

    shiny::observeEvent(input$refresh_models, {
      prov <- input$provider
      if (!nzchar(prov %||% "")) return()
      models_cache[[prov]] <- NULL
    })

    # --- Dynamic API key input (hidden for Ollama) ---
    output$key_input <- shiny::renderUI({
      prov <- input$provider
      if (!nzchar(prov %||% "") || prov == "ollama") return(NULL)
      shiny::tagList(
        shiny::passwordInput(session$ns("api_key"),
                             "API key",
                             value = ai_key_get(prov) %||% ""),
        shiny::tags$p(class = "small text-muted",
          "(Stored encrypted in OS keychain via keyring.)")
      )
    })

    # --- Test button: 1-token round-trip ---
    shiny::observeEvent(input$test_provider, {
      prov <- input$provider
      if (!nzchar(prov %||% "")) {
        shiny::showNotification("Select a provider first.", type = "warning")
        return()
      }
      model <- input$model
      if (is.null(model) || !nzchar(model)) {
        shiny::showNotification("Select a model first.", type = "warning")
        return()
      }
      key <- if (prov == "ollama") NULL else input$api_key
      tryCatch({
        chat <- ai_chat(prov, model, api_key = key)
        chat$chat("Reply with the single word: OK")
        shiny::showNotification(
          sprintf("Provider %s / %s responded.", prov, model),
          type = "message"
        )
      }, ai_no_key = function(e) {
        shiny::showNotification(
          "Auth failed. Check the API key.", type = "error", duration = 10
        )
      }, ai_network = function(e) {
        msg <- if (prov == "ollama") {
          "Could not reach Ollama. Start it with 'ollama serve' and try again."
        } else "Network error reaching provider."
        shiny::showNotification(msg, type = "error", duration = 10)
      }, ai_rate_limit = function(e) {
        shiny::showNotification("Rate limited. Try again in a moment.",
                                type = "warning", duration = 10)
      }, error = function(e) {
        shiny::showNotification(
          sprintf("Test failed: %s", conditionMessage(e)),
          type = "error", duration = 10
        )
      })
    })

    # --- Save button: persist settings + key, refresh settings_rv ---
    shiny::observeEvent(input$save_settings, {
      prov <- input$provider
      if (!nzchar(prov %||% "")) prov <- NULL
      model <- input$model %||% NULL
      ai_settings_save(list(
        enabled = isTRUE(input$enabled),
        provider = prov,
        model = model,
        default_privacy = input$default_privacy
      ))
      if (!is.null(prov) && prov != "ollama") {
        key <- input$api_key %||% ""
        if (nzchar(key)) {
          ai_key_set(prov, key)
        }
      }
      settings_rv(ai_settings_load())
      shiny::removeModal()
      shiny::showNotification("AI settings saved.", type = "message")
    })

    settings_rv
  })
}
