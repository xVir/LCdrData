#!/bin/bash
#
# Runs the LCdrDataUITests suite.
#
# Execution goes through Tuist on purpose, not Bazel. rules_apple's default test
# runner rejects macOS XCUITEST outright, so `bazel test //:LCdrDataUITests`
# cannot drive these at all — see docs/BAZEL_MIGRATION.md section 2.4. Bazel
# still *builds* the target, which is what keeps the sources compiling.
#
# Caveat: this exercises the Xcode-built app, not the Bazel-built one. Validating
# the Bazel bundle is the job of the unit tests and the Phase 7 bundle diff.
#
# Usage:
#   scripts/run-ui-tests.sh                                # whole suite
#   scripts/run-ui-tests.sh PanelSelectionUITests          # one class
#   scripts/run-ui-tests.sh PanelSelectionUITests/testFoo  # one test

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# UI tests drive the app through the accessibility APIs, which need a real Aqua
# login session. Without one they hang until the timeout rather than failing, so
# fail fast with something actionable instead.
if ! launchctl print "gui/$(id -u)" >/dev/null 2>&1; then
    cat >&2 <<'MSG'
error: no GUI login session found for the current user.

macOS UI tests need a real Aqua session and cannot run over SSH or on a
headless CI runner. Run this from a terminal inside a logged-in desktop
session.
MSG
    exit 1
fi

target="LCdrDataUITests"
if [[ $# -gt 0 ]]; then
    target="LCdrDataUITests/$1"
fi

echo "Running UI tests: ${target}"
echo
echo "If this hangs with no output, check System Settings > Privacy & Security >"
echo "Automation and Accessibility — an ungranted permission stalls the runner"
echo "rather than failing it."
echo

# --no-selective-testing: Tuist otherwise skips the run when target hashes are
# unchanged and reports "no tests to run", which is useless for a script whose
# entire purpose is to run these tests.
exec tuist test LCdrData \
    --test-targets "${target}" \
    --no-selective-testing
