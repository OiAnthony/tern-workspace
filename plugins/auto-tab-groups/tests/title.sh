#!/usr/bin/env bash
set -euo pipefail
plugin="${1:-$(dirname "$0")/..}"
checker="$(dirname "$0")/title_pixels.py"
command -v tern >/dev/null
command -v jq >/dev/null
command -v python3 >/dev/null
tmp=$(mktemp -d /tmp/tern-pane-title.XXXXXX)
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
        rm -r "$tmp"
    else
        cat "$tmp/runtime.log" >&2
        printf 'Native title failure artifacts: %s\n' "$tmp" >&2
    fi
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
shot() { ctl shot "$1" | jq -r .png; }
title() {
    printf '\\e]2;%s\\a\\e]133;A\\a' "$1" >"$tmp/title.txt"
    ctl feed "$tmp/title.txt" >/dev/null
    ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
}
blank() {
    ctl css title-reference "$tmp/blank.css" >/dev/null
    shot "$1"
    ctl css title-reference >/dev/null
}
printf '#tabbar .tb-tabs::after { content: none !important; }\n' >"$tmp/blank.css"
ctl ready >/dev/null
ctl new-blocks shell >/dev/null
ctl plugins fixtures >/dev/null
ctl run pwd >/dev/null
ctl account signed-in title-tester >/dev/null
for decoration in system lights buttons; do
    ctl decorations "$decoration" >/dev/null
    ctl dump '#tabbar, #tabbar .tb-in, #tabbar .tn-peers, #tabbar .tn-session-tab' | jq -e '
        .header.viewport.width as $width |
        .elements as $e |
        $e[0].rect[0] == 0 and $e[0].rect[2] == $width and
        $e[2].visible and $e[3].visible and
        $e[2].rect[0] == $e[1].rect[0] and $e[2].rect[0] < 236 and
        $e[3].rect[0] > ($e[2].rect[0] + $e[2].rect[2]) and
        ($e[3].rect[0] + $e[3].rect[2]) <= 236
    ' >/dev/null
    if [[ "$decoration" == lights ]]; then
        ctl dump '#tabbar .tn-peers' | jq -e '.elements[0].rect[0] >= 78' >/dev/null
    fi
    read -r x y < <(ctl dump '#tabbar .tn-peers' | jq -r '.elements[0].rect | "\(.[0] + .[2]/2) \(.[1] + .[3]/2)"')
    ctl pick "$x" "$y" | jq -e '.path | contains("tn-peer")' >/dev/null
    read -r x y < <(ctl dump '#tabbar .tn-session-tab' | jq -r '.elements[0].rect | "\(.[0] + .[2]/2) \(.[1] + .[3]/2)"')
    ctl click "$x" "$y" >/dev/null
    ctl state | jq -e '.palette_scope == "Sessions"' >/dev/null
    ctl key escape >/dev/null
done
ctl decorations system >/dev/null
echo 'Native leading controls: avatar/session left-aligned, decoration safe area and session click PASS'
first=$(ctl state | jq -r .focused.id)
ctl split right >/dev/null
ctl ready >/dev/null
ctl run pwd >/dev/null
second=$(ctl state | jq -r .focused.id)
title 'Focused Beta'
ctl plugins run "plugin.auto-tab-groups.pane-$first" >/dev/null
title 'Focused Alpha'
reference=$(blank blank)
a=$(shot alpha)
python3 "$checker" center 1280 "$reference" "$a"
ctl plugins run "plugin.auto-tab-groups.pane-$second" >/dev/null
b=$(shot beta)
python3 "$checker" different 1280 "$a" "$b"
ctl plugins run "plugin.auto-tab-groups.pane-$first" >/dev/null
returned=$(shot returned)
python3 "$checker" same 1280 "$a" "$returned"
group=$(ctl tree '[data-plugin="auto-tab-groups"]' | jq -r '.nodes[].title // "" | select(startswith("plugin.auto-tab-groups.group-"))')
ctl plugins run "$group" >/dev/null
folded=$(shot folded)
python3 "$checker" same 1280 "$a" "$folded"
ctl files show >/dev/null
files=$(shot files)
python3 "$checker" same 1280 "$a" "$files"
ctl files hide >/dev/null
ctl plugins run reload_plugins >/dev/null
ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
reloaded=$(shot reloaded)
python3 "$checker" same 1280 "$a" "$reloaded"
ctl pick 640 20 | jq -e '(.path | contains("sl-plugin")) == false' >/dev/null
# Quotes and backslashes must remain literal text, never executable CSS.
title '中文 "quoted" \\ title'
quoted=$(shot quoted)
python3 "$checker" different 1280 "$a" "$quoted"
ctl resize 800 600 >/dev/null
narrow_reference=$(blank narrow-blank)
narrow=$(shot narrow)
python3 "$checker" same 800 "$narrow_reference" "$narrow"
ctl resize 1280 800 >/dev/null
ctl plugins run plugin.auto-tab-groups.toggle >/dev/null
ctl tabs vertical >/dev/null
ctl status-bar on >/dev/null
ctl dump '#tabbar' | jq -e '.elements[0].rect[0] == 236' >/dev/null
disabled_reference=$(blank disabled-blank)
disabled=$(shot disabled)
python3 "$checker" same 1280 "$disabled_reference" "$disabled"
ctl plugins run plugin.auto-tab-groups.toggle >/dev/null
ctl session new empty-title >/dev/null
ctl ready >/dev/null
ctl close >/dev/null
sleep 1.1
empty_reference=$(blank empty-blank)
empty=$(shot empty)
python3 "$checker" same 1280 "$empty_reference" "$empty"
echo 'Focused title: native paint, whole-window center, split focus, folded project, Files, reload, literal text, narrow/disabled/empty recovery PASS'
