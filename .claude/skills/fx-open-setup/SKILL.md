---
name: fx-open-setup
description: Set up and verify fx-open (Vercel's fx coding agent on Groq or OpenRouter) from its JSON task ledger, one task per iteration, marking a task as passing only after a real end-to-end check. Use when asked to install, build, test, repair or re-verify fx-open, fx-groq or fx-openrouter, or to work through openai-compat/harness/feature_list.json.
---

# fx-open setup harness

A long-running-agent harness in the shape of Anthropic's "Effective harnesses for long-running agents":
a feature list JSON where every task starts as failing, a progress file that survives sessions, an
`init.sh` that brings the environment up, and a routine that does **one task at a time** and only
marks it passing after testing it the way a user would.

## Files

| File | Role |
|---|---|
| `openai-compat/harness/feature_list.json` | The task ledger. 49 objects `{category, description, steps, passes}`. Only the `passes` field may ever change. Never delete, reorder or edit a task. |
| `openai-compat/harness/claude-progress.txt` | Cross-session log. Append one entry at the end of every session. |
| `openai-compat/harness/init.sh` | Brings the environment up: private Zig 0.16.0, incremental build, install of binary + launchers + profiles, status of both launchers. |
| `openai-compat/install.sh`, `openai-compat/test.sh` | The installer and the 30-second proof (one-shot answer, on-disk tool round-trip, TUI start). |
| `openai-compat/fx-openai-compat-spec.json` | The same 49 tasks as run and verified on 2026-08-24 (all `true`). Read-only reference for expected outputs. |

## Initializer session (first session on a machine)

1. `pwd`; confirm you are in the fx-open checkout on branch `openai-compat` (`git branch --show-current`).
2. Read `openai-compat/harness/init.sh`, `feature_list.json` and `claude-progress.txt`.
3. Ask the user: **"Groq or OpenRouter?"** — they must already have an account: Groq keys at https://console.groq.com/keys, OpenRouter keys at https://openrouter.ai/settings/keys (OpenRouter is prepaid; fx reserves 65536 output tokens per request, so a few dollars of credit are needed).
4. Ask for that provider's API key and store it **only** in `.env` at the repo root (`chmod 600`) as `GROQ_API_KEY=...` or `OPENROUTER_API_KEY=...`. Read it with `read -rs`. Never print, echo, log or commit it. `.env` is gitignored.
5. Run `./openai-compat/harness/init.sh`. Fix nothing else yet.
6. Commit (if anything tracked changed) and append a session entry to `claude-progress.txt`.

## Every session

1. `pwd`, then `git log --oneline -10` and read `openai-compat/harness/claude-progress.txt` to see what the last session did.
2. Open `feature_list.json`; pick the **first** task whose `passes` is `false`. Work on that task only.
3. Run `./openai-compat/harness/init.sh` so the environment is up.
4. Before new work, re-run the basic proof: `./openai-compat/test.sh fx-groq` (or `fx-openrouter`). If it fails, fixing that is the task.
5. Do the task exactly as its `steps` say. Verify it as a user would: the real launcher, the real provider, files checked on disk, the TUI in tmux. A reply that claims a file was written while the file is missing is a failure. Unit tests alone never justify `passes: true`.
6. When and only when every step is verified, change that task's `passes` to `true`. Change nothing else in the file.
7. Commit with a descriptive message. Append an entry to `claude-progress.txt` (what, how verified, what is left). Leave the tree clean and buildable.

## Hard rules (from the verified ledger)

- Never touch, overwrite or upgrade a stock `fx` on PATH; never run `fx upgrade`; never write into `~/.fx/bin`.
- Never set `FX_PROVIDER`; never run `fx provider openai`; never pick a provider or model inside the TUI (`/setup`, `/model`) — they persist `provider: openai` into the shared `~/.fx/settings.json`, which a stock fx rejects.
- Keys live only in `.env`. Profiles and launchers must never contain a literal key.
- `fx status` / `fx doctor` reporting Gateway auth as missing is expected under this configuration; `fx ask` and the TUI are what count.
- OpenRouter `HTTP 402` means the account has no credit for the request — tell the user, do not "fix" it.
- Build only with the private Zig 0.16.0 (`~/.local/lib/zig-0.16.0/zig`); do not put Zig on PATH, do not use Homebrew's Zig.

## Reporting

At the end of a session report: tasks flipped to `true` this session, exact outputs of `test.sh`, anything left failing with the observed error line, and the commit hash. Keys masked everywhere.
