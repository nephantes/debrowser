#' deServer
#'
#' Sets up shinyServer to be able to run DEBrowser interactively.
#'
#' @note \code{deServer}
#' @param input, input params from UI
#' @param output, output params to UI
#' @param session, session variable
#' @return the panel for main plots;
#'
#' @examples
#' deServer
#'
#' @export
#' @importFrom shiny actionButton actionLink addResourcePath column conditionalPanel downloadButton downloadHandler eventReactive fileInput fluidPage helpText isolate mainPanel need numericInput observe observeEvent outputOptions parseQueryString plotOutput radioButtons reactive reactiveValues renderPlot renderUI runApp selectInput shinyApp shinyServer shinyUI sidebarLayout sidebarPanel sliderInput stopApp tabPanel tabsetPanel textInput textOutput titlePanel uiOutput tags HTML h4 img icon updateNumericInput updateTabsetPanel updateTextInput validate wellPanel checkboxInput br p checkboxGroupInput onRestore reactiveValuesToList renderText onBookmark onBookmarked updateQueryString enableBookmarking htmlOutput onRestored NS reactiveVal withProgress tableOutput selectizeInput fluidRow div renderPrint renderImage verbatimTextOutput imageOutput renderTable incProgress a h3 strong h2 withMathJax updateCheckboxInput showNotification updateSelectInput moduleServer showModal modalDialog modalButton tagList req span updateRadioButtons setBookmarkExclude
#' @importFrom shinyjs show hide enable disable useShinyjs extendShinyjs js inlineCSS onclick
#' @importFrom DT datatable dataTableOutput renderDataTable formatStyle styleInterval formatRound
#' @importFrom ggplot2 aes geom_bar geom_point ggplot labs scale_x_discrete scale_y_discrete ylab autoplot theme_minimal theme geom_density geom_text element_blank margin facet_grid
#' @importFrom plotly renderPlotly plotlyOutput plot_ly add_bars event_data hide_legend %>% group_by ggplotly config
#' @importFrom gplots heatmap.2 redblue bluered
#' @importFrom igraph layout.kamada.kawai
#' @importFrom grDevices dev.off pdf colorRampPalette
#' @importFrom graphics barplot hist pairs par rect text plot
#' @importFrom stats aggregate as.dist cor cor.test dist hclust kmeans na.omit prcomp var sd model.matrix p.adjust runif cov mahalanobis quantile as.dendrogram density as.formula coef
#' @importFrom utils read.csv read.table write.table update.packages download.file read.delim data install.packages packageDescription installed.packages modifyList
#' @importMethodsFrom AnnotationDbi as.data.frame as.list colnames exists sample subset head mappedkeys ncol nrow subset keys mapIds select
#' @importMethodsFrom GenomicRanges as.factor setdiff
#' @importMethodsFrom IRanges as.matrix "colnames<-" mean nchar paste rownames toupper unique which as.matrix lapply "rownames<-" gsub
#' @importMethodsFrom S4Vectors eval grep grepl levels sapply t
#' @importMethodsFrom SummarizedExperiment cbind order rbind
#' @importFrom jsonlite fromJSON
#' @importFrom methods new is
#' @importFrom stringi stri_rand_strings
#' @importFrom annotate geneSymbols
#' @importFrom reshape2 melt
#' @importFrom clusterProfiler compareCluster enrichKEGG enrichGO gseGO bitr
#' @importFrom DESeq2 DESeq DESeqDataSetFromMatrix results estimateSizeFactors counts lfcShrink
#' @importFrom edgeR calcNormFactors equalizeLibSizes DGEList glmLRT exactTest estimateCommonDisp glmFit topTags
#' @importFrom limma lmFit voom eBayes topTable
#' @importFrom sva ComBat
#' @importFrom RCurl getURL
#' @import org.Hs.eg.db
#' @import shinyBS
#' @import colourpicker
#' @import RColorBrewer
#' @import heatmaply

