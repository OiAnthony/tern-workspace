#!/usr/bin/env bash
set -euo pipefail

plugin="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
command -v tern >/dev/null
command -v jq >/dev/null

tmp=$(mktemp -d /tmp/tern-auto-session.XXXXXX)
socket="$tmp/control.sock"
pid=""

cleanup() {
    status=$?
    if [[ -n "$pid" ]]; then
        tern ctl --control "$socket" quit >/dev/null 2>&1 || true
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    if [[ "$status" == 0 ]]; then
        rm -rf "$tmp"
    else
        cat "$tmp/runtime.log" >&2 || true
        printf 'Native auto-session failure artifacts: %s\n' "$tmp" >&2
    fi
    exit "$status"
}
trap cleanup EXIT

mkdir -p "$tmp/crates/tern" "$tmp/crates/plugins/fixtures" "$tmp/config" "$tmp/dir-a" "$tmp/dir-b"
cp -R "$plugin" "$tmp/crates/plugins/fixtures/auto-session"

STENCIL_FIXTURE_ROOT="$tmp/crates/tern" TERN_CONFIG_DIR="$tmp/config" \
TERN_DAEMON_SOCKET="$tmp/daemon.sock" tern serve --control "$socket" --out "$tmp/shots" \
    </dev/null >"$tmp/runtime.log" 2>&1 &
pid=$!

for ((attempt=0; attempt<100; attempt++)); do
    [[ -S "$socket" ]] && break
    kill -0 "$pid" || { cat "$tmp/runtime.log" >&2; exit 1; }
    sleep 0.1
done

ctl() { tern ctl --control "$socket" "$@"; }

run_lua() {
    ctl carly lua "$1" >/dev/null
    ctl carly ok >/dev/null
    local out
    out=$(ctl state | jq -r '.carly.last_tool.text' | awk '/^→ /{sub(/^→ /, ""); print}')
    ctl carly close >/dev/null
    printf '%s\n' "$out"
}

s1_pane=""
pump() {
    if [[ -n "$s1_pane" ]]; then
        run_lua "cx:run($s1_pane, [[ ]])" >/dev/null 2>&1 || true
    fi
}

wait_current_name() {
    local expected="$1"
    for ((attempt=0; attempt<20; attempt++)); do
        pump
        local name
        name=$(run_lua 'return tern.json.encode({ name = cx.sessions:current().name })' | jq -r '.name')
        if [[ "$name" == "$expected" ]]; then
            return 0
        fi
        sleep 0.1
    done
    run_lua 'return tern.json.encode(cx.sessions:current())' >&2
    return 1
}

ctl ready >/dev/null
ctl new-blocks shell >/dev/null
ctl plugins fixtures >/dev/null

# Let initial sync run
pump

s1_pane=$(run_lua 'return tern.json.encode({ pane = cx.session:focused() })' | jq -r '.pane')

# 1. Auto-naming a new session after its main pane cwd
run_lua "local s = cx.sessions:create({ cwd = [[$tmp/dir-a]] }); return tern.json.encode({ id = s.id })" >/dev/null
wait_current_name "dir-a"
echo "1. Auto-naming new session after cwd PASS"

# 2. Updating session name when main pane directory changes
s2_pane=$(run_lua 'return tern.json.encode({ pane = cx.session:focused() })' | jq -r '.pane')
run_lua "await(cx.session:settle($s2_pane, 5000)); cx:run($s2_pane, [[cd $tmp/dir-b]] .. string.char(13)); await(cx.session:settle($s2_pane, 5000)); return [[ok]]" >/dev/null
wait_current_name "dir-b"
echo "2. Updating session name on cwd change PASS"

# 3. Preserving manual rename even after subsequent directory changes
run_lua 'local s = cx.sessions:current(); cx.sessions:rename(s.id, [[Custom Name]]); return [[ok]]' >/dev/null
sleep 0.35
pump
run_lua "cx:run($s2_pane, [[cd $tmp/dir-a]] .. string.char(13)); await(cx.session:settle($s2_pane, 5000)); return [[ok]]" >/dev/null
sleep 0.35
pump
sleep 0.35
pump
wait_current_name "Custom Name"
echo "3. Manual rename locks session name PASS"

echo "ALL auto-session native tests PASSED"
