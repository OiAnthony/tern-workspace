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

wait_sessions_count() {
    local expected="$1"
    for ((attempt=0; attempt<20; attempt++)); do
        pump
        local count
        count=$(run_lua 'return tern.json.encode(cx.sessions:list())' | jq 'length')
        if [[ "$count" == "$expected" ]]; then
            return 0
        fi
        sleep 0.1
    done
    run_lua 'return tern.json.encode(cx.sessions:list())' >&2
    return 1
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

# Let initial sync and lifecycle observation run
pump

s1_id=$(run_lua 'return tern.json.encode({ id = cx.sessions:current().id })' | jq -r '.id')
s1_pane=$(run_lua 'return tern.json.encode({ pane = cx.session:focused() })' | jq -r '.pane')

# 1. Closing the last pane of a second session auto-closes it and returns to s1
run_lua "local s = cx.sessions:create({ cwd = [[$tmp/dir-a]] }); return tern.json.encode({ id = s.id })" >/dev/null
wait_current_name "dir-a"
echo "1. Auto-naming new session after cwd PASS"

run_lua 'local p = cx.session:focused(); cx.layout:close(p); return tern.json.encode({ closed = p })' >/dev/null
wait_sessions_count 1
cur_after_close=$(run_lua 'return tern.json.encode({ id = cx.sessions:current().id })' | jq -r '.id')
[[ "$cur_after_close" == "$s1_id" ]]
echo "2. Closing last pane auto-closes empty session and switches back PASS"

# 2. Locked session stays open when emptied
s_lock_id=$(run_lua "local s = cx.sessions:create({ cwd = [[$tmp/dir-b]] }); cx.sessions:lock(s.id); return tern.json.encode({ id = s.id })" | jq -r '.id')
wait_sessions_count 2
run_lua 'local p = cx.session:focused(); cx.layout:close(p); return tern.json.encode({ closed = p })' >/dev/null
sleep 0.35
pump
sleep 0.35
pump
wait_sessions_count 2
run_lua "cx.sessions:unlock($s_lock_id); cx.sessions:close($s_lock_id); return [[ok]]" >/dev/null
wait_sessions_count 1
echo "3. Locked session is preserved when emptied PASS"

# 3. Parking the only pane keeps the session open; closing the parked pane closes the session
run_lua "local s = cx.sessions:create({ cwd = [[$tmp/dir-a]] }); return tern.json.encode({ id = s.id })" >/dev/null
wait_sessions_count 2
parked_pane=$(run_lua 'local p = cx.session:focused(); local ok = cx.layout:park(p); return tern.json.encode({ p = p, ok = ok })' | jq -r '.p')
sleep 0.35
pump
sleep 0.35
pump
wait_sessions_count 2
echo "4. Parking the only pane does not auto-close session PASS"

run_lua "cx.layout:close($parked_pane); return [[ok]]" >/dev/null
wait_sessions_count 1
echo "5. Closing the remaining parked pane auto-closes session PASS"

# 4. Moving the last pane to another session auto-closes the emptied source session
run_lua "local s = cx.sessions:create({ cwd = [[$tmp/dir-b]] }); return tern.json.encode({ id = s.id })" >/dev/null
wait_sessions_count 2
run_lua "local p = cx.session:focused(); local t, err = cx.layout:move_to_new_tab(p, $s1_id); return tern.json.encode({ t = t, err = err })" >/dev/null
wait_sessions_count 1
echo "6. Moving last pane to another session auto-closes emptied source session PASS"

# 5. Closing all panes in the sole remaining session keeps it open without error
run_lua 'for _, p in cx.session:panes() do cx.layout:close(p.pane) end; return [[ok]]' >/dev/null
sleep 0.35
pump
sleep 0.35
pump
wait_sessions_count 1
echo "7. Sole remaining session stays open cleanly when emptied PASS"

echo "ALL auto-session native tests PASSED"
