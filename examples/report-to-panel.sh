#!/usr/bin/env bash
#
# Send a finished SARIF report to the LogDrop panel.
#
# WHY THIS IS A SEPARATE SCRIPT, AND NOT PART OF THE ANALYZER
#
# The analyzer contacts no server. It verifies its licence offline, counts no
# usage and tells nobody it ran — that is the product's central promise, and a
# scanner that phones home cannot make it. Reporting is therefore a step you can
# see, run by you, on a report that already exists.
#
# The GitHub Action does this same POST internally when you give it `panel-url`.
# Everywhere else — CircleCI, GitLab, Jenkins, Bitrise, a Gradle task, a laptop —
# this script is that step.
#
# THIS FILE IS A TWIN of the one in initialcodess/logdrop-taint-ios-action, and the two
# must stay identical from `set -uo pipefail` down. The report is the same SARIF
# whichever analyzer produced it, and the panel has one endpoint, so a fix that
# lands on one side and not the other means two products disagreeing about how to
# talk to the same server.
#
# It is duplicated rather than shared because the Android recipes used to curl the
# iOS copy from that repository's MOVING `v1` tag. It worked — until iOS releases
# v2, or the script grows something iOS-specific, at which point Android breaks for
# a reason nobody would look for in an iOS changelog. `scripts/verify.sh` compares
# the two and fails when they drift, and it now also compares them against the
# GitHub Action, which must break the build on exactly the same conditions.
#
# USAGE
#   PANEL_URL=https://panel.example.com \
#   LOGDROP_LICENSE="LOGDROP...." \
#   BUNDLE_ID=com.company.app \
#     ./report-to-panel.sh logdrop-taint.sarif
#
# WITHOUT PANEL_URL IT DOES NOTHING, and says so. Recipes can therefore include
# the step unconditionally: a customer who never sets PANEL_URL never sends
# anything, and one who sets it needs no further edits.
#
# EXIT CODE: DELIVERY NEVER FAILS YOUR BUILD UNLESS YOU ASK
#
# This script used to fail the build on a rejected report (400/422) and on an
# unreadable licence key (401), on the reasoning that those are yours to fix. That
# reasoning was wrong often enough to matter. A bundle id deleted or renamed in the
# panel answers 400. A licence moved to another project answers 400. Neither is
# something the developer whose pull request just went red can do anything about,
# and neither can be told apart from a typo by looking at the response.
#
# The two ways of being wrong do not cost the same. Break the build and a team
# blocked by something outside their control eventually deletes the step — and then
# no report is ever sent again. Do not break it and a report goes missing, which is
# bad, but blocks nobody and is fixed by making it visible. So every delivery
# outcome is a warning, printed loudly, and exit 0.
#
# Set FAIL_ON_DELIVERY_ERROR=true if you want the hard gate: then ANY failure to
# deliver is exit 1. One switch, no per-code table — "did the report arrive" is the
# question a team can act on, and a rule that needs a table to explain gets misread.
set -uo pipefail

SARIF="${1:-logdrop-taint.sarif}"
FAIL_ON_DELIVERY_ERROR="${FAIL_ON_DELIVERY_ERROR:-false}"

# Says what went wrong in a way that cannot be missed in a wall of build output,
# then decides the exit code from the one switch above. Every failure path ends
# here, so there is exactly one place where that decision is made.
fail_delivery() {
  echo "" >&2
  echo "  ============================================================" >&2
  echo "  LogDrop: THE REPORT WAS NOT SENT TO THE PANEL." >&2
  echo "  $1" >&2
  echo "  ============================================================" >&2
  echo "" >&2
  if [ "$FAIL_ON_DELIVERY_ERROR" = "true" ]; then
    exit 1
  fi
  exit 0
}

if [ -z "${PANEL_URL:-}" ]; then
  echo "LogDrop: PANEL_URL is not set — the report stays on this machine."
  exit 0
fi

if [ ! -f "$SARIF" ]; then
  fail_delivery "No report at '$SARIF' — nothing to send."
