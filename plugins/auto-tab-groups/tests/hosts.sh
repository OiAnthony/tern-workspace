#!/usr/bin/env bash
set -euo pipefail

# Native Host visibility must not depend on focused panes or VM reloads.
plugin="${1:-$(dirname "$0")/..}"
command -v tern >/dev/null
command -v jq >/dev/null
tmp=$(mktemp -d /tmp/auto-tab-groups-hosts.XXXXXX)
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
    if ! kill -0 "$pid" 2>/dev/null; then cat "$tmp/runtime.log" >&2; exit 1; fi
    sleep 0.1
done
[[ -S "$socket" ]] || { cat "$tmp/runtime.log" >&2; exit 1; }
ctl() { tern ctl --control "$socket" "$@"; }
failures=0
check_hosts() {
    local stage="$1" visible="$2" result
    result=$(ctl dump '.tn-vt-host, .tn-host-tab')
    if jq -e --argjson visible "$visible" '
        (.elements | map(select(.path | endswith("button.tn-host-tab"))) | length) == 1 and
        (.elements | map(select(.path | endswith("div.tn-vt-host"))) | length) == 2 and
        all(.elements[]; .visible == $visible)
    ' <<<"$result" >/dev/null; then
        printf '%s: Host visibility %s PASS\n' "$stage" "$visible"
    else
        printf '%s: unexpected Host visibility\n%s\n' "$stage" "$result" >&2
        failures=$((failures + 1))
    fi
}
check_empty_navigation() {
    ctl state | jq -e '.focused == null' >/dev/null
    ctl tree '[data-plugin="auto-tab-groups"]' | jq -e '.count == 0' >/dev/null
    ctl dump '#sidebar > nav.tn-vt, #sidebar > .tn-vt-find' | jq -e '
        (.elements | length) == 2 and all(.elements[]; .visible)
    ' >/dev/null
    ctl filter host-empty >/dev/null
    ctl tree '.tn-vt-find input' | jq -e '.nodes[0].value == "host-empty"' >/dev/null
    ctl filter >/dev/null
}
ctl ready >/dev/null
ctl plugins fixtures >/dev/null
ctl run pwd >/dev/null
ctl remote loopback host-check >/dev/null
ctl ready >/dev/null
ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
check_hosts 'Populated remote session' false

ctl session rename host-populated >/dev/null
ctl session new host-empty >/dev/null
ctl ready >/dev/null
ctl close >/dev/null
sleep 1.1
check_empty_navigation
check_hosts 'Empty session fallback' false
ctl plugins run reload_plugins >/dev/null
sleep 1.1
check_empty_navigation
check_hosts 'Reload while empty' false

ctl session switch host-populated >/dev/null
ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
ctl tree '[data-plugin="auto-tab-groups"]' | jq -e '.count > 0' >/dev/null
check_hosts 'Return to populated session' false
ctl plugins run reload_plugins >/dev/null
ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
check_hosts 'Reload while populated' false

# Positive oracle: disabling must restore the same Host elements, not remove them.
ctl plugins run plugin.auto-tab-groups.toggle >/dev/null
ctl tabs vertical >/dev/null
ctl status-bar on >/dev/null
check_hosts 'Disabled native navigation' true
ctl session switch host-empty >/dev/null
ctl plugins run reload_plugins >/dev/null
sleep 1.1
check_hosts 'Disabled reload while empty' true
[[ "$failures" == 0 ]]
