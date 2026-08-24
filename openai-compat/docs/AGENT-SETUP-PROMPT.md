# Agent setup prompt for fx-open

Paste the block below into a coding agent (Claude Code, Codex, fx itself, …) run from any directory.

```text
You are setting up fx-open (https://github.com/fcavalcantirj/fx-open): a build of vercel-labs/fx that talks to Groq or OpenRouter over their OpenAI-compatible APIs. Do the whole job yourself and verify it. Stop only to ask me the two questions in steps 1 and 2.

1. Ask me: "Groq or OpenRouter?" I must already have an account with that provider — Groq keys: https://console.groq.com/keys, OpenRouter keys: https://openrouter.ai/settings/keys. OpenRouter is prepaid and fx reserves 65536 output tokens per request, so a few dollars of credit are needed.
2. Ask me for that provider's API key. Store it ONLY in ~/dev/fx-open/.env (chmod 600) as GROQ_API_KEY=... or OPENROUTER_API_KEY=.... Never print, echo, log or commit it; read it with `read -rs`, not from a command-line argument.
3. Install Zig 0.16.0 (exact version) from https://ziglang.org/download/ into ~/.local/lib/zig-0.16.0. Do not put it on PATH and do not use Homebrew (it drags in LLVM).
4. git clone https://github.com/fcavalcantirj/fx-open.git ~/dev/fx-open && cd ~/dev/fx-open && git switch openai-compat, then build with ~/.local/lib/zig-0.16.0/zig build -Doptimize=ReleaseSafe (2-4 min) and confirm `./zig-out/bin/fx --help` lists `provider <gateway|codex|grok|openai>`.
5. Install exactly as README "SETUP & TEST" step 3: binary to ~/.local/lib/fx-openai-compat/fx, launchers openai-compat/launchers/fx-groq and fx-openrouter to ~/.local/bin/ (chmod 755), profiles openai-compat/profiles/*.env to ~/.config/fx-groq/env and ~/.config/fx-openrouter/env (chmod 600). Never touch, overwrite or upgrade an existing `fx` on PATH; never run `fx upgrade`; never copy anything into ~/.fx/bin.
6. Verify with the chosen launcher (fx-groq or fx-openrouter), from a directory outside the repo: `<launcher> --version`; `<launcher> ask --yolo --no-save "Reply with exactly: OK"`; then in a fresh temp git directory containing input.txt with the word alpha: `<launcher> ask --yolo --no-save "Read input.txt. Create result.txt with the word uppercased followed by -FX. Then read result.txt and tell me its exact contents."` and check ON DISK that result.txt contains ALPHA-FX. A reply that claims success while the file is missing is a failure. Finally start `<launcher>` with no arguments, confirm the interactive TUI shows the welcome line and answers a prompt, then /quit.
7. Rules: never set FX_PROVIDER; never run `fx provider openai` and never choose a provider or model inside the TUI (both write provider=openai into ~/.fx/settings.json, which a stock fx 0.0.5 rejects). If OpenRouter answers HTTP 402, tell me to add credits — that is not a bug. `status` and `doctor` reporting Gateway auth as missing is expected.
8. Report: provider, model, binary path, launcher, and the exact outputs of step 6, with the key masked. The full verified procedure, with expected outputs, is openai-compat/fx-openai-compat-spec.json in the repo — use it whenever a step is unclear.
```
