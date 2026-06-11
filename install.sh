#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$SCRIPT_DIR/skills/roadmap-orchestrator"
SKILL_NAME="roadmap-orchestrator"

TARGETS=(
  "$HOME/.claude/skills/$SKILL_NAME"
  "$HOME/.agents/skills/$SKILL_NAME"
)

install_link() {
  local target="$1"
  local parent
  parent="$(dirname "$target")"

  # Create parent directory if needed
  if [ ! -d "$parent" ]; then
    mkdir -p "$parent"
    echo "  created $parent"
  fi

  # Already a symlink pointing to the right place — idempotent, skip
  if [ -L "$target" ]; then
    local current_dest
    current_dest="$(readlink "$target")"
    if [ "$current_dest" = "$SKILL_SRC" ]; then
      echo "  ok      $target → $SKILL_SRC"
      return 0
    else
      echo "  update  $target (was → $current_dest)"
      rm "$target"
    fi
  fi

  # Target exists as a real directory — refuse to overwrite
  if [ -d "$target" ]; then
    echo "  ERROR   $target exists as a real directory (not a symlink)."
    echo "          Remove or rename it manually, then re-run install.sh."
    exit 1
  fi

  ln -s "$SKILL_SRC" "$target"
  echo "  linked  $target → $SKILL_SRC"
}

echo "Installing $SKILL_NAME skill..."
for t in "${TARGETS[@]}"; do
  install_link "$t"
done

echo ""
echo "Verify symlinks:"
for t in "${TARGETS[@]}"; do
  ls -la "$t"
done

# Warn if ~/.deepcode/settings.json has loose permissions (it may contain the API key)
DEEPCODE_SETTINGS="$HOME/.deepcode/settings.json"
if [ -f "$DEEPCODE_SETTINGS" ]; then
  perms="$(stat -f "%Lp" "$DEEPCODE_SETTINGS" 2>/dev/null || stat -c "%a" "$DEEPCODE_SETTINGS" 2>/dev/null || echo "unknown")"
  if [ "$perms" != "600" ] && [ "$perms" != "unknown" ]; then
    echo ""
    echo "  WARNING: $DEEPCODE_SETTINGS has permissions $perms (expected 600)."
    echo "           Run: chmod 600 $DEEPCODE_SETTINGS"
  fi
fi

echo ""
echo "Done. Start a new Claude Code session and type:"
echo "  работаем по роадмапу"
