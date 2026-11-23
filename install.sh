#!/bin/sh
set -eu

repo_url=${TERN_PLUGIN_REPO_URL:-https://github.com/OiAnthony/tern-workspace.git}
ref=${TERN_PLUGIN_REF:-main}
force=0
prune=0

usage() {
  cat <<'EOF'
Usage: install.sh [--force] [--prune] [--ref BRANCH_OR_TAG]

Installs every plugin in the repository. The default ref is main.
Set TERN_PLUGIN_REPO_URL or TERN_PLUGIN_REF to override the repository or ref.
Use --force to replace installed copies and --prune to remove installed
plugins that are no longer present in the repository.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)
      force=1
      ;;
    --prune)
      prune=1
      ;;
    --ref)
      [ "$#" -ge 2 ] || { echo "install.sh: --ref requires a value" >&2; exit 2; }
      ref=$2
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "install.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

command -v git >/dev/null 2>&1 || { echo "install.sh: git is required" >&2; exit 1; }
command -v tern >/dev/null 2>&1 || { echo "install.sh: tern is required" >&2; exit 1; }

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tern-workspace.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

git clone --depth 1 --branch "$ref" "$repo_url" "$tmp_dir/repository"

plugin_root=$(tern plugin dir)
managed_file=${TERN_PLUGIN_MANAGED_FILE:-$(dirname "$plugin_root")/.tern-workspace-managed}
desired_ids="$tmp_dir/desired-plugin-ids"
: >"$desired_ids"
for plugin_dir in "$tmp_dir/repository"/plugins/*; do
  if [ -f "$plugin_dir/plugin.toml" ]; then
    awk -F '"' '/^[[:space:]]*id[[:space:]]*=/ { print $2; exit }' \
      "$plugin_dir/plugin.toml" >>"$desired_ids"
  fi
done

for plugin_dir in "$tmp_dir/repository"/plugins/*; do
  if [ -f "$plugin_dir/plugin.toml" ]; then
    if [ "$force" -eq 1 ]; then
      tern plugin install "$plugin_dir" --force
    else
      tern plugin install "$plugin_dir"
    fi
  fi
done

if [ "$prune" -eq 1 ] && [ -f "$managed_file" ]; then
  for manifest in "$plugin_root"/*/plugin.toml; do
    [ -f "$manifest" ] || continue
    plugin_id=$(awk -F '"' '/^[[:space:]]*id[[:space:]]*=/ { print $2; exit }' "$manifest")
    [ -n "$plugin_id" ] || continue
    if grep -Fqx "$plugin_id" "$managed_file" && ! grep -Fqx "$plugin_id" "$desired_ids"; then
      tern plugin remove "$plugin_id"
    fi
  done
fi

state_tmp="$tmp_dir/managed-plugin-ids"
sort -u "$desired_ids" >"$state_tmp"
cp "$state_tmp" "$managed_file"

tern plugin list
