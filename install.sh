#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET=""

usage() {
    echo "Usage: $0 [--claude|--codex|--gemini|--cursor] [--uninstall]"
    echo ""
    echo "Options:"
    echo "  --claude     Install to ~/.claude/skills/ and ~/.claude/agents/"
    echo "  --codex      Install to ~/.codex/skills/"
    echo "  --gemini     Install to ~/.gemini/skills/"
    echo "  --cursor     Install to ~/.cursor/skills/"
    echo "  --uninstall  Remove installed skills and agents"
    exit 1
}

UNINSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --claude)  TARGET="$HOME/.claude" ;;
        --codex)   TARGET="$HOME/.codex" ;;
        --gemini)  TARGET="$HOME/.gemini" ;;
        --cursor)  TARGET="$HOME/.cursor" ;;
        --uninstall) UNINSTALL=true ;;
        *) usage ;;
    esac
    shift
done

if [ -z "$TARGET" ]; then
    echo "No target specified."
    usage
fi

SKILLS_DIR="$TARGET/skills"
AGENTS_DIR="$TARGET/agents"

if [ "$UNINSTALL" = true ]; then
    echo "Uninstalling embody-ai-research-skills..."
    for skill in "$SCRIPT_DIR"/skills/*/; do
        name=$(basename "$skill")
        if [ -L "$SKILLS_DIR/$name" ] || [ -d "$SKILLS_DIR/$name" ]; then
            rm -rf "$SKILLS_DIR/$name"
            echo "  Removed skill: $name"
        fi
    done
    for agent in "$SCRIPT_DIR"/agents/*.md; do
        name=$(basename "$agent")
        if [ -L "$AGENTS_DIR/$name" ] || [ -f "$AGENTS_DIR/$name" ]; then
            rm -f "$AGENTS_DIR/$name"
            echo "  Removed agent: $name"
        fi
    done
    echo "Done."
    exit 0
fi

echo "Installing embody-ai-research-skills to $TARGET..."

mkdir -p "$SKILLS_DIR" "$AGENTS_DIR"

for skill in "$SCRIPT_DIR"/skills/*/; do
    name=$(basename "$skill")
    ln -sfn "$skill" "$SKILLS_DIR/$name"
    echo "  Installed skill: $name"
done

for agent in "$SCRIPT_DIR"/agents/*.md; do
    name=$(basename "$agent")
    ln -sfn "$agent" "$AGENTS_DIR/$name"
    echo "  Installed agent: $name"
done

echo ""
echo "Done. Installed $(ls -d "$SCRIPT_DIR"/skills/*/ | wc -l) skills and $(ls "$SCRIPT_DIR"/agents/*.md | wc -l) agents."
echo "Restart Claude Code or run /reload-plugins to activate."
