# Agent setup for fx-open

**Preferred:** open this repo in Claude Code and say *"use the fx-open-setup skill"* (it lives in
`.claude/skills/fx-open-setup/SKILL.md` and drives the task ledger in `openai-compat/harness/` one task at a time).

**Fallback for any coding agent:** paste the block below, run from any directory.

```text
You are setting up fx-open (https://github.com/fcavalcantirj/fx-open): a build of vercel-labs/fx that talks to Groq or OpenRouter over their OpenAI-compatible APIs. Do the whole job yourself and verify it. Stop only to ask me the two questions in steps 1 and 2.

1. Ask me: "Groq or OpenRouter?" I must already have an account with that provider — Groq keys: https://console.groq.com/keys, OpenRouter keys: https://openrouter.ai/settings/keys. OpenRouter is prepaid and fx reserves 65536 output tokens per request, so a few dollars of credit are needed.
2. Ask me for that provider's API key. Store it ONLY in ~/dev/fx-open/.env (chmod 600) as GROQ_API_KEY=... or OPENROUTER_API_KEY=.... Never print, echo, log or commit it; read it with `read -rs`, not from a command-line argument.
3. git clone https://github.com/fcavalcantirj/fx-open.git ~/dev/fx-open && cd ~/dev/fx-open && git switch openai-compat, then run ./openai-compat/install.sh --no-keys. It fetches Zig 0.16.0 into ~/.local/lib (off PATH), builds fx (2-4 min), and installs the binary to ~/.local/lib/fx-openai-compat/fx, the launchers fx-groq / fx-openrouter to ~/.local/bin/, and key-free profiles to ~/.config/fx-groq/env and ~/.config/fx-openrouter/env. Never touch, overwrite or upgrade an existing `fx` on PATH; never run `fx upgrade`; never copy anything into ~/.fx/bin.
4. Verify with ./openai-compat/test.sh <launcher> (fx-groq or fx-openrouter). It must print PASS for: --version, the one-shot answer OK, and the on-disk tool round-trip whose result.txt contains ALPHA-FX (a reply that claims success while the file is missing is a failure), plus the interactive TUI if tmux is installed. Then start <launcher> yourself, confirm the welcome line and that a prompt is answered, and /quit.
5. Rules: never set FX_PROVIDER; never run `fx provider openai` and never choose a provider or model inside the TUI (both write provider=openai into ~/.fx/settings.json, which a stock fx 0.0.5 rejects). If OpenRouter answers HTTP 402, tell me to add credits — that is not a bug. `status` and `doctor` reporting Gateway auth as missing is expected.
6. Report: provider, model, binary path, launcher, and the exact test.sh output, with the key masked. The full verified procedure, with expected outputs, is openai-compat/fx-openai-compat-spec.json — use it whenever a step is unclear.
```
