#!/usr/bin/env bash
# Session start for agents working from openai-compat/harness/feature_list.json
# (see .claude/skills/fx-open-setup/SKILL.md). Makes sure the environment builds and runs,
# then prints where things stand. Safe to run every session; the build is incremental.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

echo "repo:   $(pwd)"
echo "branch: $(git branch --show-current 2>/dev/null || echo '?')   head: $(git rev-parse --short HEAD)"
[ -f .env ] || echo "note:   no .env yet — provider tests need a key (install.sh asks for it; the skill says how)"

./openai-compat/install.sh --no-keys

echo
for l in fx-groq fx-openrouter; do
  if command -v "$l" >/dev/null 2>&1; then
    printf '%-14s ' "$l:"; "$l" status --json 2>/dev/null | jq -c '{model, build_revision}' || echo "(status failed)"
  fi
done
echo
echo "next: pick the first task with \"passes\": false in openai-compat/harness/feature_list.json"
echo "      quick proof: ./openai-compat/test.sh fx-groq   (or fx-openrouter)"
