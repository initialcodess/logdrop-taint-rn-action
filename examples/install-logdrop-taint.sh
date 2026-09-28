#!/usr/bin/env bash
# Installs the LogDrop React Native taint analyzer: one self-contained JavaScript file
# that runs on any machine with Node 20 or newer.
#
#   LOGDROP_VERSION=v1.0.0 LOGDROP_DIR="$HOME/.logdrop" ./install-logdrop-taint.sh
#
# Used by the GitHub Action and by the CircleCI, GitLab, Jenkins and Bitrise recipes
# beside it, so that every CI system installs the analyzer the same way.
set -euo pipefail

VERSION="${LOGDROP_VERSION:-v1.0.0}"
DIR="${LOGDROP_DIR:-$HOME/.logdrop}"
REPO="initialcodess/logdrop-taint-rn-action"

if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid LOGDROP_VERSION: '$VERSION' (expected v1.2.3)" >&2
  exit 1
fi

MJS="logdrop-taint-rn-${VERSION}.mjs"
mkdir -p "$DIR"

# EXPECTED CHECKSUMS — and the whole point is WHERE this table lives.
#
# The bundle could be checked against a .sha256 downloaded from the same release. That
# proves a download did not arrive corrupt, and nothing more: whoever can replace the
# file in a release can replace the checksum beside it, and the check still passes. A
# verifier that ships with the thing it verifies is not a verifier.
#
# So the expected value lives HERE, in the script the customer already pinned. Pin the
# action by commit SHA and this line is fixed at that commit: swapping the release is
# no longer enough, because the attacker would also have to change a commit you have
# named. That is why the README asks for a SHA rather than @v1.
#
# It does not defend against someone who can push to THIS repository. Nothing in a
# repository can. Pinning is what limits that, and it is the customer's move.
expected_sha() {
  case "$1" in
    v1.0.0) echo "bfdc7a1bd383bc7eca8b67d806d9fcadf9af45bccff37cda913cae907a7e9679" ;;
    *)      echo "" ;;
  esac
}
EXPECTED="$(expected_sha "$VERSION")"

# STRICT MODE, checked BEFORE anything is fetched. Advisory by default, hard gate on
# request — the same shape as the analyzer's own --fail-on, because the default that
# serves the most people is the one that does not break a pipeline over something its
# owner cannot fix today. Refusing after a 10 MB download would be the same answer,
# later.
if [ -z "$EXPECTED" ] && [ "${LOGDROP_REQUIRE_PINNED_CHECKSUM:-false}" = "true" ]; then
  echo "LogDrop: NO PINNED CHECKSUM for $VERSION, and one was required." >&2
  echo "         This copy of the installer predates that version. Update the action," >&2
  echo "         or unset require-pinned-checksum to accept the published checksum." >&2
  exit 1
fi

# Already installed and already verified: do not download it again. An action used
# twice in one workflow otherwise pays for the same 10 MB twice.
if [ -f "$DIR/$MJS" ] && [ -n "$EXPECTED" ]; then
  if echo "$EXPECTED  $DIR/$MJS" | shasum -a 256 -c - >/dev/null 2>&1; then
    echo "LogDrop: reusing the verified copy of $VERSION"
    exit 0
  fi
fi

BASE="https://github.com/${REPO}/releases/download/${VERSION}"
echo "LogDrop: downloading $MJS"
curl -fsSL --retry 3 --retry-delay 2 -o "$DIR/$MJS" "$BASE/$MJS"

if [ -n "$EXPECTED" ]; then
  if ! echo "$EXPECTED  $DIR/$MJS" | shasum -a 256 -c - >/dev/null 2>&1; then
    rm -f "$DIR/$MJS"
    echo "LogDrop: CHECKSUM MISMATCH — the download was NOT what this action expects." >&2
    echo "         Expected $EXPECTED" >&2
    echo "         The file has been deleted rather than run. Report this to" >&2
    echo "         destek@initialcode.io before trying again." >&2
    exit 1
  fi
  echo "LogDrop: checksum verified against the copy pinned in this action"
else
  # No pinned value: fall back to the checksum published beside the release, and SAY
  # what that is worth. It catches a corrupt download. It does not catch a replaced
  # one, because the same person would publish both.
  curl -fsSL --retry 3 --retry-delay 2 -o "$DIR/$MJS.sha256" "$BASE/$MJS.sha256"
  ( cd "$DIR" && shasum -a 256 -c "$MJS.sha256" >/dev/null )
  echo "LogDrop: verified against the PUBLISHED checksum — this detects a corrupt"
  echo "         download, not a replaced one. Update the action to pin $VERSION."
fi

# Not chmod +x: this is run as `node <file>`, never executed directly. A shebang is in
# the file for anyone who wants to, but the Action does not rely on it.
echo "LogDrop: installed $DIR/$MJS"
