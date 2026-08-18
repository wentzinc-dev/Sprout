#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "Usage: $0 <notarytool-keychain-profile>"
  exit 64
fi

readonly notary_profile="$1"
readonly project_root="${0:A:h:h}"
readonly artifacts_dir="$project_root/dist"
readonly archive_path="$artifacts_dir/Sprouts.xcarchive"
readonly export_path="$artifacts_dir/export"
readonly zip_path="$artifacts_dir/Sprouts-1.0.zip"
readonly notarized_zip_path="$artifacts_dir/Sprouts-1.0-notarized.zip"

mkdir -p "$artifacts_dir"

xcodebuild archive \
  -project "$project_root/Sprouts.xcodeproj" \
  -scheme Sprouts \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path"

xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$project_root/Config/ExportOptions.plist"

ditto -c -k --keepParent "$export_path/Sprouts.app" "$zip_path"
xcrun notarytool submit "$zip_path" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$export_path/Sprouts.app"
xcrun stapler validate "$export_path/Sprouts.app"
codesign --verify --deep --strict --verbose=2 "$export_path/Sprouts.app"
spctl --assess --type execute --verbose=2 "$export_path/Sprouts.app"
ditto -c -k --keepParent "$export_path/Sprouts.app" "$notarized_zip_path"

print "Notarized app: $export_path/Sprouts.app"
print "Gumroad package: $notarized_zip_path"
