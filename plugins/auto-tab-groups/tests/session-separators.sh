#!/usr/bin/env bash
set -euo pipefail
plugin="${1:-$(dirname "$0")/..}"
checker="$(dirname "$0")/separator_pixels.py"
command -v tern >/dev/null
command -v jq >/dev/null
command -v python3 >/dev/null
tmp=$(mktemp -d /tmp/tern-session-separators.XXXXXX)
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
mkdir -p "$tmp/crates/tern" "$tmp/crates/plugins/fixtures" "$tmp/config"
cp -R "$plugin" "$tmp/crates/plugins/fixtures/auto-tab-groups"
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
ctl ready >/dev/null
ctl plugins fixtures >/dev/null
ctl run pwd >/dev/null
ctl session new second-session >/dev/null
ctl ready >/dev/null
ctl run pwd >/dev/null
ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
for appearance in light dark; do
    ctl theme "$appearance" "$appearance" >/dev/null
    case "$appearance" in light) mode=Light ;; dark) mode=Dark ;; esac
    code=$(printf 'return cx.settings:set("theme", "%s")' "$mode" | jq -Rs .)
    ctl carly lua "$code" >/dev/null
    ctl carly ok >/dev/null
    ctl carly close >/dev/null
    ctl tree '[data-tone="atg-session"], [data-tone="atg-session-separated"]' | jq -e '
        [.nodes[].text] == ["Default", "second-session"]
    ' >/dev/null
    ctl dump '[data-tone="atg-session"], [data-tone="atg-session-separated"]' >"$tmp/headers.json"
    jq -e --arg theme "$appearance" '.header.theme == $theme' "$tmp/headers.json" >/dev/null
    png=$(ctl shot "separator-$appearance" | jq -r .png)
    python3 "$checker" "$png" "$tmp/headers.json"
    echo "$appearance separator PASS"
done
