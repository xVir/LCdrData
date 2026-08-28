#!/bin/bash
#
# Builds LCdrData in release configuration and installs it to /Applications.
#
# `--config=release` is not merely an optimisation switch: it sets
# --compilation_mode=opt, which flips the //:release_build config_setting and so
# selects the two-key production entitlements. A debug build installed to
# /Applications runs, but carries get-task-allow and the testmanagerd mach-lookup
# exceptions — see the entitlements select() in LCdrData/BUILD.bazel.
#
# The Bazel output is LCdrData.zip, not a .app directory, so installing means
# unzipping rather than copying. The bundle is only ad-hoc signed: it launches on
# the machine that built it, but Gatekeeper will reject it if copied elsewhere.
#
# Usage:
#   scripts/install-release.sh                  # install to /Applications
#   scripts/install-release.sh ~/Applications   # install elsewhere
#
# Environment:
#   OPEN_AFTER_INSTALL=1   launch the app once it is installed

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

dest_dir="${1:-/Applications}"
app_name="LCdrData.app"
installed="${dest_dir%/}/${app_name}"

if [[ ! -d "${dest_dir}" ]]; then
    echo "error: destination directory does not exist: ${dest_dir}" >&2
    exit 1
fi

echo "==> Building release bundle"
bazel build //LCdrData --config=release

zip_path="$(bazel cquery //LCdrData --config=release --output=files 2>/dev/null | grep '\.zip$' | head -n 1)"
if [[ -z "${zip_path}" || ! -f "${zip_path}" ]]; then
    echo "error: could not locate the built LCdrData.zip" >&2
    exit 1
fi

# A running instance holds its bundle open; replacing it underneath leaves the
# process running stale code and the install looking like it did nothing.
if pgrep -x LCdrData >/dev/null 2>&1; then
    echo "==> Quitting the running LCdrData"
    osascript -e 'quit app "LCdrData"' >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do
        pgrep -x LCdrData >/dev/null 2>&1 || break
        sleep 0.25
    done
    if pgrep -x LCdrData >/dev/null 2>&1; then
        echo "error: LCdrData is still running — quit it and re-run." >&2
        exit 1
    fi
fi

# Unzip to a staging directory first. `unzip -o` overwrites files but never
# removes ones the new build dropped, so unzipping straight over an existing
# install can leave stale resources behind in the bundle.
staging="$(mktemp -d)"
trap 'rm -rf "${staging}"' EXIT

echo "==> Unpacking"
unzip -q -o "${zip_path}" -d "${staging}"

if [[ ! -d "${staging}/${app_name}" ]]; then
    echo "error: ${app_name} not found inside ${zip_path}" >&2
    exit 1
fi

echo "==> Installing to ${installed}"
rm -rf "${installed}"
mv "${staging}/${app_name}" "${installed}"

# The bundle arrives ad-hoc signed from Bazel, but unzipping stamps it with a
# quarantine attribute in some configurations. Strip it so the first launch does
# not hit an unnecessary Gatekeeper prompt on the machine that built it.
xattr -dr com.apple.quarantine "${installed}" 2>/dev/null || true

echo
echo "Installed: ${installed}"
codesign -dv "${installed}" 2>&1 | grep -E '^(Identifier|Signature)' || true

if [[ "${OPEN_AFTER_INSTALL:-0}" == "1" ]]; then
    open "${installed}"
fi
