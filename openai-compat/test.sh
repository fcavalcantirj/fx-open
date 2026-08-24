#!/usr/bin/env bash
# fx-open smoke test — proves a launcher really works: answers a one-shot prompt, performs a real
# read -> write -> read tool round-trip checked ON DISK, and (if tmux is present) starts the TUI.
#
#   ./openai-compat/test.sh fx-groq        # default
#   ./openai-compat/test.sh fx-openrouter
set -uo pipefail

L="${1:-fx-groq}"
command -v "$L" >/dev/null 2>&1 || { echo "FAIL  $L is not on PATH — run ./openai-compat/install.sh first"; exit 1; }

pass=0; fail=0
ok() { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
ko() { printf 'FAIL  %s\n      %s\n' "$1" "$2"; fail=$((fail + 1)); }
reason() { # $1 = stderr file -> one-line human explanation
  local line; line="$(grep -E 'fx ask:|error|panic' "$1" 2>/dev/null | tail -1)"
  case "$line" in
    *"HTTP 402"*) echo "OpenRouter refused: no credit left for the 65536-token reservation — add credits at https://openrouter.ai/settings/credits" ;;
    *"HTTP 401"*|*"Invalid API Key"*|*"User not found"*) echo "API key rejected — check .env" ;;
    "") echo "no error line captured (see $1)" ;;
    *) echo "$line" ;;
  esac
}

W="$(mktemp -d)"; cd "$W" && git init -q
echo "testing $L in $W"

# 1. version
if v="$("$L" --version 2>"$W/e1")"; then ok "$L --version -> $v"; else ko "$L --version" "$(reason "$W/e1")"; fi

# 2. one-shot answer
if out="$("$L" ask --yolo --no-save "Reply with exactly: OK" 2>"$W/e2")" && printf '%s\n' "$out" | grep -qx 'OK'; then
  ok "one-shot ask answered OK"
else
  ko "one-shot ask" "$(reason "$W/e2")"
fi

# 3. real tool round-trip, verified on disk
printf 'alpha\n' > input.txt
"$L" ask --yolo --no-save "Read input.txt. Create result.txt containing the original word in uppercase followed by -FX. Then read result.txt and tell me its exact contents." >"$W/o3" 2>"$W/e3"
if [ -f result.txt ] && grep -q 'ALPHA-FX' result.txt; then
  ok "tool round-trip: result.txt = $(tr -d '\n' < result.txt)"
else
  ko "tool round-trip (result.txt missing or wrong)" "$(reason "$W/e3")"
fi

# 4. interactive TUI (optional, needs tmux)
if command -v tmux >/dev/null 2>&1; then
  s="fxopen$$"
  tmux new -d -s "$s" -x 120 -y 30 -c "$W" "$L 2>$W/e4" 2>/dev/null
  sleep 8
  if tmux capture-pane -pt "$s" 2>/dev/null | grep -q 'Run /help for commands'; then
    ok "interactive TUI started"
  else
    ko "interactive TUI" "$(tail -2 "$W/e4" 2>/dev/null | tr '\n' ' ')"
  fi
  tmux send-keys -t "$s" '/quit' Enter 2>/dev/null; sleep 2; tmux kill-session -t "$s" 2>/dev/null
else
  echo "SKIP  interactive TUI (tmux not installed)"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
