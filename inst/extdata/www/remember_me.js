/* remember_me.js
 *
 * Persistent-login cookie shim. Bridges shinymanager's URL-based
 * session token (?_token_=...) to a long-lived cookie so users stay
 * signed in across browser restarts.
 *
 * shinymanager 1.0.410 doesn't expose a cookie_validity option, so we
 * implement the persistence layer client-side:
 *
 *   1. After a successful login, shinymanager rewrites the URL to
 *      include `?_token_=<jwt>`. This script captures that token into
 *      the `debrowser_remember` cookie (30-day SameSite=Lax) so the
 *      next visit can replay it.
 *
 *   2. On an unauthenticated page load (no `_token_` in the URL) where
 *      the cookie exists, this script reloads the page with the cached
 *      token appended. shinymanager sees a token, validates it against
 *      its own session table, and skips the login form.
 *
 * Consent: a `debrowser_cookie_consent` localStorage flag gates the
 * cookie WRITE. The flag is set at signup time when the user ticks the
 * Cookie Policy checkbox (see fct_signup.R / mod_account.R). Without
 * the flag, the script does nothing -- no cookie is set, and visits
 * always go through the login form. Users can revoke at any time by
 * clearing the flag (Settings -> "Sign me out everywhere", planned).
 *
 * The cookie is intentionally NOT HttpOnly because shinymanager needs
 * JS-side access to forward it into the URL. Mitigations: SameSite=Lax,
 * a short-ish 30-day TTL, and the actual JWT inside the token is
 * shinymanager-signed and bound to its own session table.
 */
(function () {
  var COOKIE_NAME   = "debrowser_remember";
  var CONSENT_KEY   = "debrowser.cookie_consent.v1";
  var MAX_AGE_SECS  = 30 * 24 * 60 * 60;
  var URL_PARAM     = "_token_";

  function hasConsent() {
    try {
      return window.localStorage &&
             window.localStorage.getItem(CONSENT_KEY) === "1";
    } catch (e) {
      // Private mode or storage disabled: no persistence, but don't break.
      return false;
    }
  }

  function readCookie(name) {
    var match = document.cookie.match(
      new RegExp("(?:^|; )" + name.replace(/([.$?*|{}()[\\]\\\\\/+^])/g, "\\$1") + "=([^;]*)")
    );
    return match ? decodeURIComponent(match[1]) : null;
  }

  function writeCookie(name, value, maxAgeSeconds) {
    var secure = window.location.protocol === "https:" ? "; Secure" : "";
    document.cookie =
      name + "=" + encodeURIComponent(value) +
      "; path=/" +
      "; max-age=" + maxAgeSeconds +
      "; SameSite=Lax" + secure;
  }

  function clearCookie(name) {
    document.cookie = name + "=; path=/; max-age=0";
  }

  function getUrlParam(name) {
    try {
      var u = new URL(window.location.href);
      return u.searchParams.get(name);
    } catch (e) {
      return null;
    }
  }

  // ----------------------------------------------------------------
  // Case A: URL carries a fresh shinymanager token. Save it to the
  // remember-me cookie so the next visit can replay it. Only do this
  // if the user has accepted cookies (consent flag in localStorage).
  // ----------------------------------------------------------------
  var urlToken = getUrlParam(URL_PARAM);
  if (urlToken && urlToken.length > 0) {
    if (hasConsent()) {
      writeCookie(COOKIE_NAME, urlToken, MAX_AGE_SECS);
    }
    // Either way, nothing to redirect; let the page finish loading.
    return;
  }

  // ----------------------------------------------------------------
  // Case B: bare URL (no token) but we have a saved cookie.
  // Reload with the cached token so shinymanager skips the login
  // screen. Guard against a redirect loop with a sessionStorage flag.
  // ----------------------------------------------------------------
  var saved = readCookie(COOKIE_NAME);
  if (saved && saved.length > 0) {
    try {
      var alreadyTried = window.sessionStorage &&
                         window.sessionStorage.getItem("debrowser_remember_tried") === "1";
      if (!alreadyTried) {
        if (window.sessionStorage)
          window.sessionStorage.setItem("debrowser_remember_tried", "1");
        var u = new URL(window.location.href);
        u.searchParams.set(URL_PARAM, saved);
        // Belt + braces: a failed-restore should be detectable by
        // the server, which can clear the cookie if it sees an
        // invalid token. For now, just navigate.
        window.location.replace(u.toString());
        return;
      } else {
        // We tried this token in this tab and didn't end up authenticated
        // (otherwise Case A would have caught the URL param). Clear the
        // stale cookie so future loads go through the normal login.
        clearCookie(COOKIE_NAME);
      }
    } catch (e) {
      // Non-fatal: just fall through to the normal login screen.
    }
  }

  // ----------------------------------------------------------------
  // Public API: anything in the app can flip the consent flag.
  // Used by the signup success handler (when the user checked the
  // Cookie Policy box) and by Settings -> "Forget me".
  // ----------------------------------------------------------------
  window.debrowserRememberMe = {
    setConsent: function (yes) {
      try {
        if (yes) localStorage.setItem(CONSENT_KEY, "1");
        else { localStorage.removeItem(CONSENT_KEY); clearCookie(COOKIE_NAME); }
      } catch (e) {}
    },
    hasConsent: hasConsent,
    forget: function () {
      try { localStorage.removeItem(CONSENT_KEY); } catch (e) {}
      clearCookie(COOKIE_NAME);
      try { sessionStorage.removeItem("debrowser_remember_tried"); } catch (e) {}
    }
  };

  // Wire the Shiny custom-message handler if/when Shiny is ready, so
  // R-side code can flip consent after signup or "Sign out everywhere".
  function wireShinyHandlers() {
    if (!window.Shiny || !window.Shiny.addCustomMessageHandler) return;
    // Shiny's addCustomMessageHandler REQUIRES handlers with exactly
    // one declared parameter (it checks `handler.length === 1`). If
    // any handler has zero or two+ params, Shiny throws "handler must
    // be a function that takes one argument" -- which aborts the
    // registration chain and silently breaks ALL custom messages
    // (including downstream Shiny features that depend on the chain
    // being initialized). Both handlers below declare exactly one
    // parameter, even though `forget_me` doesn't use its payload.
    window.Shiny.addCustomMessageHandler("debrowser:cookie_consent", function (m) {
      window.debrowserRememberMe.setConsent(!!(m && m.consented));
    });
    window.Shiny.addCustomMessageHandler("debrowser:forget_me", function (_m) {
      window.debrowserRememberMe.forget();
    });
  }
  if (window.Shiny) {
    wireShinyHandlers();
  } else {
    document.addEventListener("shiny:connected", wireShinyHandlers);
  }
})();
