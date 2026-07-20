test_that("passing NULL to public functions returns NULL safely", {
  expect_null(compareClust())
  expect_null(getGOPlots(NULL, NULL))
  expect_null(runDE(NULL))
  expect_null(plot_pca(NULL))
})
