#!/bin/sh
set -eu

repo_url=${TERN_PLUGIN_REPO_URL:-https://github.com/OiAnthony/tern-workspace.git}
ref=${TERN_PLUGIN_REF:-main}
force=0

usage() {
  cat <<'EOF'
Usage: install.sh [--force] [--ref BRANCH_OR_TAG]

Installs every plugin in the repository. The default ref is main.
Set TERN_PLUGIN_REPO_URL or TERN_PLUGIN_REF to override the repository or ref.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)
      force=1
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

for plugin_dir in "$tmp_dir/repository"/plugins/*; do
  if [ -f "$plugin_dir/plugin.toml" ]; then
    if [ "$force" -eq 1 ]; then
      tern plugin install "$plugin_dir" --force
    else
      tern plugin install "$plugin_dir"
    fi
  fi
done

tern plugin list