deServer <- function(input, output, session) {
  options(warn = -1)

  # D2.3: enableBookmarking + options(shiny.bookmarkStore) MOVED to
  # startShiny.R -- they must be set BEFORE shinyApp() is constructed,
  # not per-session, or Shiny writes bookmarks to the cwd instead of
  # data_dir(). setBookmarkExclude is per-session and stays here.

  # SECURITY-CRITICAL: never put AI keys / file-input handles /
  # button counters into bookmark state. setBookmarkExclude is the
  # primary mechanism; redact_for_bookmark() in R/fct_bookmark_state.R
  # is the defense-in-depth pass.
  setBookmarkExclude(c(
    # AI namespace -- entire E12.A inputs surface. Audited against
    # actual ns() IDs in mod_ai_settings.R + mod_ai_interpret.R.
    "ai_settings-enabled", "ai_settings-provider",
    "ai_settings-model", "ai_settings-api_key",
    "ai_settings-default_privacy", "ai_settings-save_settings",
    "ai_settings-test_provider", "ai_settings-refresh_models",
    "ai_settings-open_ai_modal",
    "ai_enrichment-ask", "ai_enrichment-question",
    "ai_enrichment-privacy", "ai_enrichment-top_n",
    # File-input handles (datapaths are per-session-tmp)
    "load-countdata", "load-metadata",
    "fgsea_gmt-manual_gmt",
    # Action-button counters (would re-fire side effects on restore).
    # Module-namespaced IDs first; deServer top-level IDs after.
    "load-uploadFile", "load-demo", "load-demo2",
    "lcf-submitLCF", "batcheffect-submitBatchEffect",
    "fgsea_gmt-msigdb_load",
    "cs-startDE", "cs-add_btn", "cs-rm_btn",
    "startDE", "Filter", "Batch", "goDE",
    "goDEFromFilter", "goMain", "goQCplots",
    "goQCplotsFromFilter", "resetsamples",
    "startGO",
    # D2.5 fix: the Bookmark navbar button must not round-trip its
    # click-count or restoring a bookmark fires session$doBookmark()
    # on session start, creating a NEW bookmark instead of restoring.
    "bookmark_share",
    # account dropdown buttons -- same pattern, prevents login/signup
    # observers from re-firing on restore.
    "account-signup_link", "account-signout",
    "account-signup_submit", "account-my_bookmarks",
    "open_signup_from_login", "login_signup_submit",
    # D2.5 fix: bslib page_navbar / navset_hidden tab selections.
    # Shiny's built-in input-restore sends these as client-side input
    # updates BEFORE the DOM is fully ready, which causes the JS
    # shiny-change-tab-visibility handler to throw "There is no
    # tabsetPanel with id equal to 'methodtabs'". Tab state is
    # managed by server-side togglePanels() / nav_select() observers
    # after data is loaded, so restoring them from bookmark input is
    # both redundant and timing-unsafe.
    "methodtabs", "DataPrep",
    # D2.5 fix: shinymanager-owned login inputs. These belong to the
    # login form mounted by `secure_app` and must NOT be bookmarked,
    # otherwise on restore shinymanager re-binds a second copy and we
    # get "Duplicate input ID - shinymanager_language: 2 inputs", and
    # the login form re-renders on top of the restored session.
    "auth-user_id", "auth-user_pwd", "auth-go_auth",
    "auth-keep_logged", "auth-resetpwd", "auth-cancel_resetpwd",
    "shinymanager_language", "shinymanager_loglout",
    "shinymanager_admin", "shinymanager_pwd_three",
    "shinymanager_where"
  ))

  # D2.5 fix: shinymanager requires BOTH secure_app (UI wrap) AND
  # secure_server (server handler). Without secure_server, the login
  # form has no submit handler. Wire it here in hosted-no-proxies mode.
  # The returned reactiveValues holds the authenticated user info; we
  # stash it in session$userData so shinymanager_auth_provider$identify
  # can read it.
  if (hosted_mode() &&
      length(getOption("debrowser.trusted_proxies", character(0))) == 0L &&
      requireNamespace("shinymanager", quietly = TRUE)) {
    # D2.5 fix: shinymanager session lifetime.
    # `timeout` is the inactivity-logout window in MINUTES. We set a
    # full week so users don't get bounced back to the login wall
    # mid-analysis. `keep_token = TRUE` preserves the
    # `?_state_id_=...` URL during the auth round-trip so bookmark
    # restore continues to work in the post-auth session.
    #
    # NOTE on persistent cross-restart cookies: shinymanager 1.0.410
    # (the version we depend on) does NOT expose a `cookie_validity`
    # parameter on `secure_server` — passing one is a fatal
    # "unused argument" error that blocks login entirely. Until
    # upstream shinymanager ships native persistent-cookie support
    # (or DEBrowser implements its own remember-me cookie layer in
    # D2.6+), the user is required to re-authenticate after closing
    # the browser. Within a single browser session, the long timeout
    # below keeps them logged in.
    res_auth <- shinymanager::secure_server(
      check_credentials = shinymanager_check_credentials_fn(),
      keep_token        = TRUE,
      timeout           = 60 * 24 * 7    # 7 days of in-session inactivity
    )
    session$userData$shinymanager_res_auth <- res_auth
    # Clear stale auth cache when the authenticated user changes
    # (login/logout flips res_auth$user). This unmemoizes
    # current_user(session) so the navbar reflects the live state.
    shiny::observe({
      u <- res_auth$user
      invalidate_user_cache(session)
    })

    # Sign-up flow accessible from the login screen (head_auth on
    # secure_app surfaces a "Sign up" link). Observers fire even while
    # the user is unauthenticated because the login screen is part of
    # the same Shiny session.
    shiny::observeEvent(input$open_signup_from_login, {
      shiny::showModal(shiny::modalDialog(
        title = "Sign up",
        shiny::tagList(
          shiny::textInput("login_signup_user", "Username"),
          shiny::textInput("login_signup_email", "Email (optional)"),
          shiny::passwordInput("login_signup_pw",
                               "Password (8+ chars)"),
          shiny::passwordInput("login_signup_pw2", "Confirm password")
        ),
        footer = shiny::tagList(
          shiny::modalButton("Cancel"),
          shiny::actionButton("login_signup_submit",
                              "Create account",
                              class = "btn-primary")
        )
      ))
    }, ignoreInit = TRUE)

    shiny::observeEvent(input$login_signup_submit, {
      err <- validate_signup_input(
        user_id = input$login_signup_user,
        email = input$login_signup_email,
        password = input$login_signup_pw,
        password_confirm = input$login_signup_pw2
      )
      if (!is.null(err)) {
        shiny::showNotification(err, type = "error", duration = 6)
        return()
      }
      con2 <- tryCatch(user_db_connect(), error = function(e) NULL)
      if (is.null(con2)) {
        shiny::showNotification("User database is unavailable.",
                                type = "error", duration = 6)
        return()
      }
      on.exit(DBI::dbDisconnect(con2), add = TRUE)
      ok <- tryCatch({
        signup_user(con2, input$login_signup_user,
                    input$login_signup_email,
                    input$login_signup_pw)
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
          "Account created. Please sign in with your credentials.",
          type = "message", duration = 8
        )
      }
    }, ignoreInit = TRUE)
  }

  onBookmark(function(state) {
    # Stamp the package version so onRestore can do a compat check.
    state$values$debrowser_version <-
      as.character(utils::packageVersion("debrowser"))
    # Resolve and stamp the user_id so onBookmarked can insert the
    # ownership row even if the auth chain re-resolves later.
    state$values$user_id <- current_user(session)

    # D2.5 fix Issue 1: snapshot the DE result container `dc()` so the
    # restored session shows DE results IMMEDIATELY without re-running
    # DESeq2 / EdgeR / Limma. Previously the bookmark only captured
    # `comparisons_spec` and the auto-replay observer re-ran DE from
    # scratch on every restore -- a 30-60s wait for medium datasets and
    # a 5+ minute wait for large ones. Snapshotting dc() here makes
    # restore as fast as `loadRDS` of the cached results.
    #
    # `dc()` is a list of comparison containers, each with:
    #   conds, cols, cond_names, init_data (DESeq2 result frame),
    #   demethod_params, dds (DESeq2 DESeqDataSet S4 object).
    # All elements are saveRDS-friendly. dds is the heaviest (~1-10MB
    # for typical data) but is needed by post-DE QC cards (Dispersion,
    # SizeFactors, Cook's) so we preserve it.
    current_dc <- tryCatch(shiny::isolate(dc()),
                           error = function(e) NULL)
    if (!is.null(current_dc) && length(current_dc) > 0L) {
      state$values$dc_data <- current_dc
    }
  })

  # D2.5 fix: track the most-recently-created bookmark's state_id so
  # the share modal's visibility radio can update its row in users.sqlite.
  # A reactiveVal lets a single deServer-level observer drive every
  # modal instance instead of registering N observers (one per bookmark).
  active_share_state_id <- shiny::reactiveVal(NULL)

  # D2.5 fix Bug C: DE auto-replay on bookmark restore. The bookmark
  # protocol saves `input$*` and `values$*` but NOT the DE result
  # container `dc()` -- so a freshly-restored session lands on Data Prep
  # with no plots until the user clicks through Filter -> Batch -> goDE
  # -> Submit again. Auto-replay closes that gap: when onRestore detects
  # a saved comparisons_spec, this rv holds it; an observer below
  # fast-forwards the wizard (Filter -> setBatch -> condSelect -> DE)
  # programmatically once the data has finished loading.
  pending_de_replay <- shiny::reactiveVal(NULL)
  # D2.5 fix Issue 1: cached dc() captured by onBookmark. When non-NULL,
  # the auto-replay observer SKIPS prepDataContainer entirely and
  # plugs the saved dc straight into `dc(<cached>)` -- restoring DE
  # results without recomputing DESeq2 / EdgeR / Limma.
  pending_dc_restore <- shiny::reactiveVal(NULL)

  # D2.5 fix: in-flight flag for the Bookmark navbar button. dc_data
  # serialization is slow (several seconds for typical data); without
  # this, users clicked the button multiple times during the save and
  # got duplicate bookmarks at the same timepoint. Reset by the
  # onBookmarked handler below. Hoisted up here so onBookmarked can
  # see the symbol.
  .bookmark_in_progress <- shiny::reactiveVal(FALSE)

  onBookmarked(function(url) {
    # state_id is the last path segment of the bookmark URL.
    # Shiny constructs URLs like:
    #   <base>?_state_id_=<id>
    state_id <- sub(".*_state_id_=", "", url)
    if (!nzchar(state_id) || state_id == url) {
      # URL has no _state_id_ -- nothing to track. Surface anyway.
      showNotification(paste("Bookmark URL:", url),
                       duration = NULL, type = "message")
      # D2.5 fix: clear in-flight flag on early return too.
      shiny::removeNotification("debrowser_bookmark_progress")
      tryCatch(shinyjs::enable("bookmark_share"),
               error = function(e) NULL)
      .bookmark_in_progress(FALSE)
      return()
    }
    user_id <- current_user(session)
    if (is.na(user_id) || is.null(user_id)) user_id <- "local"
    con <- tryCatch(user_db_connect(), error = function(e) NULL)
    if (!is.null(con)) {
      on.exit(DBI::dbDisconnect(con), add = TRUE)
      # Idempotent: re-bookmarking with the same content yields a
      # different state_id, so this is always an INSERT not an UPSERT.
      # Use tryCatch because the user row may not exist yet in
      # non-hosted mode (we only insert "local" lazily when bookmarked).
      tryCatch(
        user_db_bookmark_insert(con, state_id, user_id,
                                visibility = "private",
                                label = NA_character_),
        error = function(e) {
          # Auto-provision the implicit user row, then retry.
          # The FK from bookmarks.user_id requires a users row.
          tryCatch({
            user_db_create_user(con, user_id,
                                kind = if (identical(user_id, "local"))
                                         "local" else "header")
          }, error = function(e2) NULL)
          tryCatch(user_db_bookmark_insert(con, state_id, user_id,
                                           visibility = "private",
                                           label = NA_character_),
                   error = function(e3) NULL)
        }
      )
    }
    # Remember the state_id for the visibility-toggle observer below.
    active_share_state_id(state_id)
    # In hosted mode, expose the visibility toggle so users can mark
    # bookmarks as link-shareable for recipients to open after signup.
    showModal(modalDialog(
      title = "Bookmark created",
      build_share_modal_ui(url,
                           can_toggle = hosted_mode(),
                           current_visibility = "private"),
      easyClose = TRUE,
      footer = modalButton("Close")
    ))
    # D2.5 fix: clear the in-flight flag NOW (modal up = save done) so
    # the user can take a second bookmark if they want.
    shiny::removeNotification("debrowser_bookmark_progress")
    tryCatch(shinyjs::enable("bookmark_share"),
             error = function(e) NULL)
    .bookmark_in_progress(FALSE)
  })

  # Auto-save visibility radio changes to users.sqlite. Fires whenever
  # the user toggles Private <-> Shared via link in the share modal.
  shiny::observeEvent(input$bookmark_share_visibility, {
    state_id <- active_share_state_id()
    if (is.null(state_id) || !nzchar(state_id)) return()
    new_vis <- input$bookmark_share_visibility
    if (!new_vis %in% c("private", "link")) return()
    con <- tryCatch(user_db_connect(), error = function(e) NULL)
    if (is.null(con)) return()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    tryCatch(
      user_db_bookmark_set_visibility(con, state_id, new_vis),
      error = function(e) NULL
    )
    showNotification(
      sprintf("Bookmark visibility set to %s.",
              if (identical(new_vis, "link"))
                "Shared via link" else "Private"),
      type = "message",
      duration = 4
    )
  }, ignoreInit = TRUE)

  # Auto-save label edits in the share modal. Debounced so we don't
  # write a row to the DB on every keystroke.
  shiny::observeEvent(input$bookmark_share_label, {
    state_id <- active_share_state_id()
    if (is.null(state_id) || !nzchar(state_id)) return()
    con <- tryCatch(user_db_connect(), error = function(e) NULL)
    if (is.null(con)) return()
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    tryCatch(
      user_db_bookmark_set_label(con, state_id, input$bookmark_share_label),
      error = function(e) NULL
    )
  }, ignoreInit = TRUE)

  onRestore(function(state) {
    # D2.5 unconditional restore-side hygiene. Everything in this block
    # MUST run on every onRestore call (including post-auth shinymanager
    # sessions whose URL keeps `?token=...` for the entire session).
    # Earlier versions of this file gated the cs-cs capture and
    # redact_for_bookmark behind the `token=` early-return below -- that
    # silently skipped DE auto-replay for hosted-mode users.

    # CRITICAL: assign back. state$input / state$values are LISTS in
    # production (subagent E2E confirmed `class=list, length=279`),
    # NOT environments as earlier comments claimed. The list branch of
    # both helpers returns a NEW filtered list -- discarding the return
    # value (the previous bug) made these calls no-ops.
    if (!is.null(state$input)) {
      state$input <- strip_unrestorable_inputs(state$input)
      state$input <- redact_for_bookmark(state$input)
    }
    if (!is.null(state$values)) {
      state$values <- redact_for_bookmark(state$values)
    }

    # D2.5 Bug C: capture restored comparisons_spec for DE auto-replay.
    # Done HERE (before the token guard) so it runs in the post-auth
    # shinymanager session that actually applies the restored state.
    # state$values[["cs-cs"]] is what mod_condselect's onBookmark wrote
    # (Shiny namespaces module values as "<parent_ns>-<module_id>").
    # We capture the spec at top level so the auto-replay observer
    # downstream can call prepDataContainer directly without depending
    # on the cs module being mounted at restore time.
    cs_state <- tryCatch(state$values[["cs-cs"]],
                         error = function(e) NULL)
    if (!is.null(cs_state) && !is.null(cs_state$comparisons_spec) &&
        length(cs_state$comparisons_spec) > 0L) {
      pending_de_replay(cs_state$comparisons_spec)
    }
    # D2.5 Issue 1: capture cached dc() for direct restore. When
    # present, the auto-replay observer skips the prepDataContainer
    # call and plugs this straight into `dc()`.
    saved_dc <- tryCatch(state$values$dc_data,
                         error = function(e) NULL)
    if (!is.null(saved_dc) && length(saved_dc) > 0L) {
      pending_dc_restore(saved_dc)
    }

    # Authorization gate. Unknown / private-non-owner bookmarks
    # raise `bookmark_denied`; surface and abort.
    url_query <- shiny::parseQueryString(
      session$clientData$url_search %||% "")
    state_id <- url_query[["_state_id_"]]
    if (is.null(state_id) || !nzchar(state_id)) return(invisible())

    # D2.5 fix: when shinymanager has issued a session token, defer the
    # authz check. Two cases share this URL shape:
    #   (a) auth IS mid-flight -- secure_server hasn't populated res_auth$user
    #       yet, so current_user() reads "local" and authz would wrongly deny.
    #   (b) auth completed -- shinymanager keeps `token=...` in the URL for
    #       the whole post-auth session lifetime.
    # Either way, secure_server is the authoritative auth boundary: if the
    # token is invalid the user never gets past the login wall. So skipping
    # the secondary authz gate when a token is present is safe in both cases.
    if (!is.null(url_query[["token"]]) && nzchar(url_query[["token"]])) {
      # Still do the version-compat check -- it's user-facing UX, not a
      # security boundary.
      saved <- state$values$debrowser_version
      current <- as.character(utils::packageVersion("debrowser"))
      compat <- is_safe_to_restore(saved, current)
      if (!identical(compat, "safe")) {
        showModal(modalDialog(
          title = if (compat == "warn")
            "Bookmark from a different minor version"
          else "Bookmark from a different major version",
          tagList(
            div(class = "alert alert-warning",
                sprintf("This bookmark was made with debrowser %s; you're running %s.",
                        saved %||% "(unknown)", current)),
            div("The session will still attempt to restore. Some panels may behave unexpectedly.")
          ),
          easyClose = TRUE,
          footer = modalButton("OK")
        ))
      }
      return(invisible())
    }

    viewer <- current_user(session)
    if (is.na(viewer)) viewer <- NULL
    con <- tryCatch(user_db_connect(), error = function(e) NULL)
    if (!is.null(con)) {
      on.exit(DBI::dbDisconnect(con), add = TRUE)
      tryCatch(
        bookmark_authorize(con, state_id, viewer),
        bookmark_denied = function(cond) {
          showModal(modalDialog(
            title = "Bookmark not accessible",
            tagList(
              div(class = "alert alert-warning",
                  cond$message),
              div("Ask the owner to share the link or enable ",
                  tags$em("Shared via link"), " mode.")
            ),
            easyClose = TRUE,
            footer = modalButton("OK")
          ))
          # Hard-stop restore by clearing state. Branch on type because
          # state$values / state$input are LISTS in production but env
          # in some test paths -- list reassignment via state$X <- list()
          # works for both, while rm() only works on env.
          if (is.environment(state$values)) {
            rm(list = ls(state$values, all.names = TRUE),
               envir = state$values)
          } else {
            state$values <- list()
          }
          if (is.environment(state$input)) {
            rm(list = ls(state$input, all.names = TRUE),
               envir = state$input)
          } else {
            state$input <- list()
          }
          # Also clear the replay flag we may have just set above.
          pending_de_replay(NULL)
          return()
        }
      )
    }

    # Version compatibility check.
    saved <- state$values$debrowser_version
    current <- as.character(utils::packageVersion("debrowser"))
    compat <- is_safe_to_restore(saved, current)
    if (!identical(compat, "safe")) {
      showModal(modalDialog(
        title = if (compat == "warn") "Bookmark from a different minor version"
                else "Bookmark from a different major version",
        tagList(
          div(class = "alert alert-warning",
              sprintf("This bookmark was made with debrowser %s; you're running %s.",
                      saved %||% "(unknown)", current)),
          div("The session will still attempt to restore. Some panels may behave unexpectedly.")
        ),
        easyClose = TRUE,
        footer = modalButton("OK")
      ))
    }
  })

  onRestored(function(state) {
    # No-op for D2.3. D2.4 (account UI) will use this to re-select
    # the bookmarked tab.
  })

  # D2.5 fix: serializing dc() (Issue 1) makes the bookmark save take
  # several seconds for non-trivial datasets (the DESeqDataSet S4 inside
  # dc is large). Without UI feedback the user thought the button broke,
  # clicked multiple times, and got 3 duplicate bookmarks at the same
  # timepoint. Three guards prevent that:
  #   1. .bookmark_in_progress reactiveVal short-circuits subsequent
  #      clicks while one save is in flight.
  #   2. shinyjs::disable greys out the button visually.
  #   3. A persistent notification ("Saving bookmark...") tells the
  #      user the click was received.
  # All three are reset by the onBookmarked callback above (when the
  # share modal opens), guaranteeing the button comes back even on the
  # error/no-state_id path.
  shiny::observeEvent(input$bookmark_share, {
    if (isTRUE(.bookmark_in_progress())) {
      shiny::showNotification(
        "A bookmark save is already in progress -- please wait.",
        type = "warning",
        duration = 4
      )
      return()
    }
    .bookmark_in_progress(TRUE)
    tryCatch(shinyjs::disable("bookmark_share"),
             error = function(e) NULL)
    shiny::showNotification(
      "Saving bookmark... (this can take several seconds for large analyses)",
      id = "debrowser_bookmark_progress",
      type = "default",
      duration = NULL
    )
    session$doBookmark()
  }, ignoreInit = TRUE)  # critical: prevents auto-bookmark on restore

  tryCatch(
    {
      if (!interactive()) {
        options(
          shiny.maxRequestSize = 30 * 1024^2,
          shiny.fullstacktrace = FALSE, shiny.trace = FALSE,
          shiny.autoreload = TRUE, warn = -1
        )
      }
      # To hide the panels from 1 to 4 and only show Data Prep
      togglePanels(0, c(0), session)

      choicecounter <- reactiveValues(nc = 0)

      # B2a: progress reactiveValues drives the wizard pill / Data Prep tab
      # icon decoration. Tab visibility is still managed by togglePanels()
      # in R/uifuncs.R; this is icon state only.
      # State enum per key: pending | done | locked | skipped | "" (blank)
      progress <- reactiveValues(
        upload     = "pending",
        filter     = "locked",
        batch      = "skipped",   # batch is optional; default to skipped
        condselect = "locked",
        de         = "locked"
      )

      # Broadcast every progress field on any change. Also derives the
      # Data Prep outer tab's "data_prep" key (done iff DE is done).
      observe({
        update_progress(session, "upload",     progress$upload)
        update_progress(session, "filter",     progress$filter)
        update_progress(session, "batch",      progress$batch)
        update_progress(session, "condselect", progress$condselect)
        update_progress(session, "de",         progress$de)
        update_progress(
          session, "data_prep",
          if (progress$de == "done") "done" else ""
        )
      })

      output$programtitle <- renderUI({
        togglePanels(0, c(0), session)
        getProgramTitle(session)
      })

      updata <- reactiveVal()
      filtd <- reactiveVal()
      batch <- reactiveVal()
      sel <- reactiveVal()
      dc <- reactiveVal()
      # D2.5 fix Bug C: hoisted up from below so the auto-replay observer
      # below can flip buttonValues$startDE without forward-reference issues.
      buttonValues <- reactiveValues(
        goQCplots = FALSE, goDE = FALSE,
        startDE = FALSE
      )
      compsel <- reactive({
        cp <- 1
        if (!is.null(input$compselect_dataprep)) {
          cp <- input$compselect_dataprep
        }
        cp
      })

      # D2.5 fix Bug C: DE auto-replay state machine.
      # When onRestore captured a comparisons_spec into pending_de_replay,
      # this observer fast-forwards the wizard programmatically once the
      # data has loaded. Each reactive flush moves one step forward:
      #   updata loaded -> filtd built -> batch built -> sel built ->
      #   prepDataContainer with spec_to_replay -> dc set -> Main Plots.
      #
      # The observer guards against re-firing by clearing pending_de_replay
      # only after dc is set; intermediate steps return without clearing
      # so subsequent reactive flushes can advance.
      #
      # Diagnostic: each transition emits a message() so the R console
      # shows the auto-replay progress. Search server logs for "[D2.5
      # auto-replay]" to trace.
      .ar_logged <- shiny::reactiveValues(
        seen_replay = FALSE, seen_data = FALSE,
        seen_filt = FALSE, seen_batch = FALSE, seen_sel = FALSE
      )
      observe({
        spec_to_replay <- pending_de_replay()
        cached_dc      <- pending_dc_restore()
        # No replay needed unless one of the two replay flags is set.
        if ((is.null(spec_to_replay) || length(spec_to_replay) == 0L) &&
            is.null(cached_dc)) {
          return()
        }
        if (!isTRUE(.ar_logged$seen_replay)) {
          if (!is.null(cached_dc)) {
            message(sprintf("[D2.5 restore] cached dc available (%d comparison(s)); will plug directly without re-running DE",
                            length(cached_dc)))
          } else {
            message(sprintf("[D2.5 restore] pending_de_replay set; %d comparison(s) to restore (DE WILL re-run)",
                            length(spec_to_replay)))
          }
          .ar_logged$seen_replay <- TRUE
        }
        # Wait for data load (mod_dataLoad onRestore branch sets ldata).
        load_d <- tryCatch(updata()$load(), error = function(e) NULL)
        if (is.null(load_d) || is.null(load_d$count)) return()
        if (!isTRUE(.ar_logged$seen_data)) {
          message(sprintf("[D2.5 restore] data loaded: %d genes x %d samples (source=%s)",
                          nrow(load_d$count), ncol(load_d$count),
                          load_d$data_source %||% "?"))
          .ar_logged$seen_data <- TRUE
        }
        # Step 1: build the lcf module (auto-applies default Max<10 filter
        # via the B3.5 init_done observe inside debrowserlowcountfilter).
        if (is.null(filtd())) {
          message("[D2.5 restore] step 1: mounting lcf module")
          filtd(debrowserlowcountfilter("lcf", updata()$load()))
          return()
        }
        fd <- tryCatch(filtd()$filter(), error = function(e) NULL)
        if (is.null(fd) || is.null(fd$count)) return()
        if (!isTRUE(.ar_logged$seen_filt)) {
          message(sprintf("[D2.5 restore] filter done: %d genes after filter",
                          nrow(fd$count)))
          .ar_logged$seen_filt <- TRUE
        }
        # Step 2: skip batch effect, pass filtered data straight through.
        if (is.null(batch())) {
          message("[D2.5 restore] step 2: setBatch (skip batch effect)")
          batch(setBatch(filtd()))
          return()
        }
        bd <- tryCatch(batch()$BatchEffect(), error = function(e) NULL)
        if (is.null(bd) || is.null(bd$count)) return()
        if (!isTRUE(.ar_logged$seen_batch)) {
          message("[D2.5 restore] batch ready")
          .ar_logged$seen_batch <- TRUE
        }
        # Step 3: build sel by mounting condSelectServer with the
        # captured spec as `initial_spec`. This is the key fix: Shiny's
        # built-in module-onRestore mechanism is INACTIVE by the time
        # this observer fires (the active-restore window closed during
        # session init). Passing the spec explicitly via initial_spec
        # bypasses that mechanism and populates the cs module's
        # `comparisons` reactiveValues directly so the wizard cards
        # render with the restored treatment/control selections.
        if (is.null(sel())) {
          message(sprintf("[D2.5 restore] step 3: mounting condSelect with %d initial spec(s)",
                          length(spec_to_replay)))
          sel(condSelectServer("cs", bd$count, bd$meta,
                               initial_spec = spec_to_replay))
          choicecounter$nc <- sel()$n_comparisons()
          return()
        }
        if (!isTRUE(.ar_logged$seen_sel)) {
          message("[D2.5 restore] sel ready")
          .ar_logged$seen_sel <- TRUE
        }
        # Step 4: populate dc(). Two paths:
        #   FAST PATH (Issue 1 fix): if onRestore captured a saved
        #     dc_data from the bookmark, plug it directly into dc().
        #     This is the normal path post-fix -- no DE recomputation,
        #     restore is instantaneous.
        #   FALLBACK: if cached_dc is missing (e.g. bookmark was made
        #     before Issue 1 was introduced, or dc_data failed to
        #     deserialize), re-run DE with the captured spec_to_replay.
        dc_res <- NULL
        if (!is.null(cached_dc)) {
          message(sprintf("[D2.5 restore] step 4 FAST PATH: plugging cached dc (%d entries) -- no DE re-run",
                          length(cached_dc)))
          # Consume both flags; we're done.
          pending_dc_restore(NULL)
          pending_de_replay(NULL)
          dc_res <- cached_dc
        } else {
          message(sprintf("[D2.5 restore] step 4 FALLBACK: prepDataContainer with %d spec(s)",
                          length(spec_to_replay)))
          # Consume the replay flag FIRST so any error inside
          # prepDataContainer doesn't loop forever.
          pending_de_replay(NULL)
          dc_res <- tryCatch(
            prepDataContainer(bd$count, bd$meta, spec_to_replay),
            error = function(e) {
              message(sprintf("[D2.5 restore] prepDataContainer FAILED: %s",
                              conditionMessage(e)))
              shiny::showNotification(
                sprintf("Auto-replay of bookmarked DE failed: %s",
                        conditionMessage(e)),
                type = "error", duration = 12
              )
              NULL
            }
          )
        }
        if (!is.null(dc_res)) {
          message(sprintf("[D2.5 restore] DE container ready: dc has %d entries",
                          length(dc_res)))
          dc(dc_res)
          progress$upload     <- "done"
          progress$filter     <- "done"
          progress$batch      <- "skipped"
          progress$condselect <- "done"
          progress$de         <- "done"
          buttonValues$startDE <- TRUE
          togglePanels(1, c(0, 1, 2, 3, 4), session)
          bslib::nav_select("methodtabs", selected = "panel1",
                            session = session)
          shiny::showNotification(
            "Bookmarked analysis restored. DE results are in Main Plots.",
            type = "message", duration = 8
          )
        }
      })

      # B1.16: wizard reveal moved entirely to UI-side conditionalPanels
      # in R/ui.R (sidebar's Data Prep section). Each step's actionLink is
      # wrapped in a conditionalPanel keyed on input.<trigger> > 0, so the
      # actionButton click counts (which never decrement) give us natural
      # high-water-mark reveal without server observers.
      #
      # Sidebar nav: 6 actionLinks in the Data Prep section call
      # nav_select on the navset_hidden(id="DataPrep") body.
      observeEvent(input$nav_DataPrep_Intro, {
        bslib::nav_select("DataPrep", "Intro", session = session)
      }, ignoreInit = TRUE)
      observeEvent(input$nav_DataPrep_Upload, {
        bslib::nav_select("DataPrep", "Upload", session = session)
      }, ignoreInit = TRUE)
      observeEvent(input$nav_DataPrep_Filter, {
        bslib::nav_select("DataPrep", "Filter", session = session)
      }, ignoreInit = TRUE)
      observeEvent(input$nav_DataPrep_BatchEffect, {
        bslib::nav_select("DataPrep", "BatchEffect", session = session)
      }, ignoreInit = TRUE)
      observeEvent(input$nav_DataPrep_CondSelect, {
        bslib::nav_select("DataPrep", "CondSelect", session = session)
      }, ignoreInit = TRUE)
      observeEvent(input$nav_DataPrep_DEAnalysis, {
        bslib::nav_select("DataPrep", "DEAnalysis", session = session)
      }, ignoreInit = TRUE)

      # Auto-advance the wizard when the user clicks a Submit/Start
      # button. (Previously these observers also called nav_show/nav_hide
      # on the now-replaced navset_pill_list; with navset_hidden those
      # are no-ops.) startDE / cs-startDE -- both ids exist post-A4ac.
      observeEvent(input$startDE, {
        bslib::nav_select("DataPrep", "DEAnalysis", session = session)
      }, ignoreInit = TRUE)
      observeEvent(input[["cs-startDE"]], {
        bslib::nav_select("DataPrep", "DEAnalysis", session = session)
      }, ignoreInit = TRUE)

      # D2.3 fix: debrowserdataload MUST be called synchronously here,
      # before the first reactive flush, so that session$makeScope("load")
      # registers its onRestore bridge on the parent session BEFORE
      # Shiny's high-priority (priority=1e6) restore observe fires.
      # If called inside observe() (priority 0), the restore observe runs
      # first and the dataLoad module's onRestore callback is never invoked,
      # resulting in an empty app after bookmark restore.
      updata(debrowserdataload("load", "Filter"))

      observe({
        # D2.5 noise fix: skip pre-auth (Token A). The DataPrep navset
        # is inside deUI which isn't mounted while shinymanager's
        # login wall is showing -- the nav_select message would error
        # client-side. Post-auth (Token B) shinymanager triggers a
        # session reload and this observe re-fires.
        if (auth_complete(session)) {
          bslib::nav_select("DataPrep", "Upload", session = session)
        }

        # B2a: when counts arrive, mark upload done and unlock filter.
        # Also auto-show the QC tab (panel2) so users can inspect raw
        # QC plots without first running DE.
        observeEvent(updata()$load(), {
          if (!is.null(updata()$load())) {
            progress$upload     <- "done"
            progress$filter     <- "pending"
            # B2a.12: re-upload mid-session -- reset downstream pills so
            # stale "done" decorations from a prior run don't carry over
            # onto the new dataset.
            progress$batch      <- "skipped"
            progress$condselect <- "locked"
            progress$de         <- "locked"
            bslib::nav_show("methodtabs", target = "panel2", session = session)
          }
        }, ignoreInit = TRUE)

        observeEvent(input$Filter, {
          if (!is.null(updata()$load())) {
            bslib::nav_select("DataPrep", "Filter", session = session)
            filtd(debrowserlowcountfilter("lcf", updata()$load()))
            # B2a: filter clicked -> mark filter done; unlock batch.
            progress$filter <- "done"
            progress$batch  <- "pending"
          }
        })
        observeEvent(input$Batch, {
          if (!is.null(filtd()$filter())) {
            bslib::nav_select("DataPrep", "BatchEffect", session = session)
            batch(debrowserbatcheffect("batcheffect", filtd()$filter()))
            # B2a: batch step entered -> mark batch done; unlock condselect.
            progress$batch      <- "done"
            progress$condselect <- "pending"
          }
        })

        observeEvent(input$goDEFromFilter, {
          if (is.null(batch())) batch(setBatch(filtd()))
          bslib::nav_select("DataPrep", "CondSelect", session = session)
          sel(condSelectServer(
            "cs",
            batch()$BatchEffect()$count, batch()$BatchEffect()$meta
          ))
          choicecounter$nc <- sel()$n_comparisons()
          # B2a: skipping past Filter+Batch -- mark them done/skipped.
          if (progress$filter != "done") progress$filter <- "done"
          if (progress$batch  == "pending" || progress$batch == "locked") {
            progress$batch <- "skipped"
          }
          progress$condselect <- "pending"
        })
        observeEvent(input$goDE, {
          bslib::nav_select("DataPrep", "CondSelect", session = session)
          sel(condSelectServer(
            "cs",
            batch()$BatchEffect()$count, batch()$BatchEffect()$meta
          ))
          choicecounter$nc <- sel()$n_comparisons()
          # B2a: condselect step entered.
          progress$condselect <- "pending"
        })
        observeEvent(req(sel())$start_de(), {
          if (is.null(batch()$BatchEffect()$count)) return()
          # Guard against double-clicks: a second click while
          # prepDataContainer is still running would reassign dc()
          # mid-render and intermittently leave the scatter plot blank.
          # on.exit() ensures the button isn't left stuck disabled if
          # anything below errors out.
          shinyjs::disable("cs-startDE")
          on.exit(shinyjs::enable("cs-startDE"), add = TRUE)
          # B2a: mark condselect done at this point (the user has
          # clicked start-de, which is the natural exit from the cs step).
          progress$condselect <- "done"
          progress$de         <- "pending"
          # Re-lock plot/GO/Table tabs while DE runs (existing behavior).
          togglePanels(0, c(0, 2), session)
          # B2.5: prepDataContainer rewritten to take a structured
          # comparisons_spec instead of reaching into the module's input
          # rv. We still call it at the parent session so the inner
          # debrowserdeanalysis modules bind to the top-level "DEResultsN"
          # ids that getDEResultsUI() renders.
          dc_res <- prepDataContainer(
            batch()$BatchEffect()$count,
            batch()$BatchEffect()$meta,
            sel()$comparisons_spec()
          )
          if (is.null(dc_res)) return()
          dc(dc_res)
          bslib::nav_select("DataPrep", "DEAnalysis", session = session)
          buttonValues$startDE <- TRUE
          buttonValues$goQCplots <- FALSE
          hideObj(c(
            "load-uploadFile", "load-demo",
            "load-demo2", "goQCplots", "goQCplotsFromFilter"
          ))
          # B2a: DE finished -- mark done, unlock all outer tabs, and
          # auto-navigate to Main Plots (panel1). The existing goMain
          # observer is preserved for back-navigation but no longer
          # required for the golden path.
          progress$de <- "done"
          togglePanels(1, c(0, 1, 2, 3, 4), session)
        })

        observeEvent(input$goMain, {
          bslib::nav_select("methodtabs", "panel1", session = session)
          togglePanels(0, c(0, 1, 2, 3, 4), session)
        })

        output$compselectUI <- renderUI({
          if (!is.null(sel()) && !is.null(sel()$n_comparisons())) {
            getCompSelection("compselect_dataprep", sel()$n_comparisons())
          }
        })

        install_cutoff_preset_observers(input, session)

        cutoff_servers_registered <- reactiveValues()
        output$cutOffUI <- renderUI({
          cutOffSelectionUI(paste0("DEResults", compsel()))
        })
        observeEvent(compsel(), {
          id <- paste0("DEResults", compsel())
          if (is.null(cutoff_servers_registered[[id]])) {
            cutOffSelectionServer(id)
            cutoff_servers_registered[[id]] <- TRUE
          }
        }, ignoreNULL = TRUE)
        # Sidebar uiOutputs live inside the "DEFilter" submenu in ui.R.
        # When that submenu is collapsed, Shiny's default suspend-when-
        # hidden behavior drops the renderUI on the floor and the controls
        # never populate. Force the outputs to stay alive so the moment
        # the user clicks DEFilter to expand, the cutoff + comparison
        # widgets are already rendered.
        outputOptions(output, "cutOffUI", suspendWhenHidden = FALSE)
        outputOptions(output, "compselectUI", suspendWhenHidden = FALSE)
        output$deresUI <- renderUI({
          column(12, getDEResultsUI(paste0("DEResults", compsel())))
        })
      })
      output$mainpanel <- renderUI({
        getMainPanel()
      })
      output$qcpanel <- renderUI({
        getQCPanel(input)
      })
      output$gopanel <- renderUI({
        getGoPanel()
      })
      output$cutoffSelection <- renderUI({
        nc <- 1
        if (!is.null(choicecounter$nc)) nc <- choicecounter$nc
        getCutOffSelection(nc)
      })
      output$downloadSection <- renderUI({
        choices <- c("most-varied", "alldetected")
        if (buttonValues$startDE) {
          choices <- c(
            "up+down", "up", "down",
            "comparisons", "alldetected",
            "most-varied", "selected"
          )
        }
        choices <- c(choices, "searched")
        getDownloadSection(choices)
      })

      output$leftMenu <- renderUI({
        getLeftMenu(input)
      })
      output$loading <- renderUI({
        getLoadingMsg()
      })
      output$logo <- renderUI({
        getLogo()
      })
      output$startup <- renderUI({
        getStartupMsg()
      })
      output$afterload <- renderUI({
        getAfterLoadMsg()
      })
      output$mainmsgs <- renderUI({
        if (is.null(condmsg())) {
          getStartPlotsMsg()
        } else {
          condmsg()
        }
      })
      # D2.5 fix Bug C: buttonValues hoisted to declaration block above.
      output$dataready <- reactive({
        query <- parseQueryString(session$clientData$url_search)
        jsonobj <- query$jsonobject
        if (!is.null(jsonobj) && (is.null(updata()) || is.null(updata()$load()))) {
          return(NULL)
        }
        hide(id = "loading-debrowser", anim = TRUE, animType = "fade")
        return(!is.null(init_data()))
      })
      outputOptions(output, "dataready",
        suspendWhenHidden = FALSE
      )

      observeEvent(input$resetsamples, {
        buttonValues$startDE <- FALSE
        showObj(c("goQCplots", "goDE"))
        hideObj(c("cs-add_btn", "cs-rm_btn", "cs-startDE"))
        choicecounter$nc <- 0
      })

      observe({
        if (!is.null(sel())) {
          choicecounter$nc <- sel()$n_comparisons()
        }
      })
      observeEvent(input$goQCplotsFromFilter, {
        if (is.null(batch())) batch(setBatch(filtd()))
        buttonValues$startDE <- FALSE
        buttonValues$goQCplots <- TRUE
        # B2a.12: once DE has run, keep all unlocked tabs visible
        # rather than re-hiding Main Plots + GO Term.
        if (isTRUE(progress$de == "done")) {
          togglePanels(2, c(0, 1, 2, 3, 4), session)
        } else {
          togglePanels(2, c(0, 2, 4), session)
        }
      })
      observeEvent(input$goQCplots, {
        buttonValues$startDE <- FALSE
        buttonValues$goQCplots <- TRUE
        # B2a.12: same post-DE preservation as goQCplotsFromFilter above.
        if (isTRUE(progress$de == "done")) {
          togglePanels(2, c(0, 1, 2, 3, 4), session)
        } else {
          togglePanels(2, c(0, 2, 4), session)
        }
      })
      comparison <- reactive({
        compselect <- 1
        if (!is.null(input$compselect)) {
          compselect <- as.integer(input$compselect)
        }
        dc()[[compselect]]
      })
      conds <- reactive({
        comparison()$conds
      })
      cols <- reactive({
        comparison()$cols
      })
      cond_names <- reactive({
        comparison()$cond_names
      })

      init_data <- reactive({
        if (buttonValues$startDE && !is.null(comparison()$init_data)) {
          comparison()$init_data
        } else if (!is.null(batch())) {
          batch()$BatchEffect()$count
        }
      })
      # E4.5: fitted DESeqDataSet for the active comparison. NULL for
      # non-DESeq2 methods or pre-DE; QC cards 5-7 (Dispersion / SizeFactors /
      # Cook's) handle that as an empty-state alert.
      post_de_dds <- reactive({
        cmp <- comparison()
        if (is.null(cmp)) return(NULL)
        cmp$dds
      })
      # E1: per-comparison DE result tables for the Enrichment tab. NULL
      # pre-DE so the tab's req() chain blocks rendering until DE has run.
      # Names come from comparison_labels(dc()) which produces
      # "<treatment> vs <control>" with " (N)" suffixes on collisions.
      de_results_list <- reactive({
        if (!isTRUE(buttonValues$startDE) || is.null(dc())) return(NULL)
        comps <- dc()
        all_labels <- comparison_labels(comps)
        out <- lapply(comps, function(x) x$init_data)
        keep <- !vapply(out, is.null, logical(1))
        out <- out[keep]
        if (length(out) == 0L) return(NULL)
        names(out) <- all_labels[keep]
        out
      })

      # E11 (post-redirect): Comparison Concordance top-level tab.
      # Pure consumer of de_results_list - no DE re-running. Visibility
      # is governed by the observer immediately below: the tab is
      # hidden at startup and shown only when there are 2+ comparisons.
      comparisonConcordanceServer(
        "comparison_concordance",
        de_results_react  = de_results_list,
        comparisons_react = dc
      )
      # D2.5 noise fix: only manipulate the methodtabs nav after the
      # shinymanager login wall has cleared (Token B). Pre-auth the
      # panel doesn't exist yet and the message would error in console.
      if (auth_complete(session)) {
        bslib::nav_hide("methodtabs", target = "panel_cc",
                        session = session)
      }
      observe({
        if (!auth_complete(session)) return()
        d <- de_results_list()
        if (!is.null(d) && length(d) >= 2L) {
          bslib::nav_show("methodtabs", target = "panel_cc",
                          session = session)
        } else {
          bslib::nav_hide("methodtabs", target = "panel_cc",
                          session = session)
        }
      })

      # E2.5: fgsea-based GSEA inside the consolidated Enrichment tab
      # (panel3, formerly GO Term). Sidebar's GMT/MSigDB picker is
      # mounted here; a startGO + goplot=='fgseaGSEA' combo triggers a
      # run_gsea() pass per comparison.
      .fgsea_gmt        <- enrichmentGmtServer("fgsea_gmt")
      fgsea_pathways    <- .fgsea_gmt$pathways
      fgsea_gmt_state   <- .fgsea_gmt$state    # consumed by export module (Task 10)

      # E3: snapshot the analytical state on demand. Read on download click only;
      # nothing else depends on this reactive, so it does not invalidate other
      # computations. Returns NULL until DE has run.
      state_react <- shiny::reactive({
        if (!isTRUE(buttonValues$startDE) || is.null(dc())) return(NULL)

        count_mat <- batch()$BatchEffect()$count

        # filter inputs live in the lcf module's namespace
        lcf_input <- function(name) session$input[[paste0("lcf-", name)]]
        filter_method <- lcf_input("lcfmethod") %||% "Max"
        filter_cutoff <- switch(filter_method,
          "Max"  = as.numeric(lcf_input("maxCutoff")  %||% 10),
          "Mean" = as.numeric(lcf_input("meanCutoff") %||% 10),
          "CPM"  = as.numeric(lcf_input("CPMCutoff")  %||% 1)
        )
        filter_min_samples <- if (identical(filter_method, "CPM")) {
          as.integer(lcf_input("numSample") %||% (ncol(count_mat) - 1L))
        } else {
          NA_integer_
        }

        batch_input <- function(name) session$input[[paste0("batcheffect-", name)]]
        batch_method <- batch_input("batchmethod") %||% "none"
        batch_col    <- batch_input("batch")
        treat_col    <- batch_input("treatment")

        comps_spec <- if (!is.null(sel())) sel()$comparisons_spec() else list()

        comparisons <- lapply(seq_along(dc()), function(i) {
          cmp_spec <- if (i <= length(comps_spec)) comps_spec[[i]] else list()
          init <- dc()[[i]]$init_data
          sig_thresh_padj <- 0.05
          sig_thresh_lfc  <- 1
          n_sig <- if (!is.null(init) && all(c("padj", "log2FoldChange") %in% colnames(init))) {
            sum(!is.na(init$padj) & init$padj < sig_thresh_padj &
                abs(init$log2FoldChange) > sig_thresh_lfc)
          } else NA_integer_
          list(
            treatment_label   = cmp_spec$treatment_label   %||% "treatment",
            control_label     = cmp_spec$control_label     %||% "control",
            treatment_samples = cmp_spec$treatment_samples %||% character(0),
            control_samples   = cmp_spec$control_samples   %||% character(0),
            de_method         = cmp_spec$de_method         %||% "DESeq2",
            method_params     = cmp_spec$method_params     %||% list(),
            covariates        = cmp_spec$covariates        %||% character(0),
            n_features_in     = nrow(count_mat),
            n_sig_at_padj0.05_lfc1 = as.integer(n_sig)
          )
        })

        enrichment_state <- if (exists("fgsea_gmt_state", inherits = FALSE)) {
          fgsea_gmt_state()
        } else NULL

        list(
          meta = list(
            debrowser_version = utils::packageVersion("debrowser"),
            r_version         = R.version.string,
            timestamp         = Sys.time(),
            session_info      = utils::capture.output(utils::sessionInfo())
          ),
          load = list(
            source       = updata()$load()$data_source %||% NA_character_,
            counts_path  = NA_character_,   # original upload name not preserved through
            meta_path    = NA_character_,   # the load module today; minor, can refine later
            n_features   = nrow(count_mat),
            n_samples    = ncol(count_mat)
          ),
          filter = list(
            method         = filter_method,
            cutoff         = filter_cutoff,
            min_samples    = filter_min_samples,
            n_features_in  = nrow(updata()$load()$count),
            n_features_out = nrow(count_mat)
          ),
          batch = list(
            method           = batch_method,
            batch_column     = if (is.null(batch_col) || identical(batch_col, "None")) NA_character_ else batch_col,
            treatment_column = if (is.null(treat_col) || identical(treat_col, "None")) NA_character_ else treat_col
          ),
          comparisons = comparisons,
          enrichment  = enrichment_state,
          # E3.B: full filtered+batch-corrected matrix (all detected genes,
          # all samples) and the sample metadata table -- consumed by the
          # Sample Info / QC / PCA / All2All sections of the rich report.
          full_counts = count_mat,
          metadata    = batch()$BatchEffect()$meta
        )
      })

      exportMenuServer("export", state_react)

      # Phase E12.A: Settings dropdown wiring. Returns a reactive
      # yielding the current settings list, consumed by gates below.
      ai_settings <- debrowser::aiSettingsServer("ai_settings")

      debrowser::accountDropdownServer("account")

      .fgsea_id_col <- function(de) {
        if ("ID"   %in% names(de)) return("ID")
        if ("gene" %in% names(de)) return("gene")
        NA_character_
      }
      fgsea_results_by_comparison <- eventReactive(input$startGO, {
        req(input$goplot == "fgseaGSEA")
        if (is.null(fgsea_pathways())) {
          de_notify_warning(
            "Load gene sets first. Pick a source (.gmt upload or MSigDB) and click \"Load gene sets\" before Submit."
          )
          return(NULL)
        }
        if (is.null(de_results_list())) {
          de_notify_warning(
            "Run a DE analysis before requesting GSEA on its results."
          )
          return(NULL)
        }
        # Pre-flight: how many DE genes match the loaded pathway
        # universe? Mouse pathways vs. human DE (or vice versa) is the
        # classic species-mismatch trap -- fgsea returns 0 rows and the
        # user is left with a blank table. Catch it here and tell them
        # exactly what to fix.
        primary_de <- de_results_list()[[1]]
        primary_id_col <- .fgsea_id_col(primary_de)
        if (!is.na(primary_id_col)) {
          de_genes <- unique(as.character(primary_de[[primary_id_col]]))
          de_genes <- de_genes[nzchar(de_genes)]
          pw_universe <- unique(unlist(fgsea_pathways(),
                                       use.names = FALSE))
          n_overlap <- length(intersect(de_genes, pw_universe))
          overlap_pct <- if (length(de_genes) > 0L) {
            100 * n_overlap / length(de_genes)
          } else {
            0
          }
          if (n_overlap < input$fgsea_min_size) {
            de_notify_warning(sprintf(
              paste0(
                "Only %d of your %d DE genes (%.1f%%) match symbols in ",
                "the loaded gene sets. The most common cause is a ",
                "species mismatch (e.g. mouse gene sets loaded but ",
                "human DE input -- symbols are case-sensitive: PGK1 ",
                "won't match Pgk1). Reload MSigDB with the species ",
                "matching your DE genes, or upload a .gmt that uses ",
                "the same symbol convention."
              ),
              n_overlap, length(de_genes), overlap_pct
            ))
            return(NULL)
          }
        }
        results <- withProgress(message = "Running GSEA (fgsea)", value = 0.3, {
          lapply(de_results_list(), function(df) {
            run_gsea(df, pathways = fgsea_pathways(),
                     min_size = input$fgsea_min_size,
                     max_size = input$fgsea_max_size,
                     n_perm   = input$fgsea_n_perm,
                     seed     = input$fgsea_seed,
                     id_col   = .fgsea_id_col(df))
          })
        })
        # Even with overlap, every pathway might be filtered out by
        # min/max size -- surface that too instead of leaving the user
        # with a blank table and no clue.
        n_rows <- vapply(results, function(x) {
          if (is.data.frame(x)) nrow(x) else 0L
        }, integer(1))
        if (all(n_rows == 0L)) {
          de_notify_info(
            "GSEA finished but no pathways passed the size filters. Try lowering 'Min set size' or pick a collection with smaller pathways (e.g. Hallmark)."
          )
        }
        results
      }, ignoreNULL = TRUE)

      output$fgsea_show_heatmap <- reactive({
        length(fgsea_results_by_comparison()) >= 2L
      })
      outputOptions(output, "fgsea_show_heatmap",
                    suspendWhenHidden = FALSE)

      enrichmentNesHeatmapServer("fgsea_nes_heatmap",
                                 fgsea_results_by_comparison)

      fgsea_primary_result <- reactive({
        r <- fgsea_results_by_comparison()
        req(length(r) >= 1L)
        r[[1]]
      })

      output$fgsea_results_table <- DT::renderDT({
        df <- fgsea_primary_result()
        DT::datatable(
          df[, c("pathway", "size", "NES", "padj")],
          rownames  = FALSE,
          selection = list(mode = "single", selected = 1),
          filter    = "top",
          options   = list(pageLength = 10)
        ) |>
          DT::formatRound("NES", 4) |>
          DT::formatSignif("padj", 4)
      })

      output$fgsea_download_results <- downloadHandler(
        filename = function() "gsea_results.tsv",
        content  = function(file) {
          df <- fgsea_primary_result()
          df$leading_edge <- vapply(df$leading_edge, paste, character(1),
                                    collapse = ";")
          utils::write.table(df, file = file, sep = "\t",
                             quote = FALSE, row.names = FALSE)
        }
      )

      fgsea_selected_pw <- reactive({
        sel <- input$fgsea_results_table_rows_selected
        df  <- fgsea_primary_result()
        req(length(sel) == 1L, nrow(df) >= sel)
        df$pathway[sel]
      })

      output$fgsea_enrichment_plot <- renderPlot({
        req(fgsea_selected_pw(), fgsea_pathways(), de_results_list())
        df <- de_results_list()[[1]]
        id_col <- .fgsea_id_col(df)
        stats <- df$log2FoldChange
        names(stats) <- as.character(df[[id_col]])
        stats <- sort(stats[is.finite(stats)], decreasing = TRUE)
        fgsea::plotEnrichment(fgsea_pathways()[[fgsea_selected_pw()]],
                              stats) +
          ggplot2::labs(title = fgsea_selected_pw())
      })

      output$fgsea_leading_edge <- renderText({
        sel <- input$fgsea_results_table_rows_selected
        df  <- fgsea_primary_result()
        req(length(sel) == 1L, nrow(df) >= sel,
            "leading_edge" %in% names(df))
        paste(df$leading_edge[[sel]], collapse = ", ")
      })

      # Phase E12.A: AI panel payload reactive. Produces the gene list
      # (leading edge of the currently-selected pathway), per-gene stats
      # from the primary DE result, and the enrichment context. NULL when
      # no pathway is selected -- panel disables Ask in that case.
      ai_enrichment_payload <- reactive({
        sel <- input$fgsea_results_table_rows_selected
        req(length(sel) == 1L)
        df <- fgsea_primary_result()
        # DT keeps the old selection across re-renders, so a row index
        # may temporarily point past the new result's nrow. Guard against
        # that -- and against a missing leading_edge column -- so the AI
        # panel reactive doesn't crash the whole tab with subscript
        # errors.
        req(is.data.frame(df), nrow(df) >= sel,
            "leading_edge" %in% names(df))
        pw_row     <- df[sel, , drop = FALSE]
        leading    <- df$leading_edge[[sel]]
        if (is.null(leading)) leading <- character(0)
        primary_de <- de_results_list()
        if (is.null(primary_de) || length(primary_de) == 0L) return(NULL)
        primary_de <- primary_de[[1]]
        id_col     <- .fgsea_id_col(primary_de)
        stats_df   <- if (is.na(id_col) || length(leading) == 0L) NULL else {
          keep <- as.character(primary_de[[id_col]]) %in% leading
          data.frame(
            gene_id        = as.character(primary_de[[id_col]][keep]),
            log2FoldChange = primary_de$log2FoldChange[keep],
            padj           = primary_de$padj[keep],
            stringsAsFactors = FALSE
          )
        }
        list(
          genes      = leading,
          stats      = stats_df,
          enrichment = list(
            term      = pw_row$pathway,
            pvalue    = pw_row$padj,
            n_overlap = length(leading)
          )
        )
      })

      # Phase E12.A: gate the AI card visibility from JS-side
      # (conditionalPanel reads output$ai_panel_visibility).
      output$ai_panel_visibility <- reactive({
        s <- ai_settings()
        if (.has_required_credentials(s)) "show" else "hide"
      })
      outputOptions(output, "ai_panel_visibility", suspendWhenHidden = FALSE)

      debrowser::aiInterpretServer("ai_enrichment",
                                   payload_react = ai_enrichment_payload,
                                   settings_react = ai_settings)

      filt_data <- reactive({
        if (!is.null(init_data()) && !is.null(comparison()) && !is.null(input$padj)) {
          applyFilters(init_data(), cols(), conds(), input)
        }
      })

      selectedQCHeat <- reactiveVal()
      observe({
        if ((!is.null(input$genenames) && input$interactive == TRUE) ||
          (!is.null(input$genesetarea) && input$genesetarea != "")) {
          tmpDat <- init_data()
          if (!is.null(filt_data())) {
            tmpDat <- filt_data()
          }
          genenames <- ""
          if (!is.null(input$genenames)) {
            genenames <- input$genenames
          } else {
            tmpDat <- getSearchData(tmpDat, input)
            genenames <- paste(rownames(tmpDat), collapse = ",")
          }
        }
        if (!is.null(input$qcplot) && !is.null(normdat())) {
          if (input$qcplot == "all2all") {
            debrowserall2all("all2all", normdat(), input$cex)
          } else if (input$qcplot == "pca") {
            debrowserpcaplot("qcpca", normdat(), batch()$BatchEffect()$meta)
          } else if (input$qcplot == "heatmap") {
            selectedQCHeat(debrowserheatmap("heatmapQC", normdat()))
          } else if (input$qcplot == "IQR") {
            debrowserIQRplot("IQR", removeExtraCols(df_select()))
            debrowserIQRplot("normIQR", normdat())
          } else if (input$qcplot == "Density") {
            debrowserdensityplot("density", removeExtraCols(df_select()))
            debrowserdensityplot("normdensity", normdat())
          } else if (input$qcplot == "libraryDepth") {
            raw <- updata()$load()
            debrowserqclibrarydepth("libraryDepth",
              qc_keep_cols(raw$count, input$col_list),
              qc_keep_meta_rows(raw$meta, input$col_list),
              "treatment")
          } else if (input$qcplot == "detectionRate") {
            debrowserqcdetectionrate("detectionRate",
              qc_keep_cols(updata()$load()$count, input$col_list))
          } else if (input$qcplot == "mtPct") {
            debrowserqcmtpct("mtPct",
              qc_keep_cols(updata()$load()$count, input$col_list))
          } else if (input$qcplot == "sampleDist") {
            debrowserqcsampledist("sampleDist",
              qc_keep_cols(batch()$BatchEffect()$count, input$col_list))
          } else if (input$qcplot == "dispersion") {
            # Dispersion is a gene-level property of the fit; column
            # selection has no meaningful effect, so we always render the
            # full plot.
            debrowserqcdispersion("dispersion", post_de_dds())
          } else if (input$qcplot == "sizeFactors") {
            debrowserqcsizefactors("sizeFactors", post_de_dds(),
              selected_samples = input$col_list)
          } else if (input$qcplot == "cooks") {
            debrowserqccooks("cooks", post_de_dds(),
              selected_samples = input$col_list)
          }
        }
      })
      condmsg <- reactiveVal()
      selectedMain <- reactiveVal()
      observe({
        if (!is.null(filt_data())) {
          condmsg(getCondMsg(
            dc(), input,
            cols(), conds()
          ))
          selectedMain(debrowsermainplot("main", filt_data(), cond_names()))
        }
      })
      selectedHeat <- reactiveVal()
      observe({
        if (!is.null(selectedMain()) && !is.null(selectedMain()$selGenes())) {
          withProgress(message = "Creating plot", style = "notification", value = 0.1, {
            selectedHeat(debrowserheatmap("heatmap", filt_data()[selectedMain()$selGenes(), cols()]))
          })
        }
      })

      selgenename <- reactiveVal()
      observe({
        if (!is.null(selectedMain()) && !is.null(selectedMain()$shgClicked()) &&
          selectedMain()$shgClicked() != "") {
          selgenename(selectedMain()$shgClicked())
          if (!is.null(selectedHeat()) && !is.null(selectedHeat()$shgClicked()) &&
            selectedHeat()$shgClicked() != "") {
            js$resetInputParam("heatmap-hoveredgenenameclick")
          }
        }
      })
      observe({
        if (!is.null(selectedHeat()) && !is.null(selectedHeat()$shgClicked()) &&
          selectedHeat()$shgClicked() != "") {
          selgenename(selectedHeat()$shgClicked())
        }
      })

      observe({
        if (!is.null(selgenename()) && selgenename() != "") {
          withProgress(message = "Creating Bar/Box plots", style = "notification", value = 0.1, {
            debrowserbarmainplot("barmain", filt_data(),
              cols(), conds(), cond_names(), selgenename()
            )
            debrowserboxmainplot("boxmain", filt_data(),
              cols(), conds(), cond_names(), selgenename()
            )
          })
        }
      })

      normdat <- reactive({
        if (!is.null(init_data()) && !is.null(datasetInput())) {
          dat <- init_data()
          norm <- c()
          if (!is.null(cols())) {
            norm <- removeExtraCols(datasetInput())
          } else {
            norm <- getNormalizedMatrix(dat, input$norm_method)
          }
          getSelectedCols(norm, datasetInput(), input)
        }
      })

      df_select <- reactive({
        if (!is.null(init_data()) && !is.null(datasetInput())) {
          getSelectedCols(init_data(), datasetInput(), input)
        }
      })

      output$columnSelForQC <- renderUI({
        existing_cols <- colnames(removeExtraCols(datasetInput()))
        wellPanel(
          id = "tPanel",
          style = "overflow-y:scroll; max-height: 300px",
          checkboxGroupInput("col_list", "Select col to include:",
            existing_cols,
            selected = existing_cols
          )
        )
      })

      selectedData <- reactive({
        dat <- isolate(filt_data())
        ret <- c()
        if (input$selectedplot == "Main Plot" && !is.null(selectedMain())) {
          ret <- dat[selectedMain()$selGenes(), ]
        } else if (input$selectedplot == "Main Heatmap" && !is.null(selectedHeat())) {
          ret <- dat[selectedHeat()$selGenes(), ]
        } else if (input$selectedplot == "QC Heatmap" && !is.null(selectedQCHeat())) {
          ret <- dat[selectedQCHeat()$selGenes(), ]
        }
        ret
      })

      datForTables <- reactive({
        getDataForTables(
          input, normdat(),
          filt_data(), selectedData(),
          getMostVaried(), mergedComp()
        )
      })

      inputGOstart <- reactive({
        if (input$startGO) {
          withProgress(message = "GO Started", detail = "interactive", value = 0, {
            dat <- datForTables()
            getGOPlots(dat[[1]], isolate(getGSEARes()), input)
          })
        }
      })

      getGSEARes <- reactive({
        if (input$goplot == "GSEA") {
          dat <- datForTables()
          gopval <- as.numeric(input$gopvalue)
          getGSEA(dat[[1]],
            pvalueCutoff = gopval,
            org = input$organism, sortfield = input$sortfield
          )
        }
      })

      observeEvent(input$startGO, {
        inputGOstart()
      })

      output$GOPlots1 <- renderPlot({
        if (!is.null(inputGOstart()$p) && input$startGO) {
          if (input$goplot == "GSEA" && !is.null(input$gotable_rows_selected)) {
            require_pkg("enrichplot", feature = "GSEA plot")
            pid <- input$gotable_rows_selected
            p <- enrichplot::gseaplot(inputGOstart()$enrich_p,
              by = "all",
              title = inputGOstart()$enrich_p$Description[pid[1]],
              geneSetID = pid[1]
            )
            return(p)
          }
          return(inputGOstart()$p)
        }
      })
      observeEvent(input$KeggPathway, {
        if (is.null(input$gotable_rows_selected)) {
          showModal(modalDialog(
            title = "KEGG Pathway",
            size = "l",
            easyClose = TRUE,
            footer = modalButton("Close"),
            div(
              class = "alert alert-info de-modal-empty mb-0",
              "Please select a category in the GO/KEGG table to be able to see the pathway diagram."
            )
          ))
          return()
        }
        showModal(modalDialog(
          title = "KEGG Pathway",
          size = "l",
          easyClose = TRUE,
          footer = modalButton("Close"),
          tags$div(
            style = "display:block;overflow-y:auto;overflow-x:auto;",
            imageOutput("KEGGPlot")
          )
        ))
      })

      observeEvent(input$GeneTableButton, {
        if (is.null(input$gotable_rows_selected)) {
          showModal(modalDialog(
            title = "Genes in the category",
            size = "l",
            easyClose = TRUE,
            footer = modalButton("Close"),
            div(
              class = "alert alert-info de-modal-empty mb-0",
              "Please select a category in the GO/KEGG table to be able to see the gene list."
            )
          ))
          return()
        }
        showModal(modalDialog(
          title = "Genes in the category",
          size = "l",
          easyClose = TRUE,
          footer = modalButton("Close"),
          tags$div(
            style = "display:block;overflow-y:auto;overflow-x:auto;",
            wellPanel(DT::dataTableOutput("GOGeneTable"))
          )
        ))
      })

      output$KEGGPlot <- renderImage(
        {
          shiny::validate(need(
            !is.null(input$gotable_rows_selected),
            "Please select a category in the GO/KEGG table tab to be able to see the pathway diagram."
          ))

          withProgress(message = "KEGG Started", detail = "interactive", value = 0, {
            i <- input$gotable_rows_selected

            pid <- inputGOstart()$table$ID[i]

            drawKEGG(input, datForTables(), pid)
            list(
              src = paste0(pid, ".b.2layer.png"),
              contentType = "image/png"
            )
          })
        },
        deleteFile = TRUE
      )

      getGOCatGenes <- reactive({
        if (is.null(input$gotable_rows_selected)) {
          return(NULL)
        }
        org <- input$organism
        dat <- tabledat()
        if (is.null(dat)) {
          return(NULL)
        }
        i <- input$gotable_rows_selected
        if (input$goplot == "GSEA") {
          genes <- inputGOstart()$enrich_p$core_enrichment[i]
        } else {
          genes <- inputGOstart()$enrich_p$geneID[i]
        }

        genedata <- getEntrezTable(
          genes,
          dat[[1]], org
        )
        # `dat[[1]] <- NULL` would *remove* the data slot from the list
        # (shifting indices); coerce to an empty 0-row data frame so the
        # downstream renderer still has a data.frame to display.
        if (is.null(genedata)) {
          genedata <- dat[[1]][integer(0), , drop = FALSE]
        }
        dat[[1]] <- genedata
        dat
      })
      output$GOGeneTable <- DT::renderDataTable({
        shiny::validate(need(
          !is.null(input$gotable_rows_selected),
          "Please select a category in the GO/KEGG table to be able to see the gene list."
        ))
        dat <- getGOCatGenes()
        if (!is.null(dat)) {
          DT::datatable(dat[[1]],
            extensions = "Buttons",
            options = list(
              server = TRUE,
              dom = "Blfrtip",
              buttons =
                list("copy", list(
                  extend = "collection",
                  buttons = c("csv", "excel", "pdf"),
                  text = "Download"
                )), # end of buttons customization
              lengthMenu = list(
                c(10, 25, 50, 100),
                c("10", "25", "50", "100")
              ),
              pageLength = 25, paging = TRUE, searching = TRUE
            )
          ) %>%
            getTableStyle(input, dat[[2]], dat[[3]], buttonValues$startDE)
        }
      })

      output$getColumnsForTables <- renderUI({
        if (is.null(table_col_names())) {
          return(NULL)
        }
        selected_list <- table_col_names()
        if (!is.null(input$table_col_list) &&
          all(input$table_col_list %in% colnames(tabledat()[[1]]))) {
          selected_list <- input$table_col_list
        }
        colsForTable <- list(
          wellPanel(
            id = "tPanel",
            style = "overflow-y:scroll; max-height: 200px",
            checkboxGroupInput("table_col_list", "Select col to include:",
              table_col_names(),
              selected = selected_list
            )
          )
        )
        return(colsForTable)
      })
      table_col_names <- reactive({
        if (is.null(tabledat())) {
          return(NULL)
        }
        colnames(tabledat()[[1]])
      })
      tabledat <- reactive({
        dat <- datForTables()
        if (is.null(dat)) {
          return(NULL)
        }
        if (nrow(dat[[1]]) < 1) {
          return(NULL)
        }
        dat2 <- removeCols(c("ID", "x", "y", "Legend", "Size"), dat[[1]])

        pcols <- c(
          names(dat2)[grep("^padj", names(dat2))],
          names(dat2)[grep("pvalue", names(dat2))]
        )
        if (!is.null(pcols) && length(pcols) > 1) {
          dat2[, pcols] <- apply(
            dat2[, pcols], 2,
            function(x) format(as.numeric(x), scientific = TRUE, digits = 3)
          )
        } else {
          dat2[, pcols] <- format(as.numeric(dat2[, pcols]),
            scientific = TRUE, digits = 3
          )
        }
        rcols <- names(dat2)[!(names(dat2) %in% pcols)]
        if (!is.null(rcols) && length(rcols) > 1) {
          dat2[, rcols] <- apply(
            dat2[, rcols], 2,
            function(x) round(as.numeric(x), digits = 2)
          )
        } else {
          dat2[, rcols] <- round(as.numeric(dat2[, rcols]), digits = 2)
        }

        dat[[1]] <- dat2
        return(dat)
      })
      output$tables <- DT::renderDataTable({
        dat <- tabledat()
        if (is.null(dat) || is.null(table_col_names()) ||
          is.null(input$table_col_list) || length(input$table_col_list) < 1) {
          return(NULL)
        }
        if (!all(input$table_col_list %in% colnames(dat[[1]]), na.rm = FALSE)) {
          return(NULL)
        }
        # if (!dat[[2]] %in% input$table_col_list)
        #    dat[[2]] <- ""
        # if (!dat[[3]] %in% input$table_col_list)
        #    dat[[3]] <- ""

        datDT <- DT::datatable(dat[[1]][, input$table_col_list],
          extensions = "Buttons",
          options = list(
            server = TRUE,
            dom = "Blfrtip",
            buttons =
              list("copy", list(
                extend = "collection",
                buttons = c("csv", "excel", "pdf"),
                text = "Download"
              )), # end of buttons customization
            lengthMenu = list(
              c(10, 25, 50, 100),
              c("10", "25", "50", "100")
            ),
            pageLength = 25, paging = TRUE, searching = TRUE
          )
        ) %>%
          getTableStyle(input, dat[[2]], dat[[3]], buttonValues$startDE)
        return(datDT)
      })
      getMostVaried <- reactive({
        dat <- init_data()
        if (!is.null(cols())) {
          dat <- init_data()[, cols()]
        }
        getMostVariedList(dat, colnames(dat), input)
      })
      output$gotable <- DT::renderDataTable({
        if (!is.null(inputGOstart()$table)) {
          DT::datatable(inputGOstart()$table,
            rownames = FALSE,
            extensions = "Buttons",
            options = list(
              server = TRUE,
              dom = "Blfrtip",
              buttons =
                list("copy", list(
                  extend = "collection",
                  buttons = c("csv", "excel", "pdf"),
                  text = "Download"
                )), # end of buttons customization
              lengthMenu = list(
                c(10, 25, 50, 100),
                c("10", "25", "50", "100")
              ),
              pageLength = 25, paging = TRUE, searching = TRUE
            )
          )
        }
      })
      mergedComp <- reactive({
        dat <- applyFiltersToMergedComparison(isolate(dc()), choicecounter$nc, input)
        dat[dat$Legend == "Sig", ]
      })

      datasetInput <- function(addIdFlag = FALSE) {
        tmpDat <- NULL
        sdata <- NULL
        if (input$selectedplot != "QC Heatmap") {
          sdata <- selectedData()
        } else {
          sdata <- isolate(selectedData())
        }
        if (buttonValues$startDE) {
          mergedCompDat <- NULL
          if (input$dataset == "comparisons") {
            mergedCompDat <- mergedComp()
          }
          tmpDat <- getSelectedDatasetInput(
            rdata = filt_data(),
            getSelected = sdata, getMostVaried = getMostVaried(),
            mergedCompDat, input = input
          )
        } else {
          tmpDat <- getSelectedDatasetInput(
            rdata = init_data(),
            getSelected = sdata,
            getMostVaried = getMostVaried(),
            input = input
          )
        }
        if (addIdFlag) {
          tmpDat <- addID(tmpDat)
        }
        return(tmpDat)
      }
      output$metaFile <- renderTable({
        read.delim(system.file("extdata", "www", "metaFile.txt",
          package = "debrowser"
        ), header = TRUE, skipNul = TRUE)
      })
      output$countFile <- renderTable({
        read.delim(system.file("extdata", "www", "countFile.txt",
          package = "debrowser"
        ), header = TRUE, skipNul = TRUE)
      })

      output$downloadData <- downloadHandler(filename = function() {
        paste(input$dataset, "csv", sep = ".")
      }, content = function(file) {
        dat <- datForTables()
        dat2 <- removeCols(c("x", "y", "Legend", "Size"), dat[[1]])
        if (!("ID" %in% names(dat2))) {
          dat2 <- addID(dat2)
        }
        write.table(dat2, file, sep = ",", row.names = FALSE)
      })

      output$downloadGOPlot <- downloadHandler(filename = function() {
        paste(input$goplot, ".pdf", sep = "")
      }, content = function(file) {
        pdf(file)
        print(inputGOstart()$p)
        dev.off()
      })
    },
    err = function(errorCondition) {
      cat("in err handler")
      message(errorCondition)
    },
    warn = function(warningCondition) {
      cat("in warn handler")
      message(warningCondition)
    }
  )
}
