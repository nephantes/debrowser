# R/fct_ai_providers.R
#
# Phase E12.A - provider abstraction over ellmer. list_models() returns
# the user's available model ids per provider, with a hardcoded fallback
# list when the API call fails. ai_chat() returns a provider-specific
# ellmer chat object. Both gated via require_pkg("ellmer", "AI features").
# Tested in tests/testthat/test-fct-ai-providers.R.
