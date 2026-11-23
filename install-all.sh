#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

for plugin_dir in "$repo_dir"/plugins/*; do
  if [ -f "$plugin_dir/plugin.toml" ]; then
    tern plugin install "$plugin_dir" "$@"
  fi
done

tern plugin list
