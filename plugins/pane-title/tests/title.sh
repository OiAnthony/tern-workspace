#!/usr/bin/env bash
set -euo pipefail
plugin="${1:-$(dirname "$0")/..}"
checker="$(dirname "$0")/title_pixels.py"
command -v tern >/dev/null
command -v jq >/dev/null
command -v python3 >/dev/null
command -v vi >/dev/null
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
cp -R "$plugin" "$tmp/crates/plugins/fixtures/pane-title"
if [[ -n "${2:-}" ]]; then cp -R "$2" "$tmp/crates/plugins/fixtures/auto-tab-groups"; fi
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
wait_title() {
    for ((attempt=0; attempt<50; attempt++)); do
        ctl tree '#tabbar .tt.on .nm' | jq -e --arg expected "$1" '.count == 1 and .nodes[0].text == $expected' >/dev/null && return
        sleep 0.1
    done
    ctl tree '#tabbar .tt.on .nm' >&2
    return 1
}
title() {
    printf '\\e]2;%s\\a\\e]133;A\\a' "$1" >"$tmp/title.txt"
    ctl feed "$tmp/title.txt" >/dev/null
    wait_title "${2:-$1}"
}
focus() {
    ctl carly lua "cx.layout:focus($1)" >/dev/null
    ctl carly ok >/dev/null
    ctl carly close >/dev/null
    ctl state | jq -e --argjson pane "$1" '.focused.id == $pane' >/dev/null
}
blank() {
    ctl css title-reference "$tmp/blank.css" >/dev/null
    shot "$1"
    ctl css title-reference >/dev/null
}
printf '#tabbar .tb-tabs > .tt.on { visibility: hidden !important; }\n' >"$tmp/blank.css"
native_icon() {
    ctl dump '#tabbar .tt.on .tn-dk' | jq -e '.elements | length == 1 and .[0].visible' >/dev/null
    local reference painted
    reference=$(blank "$1-blank")
    painted=$(shot "$1")
    ctl dump '#tabbar .tb-tabs, #tabbar .tt.on .tn-dk' >"$tmp/icon-geometry.json"
    python3 "$checker" native 1280 "$reference" "$painted" "$tmp/icon-geometry.json" "${2:-any}"
}
ctl ready >/dev/null
ctl tabs vertical >/dev/null
ctl new-blocks shell >/dev/null
ctl plugins fixtures >/dev/null
ctl run pwd >/dev/null
ctl account signed-in title-tester >/dev/null
for decoration in system lights buttons; do
    ctl decorations "$decoration" >/dev/null
    ctl dump '#tabbar, #tabbar .tb-in, #tabbar .tn-peers, #tabbar .tn-session-tab' >"$tmp/controls.json"
    jq -e '
        .header.viewport.width as $width |
        .elements as $e |
        $e[0].rect[0] == 0 and $e[0].rect[2] == $width and
        $e[2].visible and $e[3].visible and
        $e[2].rect[0] == $e[1].rect[0] and $e[2].rect[0] < 236 and
        $e[3].rect[0] > ($e[2].rect[0] + $e[2].rect[2]) and
        ($e[3].rect[0] + $e[3].rect[2]) <= 480
    ' "$tmp/controls.json" >/dev/null
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
native_icon default-shell
printf 'Native application icon smoke\n' >"$tmp/app.txt"
line=$(printf 'vi "%s"' "$tmp/app.txt" | jq -Rs .)
ctl run "$line" >/dev/null
ctl state | jq -e '.focused.running | startswith("vi ")' >/dev/null
native_icon real-vim vim
ctl key escape >/dev/null
ctl type '":q!"' >/dev/null
ctl key enter >/dev/null
ctl ready >/dev/null
echo 'Native default and real Vim application icons paint without plugin refresh PASS'
first=$(ctl state | jq -r .focused.id)
ctl split right >/dev/null
ctl ready >/dev/null
ctl run pwd >/dev/null
second=$(ctl state | jq -r .focused.id)
ctl dump '#tabbar .tt.on .tn-dk-c' | jq -e '.elements | length == 2 and all(.[]; .visible)' >/dev/null
title 'Focused Beta'
focus "$first"
title 'Focused Alpha'
reference=$(blank blank)
a=$(shot alpha)
python3 "$checker" center 1280 "$reference" "$a"
focus "$second"
b=$(shot beta)
python3 "$checker" different 1280 "$a" "$b"
focus "$first"
returned=$(shot returned)
python3 "$checker" same 1280 "$a" "$returned"
if [[ -n "${2:-}" ]]; then
    group=$(ctl tree '[data-plugin="auto-tab-groups"]' | jq -r '.nodes[].title // "" | select(startswith("plugin.auto-tab-groups.group-"))')
    ctl plugins run "$group" >/dev/null
    folded=$(shot folded)
    python3 "$checker" same 1280 "$a" "$folded"
    ctl plugins run plugin.auto-tab-groups.toggle >/dev/null
    independent=$(shot sidebar-disabled)
    python3 "$checker" same 1280 "$a" "$independent"
