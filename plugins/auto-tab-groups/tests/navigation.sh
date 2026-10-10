#!/usr/bin/env bash
set -euo pipefail

# Exercise native tab actions across project/workspace and session boundaries.
plugin="${1:-$(dirname "$0")/..}"
command -v tern >/dev/null
command -v jq >/dev/null
tmp=$(mktemp -d /tmp/auto-tab-groups-navigation.XXXXXX)
socket="$tmp/control.sock"
pid=""
cleanup() {
    status=$?
    if [[ -n "$pid" ]]; then
        tern ctl --control "$socket" quit >/dev/null 2>&1 || true
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    rm -r "$tmp"
    exit "$status"
}
trap cleanup EXIT
mkdir -p "$tmp/crates/tern" "$tmp/crates/plugins/fixtures" "$tmp/config" "$tmp/alpha" "$tmp/zulu" "$tmp/gamma"
cp -R "$plugin" "$tmp/crates/plugins/fixtures/auto-tab-groups"
STENCIL_FIXTURE_ROOT="$tmp/crates/tern" TERN_CONFIG_DIR="$tmp/config" \
TERN_DAEMON_SOCKET="$tmp/daemon.sock" tern serve --control "$socket" --out "$tmp/shots" \
    </dev/null >"$tmp/runtime.log" 2>&1 &
pid=$!
for ((attempt=0; attempt<100; attempt++)); do
    [[ -S "$socket" ]] && break
    if ! kill -0 "$pid" 2>/dev/null; then cat "$tmp/runtime.log" >&2; exit 1; fi
    sleep 0.1
done
[[ -S "$socket" ]] || { cat "$tmp/runtime.log" >&2; exit 1; }
ctl() { tern ctl --control "$socket" "$@"; }
focus_is() {
    actual=$(ctl state | jq -r '.focused.id')
    [[ "$actual" == "$1" ]] || { printf 'Expected focused pane %s, got %s\n' "$1" "$actual" >&2; exit 1; }
}
change_directory() {
    ctl run "$(printf 'cd "%s"' "$1" | jq -Rs .)" >/dev/null
    ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
}
ctl ready >/dev/null
ctl plugins fixtures >/dev/null
change_directory "$tmp/alpha"
first=$(ctl state | jq -r '.focused.id')
ctl split right >/dev/null
ctl ready >/dev/null
change_directory "$tmp/alpha"
second=$(ctl state | jq -r '.focused.id')
ctl tab new >/dev/null
ctl ready >/dev/null
change_directory "$tmp/zulu"
other=$(ctl state | jq -r '.focused.id')
ctl session new navigation-session >/dev/null
ctl ready >/dev/null
change_directory "$tmp/gamma"
last=$(ctl state | jq -r '.focused.id')
ctl split right >/dev/null
ctl ready >/dev/null
ctl park >/dev/null
ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
ctl plugins run "plugin.auto-tab-groups.pane-$first" >/dev/null
focus_is "$first"

# Side-bar order: Default/alpha (first, second), Default/zulu, navigation-session/gamma.
for target in "$second" "$other" "$last" "$first"; do
    ctl plugins run next_tab >/dev/null
    focus_is "$target"
done
for target in "$last" "$other" "$second" "$first"; do
    ctl plugins run previous_tab >/dev/null
    focus_is "$target"
done
echo 'Native tab actions: cross-project, cross-session, split panes, wraparound and Parked exclusion PASS'

code=$(printf 'cx.settings:bind("ctrl+alt+shift+n", "next_tab"); cx.settings:bind("ctrl+alt+shift+p", "previous_tab")' | jq -Rs .)
ctl carly lua "$code" >/dev/null
ctl carly ok >/dev/null
ctl carly close >/dev/null
ctl plugins run reload_plugins >/dev/null
for target in "$second" "$other" "$last" "$first"; do
    ctl key ctrl+alt+shift+n >/dev/null
    focus_is "$target"
done
ctl key ctrl+alt+shift+p >/dev/null
focus_is "$last"
echo 'Reload and user shortcuts: cross-workspace pane navigation PASS'

ctl plugins run "plugin.auto-tab-groups.pane-$first" >/dev/null
ctl plugins run plugin.auto-tab-groups.toggle >/dev/null
ctl key ctrl+alt+shift+n >/dev/null
focus_is "$other"
ctl key ctrl+alt+shift+p >/dev/null
focus_is "$first"
echo 'Disabled plugin: native tab navigation restored PASS'
