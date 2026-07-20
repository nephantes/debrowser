# shinytest2 end-to-end tests

These tests are currently **skipped on CI** because the top-level UI
IDs are still legacy-shaped: A4ac migrated module *server* APIs to
`moduleServer()` but did not refactor the UI builders. The three-stage
shell rewrite in Phase B2 will stabilise top-level IDs, and that's
when this test gets enabled on CI.

To run locally:

    R -q -e 'testthat::test_file("tests/shinytest2/test-smoke.R")'
