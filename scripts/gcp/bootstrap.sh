#!/usr/bin/env bash
#
# bootstrap.sh — create the dedicated GCP project behind Google Sheets sync.
#
# Idempotent: it checks for the project and each API before creating or
# enabling anything, so re-running it is a no-op that just reprints the
# checklist. It never changes your active gcloud configuration; every call
# passes --project explicitly.
#
# What gcloud can't do for an iOS OAuth client (consent screen, publishing,
# the iOS client itself) is printed as a console checklist at the end.
# Full guide: docs/CONNECTIONS.md
#
# Usage:
#   scripts/gcp/bootstrap.sh
#   PROJECT_ID=my-other-id scripts/gcp/bootstrap.sh
#
# Requires: gcloud, logged in (`gcloud auth login`). No billing account needed.

set -euo pipefail

# --- Configuration -----------------------------------------------------------
PROJECT_ID="${PROJECT_ID:-train-ha-prod}"
PROJECT_NAME="${PROJECT_NAME:-Train}"
BUNDLE_ID="${BUNDLE_ID:-com.bradlet.train}"
SCOPE="https://www.googleapis.com/auth/drive.file"
# Publishing the consent screen requires a public home page, privacy policy
# and terms of service on an authorized domain you own (sources: bradlet.github.io repo).
HOME_PAGE="https://bradlet.com/train/"
PRIVACY_POLICY="https://bradlet.com/train/privacy/"
TERMS="https://bradlet.com/train/terms/"
AUTHORIZED_DOMAIN="bradlet.com"
# Sheets + Drive are global APIs and the project holds no regional resources,
# so there's no REGION. Add one here if that ever changes.
APIS=(sheets.googleapis.com drive.googleapis.com)

# --- Helpers -----------------------------------------------------------------
log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- Preflight ---------------------------------------------------------------
command -v gcloud >/dev/null 2>&1 \
  || die "gcloud not found — install the Google Cloud SDK first."

ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -n1)"
[[ -n "$ACCOUNT" ]] || die "no active gcloud account — run 'gcloud auth login'."
log "Using gcloud account: $ACCOUNT"

# --- Project -----------------------------------------------------------------
if gcloud projects describe "$PROJECT_ID" --format='value(projectId)' >/dev/null 2>&1; then
  log "Project $PROJECT_ID exists, skipping."
else
  log "Creating project ${PROJECT_ID} (${PROJECT_NAME})..."
  gcloud projects create "$PROJECT_ID" --name="$PROJECT_NAME" \
    || die "could not create $PROJECT_ID. If the ID is taken by another account, set PROJECT_ID to a new one."
fi

# --- APIs --------------------------------------------------------------------
for api in "${APIS[@]}"; do
  enabled="$(gcloud services list --enabled --project="$PROJECT_ID" \
    --filter="config.name=$api" --format='value(config.name)')"
  if [[ "$enabled" == "$api" ]]; then
    log "API $api already enabled, skipping."
  else
    log "Enabling ${api}..."
    gcloud services enable "$api" --project="$PROJECT_ID"
  fi
done

# --- Console-only checklist --------------------------------------------------
CONSOLE="https://console.cloud.google.com/auth"
cat <<EOF

Done with what gcloud can do. Finish these in the console (Google Auth Platform):

  1. Branding      $CONSOLE/branding?project=$PROJECT_ID
       App name: $PROJECT_NAME. Set the user support and developer contact emails.
       Required to publish: home page $HOME_PAGE,
       privacy policy $PRIVACY_POLICY,
       terms of service $TERMS,
       authorized domain $AUTHORIZED_DOMAIN (verify it first in Google Search
       Console as a Domain property, signed in as the project owner).
       Logo: the app icon. Branding verification then runs automatically.
  2. Audience      $CONSOLE/audience?project=$PROJECT_ID
       User type: External. Then "Publish app" so the status is In production.
       (drive.file is non-sensitive: no Google verification. Publishing ends
       the 7-day refresh-token expiry of Testing mode.)
  3. Data access   $CONSOLE/scopes?project=$PROJECT_ID
       Add only $SCOPE
       Never add auth/spreadsheets (sensitive, triggers verification).
  4. Clients       $CONSOLE/clients?project=$PROJECT_ID
       Create client → Application type: iOS → Bundle ID: $BUNDLE_ID
       Team ID: CB9HS9S84R. App Store ID: once the App Store record exists.
       Copy the Client ID (….apps.googleusercontent.com).
  5. Record the Client ID in docs/CONNECTIONS.md, and set GIDClientID plus the
     reversed-client URL scheme in the app's Info.plist (see that doc).
EOF
