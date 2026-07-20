# shinytest2 setup for DEBrowser

State-based UI tests (smoke + locked-tab assertions) live in
[tests/testthat/test-app-shinytest2.R](testthat/test-app-shinytest2.R).
They run cross-OS via `chromote` and are wired into CI by
[.github/workflows/shinytest2.yml](../.github/workflows/shinytest2.yml).

## Running locally

```r
testthat::test_file("tests/testthat/test-app-shinytest2.R")
```

You need `shinytest2`, `chromote`, and a working Chrome/Chromium
installation. On macOS the system Chrome works; on Linux, install
`chromium-browser` or use `browser-actions/setup-chrome` (the CI
workflow does this automatically).

If chromote can't find a browser, set `CHROMOTE_CHROME` to the binary
path before running the tests.

## Adding more state-based tests

Patterns inside the existing file:

- `app$get_values(input = TRUE)` -- read all current input values
- `app$get_values(output = TRUE)` -- read all current output values
- `app$set_inputs(name = value)` -- programmatically change an input
- `app$click("namespaced-id")` -- click a button by inputId
- `app$wait_for_idle(timeout_ms)` -- block until reactives settle

Always use `name = "..."` on `AppDriver$new(...)` so failures are
labelled in the snap dir.

## Adding visual regression (screenshot) tests

NOT yet enabled. Visual baselines must be Linux-recorded (anti-aliasing
differs across OSes; macOS-recorded baselines fail on Ubuntu CI).

When you're ready to add a screenshot test:

1. Generate baselines on Linux. Two options:
   - Run `act` locally with the
     [shinytest2 workflow](../.github/workflows/shinytest2.yml) to spin
     up a Linux container.
   - Or drop into a Bioconductor Docker image:
     ```bash
     docker run --rm -it -v "$(pwd):/pkg" -w /pkg \
       bioconductor/bioconductor_docker:RELEASE_3_18 \
       Rscript -e 'install.packages("shinytest2"); \
         testthat::test_file("tests/testthat/test-app-shinytest2.R")'
     ```
2. Add a screenshot assertion guarded by `skip_on_os("mac")`:
   ```r
   test_that("Stage 1 wizard renders consistently", {
     skip_on_cran()
     skip_on_os("mac")
     app <- shinytest2::AppDriver$new(build_debrowser_app(), name = "wizard-stage1")
     app$expect_screenshot(threshold = 0.01)
   })
   ```
3. Commit the generated `tests/testthat/_snaps/...` files.
4. CI uses `threshold = 0.01` to absorb sub-pixel anti-aliasing diffs.

Cap the visual frame count at 3-5; screenshot tests are inherently
flakier than state assertions.

## Triage

When CI fails, the workflow uploads `tests/testthat/_snaps/`,
`*.png`, and `*.log` files as the `shinytest2-debug` artifact (visible
on the run page). Download to inspect what the headless browser saw.
