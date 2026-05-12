# R/fct_shinymanager_auth.R
#
# shinymanager-backed auth provider for D2.5. The provider's wrap_app
# calls shinymanager::secure_app(app, check_credentials = ...) which
# inserts a login screen above the app when no user is authenticated.
# After login, shinymanager stores the user info in session$userData$user;
# our identify() reads that.
#
# The check_credentials function is passed at construction time so tests
# can mock it without reaching the user_db. Task 3 adds the live
# constructor shinymanager_check_credentials_fn().

#' B3.6 — inline stylesheet for the shinymanager auth screen.
#'
#' Self-contained because the auth UI renders BEFORE deUI() / addResourcePath
#' run, so we can't reference the main `inst/extdata/www/debrowser.css`.
#' Repaints shinymanager's `.panel` as a centered card on the same dark
#' navy canvas (with grid + radial glows) the rest of the app uses, and
#' styles the brand mark, eyebrow, headline, inputs, and Login button.
#'
#' @return character — a CSS blob suitable for `tags$style(HTML(...))`
#' @keywords internal
#' @noRd
de_auth_styles <- function() {
'
:root{
  --de-cyan:#5EE6D6; --de-violet:#A78BFA; --de-pink:#FF7AA2;
  --de-grad:linear-gradient(135deg,#5EE6D6 0%,#A78BFA 100%);
  --de-bg-0:#0B1020; --de-bg-1:#0F1530; --de-bg-2:#141B3A; --de-bg-3:#1A2147;
  --de-border:rgba(255,255,255,.08); --de-border-strong:rgba(255,255,255,.14);
  --de-text-1:#E6ECFF; --de-text-2:#A8B2D1; --de-text-3:#6E7BA5;
}
html, body {
  margin: 0; padding: 0; height: 100%;
  background: var(--de-bg-0);
  color: var(--de-text-1);
  font-family: "Inter", system-ui, sans-serif;
  font-size: 13.5px;
  background-image:
    radial-gradient(800px 500px at 12% -10%, rgba(94,230,214,.10), transparent 60%),
    radial-gradient(900px 600px at 110% 110%, rgba(167,139,250,.12), transparent 60%),
    linear-gradient(rgba(255,255,255,.04) 1px, transparent 1px),
    linear-gradient(90deg, rgba(255,255,255,.04) 1px, transparent 1px);
  background-size: auto, auto, 56px 56px, 56px 56px;
  background-attachment: fixed;
}
/* Hide shinymanager language/where selects we do not need */
.shinymanager_lang, #shinymanager_language, #shinymanager_where { display:none !important; }

/* Lay everything out as a single centered column */
body > .container, body > div:not(.de-auth-hero):not(.de-auth-signup):not(.de-auth-footer) {
  max-width: 420px !important; margin: 0 auto !important;
}

/* Hero (brand + eyebrow + headline + sub) above the panel */
.de-auth-hero {
  max-width: 420px; margin: 80px auto 18px;
  text-align: center;
}
.de-auth-brand {
  width: 44px; height: 44px; margin: 0 auto 18px;
  border-radius: 12px;
  background: var(--de-grad);
  box-shadow: inset 0 0 0 7px var(--de-bg-0),
              0 8px 22px rgba(94,230,214,.22);
}
.de-auth-eyebrow {
  display: inline-flex; align-items: center; gap: 8px;
  font-size: 10.5px; font-weight: 600; letter-spacing: .14em;
  color: var(--de-cyan); margin-bottom: 8px;
}
.de-auth-eyebrow-chip {
  display: inline-flex; align-items: center; justify-content: center;
  width: 18px; height: 18px; border-radius: 5px;
  background: var(--de-grad); color: #0B1020;
  font-size: 10px; font-weight: 700;
  font-family: "JetBrains Mono", ui-monospace, monospace;
}
.de-auth-headline {
  font-size: 26px; font-weight: 700; letter-spacing: -.01em;
  margin: 0; color: var(--de-text-1);
}
.de-auth-sub {
  margin-top: 6px; color: var(--de-text-3); font-size: 12px;
}

/* shinymanager renders an h3 and a .panel — restyle them as one card */
h3 { display: none !important; }
.panel, .panel-primary {
  background: var(--de-bg-1) !important;
  border: 1px solid var(--de-border) !important;
  border-radius: 14px !important;
  box-shadow: 0 12px 32px rgba(0,0,0,.45) !important;
  color: var(--de-text-1) !important;
  margin: 0 auto !important;
  max-width: 420px;
  overflow: hidden;
}
.panel-heading { display: none !important; }
.panel-body {
  padding: 22px 24px !important;
  background: transparent !important;
}

/* Field labels uppercase */
.panel-body label {
  display: block;
  font-size: 10px !important;
  font-weight: 600 !important;
  letter-spacing: .14em;
  text-transform: uppercase;
  color: var(--de-text-3) !important;
  margin: 14px 0 6px !important;
}
.panel-body label:first-child { margin-top: 0 !important; }

/* Inputs */
.panel-body input.form-control {
  height: 36px !important;
  padding: 0 12px !important;
  background: var(--de-bg-2) !important;
  color: var(--de-text-1) !important;
  border: 1px solid var(--de-border-strong) !important;
  border-radius: 6px !important;
  font-size: 13px !important;
  box-shadow: none !important;
  width: 100% !important;
}
.panel-body input.form-control:focus {
  outline: 2px solid color-mix(in srgb, var(--de-cyan) 60%, transparent);
  outline-offset: -1px;
  border-color: var(--de-cyan) !important;
}

/* Hide the language dropdown that shinymanager renders inside the panel */
.panel-body .selectize-control,
.panel-body .form-group:has(#auth-language) { display: none !important; }

/* Login button — gradient pill, full width inside the card */
#auth-go_auth {
  width: 100% !important;
  height: 40px !important;
  margin-top: 18px !important;
  background: var(--de-grad) !important;
  color: #0B1020 !important;
  border: 0 !important;
  border-radius: 999px !important;
  font-weight: 700 !important;
  font-size: 13.5px !important;
  letter-spacing: .01em;
  box-shadow: 0 4px 14px rgba(94,230,214,.20) !important;
}
#auth-go_auth:hover { filter: brightness(1.05); }

/* Sign-up row below the card */
.de-auth-signup {
  max-width: 420px; margin: 18px auto 0;
  text-align: center;
  color: var(--de-text-2); font-size: 12.5px;
}
.de-auth-signup a {
  color: var(--de-cyan) !important;
  text-decoration: none;
  font-weight: 500;
  margin-left: 4px;
}
.de-auth-signup a:hover { text-decoration: underline; }
.de-auth-signup .fa, .de-auth-signup svg { margin-right: 4px; }

/* Footer keyboard hint */
.de-auth-footer {
  position: fixed; bottom: 16px; right: 16px;
  background: var(--de-bg-1);
  border: 1px solid var(--de-border);
  border-radius: 999px;
  padding: 6px 12px;
  font-size: 11.5px;
  color: var(--de-text-2);
  box-shadow: 0 12px 32px rgba(0,0,0,.45);
}
.de-auth-footer .kbd {
  font-family: "JetBrains Mono", ui-monospace, monospace;
  font-size: 11px; padding: 1px 6px; border-radius: 4px;
  border: 1px solid var(--de-border-strong);
  color: var(--de-text-2);
  background: var(--de-bg-2);
}

/* Any error / message box on auth failure */
.shiny-notification, .alert {
  background: var(--de-bg-1) !important;
  border: 1px solid var(--de-border) !important;
  border-left: 3px solid var(--de-pink) !important;
  border-radius: 10px !important;
  color: var(--de-text-1) !important;
}
'
}

#' Construct the shinymanager auth provider.
#'
#' @param check_credentials_fn function(user, password) -> list with
#'   `result` (TRUE/FALSE) and optional `user_info` per shinymanager's
#'   contract. Defaults to a function that always denies.
#' @keywords internal
#' @noRd
shinymanager_auth_provider <- function(
    check_credentials_fn = function(user, password) list(result = FALSE)) {

  identify <- function(session) {
    if (is.null(session) || is.null(session$userData)) return(NULL)
    # Preferred path: deServer wired secure_server() and stashed the
    # returned reactiveValues here (D2.5 fix). secure_server populates
    # res_auth$user via an observer when shinymanager's login token is
    # validated, so reading it gives the live authenticated user.
    res_auth <- session$userData$shinymanager_res_auth
    if (!is.null(res_auth)) {
      u <- tryCatch(shiny::isolate(res_auth$user),
                    error = function(e) NULL)
      if (!is.null(u) && length(u) == 1L && nzchar(as.character(u))) {
        return(as.character(u))
      }
    }
    # Legacy / fallback path: test scaffolding writes
    # session$userData$user directly. Keep it working for unit tests
    # that don't spin up secure_server.
    u <- session$userData$user
    if (is.null(u) || is.null(u$user)) return(NULL)
    as.character(u$user)
  }

  wrap_app <- function(app) {
    if (!requireNamespace("shinymanager", quietly = TRUE)) {
      # Graceful degradation when the Suggests dep isn't installed:
      # return the app un-wrapped. The chain falls through to
      # local_anonymous_provider in this case.
      return(app)
    }
    # head_auth surfaces a Sign-up link ABOVE the login form so users
    # who land on a shared bookmark URL can create an account without
    # admin help. The link is wired by an observer in deServer.
    shinymanager::secure_app(
      app,
      check_credentials = check_credentials_fn,
      fab_position = "none",
      # B3.6 — auth screen redesign. shinymanager renders its own login
      # panel BEFORE deUI() runs, so the main `debrowser.css` isn't
      # loaded yet. We inline a self-contained style sheet here that
      # repaints shinymanager's panel as the same dark navy + cyan/violet
      # card the rest of the app uses, then prepend a brand mark +
      # eyebrow + headline above the panel.
      head_auth = shiny::tagList(
        shiny::tags$link(
          rel = "stylesheet",
          href = "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap"
        ),
        shiny::tags$style(htmltools::HTML(de_auth_styles())),
        # Brand mark + eyebrow + headline above the shinymanager panel.
        shiny::tags$div(
          class = "de-auth-hero",
          shiny::tags$div(class = "de-auth-brand"),
          shiny::tags$div(
            class = "de-auth-eyebrow",
            shiny::tags$span(class = "de-auth-eyebrow-chip", "0"),
            "SIGN IN"
          ),
          shiny::tags$h1(class = "de-auth-headline", "Welcome back."),
          shiny::tags$div(class = "de-auth-sub",
                          "DEBrowser v", getNamespaceVersion("debrowser"))
        ),
        # Sign-up link below the panel
        shiny::tags$div(
          class = "de-auth-signup",
          shiny::tags$span("Don't have an account? "),
          shiny::actionLink(
            inputId = "open_signup_from_login",
            label = "Sign up",
            icon = shiny::icon("user-plus")
          )
        ),
        # Footer keyboard hint
        shiny::tags$div(
          class = "de-auth-footer",
          shiny::tags$span(class = "kbd", "Enter"),
          " to sign in"
        )
      )
    )
  }

  logout <- function(session) {
    if (!is.null(session) && !is.null(session$userData)) {
      session$userData$user <- NULL
    }
    invisible(NULL)
  }

  user_info <- function(user_id) {
    if (is.null(user_id) || length(user_id) != 1L ||
        is.na(user_id) || !nzchar(user_id)) {
      return(list(kind = "shinymanager",
                  display_name = NA_character_,
                  email = NA_character_))
    }
    list(kind = "shinymanager",
         display_name = as.character(user_id),
         email = NA_character_)
  }

  new_auth_provider(
    name = "shinymanager",
    identify = identify,
    wrap_app = wrap_app,
    logout = logout,
    user_info = user_info
  )
}

#' Construct the check_credentials function passed to
#' [shinymanager::secure_app()].
#'
#' Consults `users.sqlite` (D2.1) — only rows with `kind = 'shinymanager'`
#' may authenticate via this path. OIDC/header users authenticate
#' through their respective providers' identify().
#'
#' @param db_path Optional override of the user_db path. Defaults to
#'   `user_db_path()`. Useful for tests.
#' @return A function `function(user, password)` returning a list with
#'   `result` (TRUE/FALSE) per shinymanager's contract.
#' @keywords internal
#' @noRd
shinymanager_check_credentials_fn <- function(db_path = NULL) {
  function(user, password) {
    deny <- list(result = FALSE)
    if (is.null(user) || is.null(password)) return(deny)
    if (!nzchar(user) || !nzchar(password)) return(deny)

    con <- tryCatch(
      {
        if (is.null(db_path)) user_db_connect() else {
          require_pkg("RSQLite", feature = "user database")
          c <- DBI::dbConnect(RSQLite::SQLite(), db_path)
          DBI::dbExecute(c, "PRAGMA foreign_keys = ON")
          user_db_migrate(c)
          c
        }
      },
      error = function(e) NULL
    )
    if (is.null(con)) return(deny)
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    row <- tryCatch(user_db_get_user(con, user), error = function(e) NULL)
    if (is.null(row)) return(deny)
    if (!identical(row$kind, "shinymanager")) return(deny)
    if (!verify_password(password, row$hashed_pw)) return(deny)

    user_db_update_login(con, user)
    list(result = TRUE,
         user_info = list(user = user))
  }
}
