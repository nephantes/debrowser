#' deUI
#'
#' Creates a shinyUI to be able to run DEBrowser interactively.
#' B1 shell: bslib::page_navbar with 5 nav panels (Data Prep / Main Plots /
#' QC Plots / GO Term / Tables), Slate + OK-blue theme, light/dark toggle.
#'
#' Accepts a Shiny `request` argument so that the theme can be swapped at
#' runtime via the `?preset=NAME` query parameter (e.g. `?preset=zephyr`).
#' Unknown or missing `preset` keeps the default theme.
#'
#' @param req Shiny request object (auto-supplied by Shiny when `deUI` is
#'   used as the `ui` argument to `shinyApp()`).
#' @note \code{deUI}
#' @return the page tagList for DEBrowser
#'
#' @examples
#' \dontrun{
#'   shiny::shinyApp(ui = deUI, server = deServer)
#' }
#'
#' @export
deUI <- function(req = NULL) {
  addResourcePath(
    prefix = "www",
    directoryPath = system.file("extdata", "www", package = "debrowser")
  )

  version_label <- getNamespaceVersion("debrowser")

  # Theme playground: ?preset=NAME swaps the bslib preset at runtime.
  # Precedence: explicit URL ?preset= wins, then `debrowser_preset` cookie,
  # then default. Unknown values → default Slate theme via de_theme().
  preset <- if (!is.null(req)) {
    p <- shiny::parseQueryString(req$QUERY_STRING)[["preset"]]
    if (is.null(p) || !nzchar(p)) p <- parse_preset_cookie(req$HTTP_COOKIE)
    p
  } else {
    NULL
  }

  # Visible badge so the active preset is obvious at a glance.
  preset_badge <- if (!is.null(preset)) {
    paste0(" <span class='badge bg-secondary ms-2 small'>preset: ",
           htmltools::htmlEscape(preset), "</span>")
  } else {
    ""
  }

  # Navbar coloring strategy (no non-standard classes):
  #  * Default mode: keep the original dark Slate (#0f172a) inline bg so
  #    nothing changes for users not using the playground.
  #  * Preset mode:  drop the inline bg and let a tiny <style> override
  #    paint the navbar with `var(--bs-primary)`, the standard Bootstrap 5
  #    CSS variable that bootswatch sets per preset. Result: the navbar
  #    bg automatically tracks whichever preset is active. `inverse=TRUE`
  #    is kept so bslib emits the standard `navbar-dark` class — light
  #    text on the colored bar.
  navbar_bg <- if (is.null(preset)) "#0f172a" else NULL

  bslib::page_navbar(
    id      = "methodtabs",
    title   = HTML(paste0(
      "DEBrowser <span class='text-light opacity-50 small ms-1'>v",
      version_label, "</span>", preset_badge
    )),
    window_title = paste0("DEBrowser v", version_label),
    theme    = de_theme(preset = preset),
    bg       = navbar_bg,
    inverse  = TRUE,
    fillable = FALSE,

    header = tagList(
      shinyjs::useShinyjs(),
      # Phase E3.B: Shiny custom-message handler used by the Export menu
      # "View HTML in tab" item. exportMenuServer renders a report to a
      # tempdir served via addResourcePath, then sends this message with
      # the relative URL. Window.open in a new tab; ignored if the
      # browser blocks pop-ups (user can use Download HTML instead).
      tags$head(tags$script(HTML(
        "Shiny.addCustomMessageHandler('debrowser_open_tab', function(msg) {
           window.open(msg.url, '_blank');
         });"
      ))),
      shinyjs::inlineCSS("
        #loading-debrowser {
          position: absolute;
          background: #000000;
          opacity: 0.9;
          z-index: 100;
          left: 0; right: 0;
          height: 100%;
          text-align: center;
          color: #EFEFEF;
        }"),
      tags$div(
        h4(paste0("Loading DEBrowser v", version_label)),
        id = "loading-debrowser",
        tags$img(src = "www/images/initial_loading.gif")
      ),
      tags$head(
        # Bootswatch CDN preset (when ?preset=NAME is set). Each preset
        # gets a unique CDN URL so multiple browser tabs comparing presets
        # don't collide on a single shared bslib-compiled bootstrap.min.css.
        # Loaded BEFORE debrowser.css so our overrides still win.
        de_bootswatch_link(preset),
        # Preset mode: paint the navbar with the preset's --bs-primary so
        # the menu bar adapts. Uses standard Bootstrap CSS variables only
        # (no custom classes). Includes nav-link colors so contrast holds.
        if (!is.null(preset)) tags$style(htmltools::HTML(
          paste(
            ".navbar { background-color: var(--bs-primary) !important; }",
            ".navbar .navbar-brand, .navbar .nav-link { color: rgba(255,255,255,.85) !important; }",
            ".navbar .nav-link:hover, .navbar .nav-link.active, .navbar .navbar-brand:hover { color: #fff !important; }",
            ".navbar .badge.bg-secondary { background-color: rgba(0,0,0,.25) !important; }",
            sep = "\n"
          )
        )),
        tags$link(
          rel = "stylesheet", type = "text/css",
          href = paste0(
            "www/debrowser.css?v=",
            tryCatch(
              as.integer(file.info(system.file(
                "extdata", "www", "debrowser.css", package = "debrowser"
              ))$mtime),
              error = function(e) version_label
            )
          )
        ),
        tags$script(src = "www/dropzone.js"),
        # B3: redesign layer is opt-in via `data-debrowser-redesign` on <html>.
        # The CSS file ships with everything dormant until this attribute is
        # set, so existing users see no change. We turn it on by default
        # here (can be disabled with ?redesign=0 in the URL).
        tags$script(htmltools::HTML(
          "(function(){
             var u = new URL(window.location.href);
             if (u.searchParams.get('redesign') !== '0') {
               document.documentElement.setAttribute('data-debrowser-redesign','1');
             }
           })();"
        )),
        # B3: Inter is loaded by bslib; JetBrains Mono is added for tables.
        tags$link(rel = "stylesheet",
                  href = "https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500&display=swap"),
        # Wires the navbar preset picker → cookie + reload (see de_theme.R).
        de_preset_js(),
        # Dark-mode toggle: flips data-bs-theme on <html> on click.
        # Plus B3.2: keyboard shortcuts 1-6 (switch tabs), T (toggle theme).
        tags$script(htmltools::HTML(
          "document.addEventListener('click', function(e) {
             var btn = e.target.closest && e.target.closest('#dark_mode_toggle');
             if (!btn) return;
             var html = document.documentElement;
             var current = html.getAttribute('data-bs-theme');
             html.setAttribute('data-bs-theme', current === 'dark' ? 'light' : 'dark');
           });

           // Keyboard shortcuts — ignore when focus is in an input/select/textarea
           document.addEventListener('keydown', function(e) {
             var t = e.target;
             if (!t) return;
             var tag = (t.tagName || '').toUpperCase();
             if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
             if (t.isContentEditable) return;
             if (e.metaKey || e.ctrlKey || e.altKey) return;

             // Number keys → switch top-level tabs (panel0..panel5)
             var n = parseInt(e.key, 10);
             if (n >= 1 && n <= 6) {
               var panels = ['panel0','panel1','panel2','panel_cc','panel3','panel4'];
               var target = panels[n - 1];
               if (target) {
                 var sel = document.querySelector(\"a[data-value='\" + target + \"']\");
                 if (sel) sel.click();
               }
             }
             // T toggles theme
             if (e.key === 't' || e.key === 'T') {
               var html = document.documentElement;
               var cur = html.getAttribute('data-bs-theme');
               html.setAttribute('data-bs-theme', cur === 'dark' ? 'light' : 'dark');
             }
           });"
        )),
        # Footer keyboard-shortcut hint pill (matches mockup's bottom-right)
        tags$div(
          class = "de-foot-hint",
          tags$span(class = "kbd", "T"),
          " light/dark · ",
          tags$span(class = "kbd", "1–6"),
          " tabs"
        ),
        # B3.29 — Middle-truncate long sidebar checkbox / radio labels so
        # they fit on one line. Stores original text in data-de-orig and
        # mirrors it into title= so hover shows the full string.
        tags$script(htmltools::HTML(
          "(function(){
             function midTrunc(s, n){
               if (s.length <= n) return s;
               var k1 = Math.ceil((n - 3) / 2);
               var k2 = Math.floor((n - 3) / 2);
               return s.slice(0, k1) + '...' + s.slice(-k2);
             }
             function processLabels(){
               // Sidebar checkboxes / radios: each option label has a child span
               var sel = '.bslib-sidebar-layout .checkbox label > span,' +
                         '.bslib-sidebar-layout .radio label > span,' +
                         '.bslib-sidebar-layout .form-check-label';
               document.querySelectorAll(sel).forEach(function(span){
                 // Skip group-header labels (they don't carry an input sibling)
                 var orig = span.dataset.deOrig || span.textContent.trim();
                 if (!orig) return;
                 // Estimate available width: sidebar is ~240 px minus checkbox+padding (~46 px)
                 // ~22 chars at 12 px Inter ~ fits in 200 px. Use 24 as the threshold.
                 var maxLen = 24;
                 if (orig.length <= maxLen) return;
                 if (!span.dataset.deOrig) span.dataset.deOrig = orig;
                 var truncated = midTrunc(orig, maxLen);
                 if (span.textContent !== truncated) {
                   span.textContent = truncated;
                   span.title = orig;
                 }
               });
             }
             $(document).on('shiny:value shiny:bound shiny:inputchanged',
                            function(){ setTimeout(processLabels, 50); });
             setTimeout(processLabels, 500);
             setTimeout(processLabels, 1500);
           })();"
        ))
      ),
      debrowser::getJSLine(),
      debrowser::getTabUpdateJS()
    ),

    sidebar = bslib::sidebar(
      id = "shared_sidebar",
      width = 300, open = "open",

      # Data Prep tab — wizard nav lives in the sidebar (was nested in
      # navset_pill_list inside the panel content prior to B1.16). DE
      # Filter (cutoff + comparison-selector) docks below the wizard nav
      # when on the DEAnalysis step (matches pre-B1 sidebar location;
      # B1.2 had moved it into the DEAnalysis panel content but the user
      # asked for the sidebar location).
      conditionalPanel(
        condition = "input.methodtabs == 'panel0'",
        # B3.11 — wizard pipeline + DEMOS + SETTINGS sections, matching
        # the mockup pixel-by-pixel. Each step = [num] [dot] [label].
        # State on dot only (mint=done, cyan=active, gray=pending).
        tags$h6("Pipeline", class = "side-title"),
        tags$div(
          class = "wizard-step-list",
          local({
            mk_step <- function(input_id, num, label, pill = NULL, requires = NULL,
                                locked = FALSE) {
              attrs <- list(
                inputId = input_id,
                class   = paste("wiz-step",
                                if (locked) "de-pill-locked" else NULL),
                `data-progress-pill` = pill,
                `data-requires`      = requires,
                `data-step`          = num
              )
              content <- htmltools::tagList(
                htmltools::tags$span(class = "wiz-step-num", num),
                htmltools::tags$span(class = "wiz-step-dot"),
                htmltools::tags$span(class = "wiz-step-label", label)
              )
              do.call(actionLink, c(list(label = content), attrs))
            }
            htmltools::tagList(
              mk_step("nav_DataPrep_Intro",       "01", "Quick start"),
              mk_step("nav_DataPrep_Upload",      "02", "Upload data",
                      pill = "upload"),
              mk_step("nav_DataPrep_Filter",      "03", "Filter & normalize",
                      pill = "filter",     locked = TRUE,
                      requires = "input.Filter"),
              mk_step("nav_DataPrep_BatchEffect", "04", "Batch effect",
                      pill = "batch",      locked = TRUE,
                      requires = "input.Batch"),
              mk_step("nav_DataPrep_CondSelect",  "05", "Comparison",
                      pill = "condselect", locked = TRUE,
                      requires = "input.goDE || input.goDEFromFilter"),
              mk_step("nav_DataPrep_DEAnalysis",  "06", "DE analysis",
                      pill = "de",         locked = TRUE,
                      requires = "input.startDE || input['cs-startDE']")
            )
          })
        ),

        # DEMOS — simple two-column row (prefix + label).
        tags$h6("Demos", class = "side-title"),
        tags$div(class = "de-side-list",
          tags$a(class = "de-side-list-item", href = "#",
                 onclick = "document.querySelector('#load-demo')?.click(); return false;",
                 tags$span(class = "de-side-list-prefix", "▸"),
                 "Vernia et al."),
          tags$a(class = "de-side-list-item", href = "#",
                 onclick = "document.querySelector('#load-demo2')?.click(); return false;",
                 tags$span(class = "de-side-list-prefix", "▸"),
                 "Donnard et al.")
        ),

        # SETTINGS — simple two-column row
        tags$h6("Settings", class = "side-title"),
        tags$div(class = "de-side-list",
          tags$a(class = "de-side-list-item", href = "#",
                 onclick = "document.querySelector('#dark_mode_toggle')?.click(); return false;",
                 tags$span(class = "de-side-list-prefix", "⚙"),
                 "Theme & layout"),
          tags$a(class = "de-side-list-item", href = "#",
                 onclick = "alert('Shortcuts:\\n1-6 → switch tabs\\nT → toggle theme'); return false;",
                 tags$span(class = "de-side-list-prefix", "⌘"),
                 "Keyboard shortcuts")
        ),

        # B3.21 — Permanent safety net for green-dot persistence.
        # The Shiny addCustomMessageHandler pathway was unreliable in our
        # observed sessions (the registered handler didn't run for every
        # 'debrowser-progress' broadcast). This direct WebSocket listener
        # intercepts the same messages and applies de-pill-done / -locked
        # / -skipped to the matching wiz-step. Once de-pill-done is set on
        # a step it is never demoted except by an explicit 'locked' state
        # (the re-upload reset path).
        tags$script(htmltools::HTML(
          "$(document).on('shiny:connected', function(){
             try {
               var ws = Shiny.shinyapp.$socket;
               if (ws && !ws._deWsListener) {
                 ws.addEventListener('message', function(ev){
                   try {
                     var d = JSON.parse(ev.data);
                     if (!d.custom || !d.custom['debrowser-progress']) return;
                     var m = d.custom['debrowser-progress'];
                     // Defer so we run AFTER whatever Shiny's own handler does
                     setTimeout(function(){
                       var el = document.querySelector('a[data-progress-pill=\"' + m.key + '\"]');
                       if (!el) return;
                       var wasDone = el.classList.contains('de-pill-done');
                       if (m.state === 'done') {
                         el.classList.remove('de-pill-locked','de-pill-skipped');
                         el.classList.add('de-pill-done');
                       } else if (m.state === 'locked') {
                         // Locked is the re-upload reset path: clear done.
                         el.classList.remove('de-pill-done','de-pill-skipped');
                         el.classList.add('de-pill-locked');
                       } else if (m.state === 'skipped') {
                         if (!wasDone) {
                           el.classList.remove('de-pill-locked');
                           el.classList.add('de-pill-skipped');
                         }
                       } else {
                         // pending / blank — leave done alone
                         if (!wasDone) {
                           el.classList.remove('de-pill-locked','de-pill-skipped');
                         }
                       }
                     }, 60);
                   } catch(e){}
                 });
                 ws._deWsListener = true;
               }
             } catch(e){}
           });"
        )),

        # Active-step observer: read input.DataPrep (current navset_hidden
        # value) and add .active to the matching wiz-step.
        # B3.19 — Also enforces the locking rule: once a step is .de-pill-done
        # it stays unlockable even if its data-requires input briefly goes
        # falsy. Previously every shiny:inputchanged fire would re-add
        # .de-pill-locked to completed steps, dimming them under the green dot.
        tags$script(htmltools::HTML(
          "function deUpdateActiveStep(){
             try {
               var v = Shiny.shinyapp ? Shiny.shinyapp.$inputValues : {};
               var map = {
                 'Intro':       '#nav_DataPrep_Intro',
                 'Upload':      '#nav_DataPrep_Upload',
                 'Filter':      '#nav_DataPrep_Filter',
                 'BatchEffect': '#nav_DataPrep_BatchEffect',
                 'CondSelect':  '#nav_DataPrep_CondSelect',
                 'DEAnalysis':  '#nav_DataPrep_DEAnalysis'
               };
               $('.wiz-step').removeClass('active');
               var key = v && v.DataPrep;
               if (key && map[key]) $(map[key]).addClass('active');

               // Re-evaluate locked state for gated steps, but NEVER
               // re-lock a step that has already been completed.
               $('.wiz-step[data-requires]').each(function(){
                 var $el = $(this);
                 if ($el.hasClass('de-pill-done')) {
                   $el.removeClass('de-pill-locked');
                   return;
                 }
                 try {
                   var expr = $el.attr('data-requires');
                   var ok = false;
                   if (expr === 'input.Filter')             ok = !!v.Filter;
                   else if (expr === 'input.Batch')         ok = !!v.Batch;
                   else if (expr.indexOf('goDE')   >= 0)    ok = !!v.goDE || !!v.goDEFromFilter;
                   else if (expr.indexOf('startDE')>= 0)    ok = !!v.startDE || !!v['cs-startDE'];
                   if (ok) $el.removeClass('de-pill-locked');
                   else    $el.addClass('de-pill-locked');
                 } catch(err){}
               });
             } catch(e){}
           }
           $(document).on('shiny:inputchanged shiny:value shiny:connected',
                          deUpdateActiveStep);
           setTimeout(deUpdateActiveStep, 200);
           setTimeout(deUpdateActiveStep, 800);"
        )),
        # JS to unlock steps as their gating inputs become truthy
        tags$script(htmltools::HTML(
          "$(document).on('shiny:inputchanged shiny:value', function(e){
             $('.wizard-step-list [data-requires]').each(function(){
               try {
                 var expr = $(this).data('requires');
                 // Map the inputs by name (Shiny.shinyapp.$inputValues uses
                 // bracketed access). Evaluating arbitrary expressions
                 // safely is tricky, so we hard-code the supported keys.
                 var v  = Shiny.shinyapp.$inputValues;
                 var ok = false;
                 if (expr === 'input.Filter')            ok = !!v.Filter;
                 else if (expr === 'input.Batch')        ok = !!v.Batch;
                 else if (expr.indexOf('goDE') >= 0)     ok = !!v.goDE || !!v.goDEFromFilter;
                 else if (expr.indexOf('startDE') >= 0)  ok = !!v.startDE || !!v['cs-startDE'];
                 if (ok) {
                   $(this).removeClass('de-pill-locked');
                 } else {
                   $(this).addClass('de-pill-locked');
                 }
               } catch(err) {}
             });
           });"
        )),
        conditionalPanel(
          condition = "input.DataPrep == 'DEAnalysis'",
          tags$hr(),
          tags$h6("DE Filter", style = "font-weight: 600; margin-top: 8px;"),
          uiOutput("cutOffUI"),
          uiOutput("compselectUI")
        )
      ),

      # Plot/table tabs — existing left-menu content
      conditionalPanel(
        condition = "input.methodtabs != 'panel0'",
        conditionalPanel(
          condition = "(output.dataready)",
          conditionalPanel(
            condition = "input.methodtabs == 'panel1'",
            debrowser::mainPlotControlsUI("main")
          ),
          uiOutput("downloadSection"),
          uiOutput("cutoffSelection"),
          uiOutput("leftMenu")
        )
      )
    ),

    bslib::nav_panel(
      title = de_nav_chip(1, "Data Prep", progress_pill = "data_prep"), value = "panel0",
      # B3: per-step eyebrow + headline. Each sub-step shows its own pair via
      # conditionalPanel so the user always knows where they are.
      conditionalPanel(
        condition = "input.DataPrep == 'Intro'",
        de_eyebrow(1, "Quick Start Guide"),
        de_headline("Welcome to DEBrowser.")
      ),
      conditionalPanel(
        condition = "input.DataPrep == 'Upload'",
        de_eyebrow(1, "Upload & configure"),
        de_headline("Bring your counts & metadata in.")
      ),
      conditionalPanel(
        condition = "input.DataPrep == 'Filter'",
        de_eyebrow(2, "Filter & normalize"),
        de_headline("Trim the noise before you model.")
      ),
      conditionalPanel(
        condition = "input.DataPrep == 'BatchEffect'",
        de_eyebrow(3, "Batch effect"),
        de_headline("Correct for technical confounders.")
      ),
      conditionalPanel(
        condition = "input.DataPrep == 'CondSelect'",
        de_eyebrow(4, "Comparison selection"),
        de_headline("Pick the contrast you care about.")
      ),
      conditionalPanel(
        condition = "input.DataPrep == 'DEAnalysis'",
        de_eyebrow(5, "Differential expression"),
        de_headline("Pick a contrast, see what moves.")
      ),
      bslib::navset_hidden(
        id = "DataPrep",
        bslib::nav_panel(
          title = "Quick Start Guide", value = "Intro",
          bslib::navset_pill(
            bslib::nav_panel("Introduction",       debrowser::getIntroText()),
            bslib::nav_panel("Data Assesment",     debrowser::getDataAssesmentText()),
            bslib::nav_panel("Data Preparation",   debrowser::getDataPreparationText()),
            bslib::nav_panel("DE Analysis",        debrowser::getDEAnalysisText()),
            bslib::nav_panel("FAQ",                debrowser::getQAText())
          )
        ),
        bslib::nav_panel(
          title = "Upload", value = "Upload",
          debrowser::dataLoadUI("load")
        ),
        bslib::nav_panel(
          title = "Filter", value = "Filter",
          conditionalPanel(
            condition = "input.Filter",
            debrowser::dataLCFUI("lcf")
          )
        ),
        bslib::nav_panel(
          title = "BatchEffect", value = "BatchEffect",
          conditionalPanel(
            condition = "input.Batch",
            debrowser::batchEffectUI("batcheffect")
          )
        ),
        bslib::nav_panel(
          title = "CondSelect", value = "CondSelect",
          conditionalPanel(
            condition = "input.goDE || input.goDEFromFilter",
            debrowser::condSelectUI("cs")
          )
        ),
        bslib::nav_panel(
          title = "DE Analysis", value = "DEAnalysis",
          conditionalPanel(
            condition = "input.goDE || input.goDEFromFilter",
            uiOutput("deresUI")
          )
        )
      )
    ),

    bslib::nav_panel(
      title = de_nav_chip(2, "Main Plots"), value = "panel1",
      de_eyebrow(2, "Main plots"),
      de_headline("Volcano, MA, scatter — at a glance."),
      uiOutput("mainmsgs"),
      uiOutput("mainpanel")
    ),

    bslib::nav_panel(
      title = de_nav_chip(3, "QC Plots"), value = "panel2",
      de_eyebrow(3, "Quality control"),
      de_headline("Are your samples behaving themselves?"),
      uiOutput("qcpanel")
    ),

    # E11 (post-redirect): Comparison Concordance — top-level tab
    # between QC Plots and Enrichment. Hidden at startup; shown by an
    # observer in R/server.R when length(de_results_list()) >= 2.
    bslib::nav_panel(
      title = de_nav_chip(4, "Concordance"), value = "panel_cc",
      de_eyebrow(4, "Cross-contrast"),
      de_headline("Where do the two stories agree?"),
      debrowser::comparisonConcordanceUI("comparison_concordance")
    ),

    bslib::nav_panel(
      title = de_nav_chip(5, "Enrichment"), value = "panel3",
      de_eyebrow(5, "Pathways & signatures"),
      de_headline("What story is the list telling?"),
      uiOutput("gopanel")
    ),

    bslib::nav_panel(
      title = de_nav_chip(6, "Tables"), value = "panel4",
      de_eyebrow(6, "Browse & export"),
      de_headline("All your results, one compact table."),
      DT::dataTableOutput("tables")
    ),

    bslib::nav_spacer(),

    debrowser::exportMenuUI("export"),

    bslib::nav_item(
      shiny::actionButton("bookmark_share", "Bookmark",
                          icon = shiny::icon("bookmark"))
    ),

    debrowser::aiSettingsUI("ai_settings"),

    # D2.5: account dropdown only surfaces in hosted mode (the only
    # mode where signup/signin/signout are meaningful). Non-hosted
    # desktop launches don't have real users to manage. Returning
    # `if (FALSE) X` => NULL is filtered by bslib::page_navbar's
    # do.call(..., list_drop_nulls).
    if (hosted_mode()) debrowser::accountDropdownUI("account"),

    bslib::nav_item(
      tags$button(
        id = "dark_mode_toggle",
        type = "button",
        class = "nav-link de-theme-toggle",
        `aria-label` = "Toggle dark mode",
        title = "Toggle dark mode",
        # Shown in light mode; clicking switches to dark.
        tags$svg(
          class = "de-theme-icon de-theme-icon-moon",
          xmlns = "http://www.w3.org/2000/svg",
          viewBox = "0 0 16 16", width = "18", height = "18",
          fill = "currentColor", `aria-hidden` = "true",
          tags$path(d = "M6 .278a.77.77 0 0 1 .08.858 7.2 7.2 0 0 0-.878 3.46c0 4.021 3.278 7.277 7.318 7.277q.792-.001 1.533-.16a.79.79 0 0 1 .81.316.73.73 0 0 1-.031.893A8.35 8.35 0 0 1 8.344 16C3.734 16 0 12.286 0 7.71 0 4.266 2.114 1.312 5.124.06A.75.75 0 0 1 6 .278")
        ),
        # Shown in dark mode; clicking switches to light.
        tags$svg(
          class = "de-theme-icon de-theme-icon-sun",
          xmlns = "http://www.w3.org/2000/svg",
          viewBox = "0 0 16 16", width = "18", height = "18",
          fill = "currentColor", `aria-hidden` = "true",
          tags$path(d = "M8 11a3 3 0 1 1 0-6 3 3 0 0 1 0 6m0 1a4 4 0 1 0 0-8 4 4 0 0 0 0 8M8 0a.5.5 0 0 1 .5.5v2a.5.5 0 0 1-1 0v-2A.5.5 0 0 1 8 0m0 13a.5.5 0 0 1 .5.5v2a.5.5 0 0 1-1 0v-2A.5.5 0 0 1 8 13m8-5a.5.5 0 0 1-.5.5h-2a.5.5 0 0 1 0-1h2a.5.5 0 0 1 .5.5M3 8a.5.5 0 0 1-.5.5h-2a.5.5 0 0 1 0-1h2A.5.5 0 0 1 3 8m10.657-5.657a.5.5 0 0 1 0 .707l-1.414 1.415a.5.5 0 1 1-.707-.708l1.414-1.414a.5.5 0 0 1 .707 0m-9.193 9.193a.5.5 0 0 1 0 .707L3.05 13.657a.5.5 0 0 1-.707-.707l1.414-1.414a.5.5 0 0 1 .707 0m9.193 2.121a.5.5 0 0 1-.707 0l-1.414-1.414a.5.5 0 0 1 .707-.707l1.414 1.414a.5.5 0 0 1 0 .707M4.464 4.465a.5.5 0 0 1-.707 0L2.343 3.05a.5.5 0 1 1 .707-.707l1.414 1.414a.5.5 0 0 1 0 .708")
        )
      )
    ),

    # Theme preset picker. Persists choice in `debrowser_preset` cookie via
    # de_preset_js(). Reload-driven so the chosen preset's CSS is loaded
    # cleanly (bslib doesn't support hot-swapping themes mid-session).
    bslib::nav_item(de_preset_picker(current = preset)),

    bslib::nav_item(
      tags$a(
        href = "https://www.umassmed.edu/biocore/",
        target = "_blank",
        class = "nav-link",
        "UMMS Biocore"
      )
    )
  )
}
