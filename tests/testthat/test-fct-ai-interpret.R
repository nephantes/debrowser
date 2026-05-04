test_that("ai_error() raises a classed condition with ai_error in class chain", {
  expect_error(
    ai_error("test message"),
    class = "ai_error"
  )
})

test_that("ai_error() passes through subclass", {
  expect_error(
    ai_error("auth failed", class = "ai_no_key"),
    class = "ai_no_key"
  )
  # And ai_no_key inherits ai_error
  err <- tryCatch(ai_error("auth", class = "ai_no_key"),
                  ai_error = function(e) e)
  expect_s3_class(err, "ai_error")
  expect_s3_class(err, "ai_no_key")
})

test_that("ai_error() recognizes all 5 spec subclasses", {
  for (sub in c("ai_no_key", "ai_rate_limit", "ai_network",
                "ai_invalid_response", "ai_disabled")) {
    err <- tryCatch(ai_error(sprintf("msg for %s", sub), class = sub),
                    ai_error = function(e) e)
    expect_s3_class(err, sub)
    expect_s3_class(err, "ai_error")
  }
})
