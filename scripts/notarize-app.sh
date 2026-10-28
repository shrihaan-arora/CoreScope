#!/usr/bin/env bash
# ==============================================================================
# notarize-app.sh — CoreScope Apple Developer ID Signing & Notarization Pipeline
#
# Automates the Apple-supported Developer ID Application code signing, hardened
# runtime enablement, notarytool submission, ticket stapling, and distribution
# packaging for CoreScope.app.
#
# SECURITY REQUIREMENTS:
# - Never commit certificates, keys, or passwords to Git.
# - Do not print secret credentials to build or CI logs.
# - Requires an active Apple Developer Program membership.
#
# SUPPORTED AUTHENTICATION MODES (set via environment variables):
#
# Option A: Keychain Profile (Recommended by Apple)
#   First, run once on your local machine:
#     xcrun notarytool store-credentials "CoreScopeNotary" \
#       --apple-id "your-apple-id@example.com" \
#       --team-id "YOUR_TEAM_ID" \
#       --password "app-specific-password"
#   Then run:
#     KEYCHAIN_PROFILE="CoreScopeNotary" \
#     DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#     ./scripts/notarize-app.sh
#
# Option B: App Store Connect API Key
#   API_KEY_PATH="/path/to/AuthKey_XXXX.p8" \
#   API_KEY_ID="XXXX" \
#   API_KEY_ISSUER="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#   ./scripts/notarize-app.sh
#
# Option C: Direct Credentials (CI environment secrets)
#   APPLE_ID="your-apple-id@example.com" \
#   APPLE_TEAM_ID="YOUR_TEAM_ID" \
#   APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#   ./scripts/notarize-app.sh
# ==============================================================================

set -euo pipefail
# Ensure debug tracing is off so secret environment variables are never printed
set +x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

APP_NAME="CoreScope"
OUTPUT_DIR="${OUTPUT_DIR:-build}"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
APP_VERSION="${APP_VERSION:-1.0.0}"
ZIP_PATH="${OUTPUT_DIR}/${APP_NAME}-${APP_VERSION}-notarized.zip"

echo "======================================================================"
echo " CoreScope Developer ID Signing & Notarization Workflow"
echo "======================================================================"

DEVELOPER_ID="${DEVELOPER_ID:-}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-}"
API_KEY_PATH="${API_KEY_PATH:-}"
API_KEY_ID="${API_KEY_ID:-}"
API_KEY_ISSUER="${API_KEY_ISSUER:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"

# 1. Verify developer identity configuration
if [[ -z "${DEVELOPER_ID}" ]]; then
    echo "ERROR: DEVELOPER_ID environment variable is required." >&2
    echo "Example: DEVELOPER_ID=\"Developer ID Application: Shrihaan Arora (TEAMID)\"" >&2
    echo "" >&2
    echo "Outstanding Maintainer Action:" >&2
    echo "1. Enroll in Apple Developer Program." >&2
    echo "2. Download and install your Developer ID Application certificate into Keychain." >&2
    echo "3. Run 'security find-identity -p codesigning -v' to find your identity string." >&2
    exit 1
fi

# 2. Package release bundle first
echo "==> Packaging base application via scripts/package-app.sh..."
./scripts/package-app.sh

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "ERROR: ${APP_BUNDLE} was not created." >&2
    exit 1
fi

# 3. Apply Apple Developer ID Code Signature with Hardened Runtime & Timestamp
echo "==> Applying Developer ID signature with hardened runtime (--options runtime)..."
codesign --force --deep --options runtime --timestamp \
    --sign "${DEVELOPER_ID}" \
    "${APP_BUNDLE}"

echo "==> Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

# 4. Prepare ZIP archive for notary submission
NOTARY_SUBMISSION_ZIP="${OUTPUT_DIR}/${APP_NAME}-submit.zip"
rm -f "${NOTARY_SUBMISSION_ZIP}"
echo "==> Creating submission archive via ditto..."
ditto -c -k --keepParent "${APP_BUNDLE}" "${NOTARY_SUBMISSION_ZIP}"

# 5. Submit to Apple Notary Service
echo "==> Submitting to Apple Notary Service via xcrun notarytool..."

NOTARY_ARGS=()
if [[ -n "${KEYCHAIN_PROFILE}" ]]; then
    echo "Using stored Keychain profile: ${KEYCHAIN_PROFILE}"
    NOTARY_ARGS=(--keychain-profile "${KEYCHAIN_PROFILE}")
elif [[ -n "${API_KEY_PATH}" && -n "${API_KEY_ID}" && -n "${API_KEY_ISSUER}" ]]; then
    echo "Using App Store Connect API Key: ${API_KEY_ID}"
    NOTARY_ARGS=(--key "${API_KEY_PATH}" --key-id "${API_KEY_ID}" --issuer "${API_KEY_ISSUER}")
elif [[ -n "${APPLE_ID}" && -n "${APPLE_TEAM_ID}" && -n "${APPLE_APP_SPECIFIC_PASSWORD}" ]]; then
    echo "Using Apple ID credentials for team: ${APPLE_TEAM_ID}"
    NOTARY_ARGS=(--apple-id "${APPLE_ID}" --team-id "${APPLE_TEAM_ID}" --password "${APPLE_APP_SPECIFIC_PASSWORD}")
else
    echo "ERROR: No notarization credentials provided." >&2
    echo "Set KEYCHAIN_PROFILE, API_KEY_*, or APPLE_ID/TEAM_ID/APP_SPECIFIC_PASSWORD." >&2
    exit 1
fi

SUBMISSION_LOG="${OUTPUT_DIR}/notary-submission.log"
xcrun notarytool submit "${NOTARY_SUBMISSION_ZIP}" "${NOTARY_ARGS[@]}" --wait | tee "${SUBMISSION_LOG}"

# Check for Accepted status
if grep -q "status: Accepted" "${SUBMISSION_LOG}"; then
    echo "==> Notarization SUCCESSFUL!"
else
    echo "ERROR: Notarization did not return 'Accepted' status. Review log:" >&2
    cat "${SUBMISSION_LOG}" >&2
    exit 1
fi

# 6. Staple notarization ticket to the app bundle
echo "==> Stapling notarization ticket to ${APP_BUNDLE}..."
xcrun stapler staple "${APP_BUNDLE}"

echo "==> Validating stapled ticket..."
xcrun stapler validate "${APP_BUNDLE}"

# 7. Gatekeeper Assessment
echo "==> Verifying Gatekeeper compliance (spctl --assess)..."
spctl --assess --type execute --verbose "${APP_BUNDLE}"

# 8. Create final distributable archive
rm -f "${ZIP_PATH}" "${NOTARY_SUBMISSION_ZIP}" "${SUBMISSION_LOG}"
(cd "${OUTPUT_DIR}" && zip -qry -X "$(basename "${ZIP_PATH}")" "${APP_NAME}.app")

echo "======================================================================"
echo " Notarized Release Package Summary"
echo "======================================================================"
echo "App Bundle:   ${APP_BUNDLE}"
echo "Distribution: ${ZIP_PATH}"
echo "Size:         $(du -sh "${ZIP_PATH}" | awk '{print $1}')"
echo "SHA-256:      $(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"
echo "Gatekeeper:   Ready for global macOS distribution (signed & notarized)"
echo "======================================================================"
