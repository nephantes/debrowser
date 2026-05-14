/* selectize_init.js
 *
 * Global overrides for every selectize.js dropdown the app renders.
 *
 * Two fixes shipped here:
 *
 *   (1) dropdownParent = 'body'
 *       The DE comparison wizard and several other panels live inside
 *       bslib cards / accordion-collapse containers, which apply
 *       overflow: hidden to clip the slide animation. That clipping
 *       also chops off the selectize dropdown menu when it opens
 *       downward (Covariates, Samples, Filter by metadata, etc.).
 *       Reparenting the dropdown to <body> lets the menu render at the
 *       top of the document and never get clipped by an ancestor.
 *
 *   (2) plugins: ['remove_button']
 *       Every multi-select pill now ships with an explicit X button
 *       so users can deselect individual samples / covariates without
 *       having to reopen the dropdown and click the already-selected
 *       row. The plugin is a no-op for single-select inputs, so it's
 *       safe to enable globally.
 *
 * Both settings are applied as selectize defaults BEFORE any input is
 * created, so Shiny's selectize wrapper picks them up automatically on
 * every selectInput / selectizeInput in the app. No per-call R changes
 * required.
 *
 * If a specific input needs different behavior, it can still pass its
 * own `options = list(plugins = ..., dropdownParent = ...)` -- selectize
 * merges the per-instance options on top of these defaults.
 */
(function () {
  function applyDefaults() {
    if (!window.$ || !$.fn || !$.fn.selectize) return false;
    var d = $.fn.selectize.defaults;
    if (!d) return false;

    // Plugins: array of plugin names. Append, don't replace, so any
    // global default selectize ships with is preserved.
    var plugins = Array.isArray(d.plugins) ? d.plugins.slice() : [];
    if (plugins.indexOf("remove_button") < 0) plugins.push("remove_button");
    d.plugins = plugins;

    // Reparent every dropdown to <body> so card / accordion overflow:hidden
    // can't clip the menu.
    d.dropdownParent = "body";

    return true;
  }

  // selectize.js loads before this script in Shiny's selectize bundle,
  // but be defensive: retry briefly if the global isn't ready yet.
  if (!applyDefaults()) {
    var tries = 0;
    var iv = setInterval(function () {
      tries += 1;
      if (applyDefaults() || tries > 20) clearInterval(iv);
    }, 50);
  }
})();
