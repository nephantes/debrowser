/* plotly_theme.js
 *
 * Two cross-cutting fixes for every Plotly chart the app renders:
 *
 *   1. Theme integration. Plotly's defaults paint paper_bgcolor /
 *      plot_bgcolor opaque white and axis text near-black, which fights
 *      DEBrowser's dark navy theme and looks broken when the user
 *      toggles dark/light. We listen for shiny:value (which fires after
 *      every Shiny output render) and re-style every newly-painted
 *      Plotly graph div in place via Plotly.relayout, sourcing colors
 *      from the same theme variables the rest of the app uses.
 *
 *   2. Modebar repositioning. By default Plotly floats the modebar
 *      (zoom / pan / camera / save / autoscale icons) inside the upper-
 *      right corner of the plot area, where it overlaps legend entries
 *      and high-value data points. We push it above the plot via
 *      Plotly's `modebar` layout property + a CSS rule that reserves
 *      24px of headroom on Plotly containers.
 */
(function () {

  function isDark() {
    var html = document.documentElement;
    if (html.getAttribute("data-bs-theme") === "dark") return true;
    // The DEBrowser redesign layer is dark-only.
    if (html.getAttribute("data-debrowser-redesign") === "1") return true;
    return false;
  }

  function themeFor(dark) {
    return dark ? {
      paper:  "rgba(15,21,48,0)",       // transparent so card bg shows
      plot:   "rgba(0,0,0,0)",
      fg:     "#A8B2D1",
      grid:   "rgba(255,255,255,0.06)",
      zero:   "rgba(255,255,255,0.18)",
      line:   "rgba(255,255,255,0.12)",
      hoverbg: "#1A2147",
      hoverfg: "#E6ECFF"
    } : {
      paper:  "rgba(255,255,255,0)",
      plot:   "rgba(255,255,255,0)",
      fg:     "#475569",
      grid:   "rgba(15,23,42,0.08)",
      zero:   "rgba(15,23,42,0.22)",
      line:   "rgba(15,23,42,0.14)",
      hoverbg: "#0f172a",
      hoverfg: "#f8fafc"
    };
  }

  function applyTheme(gd) {
    if (!window.Plotly || !gd) return;
    var t = themeFor(isDark());
    var update = {
      "paper_bgcolor":  t.paper,
      "plot_bgcolor":   t.plot,
      "font.color":     t.fg,
      "xaxis.gridcolor": t.grid,
      "yaxis.gridcolor": t.grid,
      "xaxis.zerolinecolor": t.zero,
      "yaxis.zerolinecolor": t.zero,
      "xaxis.linecolor": t.line,
      "yaxis.linecolor": t.line,
      "xaxis.tickcolor": t.line,
      "yaxis.tickcolor": t.line,
      "hoverlabel.bgcolor": t.hoverbg,
      "hoverlabel.font.color": t.hoverfg,
      // Move modebar above the plot area so it doesn't overlap data.
      "modebar.orientation": "h",
      "modebar.bgcolor": "rgba(0,0,0,0)",
      "modebar.color": t.fg,
      "modebar.activecolor": "#5EE6D6"
    };
    try { window.Plotly.relayout(gd, update); } catch (e) {}
  }

  function rethemeAll() {
    var nodes = document.querySelectorAll(".js-plotly-plot");
    for (var i = 0; i < nodes.length; i++) applyTheme(nodes[i]);
  }

  // Apply on every Shiny output value update -- this fires AFTER the
  // Plotly graph div is in the DOM. Scope the query to e.target to
  // avoid re-theming the entire app on every output change.
  document.addEventListener("shiny:value", function (e) {
    setTimeout(function () {
      var t = e && e.target;
      if (!t || !t.querySelectorAll) return rethemeAll();
      var gds = t.querySelectorAll(".js-plotly-plot");
      if (gds.length === 0) return; // not a Plotly output
      for (var i = 0; i < gds.length; i++) applyTheme(gds[i]);
    }, 0);
  });

  // Re-theme when the user toggles dark/light or the redesign layer.
  if (window.MutationObserver) {
    new MutationObserver(rethemeAll).observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-bs-theme", "data-debrowser-redesign"]
    });
  }

  // First pass on initial connect.
  if (window.Shiny && window.Shiny.shinyapp) {
    document.addEventListener("shiny:connected", rethemeAll);
  } else {
    document.addEventListener("DOMContentLoaded", rethemeAll);
  }
})();
