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
SPIN_VERSION="$("$SPIN_BIN" -V 2>&1)"
echo "$SPIN_VERSION"
echo ""

FAILED=0
RUN_STARTED_EPOCH="$(date +%s)"
RUN_STARTED_AT="$(date '+%Y-%m-%d %H:%M:%S %Z')"
RUN_ID="$(date '+%Y-%m-%d_%H-%M-%S')-$$"
REPORT_DIR="$SCRIPT_DIR/Verification Reports/$RUN_ID"
LOG_DIR="$REPORT_DIR/logs"
RESULTS_FILE="$REPORT_DIR/results.tsv"

if ! mkdir -p "$LOG_DIR"; then
    echo "ERROR: Could not create the verification report directory:"
    echo "$REPORT_DIR"
    exit 1
fi
: > "$RESULTS_FILE"

run_check() {
    CHECK_NAME="$1"
    CHECK_SLUG="$2"
    CHECK_SCOPE="$3"
    CHECK_METHOD="$4"
    shift 4
    LOG_FILE="$LOG_DIR/$CHECK_SLUG.log"
    COMMAND_LINE="$(printf '%q ' "$SPIN_BIN" "$@")"
    CHECK_STARTED_EPOCH="$(date +%s)"

    echo "--- $CHECK_NAME ---"
    "$SPIN_BIN" "$@" > "$LOG_FILE" 2>&1
    CHECK_STATUS=$?
    cat "$LOG_FILE"

    if [[ "$CHECK_STATUS" -eq 0 ]]; then
        echo "PASS: $CHECK_NAME"
        CHECK_RESULT="PASS"
    else
        echo "FAIL: $CHECK_NAME"
        CHECK_RESULT="FAIL"
        FAILED=1
    fi

    CHECK_DURATION=$(( $(date +%s) - CHECK_STARTED_EPOCH ))
    SUMMARY_LINE="$(grep 'State-vector .*depth reached' "$LOG_FILE" | tail -n 1)"
    CHECK_DEPTH="$(echo "$SUMMARY_LINE" | sed -nE 's/.*depth reached ([0-9]+), errors: ([0-9]+).*/\1/p')"
    CHECK_ERRORS="$(echo "$SUMMARY_LINE" | sed -nE 's/.*depth reached ([0-9]+), errors: ([0-9]+).*/\2/p')"
    CHECK_STATES="$(awk '/states, stored/{print $1; exit}' "$LOG_FILE")"
    CHECK_TRANSITIONS="$(awk '/transitions \(/{print $1; exit}' "$LOG_FILE")"
    CHECK_MEMORY="$(awk '/total actual memory usage/{print $1; exit}' "$LOG_FILE")"

    CHECK_DEPTH="${CHECK_DEPTH:---}"
    CHECK_ERRORS="${CHECK_ERRORS:---}"
    CHECK_STATES="${CHECK_STATES:---}"
    CHECK_TRANSITIONS="${CHECK_TRANSITIONS:---}"
    CHECK_MEMORY="${CHECK_MEMORY:---}"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$CHECK_NAME" "$CHECK_SLUG" "$CHECK_RESULT" "$CHECK_DURATION" \
        "$CHECK_SCOPE" "$CHECK_METHOD" "$CHECK_DEPTH" "$CHECK_ERRORS" \
        "$CHECK_STATES" "$CHECK_TRANSITIONS" "$CHECK_MEMORY" \
        "$COMMAND_LINE" >> "$RESULTS_FILE"
    echo ""
}

run_check "exhaustive tunnel safety (p1)" \
    "p1-tunnel-safety" \
    "Exhaustive safety search: no reachable state has two trains in one tunnel." \
    "Exhaustive BFS" \
    -search -safety -bfs -ltl p1 Source/TerminalLine.pml

run_check "deadlock and assertion search" \
    "deadlock-assertions" \
    "Exhaustive search for invalid end states and failed model assertions." \
    "Exhaustive DFS" \
    -search -noclaim -m2000000 Source/TerminalLine.pml

run_check "initial train movement (p2)" \
    "p2-initial-movement" \
    "Liveness search: the initial system cannot avoid all train movement forever." \
    "Exhaustive DFS liveness" \
    -search -ltl p2 Source/TerminalLine.pml

run_check "fair request response smoke test (p4)" \
    "p4-request-response" \
    "Bitstate smoke test under weak fairness: pending requests receive a response in the explored sample." \
    "Bitstate DFS with fairness" \
    -search -ltl p4 -f -DNOREDUCE -DBITSTATE -DNFAIR=4 -w20 -m20000 Source/TerminalLine.pml

run_check "bounded reservation consistency (p3)" \
    "p3-reservation-consistency" \
    "Depth-bounded search: no occupied tunnel lacked a matching reservation through depth 80." \
    "Depth-bounded BFS" \
    -DEXPANDED_VERIFY -search -safety -bfs -ltl p3 -m80 Source/TerminalLine.pml

