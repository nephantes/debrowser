test_that("user_db_connect creates tables on first call (idempotent)", {
  with_test_data_dir({
    ensure_data_dir()
    con <- user_db_connect()
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    tbls <- DBI::dbListTables(con)
    expect_true(all(c("users", "ai_settings", "bookmarks", "upload_refs",
                      "schema_version") %in% tbls))

    # Idempotent: re-running the migration does not error and does not
    # change schema_version.
    user_db_migrate(con)
    v <- DBI::dbGetQuery(con, "SELECT version FROM schema_version")$version
    expect_equal(v, 1L)
  })
})

test_that("user_db_path resolves under data_dir", {
  with_test_data_dir({
    ensure_data_dir()
    expect_equal(
      normalizePath(user_db_path(), mustWork = FALSE),
      normalizePath(file.path(data_dir(), "users.sqlite"), mustWork = FALSE)
    )
  })
})
