#!/usr/bin/env bash
# tools/check-grid.sh — enforce the §1 grid-system-plan invariants
# (docs/design/01-grid-system-plan.md). Exit non-zero if a retired idiom
# reappears. Run from the repo root.
#
# The consolidation collapsed four grid idioms to one primitive
# (bslib::layout_columns) and two card systems to one wrapper
# (de_card()). Checks 1-4 guard those invariants and FAIL the build.
# Checks 5-6 are informational only: component-internal `<style>` blocks
# legitimately use pixel dimensions, so a blanket "no px" rule would be a
# false positive — those are surfaced, not enforced.
set -u
fail=0
note() { printf '\n== %s ==\n' "$1"; }

note "1) layout_column_wrap must be gone (use layout_columns(col_widths=))"
if grep -rn "layout_column_wrap" R/; then
  echo "FAIL: layout_column_wrap found"; fail=1
else echo "ok"; fi

note "2) hand-rolled inline CSS grid must be gone (use layout_columns)"
if grep -rnE "display:\s*grid" R/; then
  echo "FAIL: inline display:grid found in R/"; fail=1
else echo "ok"; fi

note "3) fixed-height spacer divs must be gone (use a gap container / --de-space-*)"
if grep -rnE 'style\s*=\s*"height:\s*[0-9]+px' R/; then
  echo "FAIL: fixed-height spacer div found — wrap siblings in a flex/grid gap"; fail=1
else echo "ok"; fi

note "4) raw bslib::card() must carry a 'RAW CARD (de_card exception)' comment"
raw=$(grep -rn "bslib::card(" R/ | grep -v 'R/de_card.R')
if [ -n "$raw" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    f=${line%%:*}; rest=${line#*:}; n=${rest%%:*}
    ctx=$(sed -n "$((n>3 ? n-3 : 1)),$((n-1))p" "$f")
    if ! printf '%s' "$ctx" | grep -q 'RAW CARD (de_card exception)'; then
      echo "FAIL: raw bslib::card() without exception comment -> $line"; fail=1
    fi
  done <<< "$raw"
fi
[ "$fail" -eq 0 ] && echo "ok"

note "5) [info] inline pixel margins/gaps — prefer var(--de-space-*) (not enforced)"
grep -rnE 'style\s*=\s*"[^"]*(margin-top|gap):\s*[0-9]+px' R/ \
  || echo "   none in inline style= attrs"

note "6) [info] classic column() width inventory (only c(5,2,5) rows expected)"
grep -rhoE "column\(\s*[0-9]+" R/ | sed -E 's/.*column\(\s*//' | sort | uniq -c | sort -rn

if [ "$fail" -eq 0 ]; then echo -e "\nGRID CHECK PASSED"; else echo -e "\nGRID CHECK FAILED"; fi
exit "$fail"
