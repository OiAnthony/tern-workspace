#!/usr/bin/env bash
set -euo pipefail

repo=$(mktemp -d /tmp/tern-install-test.XXXXXX)
config=$(mktemp -d /tmp/tern-install-config.XXXXXX)
trap 'rm -rf "$repo" "$config"' EXIT

make_plugin() {
  local id=$1
  mkdir -p "$repo/plugins/$id"
  cat >"$repo/plugins/$id/plugin.toml" <<EOF
schema = 1
id = "$id"
name = "$id"
version = "0.1.0"
window = "window.luau"
EOF
  printf '%s\n' '--!strict' >"$repo/plugins/$id/window.luau"
}

make_plugin first-plugin
make_plugin removed-plugin
git -C "$repo" init -q -b main
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
git -C "$repo" add .
git -C "$repo" commit -qm initial

TERN_PLUGIN_REPO_URL="$repo" TERN_CONFIG_DIR="$config" TERN_DAEMON_SOCKET="$config/daemon.sock" ./install.sh --force --prune >/dev/null
[ -d "$config/plugins/removed-plugin" ]
mkdir -p "$repo/foreign-plugin"
cat >"$repo/foreign-plugin/plugin.toml" <<'EOF'
schema = 1
id = "foreign-plugin"
name = "foreign-plugin"
version = "0.1.0"
window = "window.luau"
EOF
printf '%s\n' '--!strict' >"$repo/foreign-plugin/window.luau"
TERN_CONFIG_DIR="$config" TERN_DAEMON_SOCKET="$config/daemon.sock" tern plugin install "$repo/foreign-plugin" >/dev/null
[ -d "$config/plugins/foreign-plugin" ]

rm -rf "$repo/plugins/removed-plugin"
git -C "$repo" add -A
git -C "$repo" commit -qm remove-plugin
TERN_PLUGIN_REPO_URL="$repo" TERN_CONFIG_DIR="$config" TERN_DAEMON_SOCKET="$config/daemon.sock" ./install.sh --force --prune >/dev/null
[ ! -e "$config/plugins/removed-plugin" ]
[ -d "$config/plugins/foreign-plugin" ]
