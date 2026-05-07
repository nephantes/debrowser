# R/mod_account.R
#
# Navbar account dropdown for D2.5. Shows the current user (resolved
# via current_user(session)), exposes a Sign up modal, and a Sign out
# action that clears the per-session auth cache + reloads.
#
# D2.6 will add a "My Bookmarks" entry to this dropdown.

#' UI: navbar account dropdown.
#' @export
accountDropdownUI <- function(id) {
  ns <- shiny::NS(id)
  bslib::nav_menu(
    title = shiny::uiOutput(ns("label"), inline = TRUE),
    icon = shiny::icon("user"),
    align = "right",
    bslib::nav_item(shiny::actionLink(ns("signup_link"),
                                      "Sign up",
                                      icon = shiny::icon("user-plus"))),
    bslib::nav_item(shiny::actionLink(ns("signout"),
                                      "Sign out",
                                      icon = shiny::icon("sign-out-alt")))
  )
}

#' Server: wires the dropdown to current_user, signup modal, signout.
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
  })
}
