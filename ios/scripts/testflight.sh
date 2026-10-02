#!/usr/bin/env bash
# Archive the app and upload it to App Store Connect for TestFlight.
#
# Usage: ios/scripts/testflight.sh
#
# Needs, in ios/Config/Local.xcconfig: BANKOFDAD_BUNDLE_ID and DEVELOPMENT_TEAM.
# Family servers are selected at runtime. Xcode must be signed in to that team, and the
# app must already exist in App Store Connect. See ios/README.md.
#
# Environment:
#   BUILD_NUMBER   CFBundleVersion (default: UTC timestamp YYYYMMDD.HHMM, always increasing)
#   UPLOAD=0       export a signed .ipa to ios/build/export instead of uploading
#   ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID
#                  App Store Connect API key (App Manager role) to use instead of the
#                  Xcode account, e.g. on a build machine
set -euo pipefail

cd "$(dirname "$0")/.."
die() { echo "testflight.sh: $*" >&2; exit 1; }

[[ -f Config/Local.xcconfig ]] || die "create Config/Local.xcconfig from Config/Local.xcconfig.example first"
command -v xcodegen >/dev/null || die "install XcodeGen: brew install xcodegen"

xcodegen generate --quiet

settings=$(xcodebuild -showBuildSettings -scheme BankOfDad -configuration Release -destination 'generic/platform=iOS' 2>/dev/null)
setting() { awk -F' = ' -v k="    $1" '$1 == k { print $2; exit }' <<<"$settings"; }
bundle_id=$(setting PRODUCT_BUNDLE_IDENTIFIER)
team=$(setting DEVELOPMENT_TEAM)
version=$(setting MARKETING_VERSION)

[[ -n $team ]] || die "set DEVELOPMENT_TEAM in Config/Local.xcconfig"
[[ $bundle_id != com.example.* ]] || die "set BANKOFDAD_BUNDLE_ID in Config/Local.xcconfig (currently $bundle_id)"

build=${BUILD_NUMBER:-$(date -u +%Y%m%d.%H%M)}
archive=build/BankOfDad.xcarchive
export_dir=build/export
destination=upload
auth=()
if [[ -n ${ASC_KEY_PATH:-} ]]; then
  auth=(-authenticationKeyPath "$ASC_KEY_PATH"
        -authenticationKeyID "${ASC_KEY_ID:?set ASC_KEY_ID with ASC_KEY_PATH}"
        -authenticationKeyIssuerID "${ASC_ISSUER_ID:?set ASC_ISSUER_ID with ASC_KEY_PATH}")
fi
[[ ${UPLOAD:-1} == 0 ]] && destination=export

echo "Archiving $bundle_id $version ($build) for team $team"
rm -rf "$archive" "$export_dir"
xcodebuild archive -quiet \
  -scheme BankOfDad -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive" \
  -allowProvisioningUpdates ${auth[@]+"${auth[@]}"} \
  CURRENT_PROJECT_VERSION="$build"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
options=$tmp/ExportOptions.plist
cat > "$options" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$destination</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
EOF

echo "Exporting ($destination)..."
xcodebuild -exportArchive -quiet \
  -archivePath "$archive" \
  -exportOptionsPlist "$options" \
  -exportPath "$export_dir" \
  -allowProvisioningUpdates ${auth[@]+"${auth[@]}"}

if [[ $destination == upload ]]; then
  echo "Uploaded $version ($build). It appears in App Store Connect > TestFlight after processing (usually 5-15 minutes)."
else
  echo "Exported to ios/$export_dir"
fi
