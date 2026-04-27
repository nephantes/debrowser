# shinytest2 end-to-end tests

These tests are currently **skipped on CI** because the legacy app uses
ad-hoc input IDs that change as we refactor (Phase A4). They will be
re-enabled once modules have stable namespaced IDs.

To run locally:

    R -q -e 'testthat::test_file("tests/shinytest2/test-smoke.R")'
