# debrowser NEWS

For releases prior to 1.31, see the legacy `NEWS` file.

## debrowser 1.31.2 (in development)

### Phase A1 — foundation modernization

* Bumped minimum R version to 4.2 and `RoxygenNote` to 7.3.x.
* Added `lintr` and `styler` configs; one-time formatting pass.
* Added GitHub Actions for R-CMD-check (R-release + R-devel),
  BiocCheck, lintr, and `covr` coverage (codecov).
* Extended `.Rbuildignore` for docs, CI, lint, and dev configs.
* Removed stale empty `viafoundry_errors.log` from the repo.

### User-visible

* Raised `startDEBrowser()` upload limit from 30 MB to 90 MB.
