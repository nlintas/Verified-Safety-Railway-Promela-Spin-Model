#!/bin/zsh

# Double-click this file in Finder to run the short verification suite.
# It is also safe to run from Terminal.

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$SCRIPT_DIR"

cleanup() {
    rm -f pan pan.b pan.c pan.h pan.m pan.p pan.t
    rm -f _spin_nvr.tmp TerminalLine.pml.trail Source/TerminalLine.pml.trail
}
trap cleanup EXIT

if [[ ! -f Source/TerminalLine.pml ]]; then
    echo "ERROR: Source/TerminalLine.pml was not found."
    echo "Run this script from the project copied or cloned from GitHub."
    exit 1
fi

# Finder may not load the user's shell profile.  Include the usual Homebrew
# locations explicitly, especially the Apple Silicon location.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SPIN_BIN=""
if command -v spin >/dev/null 2>&1; then
    SPIN_BIN="$(command -v spin)"
fi

if [[ -z "$SPIN_BIN" ]]; then
    echo "ERROR: SPIN was not found."
    echo "Install it with: brew install spin"
    echo "Then double-click this file again."
    exit 1
fi

echo "TerminalLine verification"
echo "Project: $SCRIPT_DIR"
echo "SPIN:    $SPIN_BIN"
"$SPIN_BIN" -V
echo ""

FAILED=0

run_check() {
    CHECK_NAME="$1"
    shift
    echo "--- $CHECK_NAME ---"
    if "$SPIN_BIN" "$@"; then
        echo "PASS: $CHECK_NAME"
    else
        echo "FAIL: $CHECK_NAME"
        FAILED=1
    fi
    echo ""
}

run_check "exhaustive tunnel safety (p1)" \
    -search -safety -bfs -ltl p1 Source/TerminalLine.pml

run_check "deadlock and assertion search" \
    -search -noclaim -m2000000 Source/TerminalLine.pml

run_check "initial train movement (p2)" \
    -search -ltl p2 Source/TerminalLine.pml

run_check "fair request response smoke test (p4)" \
    -search -ltl p4 -f -DNOREDUCE -DBITSTATE -DNFAIR=4 -w20 -m20000 Source/TerminalLine.pml

run_check "bounded reservation consistency (p3)" \
    -DEXPANDED_VERIFY -search -safety -bfs -ltl p3 -m80 Source/TerminalLine.pml

if [[ "$FAILED" -eq 0 ]]; then
    echo "ALL CHECKS PASSED"
else
    echo "ONE OR MORE CHECKS FAILED"
fi

# Keep a Finder-opened Terminal window visible long enough to read the result.
if [[ -t 0 && -n "${TERM_PROGRAM:-}" ]]; then
    read -k 1 "?Press any key to close this window."
    echo ""
fi

exit "$FAILED"