fi

if [ -z "${LOGDROP_LICENSE:-}" ]; then
  fail_delivery "PANEL_URL is set but LOGDROP_LICENSE is not; the panel identifies you by your key."
fi

if [ -z "${BUNDLE_ID:-}" ]; then
  fail_delivery "PANEL_URL is set but BUNDLE_ID is not; the panel needs it to know which app this is."
fi

# Which app, which build. Everything here is optional context — the panel works
# without it, and reads WHICH CUSTOMER this belongs to from the licence key, not
# from anything sent here.
APP_NAME="${APP_NAME:-$(basename "$PWD")}"
VERSION="${VERSION:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)}"
COMMIT="${COMMIT:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"

URL="${PANEL_URL%/}/api/reports/sarif"
BODY="$(mktemp)"
trap 'rm -f "$BODY"' EXIT

# `|| CODE=000` is load-bearing, and is not the same as `|| echo 000`.
#
# Under `set -e` — which this script does not set, but a caller may (`bash -e`), and
# the GitHub Action's shell does — an assignment from a command substitution carries
# the command's exit status, so an unreachable panel (curl exit 7) would kill the
# script on this line: the `000)` branch would never run and the delivery switch
# would be skipped. A command in a `||` list is exempt from `-e`.
#
# And it must assign, not echo: curl's -w already prints "000" when it cannot
# connect, so `|| echo 000` yields "000000", which matches no branch below and falls
# through to the catch-all. Both spellings look equivalent and only one is.
CODE=$(curl -sS -o "$BODY" -w '%{http_code}' -X POST "$URL" \
  -H "Authorization: Bearer $LOGDROP_LICENSE" \
  -F "sarif=@$SARIF" \
  -F "bundle_id=$BUNDLE_ID" \
  -F "app_name=$APP_NAME" \
  -F "version=$VERSION" \
  -F "commit=$COMMIT") || CODE=000
# Guarded for the same reason as the line above: a caller running this with
# `bash -e` must not die here when there is nothing to read.
DETAIL=$(head -c 300 "$BODY" 2>/dev/null) || DETAIL=""

case "$CODE" in
  200|201)
    echo "LogDrop: report sent to the panel."
    exit 0
    ;;
  400|422)
    # The usual cause is a bundle id that is not registered for this project. The
    # panel says which one it did not recognise; it does not list the ones it knows,
    # on purpose — a CI log is not always private. But it is NOT always a typo: a
    # bundle id deleted in the panel, or a licence moved to another project, lands
    # here too, and neither is fixable from this pipeline.
    fail_delivery "The panel rejected the report ($CODE): $DETAIL — check that the bundle id is registered for this project and that the licence covers it. Nothing was stored."
    ;;
  401)
    # A key the panel cannot read at all: the wrong secret, or one mangled in
    # copying. Whoever configured it can fix it — but they are usually not the
    # person whose build this is, which is why it warns rather than blocks.
    fail_delivery "The panel could not read the licence key (401). Check the licence secret — a line break in the value is the usual cause."
    ;;
  403)
    # Recognised but no longer permitted — expired, or revoked. A commercial matter
    # between two companies, and the developer who pushed this commit can do nothing
    # about it. The analyzer already refuses to run on an expired key (exit 2) long
    # before the report gets this far.
    fail_delivery "The panel did not accept the licence (403): $DETAIL — it may be expired or revoked. satis@initialcode.io"
    ;;
  413)
    fail_delivery "The report exceeded the panel's size limit (413). Narrow the scan with 'exclude' in .logdrop.json to drop generated code."
    ;;
  503)
    fail_delivery "The panel is currently unavailable (503). The scan was unaffected; the next run will try again."
    ;;
  000)
    fail_delivery "The panel could not be reached ($PANEL_URL). The scan was unaffected."
    ;;
  *)
    # An unfamiliar code is not evidence that the customer did anything wrong.
    fail_delivery "The panel returned $CODE: $DETAIL"
    ;;
esac