fi
ctl files show >/dev/null
files=$(shot files)
python3 "$checker" same 1280 "$a" "$files"
ctl files hide >/dev/null
ctl plugins run reload_plugins >/dev/null
reloaded=$(shot reloaded)
python3 "$checker" same 1280 "$a" "$reloaded"
ctl pick 640 20 | jq -e '(.path | contains("button.tt")) == false' >/dev/null
# Quotes and backslashes must remain literal text, never executable CSS.
title '中文 "quoted" \\ title'
quoted=$(shot quoted)
python3 "$checker" different 1280 "$a" "$quoted"
icon_title='󰖯 TITLE: Native badge'
for appearance in Light Dark; do
    code=$(printf 'cx.settings:set("theme", "%s")' "$appearance" | jq -Rs .)
    ctl carly lua "$code" >/dev/null
    ctl carly ok >/dev/null
    ctl carly close >/dev/null
    title 'Plain title after icon'
    plain=$(shot "plain-$appearance")
    title "$icon_title" 'TITLE: Native badge'
    ctl tree '#tabbar .tt.on .tn-dk-g' | jq -e '.nodes[0].text == "󰖯"' >/dev/null
    native_icon "glyph-$appearance"
    icon_painted=$(shot "icon-$appearance")
    focus "$second"
    wait_title 'Focused Beta'
    no_icon=$(shot "other-pane-$appearance")
    python3 "$checker" different 1280 "$icon_painted" "$no_icon"
    focus "$first"
    wait_title 'TITLE: Native badge'
    restored=$(shot "icon-restored-$appearance")
    python3 "$checker" same 1280 "$icon_painted" "$restored"
    ctl plugins run reload_plugins >/dev/null
    wait_title 'TITLE: Native badge'
    icon_reloaded=$(shot "icon-reloaded-$appearance")
    python3 "$checker" same 1280 "$icon_painted" "$icon_reloaded"
    title 'Plain title after icon'
    plain_restored=$(shot "plain-restored-$appearance")
    python3 "$checker" same 1280 "$plain" "$plain_restored"
done
long_text='TITLE: A deliberately long label that must truncate while keeping its icon visible and the complete group inside the symmetric safe area'
title "󰖯 $long_text" "$long_text"
native_icon long-icon
code=$(printf 'cx.layout:name_tab(cx.session:pane(cx.session:focused()).tab, "Native renamed tab")' | jq -Rs .)
ctl carly lua "$code" >/dev/null
ctl carly ok >/dev/null
ctl carly close >/dev/null
wait_title 'Native renamed tab'
focus "$second"
wait_title 'Native renamed tab'
focus "$first"
wait_title 'Native renamed tab'
ctl tab new >/dev/null
ctl ready >/dev/null
title 'Second native tab'
ctl tree '#tabbar .tt .nm' | jq -e '.count == 1 and .nodes[0].text == "Second native tab"' >/dev/null
focus "$first"
wait_title 'Native renamed tab'
ctl resize 800 600 >/dev/null
narrow_reference=$(blank narrow-blank)
narrow=$(shot narrow)
python3 "$checker" same 800 "$narrow_reference" "$narrow"
ctl resize 1280 800 >/dev/null
ctl plugins run plugin.pane-title.toggle >/dev/null
ctl tabs vertical >/dev/null
ctl status-bar on >/dev/null
ctl dump '#tabbar' | jq -e '.elements[0].rect[0] == 236' >/dev/null
disabled_reference=$(blank disabled-blank)
disabled=$(shot disabled)
python3 "$checker" same 1280 "$disabled_reference" "$disabled"
ctl plugins run plugin.pane-title.toggle >/dev/null
ctl session new empty-title >/dev/null
ctl ready >/dev/null
ctl close >/dev/null
ctl wait 1100 >/dev/null
empty_reference=$(blank empty-blank)
empty=$(shot empty)
python3 "$checker" same 1280 "$empty_reference" "$empty"
ctl plugins run reload_plugins >/dev/null
empty_reloaded=$(shot empty-reloaded)
python3 "$checker" same 1280 "$empty_reference" "$empty_reloaded"
code=$(printf 'cx.sessions:switch("Default")' | jq -Rs .)
ctl carly lua "$code" >/dev/null
ctl carly ok >/dev/null
ctl carly close >/dev/null
wait_title 'Native renamed tab'
native_icon session-return
echo 'Native title reuse: default/application/glyph icons, split composition/focus, native rename, light/dark, Files, reload, clipping and narrow/disabled/empty recovery PASS'
