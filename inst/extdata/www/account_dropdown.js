/* account_dropdown.js
 *
 * CSP-safe click delegate for navbar dropdown items. We can't use
 * inline `onclick`, `onmousedown`, or `javascript:` href URLs because
 * Shiny's default CSP blocks all three (no `unsafe-inline`, no
 * `unsafe-eval`).
 *
 * Pattern: each dropdown item carries `data-debrowser-input="<full
 * Shiny input id>"`. This script attaches a SINGLE click listener on
 * `document` that reads the attribute and calls Shiny.setInputValue
 * with the matched id. addEventListener + click on data-attribute
 * are NOT blocked by CSP.
 *
 * Works for:
 *   - account dropdown items (My Bookmarks / Sign out / Sign up)
 *   - settings dropdown items (AI Assistant)
 *   - any future dropdown item that carries data-debrowser-input
 *
 * The listener is in capture phase so it runs BEFORE Bootstrap's
 * dropdown auto-close handler, guaranteeing the input fires even if
 * a parent decides to stopPropagation.
 */
(function () {
  if (window.__debrowserDropdownWired) return;
  window.__debrowserDropdownWired = true;

  // Per-event-id dedup so mousedown+click on the same physical click
  // don't fire the input twice (Shiny treats two setInputValue calls
  // with the same value as a no-op for priority:event, but the value
  // we send is Date.now(), which DOES change between mousedown and
  // click and would fire the observer twice).
  var lastFiredAt = 0;

  function fire(inputId, sourceEvent) {
    var now = Date.now();
    if (now - lastFiredAt < 50) return;     // dedup mousedown+click pair
    lastFiredAt = now;
    if (window.Shiny && Shiny.setInputValue) {
      try {
        Shiny.setInputValue(inputId, now, { priority: "event" });
        console.log("[debrowser] fired", inputId, "via", sourceEvent);
      } catch (err) {
        console.warn("[debrowser] setInputValue failed", inputId, err);
      }
    } else {
      console.warn("[debrowser] click on", inputId,
        "but Shiny.setInputValue is not available yet");
    }
  }

  function handler(e) {
    var el = e.target && e.target.closest
      ? e.target.closest("[data-debrowser-input]")
      : null;
    if (!el) return;
    var inputId = el.getAttribute("data-debrowser-input");
    if (!inputId) return;

    // Block the default <a href="#"> navigation (would scroll to top).
    // For downloadLinks (shiny-download-link), DON'T preventDefault --
    // they need Shiny's own handler to follow `href` for the download.
    if (!el.classList.contains("shiny-download-link")) {
      e.preventDefault();
    }
    // DO NOT stopPropagation -- we want Bootstrap's dropdown to close
    // after the click registers.

    fire(inputId, e.type);
  }

  // Capture phase: runs before bubble-phase listeners (including
  // Bootstrap's dropdown handler that might otherwise eat the event).
  // We listen on BOTH mousedown and click -- mousedown fires FIRST
  // (before Bootstrap's dropdown auto-close), guaranteeing the input
  // fires even on flaky pointer environments. The fire() dedup window
  // prevents double-firing when both events arrive normally.
  document.addEventListener("mousedown", handler, true);
  document.addEventListener("click",     handler, true);

  // Also wire keyboard: Enter/Space on a focused dropdown item.
  document.addEventListener("keydown", function (e) {
    if (e.key !== "Enter" && e.key !== " ") return;
    var el = document.activeElement &&
             document.activeElement.closest &&
             document.activeElement.closest("[data-debrowser-input]");
    if (!el) return;
    var inputId = el.getAttribute("data-debrowser-input");
    if (!inputId) return;
    if (!el.classList.contains("shiny-download-link")) {
      e.preventDefault();
    }
    fire(inputId, "keydown");
  }, true);

  // -------------------------------------------------------------------
  // Modal aria-hidden focus warning fix.
  //
  // Bootstrap 5 fires `hide.bs.modal` BEFORE it sets aria-hidden=true on
  // the closing modal. If the element with focus (typically a button
  // inside the modal, or the actionLink that opened it) is still inside
  // the modal at that moment, Chrome logs:
  //   "Blocked aria-hidden on an element because its descendant retained
  //   focus."
  // The fix is to move focus OFF the modal before aria-hidden lands.
  // We blur the active element on hide.bs.modal; Bootstrap will then
  // restore focus to the trigger (or the body) safely.
  //
  // We also listen for our own click events: when a `data-debrowser-input`
  // click fires (which usually opens a modal), blur the source element
  // so it can't end up trapped inside the modal-to-be.
  // -------------------------------------------------------------------
  document.addEventListener("hide.bs.modal", function (e) {
    try {
      var modal = e.target;
      if (modal && modal.contains && document.activeElement &&
          modal.contains(document.activeElement)) {
        document.activeElement.blur();
      }
    } catch (err) {}
  }, true);

  // Same handler also blurs the trigger element AFTER firing the input,
  // so that when the resulting modal opens, the trigger (an <a> in the
  // navbar) isn't the focus-trap candidate.
  document.addEventListener("click", function (e) {
    var el = e.target && e.target.closest
      ? e.target.closest("[data-debrowser-input]")
      : null;
    if (el && el.blur) {
      // Defer so we don't interfere with our own fire() call above.
      setTimeout(function () { try { el.blur(); } catch (err) {} }, 0);
    }
  }, false);

  console.log("[debrowser] account_dropdown.js loaded -- data-debrowser-input click delegate active (mousedown+click+keydown)");
})();
