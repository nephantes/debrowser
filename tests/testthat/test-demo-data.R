test_that("bundled demo data has the expected shape and a known cell value", {
  load(system.file("extdata", "demo", "demodata.Rda", package = "debrowser"))

  expect_s3_class(demodata, "data.frame")
  expect_equal(demodata[29311, 2], 2)
  expect_equal(demodata[29311, 5], 7.1)
  expect_equal(demodata[29311, 6], 6)
  expect_null(demodata[1, 7])
})
