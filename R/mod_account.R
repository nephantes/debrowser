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
    output$label <- shiny::renderUI({
      shiny::invalidateLater(2000, session)
      uid <- current_user(session)
      if (is.na(uid) || identical(uid, "local")) {
        shiny::tags$span("Not signed in")
      } else {
        shiny::tags$span(paste0("@", uid))
      }
    })

    # Menu items swap based on login state.
    output$menu_items <- shiny::renderUI({
      shiny::invalidateLater(2000, session)
      uid <- current_user(session)
      if (is.na(uid) || identical(uid, "local")) {
        # Not signed in: show Sign up only.
        shiny::actionLink(session$ns("signup_link"),
                          "Sign up",
                          icon = shiny::icon("user-plus"))
      } else {
        # Signed in: show My Bookmarks + Sign out.
        shiny::tagList(
          shiny::actionLink(session$ns("my_bookmarks"),
                            "My Bookmarks",
                            icon = shiny::icon("bookmark")),
          shiny::tags$br(),
          shiny::actionLink(session$ns("signout"),
                            "Sign out",
                            icon = shiny::icon("sign-out-alt"))
        )
      }
    })

    shiny::observeEvent(input$signup_link, {
      shiny::showModal(shiny::modalDialog(
        title = "Sign up",
        shiny::tagList(
          shiny::textInput(session$ns("signup_user"), "Username"),
          shiny::textInput(session$ns("signup_email"),
                           "Email (optional)"),
          shiny::passwordInput(session$ns("signup_pw"),
                               "Password (8+ chars)"),
          shiny::passwordInput(session$ns("signup_pw2"),
                               "Confirm password")
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
        password_confirm = input$signup_pw2
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
      ok <- tryCatch({
        signup_user(con, input$signup_user, input$signup_email,
                    input$signup_pw)
        TRUE
      }, error = function(e) {
        shiny::showNotification(
          paste("Signup failed:", conditionMessage(e)),
          type = "error", duration = 8
        )
        FALSE
      })
      if (isTRUE(ok)) {
        shiny::removeModal()
        shiny::showNotification(
          "Account created. Please sign in.",
          type = "message", duration = 6
        )
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
