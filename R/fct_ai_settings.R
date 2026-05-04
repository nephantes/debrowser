# R/fct_ai_settings.R
#
# Phase E12.A - settings persistence. Non-secret preferences live in a
# plaintext JSON at R_user_dir("debrowser", "config")/ai-settings.json.
# API keys live in the OS keyring (service "debrowser-ai", username per
# provider). .has_required_credentials() encapsulates the
# "panel-should-render?" predicate. Tested in
# tests/testthat/test-fct-ai-settings.R.
