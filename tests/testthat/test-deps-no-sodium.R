# The Bioconductor Linux builder (nebbiolo2) has no libsodium, so a
# 'sodium' dependency fails `R CMD check` there with "Package suggested
# but not available". Auth crypto uses scrypt + openssl instead, both of
# which are already Imports of shinymanager. These guard the regression.

test_that("sodium is not a declared dependency", {
  deps <- utils::packageDescription(
    "debrowser",
    fields = c("Depends", "Imports", "Suggests", "LinkingTo")
  )
  expect_false(any(grepl("\\bsodium\\b", deps[!is.na(deps)])))
})

test_that("no R source references the sodium namespace", {
  r_dir <- test_path("..", "..", "R")
  skip_if_not(dir.exists(r_dir), "R/ sources unavailable (installed check)")
  hits <- unlist(lapply(
    list.files(r_dir, pattern = "[.][Rr]$", full.names = TRUE),
    function(f) grep("sodium", readLines(f, warn = FALSE), value = TRUE)
  ))
  expect_equal(unname(hits), character(0))
})
