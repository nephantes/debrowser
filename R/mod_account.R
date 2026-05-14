# R/mod_account.R
#
# Navbar account dropdown for D2.5. Shows the current user (resolved
# via current_user(session)), exposes a Sign up modal, and a Sign out
# action that clears the per-session auth cache + reloads.
#
# D2.6 will add a "My Bookmarks" entry to this dropdown.

#' UI: navbar account dropdown.
#' @param id Shiny module namespace id.
#' @export
accountDropdownUI <- function(id) {
  ns <- shiny::NS(id)
  # Sign up vs Sign out are rendered server-side via uiOutput so the
  # set of menu items can swap on login/logout. When logged in we
  # only show Sign out; when anonymous we only show Sign up.
  bslib::nav_menu(
    title = shiny::uiOutput(ns("label"), inline = TRUE),
    icon = shiny::icon("user"),
    align = "right",
    bslib::nav_item(shiny::uiOutput(ns("menu_items")))
  )
}

#' Server: wires the dropdown to current_user, signup modal, signout.
#' @param id Shiny module namespace id.
#' @export
accountDropdownServer <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {

    # Auth-state poll: every 2s, recompute the user id and write into a
    # reactiveVal. Outputs depend on the reactiveVal, NOT on a fresh
    # invalidateLater(), so the renderUI fires ONLY when the user
    # identifier actually changes (login, logout). This eliminates the
    # race where the 2-second auto-re-render replaced the dropdown DOM
    # mid-click, dropping the click event before Shiny could deliver it
    # to input$signout / input$my_bookmarks.
    user_id_rv <- shiny::reactiveVal(NA_character_)
    shiny::observe({
      shiny::invalidateLater(2000, session)
      shiny::isolate({
        uid <- current_user(session)
        if (!identical(uid, user_id_rv())) user_id_rv(uid)
      })
    })

    output$label <- shiny::renderUI({
      uid <- user_id_rv()
      if (is.na(uid) || identical(uid, "local")) {
        shiny::tags$span("Not signed in")
      } else {
        shiny::tags$span(paste0("@", uid))
      }
    })

    # Menu items render as `<a data-debrowser-action="...">` with both
    # (a) a document-level click delegate installed from
    # inst/extdata/www/account_dropdown.js (loaded by ui.R), AND
    # (b) an inline onclick attribute that fires the same setInputValue
    # call directly. We need both because:
    #   - The external script can be blocked by aggressive cache or
    #     CSP -- onclick is a hard guarantee.
    #   - The document-level delegate handles edge cases like clicks on
    #     the icon (e.target may be the <i>, not the <a>), via
    #     `closest('[data-debrowser-action]')`. onclick on the <a>
    #     handles direct anchor clicks.
    # Inline onclick is safe from the "innerHTML strips scripts" gotcha
    # because it's an attribute, not a <script> element.
    output$menu_items <- shiny::renderUI({
      uid <- user_id_rv()
      ns_prefix <- session$ns("")  # "account-"
      # CSP-safe click delivery: we emit the FULL Shiny input id in a
      # `data-debrowser-input` attribute, and the
      # inst/extdata/www/account_dropdown.js script (loaded by ui.R)
      # attaches a single document-level listener that reads this
      # attribute on click and fires Shiny.setInputValue with the
      # right id. No inline onclick / onmousedown / javascript: href
      # -- all three of those are blocked by Shiny's default CSP, so
      # the previous attempts silently failed even though the
      # attributes were in the DOM.
      #
      # `mk_item()` defaults to firing an input INSIDE this module's
      # namespace ("account-<action_name>"). For AI Assistant we point
      # to the aiSettings module's namespace directly:
      # "ai_settings-open_ai_modal" so the Settings nav_menu in the
      # navbar can be removed entirely while the existing
      # aiSettingsServer observer still picks the click up.
      mk_item <- function(action_name, label, icon_name,
                          full_input_id = NULL) {
        input_id <- if (!is.null(full_input_id)) full_input_id
                    else paste0(ns_prefix, action_name)
        shiny::tags$li(
          shiny::tags$a(
            href = "#",
            `data-debrowser-input` = input_id,
            class = "dropdown-item de-account-item",
            style = "color: #0f172a; cursor: pointer;",
            shiny::icon(icon_name), " ", label
          )
        )
      }
      ai_item <- mk_item(
        action_name   = "ai_assistant",
        label         = "AI Assistant",
        icon_name     = "robot",
        full_input_id = "ai_settings-open_ai_modal"
      )

      # B3.34: Export items rendered inline here (was previously a
      # separate navbar dropdown). They live in the "export" namespace,
      # which matches exportMenuServer("export", ...) wired in server.R,
      # so their downloads / actionLinks keep working unchanged.
      export_section <- shiny::tagList(
        shiny::tags$li(shiny::tags$hr(
          class = "dropdown-divider",
          style = "margin: 4px 6px; opacity: .35;"
        )),
        shiny::tags$li(shiny::tags$div(
          class = "dropdown-header",
          style = paste(
            "font-size: 11px; font-weight: 700;",
            "text-transform: uppercase; letter-spacing: .05em;",
            "padding: 4px 12px; color: #64748b;"
          ),
          "Export"
        )),
        # Same-package call (no `debrowser::` prefix needed and avoids
        # the "not an exported object" error before NAMESPACE is
        # regenerated by roxygen). `exportMenuItems` lives in
        # R/mod_export.R.
        exportMenuItems("export")
      )

      if (is.na(uid) || identical(uid, "local")) {
        # Anonymous: Sign up + AI Assistant + Export
        # (settings + export are still useful without an account).
        shiny::tags$ul(class = "de-account-menu",
                       mk_item("signup_link", "Sign up", "user-plus"),
                       ai_item,
                       export_section)
      } else {
        # Signed in: My Bookmarks -> AI Assistant -> Export... -> Sign out
        shiny::tags$ul(class = "de-account-menu",
                       mk_item("my_bookmarks", "My Bookmarks", "bookmark"),
                       ai_item,
                       export_section,
                       shiny::tags$li(shiny::tags$hr(
                         class = "dropdown-divider",
                         style = "margin: 4px 6px; opacity: .35;"
                       )),
                       mk_item("signout",      "Sign out",     "sign-out-alt"))
      }
    })

    shiny::observeEvent(input$signup_link, {
      shiny::showModal(shiny::modalDialog(
        title = "Create your DEBrowser account",
        shiny::tagList(
          shiny::textInput(session$ns("signup_user"), "Username"),
          shiny::textInput(session$ns("signup_email"),
                           "Email (required for verification)"),
          shiny::passwordInput(session$ns("signup_pw"),
                               "Password (8+ chars)"),
          shiny::passwordInput(session$ns("signup_pw2"),
                               "Confirm password"),
          shiny::tags$hr(),
          shiny::tags$div(
            class = "de-signup-consent",
            shiny::checkboxInput(
              session$ns("signup_accept_terms"),
              shiny::HTML(
                "I accept the <a href='www/legal/terms.html' target='_blank' rel='noopener'>Terms of Service</a>."
              ),
              value = FALSE
            ),
            shiny::checkboxInput(
              session$ns("signup_accept_privacy"),
              shiny::HTML(
                "I have read the <a href='www/legal/privacy.html' target='_blank' rel='noopener'>Privacy Policy</a> and consent to the described processing of my data."
              ),
              value = FALSE
            ),
            shiny::checkboxInput(
              session$ns("signup_accept_cookies"),
              shiny::HTML(
                "I accept the use of cookies and similar technologies as described in the <a href='www/legal/cookies.html' target='_blank' rel='noopener'>Cookie Policy</a>."
              ),
              value = FALSE
            )
          )
        ),
        footer = shiny::tagList(
          shiny::modalButton("Cancel"),
          shiny::actionButton(session$ns("signup_submit"),
                              "Create account",
                              class = "btn-primary")
        )
      ))
    })

    shiny::observeEvent(input$signup_submit, {
      err <- validate_signup_input(
        user_id = input$signup_user,
        email = input$signup_email,
        password = input$signup_pw,
        password_confirm = input$signup_pw2,
        require_email = TRUE
      )
      if (!is.null(err)) {
        shiny::showNotification(err, type = "error", duration = 6)
        return()
      }
      con <- tryCatch(user_db_connect(), error = function(e) NULL)
      if (is.null(con)) {
        shiny::showNotification("User database is unavailable.",
                                type = "error", duration = 6)
        return()
      }
      on.exit(DBI::dbDisconnect(con), add = TRUE)
      base_url <- compose_base_url(session)
      result <- tryCatch({
        signup_user(con, input$signup_user, input$signup_email,
                    input$signup_pw,
                    base_url = base_url,
                    require_verification = FALSE)
      }, error = function(e) {
        shiny::showNotification(
          paste("Signup failed:", conditionMessage(e)),
          type = "error", duration = 8
        )
        NULL
      })
      if (!is.null(result)) {
        shiny::removeModal()
        if (isTRUE(result$verify_required)) {
          shiny::showModal(shiny::modalDialog(
            title = "Check your email",
            shiny::tags$p(
              "We sent a verification link to ",
              shiny::tags$b(input$signup_email), ". ",
              "Click it within 24 hours to activate your account."
            ),
            easyClose = TRUE,
            footer = shiny::modalButton("OK")
          ))
        } else {
          shiny::showNotification(
            "Account created. Please sign in.",
            type = "message", duration = 6
          )
        }
      }
    })

    shiny::observeEvent(input$signout, {
      ud <- session$userData
      if (!is.null(ud)) {
        ud$debrowser_auth <- NULL
        ud$user <- NULL  # shinymanager uses this slot
      }
      chain <- getOption("debrowser.auth_chain")
      if (!is.null(chain)) chain$logout(session)
      session$reload()
    })

    # My Bookmarks - modal listing the current user's saved bookmarks.
    shiny::observeEvent(input$my_bookmarks, {
      uid <- current_user(session)
      if (is.na(uid) || identical(uid, "local")) return()
      con <- tryCatch(user_db_connect(), error = function(e) NULL)
      if (is.null(con)) {
        shiny::showNotification("User database is unavailable.",
                                type = "error", duration = 6)
        return()
      }
      on.exit(DBI::dbDisconnect(con), add = TRUE)
      rows <- tryCatch(user_db_bookmarks_for_user(con, uid),
                       error = function(e) data.frame())
      shiny::showModal(shiny::modalDialog(
        title = "My Bookmarks",
        size = "l",
        easyClose = TRUE,
        if (NROW(rows) == 0L) {
          shiny::div(class = "text-muted",
                     "You don't have any bookmarks yet.")
        } else {
          # Build a table with one row per bookmark.
          shiny::tags$table(
            class = "table table-sm",
            shiny::tags$thead(shiny::tags$tr(
              shiny::tags$th("Name"),
              shiny::tags$th("Visibility"),
              shiny::tags$th("Created"),
              shiny::tags$th("")
            )),
            shiny::tags$tbody(lapply(seq_len(NROW(rows)), function(i) {
              r <- rows[i, , drop = FALSE]
              state_id <- as.character(r$state_id)
              label_txt <- r$label
              if (is.na(label_txt) || !nzchar(label_txt)) {
                label_txt <- paste0("(unnamed: ",
                                    substr(state_id, 1, 8), "...)")
              }
              created <- format(
                as.POSIXct(r$created_at, origin = "1970-01-01"),
                "%Y-%m-%d %H:%M")
              vis_label <- if (identical(r$visibility, "link"))
                "Shared via link" else "Private"
              # Bookmark URLs are relative to the app root; we just
              # anchor with the query string.
              href <- paste0("?_state_id_=", state_id)
              shiny::tags$tr(
                shiny::tags$td(shiny::tags$a(
                  href = href, label_txt
                )),
                shiny::tags$td(vis_label),
                shiny::tags$td(created),
                shiny::tags$td(shiny::actionButton(
                  inputId = session$ns(paste0("delete_", state_id)),
                  label = NULL, icon = shiny::icon("trash"),
                  class = "btn-sm btn-link text-danger",
                  title = "Delete bookmark"
                ))
              )
            }))
          )
        },
        footer = shiny::modalButton("Close")
      ))
    })

    # Delete-button observer - uses a single observer that watches
    # input names matching the delete_* pattern. Less elegant than
    # individual observers but doesn't leak handlers per modal open.
    shiny::observe({
      # Iterate input names; this is a reactive dependency.
      nm <- names(input)
      del_inputs <- grep("^delete_", nm, value = TRUE)
      lapply(del_inputs, function(in_name) {
        clicks <- input[[in_name]]
        if (is.null(clicks) || clicks == 0L) return()
        # state_id is everything after "delete_"
        sid <- sub("^delete_", "", in_name)
        # Idempotency: only act when the click count was bumped THIS turn.
        prev_key <- paste0("__last_click_", in_name)
        prev <- session$userData[[prev_key]]
        if (!is.null(prev) && prev == clicks) return()
        session$userData[[prev_key]] <- clicks
        # Confirm + delete.
        con2 <- tryCatch(user_db_connect(), error = function(e) NULL)
        if (is.null(con2)) return()
        on.exit(DBI::dbDisconnect(con2), add = TRUE)
        tryCatch(
          user_db_bookmark_delete(con2, sid),
          error = function(e) NULL
        )
        # Also remove the on-disk bookmark dir.
        bm_dir <- file.path(data_dir(), "shiny_bookmarks", sid)
        if (dir.exists(bm_dir)) unlink(bm_dir, recursive = TRUE)
        shiny::showNotification(
          paste("Deleted bookmark", substr(sid, 1, 8)),
          type = "message", duration = 4
        )
        # Re-render the list by re-firing the my_bookmarks click.
        shiny::removeModal()
      })
    })
  })
}
