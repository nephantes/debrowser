test_that("de_theme() with no args returns a bs_theme object", {
  t <- de_theme()
  expect_s3_class(t, "bs_theme")
})
