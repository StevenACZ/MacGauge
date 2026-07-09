#!/usr/bin/env bash
# Build, sign, install, and launch the local development app bundle.
# The SwiftPM bundle script defaults to ad-hoc signing; this wrapper requires a
# stable Apple Development identity so local app identity does not churn during
# iteration.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DST="$HOME/Applications/MacGauge.app"
LEGACY_APP="$HOME/Applications/MacFan.app"

cd "$ROOT"

SIGN_IDENTITY="${MACGAUGE_SIGN_IDENTITY:-${SIGN_IDENTITY:-}}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -p codesigning -v | awk -F '"' '/Apple Development/ { print $2; exit }')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "install-dev: no Apple Development signing identity found." >&2
  echo "install-dev: set MACGAUGE_SIGN_IDENTITY or install an Apple Development certificate." >&2
  exit 65
fi

# Drop the pre-rename bundle so two copies never race for the menu bar.
rm -rf "$LEGACY_APP"

SIGN_IDENTITY="$SIGN_IDENTITY" ./scripts/build_and_run.sh --install

if [[ ! -d "$APP_DST" ]]; then
  echo "install-dev: expected app bundle at $APP_DST" >&2
  exit 66
fi

SIGNING_DETAILS="$(codesign -dvvv "$APP_DST" 2>&1 || true)"
if ! grep -q "Authority=Apple Development" <<<"$SIGNING_DETAILS"; then
  echo "install-dev: installed app is not signed with Apple Development." >&2
  exit 65
fi
if ! grep -q "^TeamIdentifier=" <<<"$SIGNING_DETAILS"; then
  echo "install-dev: installed app has no TeamIdentifier." >&2
  exit 65
fi

CDHASH="$(sed -n 's/^CDHash=//p' <<<"$SIGNING_DETAILS" | head -1)"
echo "install-dev: installed CDHash=${CDHASH:-unknown} to $APP_DST"
