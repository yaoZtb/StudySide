#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/keban-build.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
app_dir="$build_dir/StudySide.app"
mkdir -p "$build_dir/cache" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
swiftc -parse-as-library -O -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$build_dir/cache" Sources/*.swift -o "$build_dir/StudySide" -framework SwiftUI -framework ScreenCaptureKit -framework Security
cp "$build_dir/StudySide" "$app_dir/Contents/MacOS/StudySide"
cp Info.plist "$app_dir/Contents/Info.plist"
cp Assets/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
cp -R Assets/AnswerRenderer "$app_dir/Contents/Resources/AnswerRenderer"
codesign --force --deep --sign - "$app_dir"
ditto --norsrc "$app_dir" "../StudySide.app"
ditto --norsrc -c -k --keepParent "$app_dir" "../StudySide-Mac.zip"
print "Built: ${PWD:h}/StudySide.app"
