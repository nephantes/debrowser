# R/mod_ai_interpret.R
#
# Phase E12.A - AI interpretation panel. aiInterpretUI() renders the
# panel card; aiInterpretServer() wires the question / privacy / Top-N /
# disclosure / Ask button / response. Reads the parent's payload reactive
# and the user's settings reactive; calls the pure ai_interpret() helper.
# No tests for this module (Shiny module is thin).
