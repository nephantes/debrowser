test_that("build_share_modal_ui: contains the URL", {
  ui <- build_share_modal_ui("https://example/?_state_id_=abc")
  out <- as.character(ui)
  expect_true(any(grepl("https://example/?_state_id_=abc", out, fixed = TRUE)))
})

test_that("build_share_modal_ui: includes Open-in-new-tab link", {
  ui <- build_share_modal_ui("https://example/?_state_id_=abc")
  out <- as.character(ui)
  expect_true(any(grepl("target=\"_blank\"", out, fixed = TRUE)))
})

test_that("build_share_modal_ui: includes copy-friendly text input", {
  ui <- build_share_modal_ui("https://example/?_state_id_=abc")
  out <- as.character(ui)
  expect_true(any(grepl("readonly|<input", out, ignore.case = TRUE)))
})

test_that("build_share_modal_ui: visibility toggle hidden by default", {
  ui <- build_share_modal_ui("https://example/?_state_id_=abc",
                             can_toggle = FALSE)
  out <- as.character(ui)
  expect_false(any(grepl("Shared via link", out, fixed = TRUE)))
})

test_that("build_share_modal_ui: visibility toggle when can_toggle = TRUE", {
  ui <- build_share_modal_ui("https://example/?_state_id_=abc",
                             can_toggle = TRUE,
                             current_visibility = "private")
  out <- as.character(ui)
  expect_true(any(grepl("Shared via link", out, fixed = TRUE)) ||
              any(grepl("Visibility", out, fixed = TRUE)))
})
