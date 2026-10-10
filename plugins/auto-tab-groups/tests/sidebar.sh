#!/usr/bin/env bash
set -euo pipefail

# Native consumer regression: transparent projects must hide native tabs and preserve empty-session navigation.
plugin="${1:-$(dirname "$0")/..}"
command -v tern >/dev/null
command -v jq >/dev/null
tmp=$(mktemp -d /tmp/auto-tab-groups-sidebar.XXXXXX)
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
ctl ready >/dev/null
baseline=$(ctl state)
ctl plugins fixtures >/dev/null
ctl run pwd >/dev/null
ctl plugins run plugin.auto-tab-groups.refresh >/dev/null

first=$(ctl state | jq -r '.focused.id')
ctl tree '[data-plugin="auto-tab-groups"]' | jq -e --arg command "plugin.auto-tab-groups.pane-$first" '
    [.nodes[] | select(.role == "button") | .title] as $commands |
    ($commands | map(select(startswith("plugin.auto-tab-groups.pane-")))) == [$command] and
    ($commands | map(select(startswith("plugin.auto-tab-groups.tab-"))) | length) == 0
' >/dev/null
ctl split right >/dev/null
ctl ready >/dev/null
ctl run pwd >/dev/null
ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
second=$(ctl state | jq -r '.focused.id')
ctl tree '[data-plugin="auto-tab-groups"]' | jq -e --arg first "plugin.auto-tab-groups.pane-$first" --arg second "plugin.auto-tab-groups.pane-$second" '
    [.nodes[] | .title // "" | select(startswith("plugin.auto-tab-groups.pane-"))] == [$first, $second]
' >/dev/null
row=$(ctl dump "[title='plugin.auto-tab-groups.pane-$first']")
x=$(jq -r '.elements[0].rect | .[0] + .[2] / 2' <<<"$row")
y=$(jq -r '.elements[0].rect | .[1] + .[3] / 2' <<<"$row")
ctl click "$x" "$y" >/dev/null
ctl state | jq -e --argjson first "$first" '.focused.id == $first and .tabs[0].panes == 2' >/dev/null
group=$(ctl tree '[data-plugin="auto-tab-groups"]' | jq -r '.nodes[] | .title // "" | select(startswith("plugin.auto-tab-groups.group-"))')
ctl plugins run "$group" >/dev/null
ctl tree '[data-plugin="auto-tab-groups"]' | jq -e '
    [.nodes[] | .title // "" | select(startswith("plugin.auto-tab-groups.pane-"))] == []
' >/dev/null
ctl plugins run "plugin.auto-tab-groups.pane-$second" >/dev/null
ctl state | jq -e --argjson second "$second" '.focused.id == $second' >/dev/null
ctl plugins run "$group" >/dev/null

# Native tab actions must follow project panes, even inside one split tab and when folded.
ctl plugins run previous_tab >/dev/null
ctl state | jq -e --argjson first "$first" '.focused.id == $first and .tabs[0].panes == 2' >/dev/null
ctl plugins run previous_tab >/dev/null
ctl state | jq -e --argjson second "$second" '.focused.id == $second' >/dev/null
ctl plugins run next_tab >/dev/null
ctl state | jq -e --argjson first "$first" '.focused.id == $first' >/dev/null
ctl plugins run next_tab >/dev/null
ctl state | jq -e --argjson second "$second" '.focused.id == $second' >/dev/null
ctl plugins run "$group" >/dev/null
ctl plugins run previous_tab >/dev/null
ctl state | jq -e --argjson first "$first" '.focused.id == $first' >/dev/null
ctl plugins run "$group" >/dev/null

# Navigation crosses project boundaries in sidebar order, not native tab order.
ctl tab new >/dev/null
ctl ready >/dev/null
ctl run "$(printf 'cd "%s"' "$tmp" | jq -Rs .)" >/dev/null
ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
other=$(ctl state | jq -r '.focused.id')
ctl plugins run next_tab >/dev/null
ctl state | jq -e --argjson first "$first" '.focused.id == $first' >/dev/null
ctl plugins run previous_tab >/dev/null
ctl state | jq -e --argjson other "$other" '.focused.id == $other' >/dev/null
ctl tab new >/dev/null
ctl ready >/dev/null
ctl run "$(printf 'cd "%s"' "$PWD" | jq -Rs .)" >/dev/null
ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
third=$(ctl state | jq -r '.focused.id')
ctl plugins run next_tab >/dev/null
ctl state | jq -e --argjson other "$other" '.focused.id == $other' >/dev/null
ctl plugins run previous_tab >/dev/null
ctl state | jq -e --argjson third "$third" '.focused.id == $third' >/dev/null

# User bindings still dispatch the native actions.
code=$(printf 'cx.settings:bind("ctrl+alt+shift+n", "next_tab"); cx.settings:bind("ctrl+alt+shift+p", "previous_tab")' | jq -Rs .)
ctl carly lua "$code" >/dev/null
ctl carly ok >/dev/null
ctl carly close >/dev/null
ctl key ctrl+alt+shift+n >/dev/null
ctl state | jq -e --argjson other "$other" '.focused.id == $other' >/dev/null
ctl key ctrl+alt+shift+p >/dev/null
ctl state | jq -e --argjson third "$third" '.focused.id == $third' >/dev/null
ctl plugins run "plugin.auto-tab-groups.pane-$first" >/dev/null
ctl plugins run plugin.auto-tab-groups.toggle >/dev/null
ctl key ctrl+alt+shift+n >/dev/null
ctl state | jq -e --argjson other "$other" '.focused.id == $other' >/dev/null
ctl key ctrl+alt+shift+p >/dev/null
ctl state | jq -e --argjson first "$first" '.focused.id == $first' >/dev/null
ctl plugins run plugin.auto-tab-groups.toggle >/dev/null
ctl plugins run "plugin.auto-tab-groups.pane-$third" >/dev/null
ctl close >/dev/null
ctl plugins run "plugin.auto-tab-groups.pane-$other" >/dev/null
ctl close >/dev/null
ctl plugins run "plugin.auto-tab-groups.pane-$second" >/dev/null
echo 'Native tab actions: sidebar cycle, folded/single/split/cross-tab panes, cross-project navigation, keybindings and disabled fallback PASS'

ctl close >/dev/null
ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
ctl tree '[data-plugin="auto-tab-groups"]' | jq -e --arg first "plugin.auto-tab-groups.pane-$first" '
    [.nodes[] | .title // "" | select(startswith("plugin.auto-tab-groups.pane-"))] == [$first]
' >/dev/null
echo 'Single/split panes: direct navigation, click focus, folded command access and split removal PASS'

printf 'body { background-color: transparent; }\n' >"$tmp/transparent.css"
ctl css transparent-test "$tmp/transparent.css" | jq -e '.errors == []' >/dev/null

for appearance in light dark; do
    ctl theme "$appearance" "$appearance" >/dev/null
    case "$appearance" in light) mode=Light ;; dark) mode=Dark ;; esac
    code=$(printf 'return cx.settings:set("theme", "%s")' "$mode" | jq -Rs .)
    ctl carly lua "$code" >/dev/null
    ctl carly ok >/dev/null
    ctl glass 45 >/dev/null
    ctl dump body | jq -e --arg appearance "$appearance" '
        .header.theme == $appearance and .elements[0].backgroundColor == "rgba(0, 0, 0, 0)"
    ' >/dev/null
    overlay=$(ctl dump .sl-plugins)
    if ! jq -e '.elements[0] | .visible and .backgroundColor == "rgba(0, 0, 0, 0)"' <<<"$overlay" >/dev/null; then
        printf 'Project layer must be transparent in %s appearance:\n%s\n' "$appearance" "$overlay" >&2
        exit 1
    fi
    ctl dump '#sidebar > .tn-vt, #sidebar > .tn-vt-find' | jq -e '
        (.elements | length) >= 3 and all(.elements[]; .visible == false)
    ' >/dev/null
    ctl pick 100 80 | jq -e '.path | contains("sl-plugins")' >/dev/null
    echo "$appearance transparent window: transparent projects; native navigation hidden PASS"
done

ctl session new empty-sidebar-check >/dev/null
ctl ready >/dev/null
ctl close >/dev/null
ctl dump .sl-plugins | jq -e '.elements[0].visible == false' >/dev/null
# Empty windows supply no WindowCx; the metadata tick clears native-navigation CSS.
for ((attempt=0; attempt<30; attempt++)); do
    ctl dump '#sidebar > .tn-vt-find' | jq -e '.elements[0].visible' >/dev/null && break
    sleep 0.1
done
ctl dump '#sidebar > nav.tn-vt, #sidebar > .tn-vt-find' | jq -e '
    (.elements | length) == 2 and all(.elements[]; .visible)
' >/dev/null
ctl filter sidebar-check >/dev/null
ctl tree '.tn-vt-find input' | jq -e '.nodes[0].value == "sidebar-check"' >/dev/null
ctl filter >/dev/null
ctl session switch Default >/dev/null
ctl run pwd >/dev/null
ctl dump .sl-plugins | jq -e '
    .elements[0] | .visible and .backgroundColor == "rgba(0, 0, 0, 0)"
' >/dev/null
ctl dump '#sidebar > .tn-vt, #sidebar > .tn-vt-find' | jq -e '
    (.elements | length) >= 3 and all(.elements[]; .visible == false)
' >/dev/null
echo 'Empty session: native filter restored; populated session: transparent projects restored PASS'

ctl plugins run plugin.auto-tab-groups.toggle >/dev/null
ctl state | jq -e --argjson baseline "$baseline" '
    .tab_orientation == $baseline.tab_orientation and .status_bar == $baseline.status_bar
' >/dev/null
# The baseline uses horizontal tabs. Reveal vertical navigation to check no hidden layer remains.
ctl tabs vertical >/dev/null
ctl status-bar on >/dev/null
ctl dump '#sidebar > nav.tn-vt' | jq -e '.elements[0].visible' >/dev/null
echo 'Disable: original native preferences restored PASS'

ctl plugins run plugin.auto-tab-groups.toggle >/dev/null
ctl split right >/dev/null
ctl ready >/dev/null
ctl run pwd >/dev/null
ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
reloaded=$(ctl state | jq -r '.focused.id')
ctl plugins run reload_plugins >/dev/null
ctl key ctrl+alt+shift+p >/dev/null
ctl state | jq -e --argjson first "$first" '.focused.id == $first' >/dev/null
ctl key ctrl+alt+shift+n >/dev/null
ctl state | jq -e --argjson reloaded "$reloaded" '.focused.id == $reloaded' >/dev/null
echo 'Reload: native tab keybindings still navigate project panes PASS'
