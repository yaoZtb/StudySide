#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/keban-check.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
mkdir -p "$check_dir/cache"
swiftc -parse-as-library -module-cache-path "$check_dir/cache" Sources/Core.swift Tests/CoreTests.swift -o "$check_dir/checks"
"$check_dir/checks"
swiftc -parse-as-library -module-cache-path "$check_dir/cache" Sources/Core.swift Sources/ChatGPTPlan.swift Tests/ChatGPTPlanTests.swift -o "$check_dir/plan-checks"
"$check_dir/plan-checks"
swiftc -parse-as-library -D PREVIEW -module-cache-path "$check_dir/cache" Sources/*.swift Tests/WindowLevelTests.swift -o "$check_dir/window-checks" -framework SwiftUI -framework ScreenCaptureKit -framework Security
"$check_dir/window-checks"

swiftc -parse-as-library -module-cache-path "$check_dir/cache" Sources/Core.swift Sources/LocalSubscriptions.swift Tests/LocalSubscriptionTests.swift -o "$check_dir/local-checks"
"$check_dir/local-checks"

swiftc -parse-as-library -D PREVIEW -module-cache-path "$check_dir/cache" Sources/*.swift Tests/AnswerFormattingTests.swift -o "$check_dir/format-checks" -framework SwiftUI -framework ScreenCaptureKit -framework Security
"$check_dir/format-checks"

swiftc -parse-as-library -module-cache-path "$check_dir/cache" Sources/Core.swift Sources/WindowArrangement.swift Tests/WindowArrangementTests.swift -o "$check_dir/arrangement-checks"
"$check_dir/arrangement-checks"

python3 Tests/SigningIdentityTests.py

swiftc -parse-as-library -D PREVIEW -module-cache-path "$check_dir/cache" Sources/*.swift Tests/AnswerScrollingTests.swift -o "$check_dir/scroll-checks" -framework SwiftUI -framework ScreenCaptureKit -framework Security -framework WebKit
"$check_dir/scroll-checks"
