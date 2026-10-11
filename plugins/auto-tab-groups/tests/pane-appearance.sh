#!/usr/bin/env bash
set -euo pipefail
plugin="${1:-$(dirname "$0")/..}"
checker="$(dirname "$0")/pane_pixels.py"
command -v tern >/dev/null
command -v jq >/dev/null
command -v python3 >/dev/null

tmp=$(mktemp -d /tmp/auto-tab-groups-pane-appearance.XXXXXX)
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
        printf 'Pane appearance failure artifacts: %s\n' "$tmp" >&2
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
    if ! kill -0 "$pid" 2>/dev/null; then cat "$tmp/runtime.log" >&2; exit 1; fi
    sleep 0.1
done
[[ -S "$socket" ]] || { cat "$tmp/runtime.log" >&2; exit 1; }
ctl() { tern ctl --control "$socket" "$@"; }
shot() { ctl shot "$1" | jq -r .png; }
feed() {
    printf '%b' "$1" >"$tmp/osc.txt"
    ctl feed "$tmp/osc.txt" >/dev/null
    ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
}

ctl ready >/dev/null
ctl plugins fixtures >/dev/null
ctl run pwd >/dev/null
observer=$(ctl state | jq -r .focused.id)
ctl tab new >/dev/null
ctl ready >/dev/null
ctl run pwd >/dev/null
pane=$(ctl state | jq -r .focused.id)
ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
command="plugin.auto-tab-groups.pane-$pane"
long_title='Appearance regression: deliberately long pane title without status decoration'
feed "\\e]2;$long_title\\a\\e]133;A\\a"

ctl tree "[title='$command']" | jq -e --arg title "$long_title" '.nodes | length == 1 and .[0].text == $title' >/dev/null
row=$(ctl dump "[title='$command']")
jq -e '.elements | length == 1 and .[0].visible and .[0].rect[3] >= 30 and .[0].rect[2] > 100 and
    (.[0].fontSize | sub("px$"; "") | tonumber) == 13.5' <<<"$row" >/dev/null
ctl tree "[title='$command'] svg.ico" | jq -e '.count == 0' >/dev/null

for appearance in light dark; do
    ctl theme "$appearance" "$appearance" >/dev/null
    case "$appearance" in light) mode=Light ;; dark) mode=Dark ;; esac
    code=$(printf 'return cx.settings:set("theme", "%s")' "$mode" | jq -Rs .)
    ctl carly lua "$code" >/dev/null
    ctl carly ok >/dev/null
    ctl carly close >/dev/null
    feed '\e]133;A\a'
    geometry=$(ctl dump "[title='$command']")
    jq -e '.elements | length == 1 and .[0].visible and .[0].rect[3] >= 30 and
        (.[0].fontSize | if type == "number" then . else sub("px$"; "") | tonumber end) == 13.5' <<<"$geometry" >/dev/null
    inactive=$(shot "$appearance-inactive-1")
    group_geometry=$(ctl dump "[data-plugin='auto-tab-groups'][data-tone~='atg-group']")
    printf '%s' "$group_geometry" >"$tmp/group-$appearance.json"
    printf '%s' "$geometry" >"$tmp/row-$appearance.json"
    python3 "$(dirname "$0")/layout_pixels.py" "$tmp/group-$appearance.json" "$tmp/row-$appearance.json" "$inactive"
    feed '\e]133;C\a'
    busy1=$(shot "$appearance-busy-1")
    # Sample more than one full native breathing period without resetting Busy.
    pulse=("$busy1")
    for ((frame=1; frame<=5; frame++)); do
        sleep 0.5
        pulse+=("$(shot "$appearance-pulse-$frame")")
    done
    printf '%s' "$geometry" >"$tmp/row-$appearance.json"
    python3 "$checker" "$tmp/row-$appearance.json" "${pulse[@]}"
    feed '\e]133;A\a'
    inactive2=$(shot "$appearance-inactive-2")
    feed '\e]133;C\a'
    busy2=$(shot "$appearance-busy-2")
    feed '\e]133;A\a'
    inactive3=$(shot "$appearance-inactive-3")
    printf '%s' "$geometry" >"$tmp/row-$appearance.json"
    python3 "$checker" "$tmp/row-$appearance.json" "$inactive" "$busy1" "$inactive2" "$busy2" "$inactive3"
    # The native mark and PaneInfo.alert must both clear when the message pane is seen.
    # feed replaces the pane's program with a stand-in; alerts need a fresh real shell.
    ctl tab new >/dev/null
    ctl ready >/dev/null
    ctl run pwd >/dev/null
    notification=$(ctl state | jq -r .focused.id)
    notification_command="plugin.auto-tab-groups.pane-$notification"
    ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
    ctl alert finished unread-message >/dev/null
    ctl plugins run "plugin.auto-tab-groups.pane-$observer" >/dev/null
    ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
    ctl tree '.tn-vt .tn-dk-c[data-st="done"]' | jq -e '.count == 1' >/dev/null
    ctl tree "[title='$notification_command'][data-tone~='atg-alert']" | jq -e '.count == 1' >/dev/null
    ctl dump "[title='$notification_command']" >"$tmp/unread-$appearance.json"
    unread=$(shot "$appearance-unread")
    ctl plugins run "$notification_command" >/dev/null
    ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
    ctl tree '.tn-vt .tn-dk-c[data-st="done"]' | jq -e '.count == 0' >/dev/null
    ctl tree "[title='$notification_command'][data-tone~='atg-alert']" | jq -e '.count == 0' >/dev/null
    read=$(shot "$appearance-read")
    python3 "$checker" "$tmp/unread-$appearance.json" "$unread" "$read"
    ctl plugins run "$command" >/dev/null
done

ctl plugins run reload_plugins >/dev/null
ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
ctl tree "[title='$command']" | jq -e --arg title "$long_title" '.nodes | length == 1 and .[0].text == $title' >/dev/null
reloaded=$(ctl dump "[title='$command']")
jq -e '.elements | length == 1 and .[0].visible and .[0].rect[3] >= 30 and
    (.[0].fontSize | sub("px$"; "") | tonumber) == 13.5' <<<"$reloaded" >/dev/null
ctl plugins run plugin.auto-tab-groups.toggle >/dev/null
ctl tabs vertical >/dev/null
ctl dump '#sidebar > nav.tn-vt' | jq -e '.elements[0].visible' >/dev/null
ctl plugins run plugin.auto-tab-groups.toggle >/dev/null
ctl plugins run plugin.auto-tab-groups.refresh >/dev/null
printf 'Native pane appearance: no terminal glyph, light/dark busy/off and unread/read lamp paint, stable title, reload and disabled navigation recovery PASS\n'