generate_report() {
    REPORT_PATH="$REPORT_DIR/verification-report.md"
    RUN_FINISHED_AT="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    RUN_DURATION=$(( $(date +%s) - RUN_STARTED_EPOCH ))
    HOST_NAME="$(scutil --get ComputerName 2>/dev/null || hostname)"
    ARCHITECTURE="$(uname -m)"
    OS_VERSION="$(sw_vers -productVersion 2>/dev/null || uname -sr)"
    GIT_REVISION="not available"
    SOURCE_STATE="not a Git working tree"

    if command -v git >/dev/null 2>&1 && git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        GIT_REVISION="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
        SOURCE_STATE="clean"
        if ! git -C "$SCRIPT_DIR" diff --quiet --ignore-submodules HEAD -- 2>/dev/null; then
            SOURCE_STATE="modified"
        fi
    fi

    if [[ "$FAILED" -eq 0 ]]; then
        OVERALL_RESULT="PASS"
        OUTCOME_TEXT="All five verification checks completed successfully."
    else
        OVERALL_RESULT="FAIL"
        OUTCOME_TEXT="One or more verification checks reported a counterexample, error, or execution failure."
    fi

    if ! {
        echo "# TerminalLine verification report"
        echo ""
        echo "**Overall result: $OVERALL_RESULT** — $OUTCOME_TEXT"
        echo ""
        echo "- Run started: $RUN_STARTED_AT"
        echo "- Run finished: $RUN_FINISHED_AT"
        echo "- Duration: ${RUN_DURATION}s"
        echo "- Source revision: \`$GIT_REVISION\` ($SOURCE_STATE working tree)"
        echo "- SPIN: \`$SPIN_VERSION\`"
        echo "- Host: $HOST_NAME, $OS_VERSION, $ARCHITECTURE"
        echo ""
        echo "## What was established"
        echo ""
        echo "| Result | Verification check | Evidence scope | Time |"
        echo "|---|---|---|---:|"
        while IFS=$'\t' read -r NAME SLUG RESULT DURATION SCOPE METHOD DEPTH ERRORS STATES TRANSITIONS MEMORY COMMAND; do
            echo "| **$RESULT** | [$NAME](logs/$SLUG.log) | $SCOPE | ${DURATION}s |"
        done < "$RESULTS_FILE"
        echo ""
        echo "> A passing exhaustive check is a proof relative to this Promela model, its initial state, and the reported search bounds. The p4 bitstate run is deliberately a smoke test, and p3 is deliberately depth-bounded; neither is presented as an unbounded exhaustive proof."
        echo ""
        echo "## Search statistics"
        echo ""
        echo "| Verification check | Search method | States stored | Transitions explored | Maximum depth | Counterexamples | Memory |"
        echo "|---|---|---:|---:|---:|---:|---:|"
        while IFS=$'\t' read -r NAME SLUG RESULT DURATION SCOPE METHOD DEPTH ERRORS STATES TRANSITIONS MEMORY COMMAND; do
            echo "| $NAME | $METHOD | $STATES | $TRANSITIONS | $DEPTH | $ERRORS | ${MEMORY} MB |"
        done < "$RESULTS_FILE"
        echo ""
        echo "SPIN explores a state graph rather than running a fixed number of test iterations. **States stored** counts distinct model states retained by the verifier, while **transitions explored** is the closest useful equivalent to iterations. Maximum depth is the longest execution path reached, not the number of scenarios tested. **Counterexamples** is SPIN's final property-error count; it does not include an expected depth-limit notice from the bounded p3 run. Bitstate figures are approximate because hash collisions can merge states."
        echo ""
        echo "## Railway and signalling topology"
        echo ""
        echo '```mermaid'
        echo 'flowchart LR'
        echo '    S1["Station 1 / Box 1"] -->|Tunnel 1→2| S2["Station 2 / Box 2"]'
        echo '    S2 -->|Tunnel 2→3| S3["Station 3 / Box 3"]'
        echo '    S3 -->|Tunnel 3→4| S4["Station 4 / Box 4"]'
        echo '    S4 -->|Tunnel 4→1| S1'
        echo '    classDef node fill:#dbeafe,stroke:#2563eb,color:#111827;'
        echo '    class S1,S2,S3,S4 node;'
        echo '```'
        echo ""
        echo "Trains move clockwise. Each local signal box grants departure only when its outgoing tunnel is free, and an arrival releases that tunnel's reservation back to the box behind it."
        echo ""
        echo "## Reproduction commands"
        echo ""
        while IFS=$'\t' read -r NAME SLUG RESULT DURATION SCOPE METHOD DEPTH ERRORS STATES TRANSITIONS MEMORY COMMAND; do
            echo "### $NAME"
            echo ""
            echo '```sh'
            echo "$COMMAND"
            echo '```'
            echo ""
            echo "Full SPIN output: [\`logs/$SLUG.log\`](logs/$SLUG.log)"
            echo ""
        done < "$RESULTS_FILE"
        echo "## Interpretation"
        echo ""
        echo "A PASS means SPIN found no counterexample within that check's stated search method and bounds. A FAIL means the linked log must be inspected for a counterexample, assertion failure, depth limit, resource issue, or tool error."
    } > "$REPORT_PATH"; then
        echo "ERROR: Could not write verification report: $REPORT_PATH"
        return 1
    fi

    rm -f "$RESULTS_FILE"
    echo "Verification report: $REPORT_PATH"
}

if ! generate_report; then
    FAILED=1
fi

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
