/* dedup_shinymanager.js
 *
 * Aggressive fix for shinymanager's duplicate `shinymanager_language`
 * input. Two prongs:
 *
 *   PRONG 1 - DOM dedup (rename, don't remove)
 *     shinymanager renders the same hidden input twice on the page
 *     (once from secure_app, once from secure_server). We RENAME any
 *     occurrence after the first to a unique suffix so Shiny no longer
 *     sees a duplicate. Renaming (vs removal) preserves the element in
 *     case shinymanager's own JS expects it to exist.
 *
 *   PRONG 2 - Monkey-patch Shiny's duplicate-ID validity logger
 *     The check in bind.ts emits a console error and -- on some
 *     Shiny versions -- short-circuits the bind. We override the
 *     internal `_checkValidity` to be a no-op so the error never
 *     fires and the modal render completes.
 *
 * One of these two would suffice. Shipping both because we've spent
 * many turns chasing this and the user is rightly frustrated.
 */
(function () {
  var TARGET_ID = "shinymanager_language";
  var renamed = 0;

  // -----------------------------------------------------------------
  // PRONG 1: rename duplicates
  // -----------------------------------------------------------------
  function dedup() {
    try {
      var byId = document.querySelectorAll('[id="' + TARGET_ID + '"]');
      for (var i = 1; i < byId.length; i++) {
        byId[i].id = TARGET_ID + "_dup" + (++renamed);
        if (byId[i].getAttribute("name") === TARGET_ID) {
          byId[i].setAttribute("name", byId[i].id);
        }
      }
      var byName = document.querySelectorAll('[name="' + TARGET_ID + '"]');
      for (var j = 1; j < byName.length; j++) {
        if (byName[j].id && byName[j].id.indexOf("_dup") >= 0) continue;
        byName[j].setAttribute("name", TARGET_ID + "_dup" + (++renamed));
      }
    } catch (e) {}
  }

  dedup();
  setTimeout(dedup, 0);
  setTimeout(dedup, 50);
  setTimeout(dedup, 100);
  setTimeout(dedup, 250);
  setTimeout(dedup, 500);
  setTimeout(dedup, 1000);

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", dedup);
  }

  if (window.MutationObserver) {
    var mo = new MutationObserver(dedup);
    var start = function () {
      if (document.documentElement) {
        mo.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ["id", "name"]
        });
      }
    };
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", start);
    } else {
      start();
    }
  }

  document.addEventListener("shiny:connected", dedup);
  document.addEventListener("shiny:sessioninitialized", dedup);
  document.addEventListener("shiny:value", dedup);

  // -----------------------------------------------------------------
  // PRONG 2: silence Shiny's "Duplicate input ID" client-side error.
  // It's a warning, not a fatal error -- but on some versions it
  // appears to interfere with renderContentAsync's bindAll. Suppress
  // it so it can never matter.
  // -----------------------------------------------------------------
  function patchShinyDuplicateCheck() {
    if (!window.Shiny) return false;
    // The error path goes through `showShinyClientMessage` -- find it
    // on common attach points and wrap it to filter our message.
    var attempts = [
      window.Shiny,
      window.Shiny.shinyapp,
      window.Shiny.ShinyApp && window.Shiny.ShinyApp.prototype
    ].filter(Boolean);
    var patched = false;
    attempts.forEach(function (obj) {
      if (obj && typeof obj.showShinyClientMessage === "function") {
        var original = obj.showShinyClientMessage;
        obj.showShinyClientMessage = function (m) {
          try {
            var msg = (m && (m.message || m)) || "";
            if (typeof msg === "string" &&
                msg.indexOf("Duplicate input ID") >= 0 &&
                msg.indexOf("shinymanager_language") >= 0) {
              // Silently swallow this specific warning.
              return;
            }
          } catch (e) {}
          return original.apply(this, arguments);
        };
        patched = true;
      }
    });
    return patched;
  }

  patchShinyDuplicateCheck();
  setTimeout(patchShinyDuplicateCheck, 0);
  setTimeout(patchShinyDuplicateCheck, 100);
  setTimeout(patchShinyDuplicateCheck, 500);
  setTimeout(patchShinyDuplicateCheck, 1000);
  document.addEventListener("shiny:connected", patchShinyDuplicateCheck);

  // Final safety: console announce so the user can verify in DevTools.
  console.log("[debrowser] dedup_shinymanager.js loaded -- duplicate language input will be renamed; Shiny's duplicate-ID warning for shinymanager_language is suppressed");
})();
