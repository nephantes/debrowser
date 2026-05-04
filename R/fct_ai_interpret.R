# R/fct_ai_interpret.R
#
# Phase E12.A - pure AI interpretation orchestrator. ai_interpret() takes a
# preset question key, a payload of analytical context, a privacy mode, and
# an ellmer chat object, and returns the model's response. Errors are
# raised as classed conditions (ai_error subclasses) for the Shiny module
# to map to friendly notifications. Tested in
# tests/testthat/test-fct-ai-interpret.R.
