test_that("de_theme() with no args returns a bs_theme object", {
  t <- de_theme()
  expect_s3_class(t, "bs_theme")
})

test_that("de_theme(preset) returns a bs_theme using the named preset", {
  t <- de_theme(preset = "zephyr")
  expect_s3_class(t, "bs_theme")
})

test_that("de_theme(preset = '<unknown>') falls back to default with a message", {
  expect_message(
    t <- de_theme(preset = "not-a-real-preset"),
    regexp = "not-a-real-preset"
  )
  expect_s3_class(t, "bs_theme")
})
