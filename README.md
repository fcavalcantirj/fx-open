# fx-open — fx on Groq / OpenRouter

> ## WHY THIS FORK
>
> - Upstream [`vercel-labs/fx`](https://github.com/vercel-labs/fx) only speaks Vercel AI Gateway's own wire (plus ChatGPT and Grok subscription OAuth). There is **no way to point it at Groq, OpenRouter, Ollama, LiteLLM or any OpenAI-compatible endpoint** — its only base-URL overrides are loopback-only test hooks.
> - Upstream [PR #168](https://github.com/vercel-labs/fx/pull/168) adds a real OpenAI-compatible provider, but it is an **open draft that conflicts with `main`, never ran upstream CI, and its interactive TUI panics** the moment the provider is active.
> - **This fork = PR #168's head + a 16-line fix for that panic**, built and verified end to end (real read → write → read tool round-trips, streaming, isolation from the Vercel gateway) on **Groq** and **OpenRouter**, shipped as two launchers, `fx-groq` and `fx-openrouter`, that never touch a stock `fx` on your PATH.
> - Intent: get this upstream (the fix belongs on PR #168). Until then, this is a reproducible, working build. Everything here was produced from a 49-task verification ledger (`openai-compat/fx-openai-compat-spec.json`), every task verified.

> ## SETUP & TEST — https://github.com/fcavalcantirj/fx-open
>
> **You need an account with Groq or OpenRouter (or both) — the launchers do nothing without a key.** Get one at [console.groq.com/keys](https://console.groq.com/keys) or [openrouter.ai/settings/keys](https://openrouter.ai/settings/keys). OpenRouter is prepaid and fx reserves 65 536 output tokens per request, so keep a few dollars of credit there.
>
> Tools: Zig **0.16.0** (exact), git, curl, jq. macOS arm64 is what was verified; Linux should work the same (pick your tarball).
>
> ```bash
> # 1. Zig 0.16.0 — self-contained, stays off your PATH
> mkdir -p ~/.local/lib && cd ~/.local/lib
> curl -fsSLO https://ziglang.org/download/0.16.0/zig-aarch64-macos-0.16.0.tar.xz     # other platforms: https://ziglang.org/download/
> tar -xJf zig-aarch64-macos-0.16.0.tar.xz && mv zig-aarch64-macos-0.16.0 zig-0.16.0 && rm zig-aarch64-macos-0.16.0.tar.xz
>
> # 2. This repo, buildable branch
> git clone https://github.com/fcavalcantirj/fx-open.git ~/dev/fx-open
> cd ~/dev/fx-open && git switch openai-compat
> ~/.local/lib/zig-0.16.0/zig build -Doptimize=ReleaseSafe                              # ~2.5–3.5 min cold
> ./zig-out/bin/fx --help | grep 'provider <gateway|codex|grok|openai>'                # must print the line
>
> # 3. Install the binary, launchers and key-free profiles
> mkdir -p ~/.local/lib/fx-openai-compat ~/.local/bin ~/.config/fx-groq ~/.config/fx-openrouter
> cp zig-out/bin/fx ~/.local/lib/fx-openai-compat/fx && chmod 755 ~/.local/lib/fx-openai-compat/fx
> cp openai-compat/launchers/fx-groq openai-compat/launchers/fx-openrouter ~/.local/bin/ && chmod 755 ~/.local/bin/fx-groq ~/.local/bin/fx-openrouter
> install -m 600 openai-compat/profiles/fx-groq.env ~/.config/fx-groq/env
> install -m 600 openai-compat/profiles/fx-openrouter.env ~/.config/fx-openrouter/env
>
> # 4. Keys — ONE private file, gitignored; the launchers source ~/dev/fx-open/.env (edit them if you cloned elsewhere)
> #    Groq: https://console.groq.com/keys   OpenRouter: https://openrouter.ai/settings/keys
> cp openai-compat/.env.example .env && chmod 600 .env && "${EDITOR:-vi}" .env       # GROQ_API_KEY=... / OPENROUTER_API_KEY=...
>
> # 5. Test (~30 s)
> cd $(mktemp -d) && git init -q && printf 'alpha\n' > input.txt
> fx-groq ask --yolo --no-save "Reply with exactly: OK"
> fx-groq ask --yolo --no-save "Read input.txt. Create result.txt with the word uppercased followed by -FX." && cat result.txt   # → ALPHA-FX
> fx-groq                                                                                # interactive TUI; /quit to leave
> ```
>
> Swap `fx-groq` for `fx-openrouter` to test OpenRouter. If anything fails, `openai-compat/fx-openai-compat-spec.json` is the exact step-by-step verification path.

> ## OR LET AN AGENT DO IT
>
> Paste this into a coding agent (Claude Code, Codex, fx itself, …). It asks you for the provider and the key, does the steps above, and proves the tool round-trip. Also in `openai-compat/docs/AGENT-SETUP-PROMPT.md`.
>
> ```text
> You are setting up fx-open (https://github.com/fcavalcantirj/fx-open): a build of vercel-labs/fx that talks to Groq or OpenRouter over their OpenAI-compatible APIs. Do the whole job yourself and verify it. Stop only to ask me the two questions in steps 1 and 2.
>
> 1. Ask me: "Groq or OpenRouter?" I must already have an account with that provider — Groq keys: https://console.groq.com/keys, OpenRouter keys: https://openrouter.ai/settings/keys. OpenRouter is prepaid and fx reserves 65536 output tokens per request, so a few dollars of credit are needed.
> 2. Ask me for that provider's API key. Store it ONLY in ~/dev/fx-open/.env (chmod 600) as GROQ_API_KEY=... or OPENROUTER_API_KEY=.... Never print, echo, log or commit it; read it with `read -rs`, not from a command-line argument.
> 3. Install Zig 0.16.0 (exact version) from https://ziglang.org/download/ into ~/.local/lib/zig-0.16.0. Do not put it on PATH and do not use Homebrew (it drags in LLVM).
> 4. git clone https://github.com/fcavalcantirj/fx-open.git ~/dev/fx-open && cd ~/dev/fx-open && git switch openai-compat, then build with ~/.local/lib/zig-0.16.0/zig build -Doptimize=ReleaseSafe (2-4 min) and confirm `./zig-out/bin/fx --help` lists `provider <gateway|codex|grok|openai>`.
> 5. Install exactly as README "SETUP & TEST" step 3: binary to ~/.local/lib/fx-openai-compat/fx, launchers openai-compat/launchers/fx-groq and fx-openrouter to ~/.local/bin/ (chmod 755), profiles openai-compat/profiles/*.env to ~/.config/fx-groq/env and ~/.config/fx-openrouter/env (chmod 600). Never touch, overwrite or upgrade an existing `fx` on PATH; never run `fx upgrade`; never copy anything into ~/.fx/bin.
> 6. Verify with the chosen launcher (fx-groq or fx-openrouter), from a directory outside the repo: `<launcher> --version`; `<launcher> ask --yolo --no-save "Reply with exactly: OK"`; then in a fresh temp git directory containing input.txt with the word alpha: `<launcher> ask --yolo --no-save "Read input.txt. Create result.txt with the word uppercased followed by -FX. Then read result.txt and tell me its exact contents."` and check ON DISK that result.txt contains ALPHA-FX. A reply that claims success while the file is missing is a failure. Finally start `<launcher>` with no arguments, confirm the interactive TUI shows the welcome line and answers a prompt, then /quit.
> 7. Rules: never set FX_PROVIDER; never run `fx provider openai` and never choose a provider or model inside the TUI (both write provider=openai into ~/.fx/settings.json, which a stock fx 0.0.5 rejects). If OpenRouter answers HTTP 402, tell me to add credits — that is not a bug. `status` and `doctor` reporting Gateway auth as missing is expected.
> 8. Report: provider, model, binary path, launcher, and the exact outputs of step 6, with the key masked. The full verified procedure, with expected outputs, is openai-compat/fx-openai-compat-spec.json in the repo — use it whenever a step is unclear.
> ```

## Using it

### Daily use

```bash
cd /path/to/project        # fx uses cwd as the workspace (git repo recommended)
fx-groq                    # interactive TUI on Groq  (default model openai/gpt-oss-120b)
fx-openrouter              # interactive TUI on OpenRouter (default model z-ai/glm-5.3)
```

Inside the TUI: type prompts, `/help`, `/quit`. Avoid `/setup` → *Switch provider* and `/model`: both persist `provider: openai` into the shared `~/.fx/settings.json`, which a stock fx 0.0.5 then rejects (`malformed_settings`).

Headless:

```bash
fx-groq ask "Explain this repo's build system."          # asks before running tools
fx-groq ask --yolo "Fix the typo in README.md"           # no permission prompts
fx-groq ask --yolo --no-save --json "…" | jq .output     # machine-readable, no session saved
```

`--json` payload: `{exit_code, model, output, session_id, steps, tool_calls:[{name,status}]}`.


Inspect / tweak:

- `fx-groq status --json` — `auth: "missing"` is cosmetic on this build (auto-select applies to the agent path); `ask` and the TUI work.
- `fx-groq models` — live catalog (Groq: 13 models; tool-capable are `openai/gpt-oss-120b`, `openai/gpt-oss-20b`, `qwen/qwen3.6-27b`).
- Change model: edit `FX_MODEL` in `~/.config/fx-groq/env` / `~/.config/fx-openrouter/env`. Keys live only in `.env` (see below).

### What is in `openai-compat/`

| Path | Purpose |
|---|---|
| `fx-openai-compat-spec.json` | 49-task build/verify ledger (`category`, `description`, `steps`, `passes`), all verified |
| `patches/0001-openai-compat-tui-catalog-context.patch` | The TUI fix (also committed on the `openai-compat` branch) |
| `launchers/fx-groq`, `launchers/fx-openrouter` | Launchers: unset gateway vars, source `.env` + profile, exec the custom binary |
| `profiles/*.env` | Per-provider profiles, no secrets |
| `tools/gw-capture.py` | Loopback listener used to prove no request reaches a Vercel gateway URL |
| `docs/BUILD_INFO.txt` | Provenance, defects observed, validation notes |
| `docs/TASK-PROMPT.md` | The original task prompt this was built from |

### The TUI fix

PR #168's interactive mode panics (`attempt to use null value`) whenever the OpenAI-compatible provider is active: `src/main.zig` hands the TUI catalog preload `builtin_providers.modelCatalog(.openai)` whose `context` is null, and `src/gateway/openai_compatible_models.zig:20` unwraps it. The CLI path already attaches `startup.openAiCompatibleConfig()`; the patch (+16/−2 in `src/main.zig`) applies the same construction to the preload/warmup paths. `fx ask` was never affected.

### Verified on 2026-08-24

- Build: PR #168 head compiles clean on Zig 0.16.0. Fake-server e2e tests 5/5. Unit tests 8491 pass / 4 skip / 8 fail / 1 crash — the same 9 failures before and after the patch (6 also fail on upstream `main` on this machine, 3 are PR-specific; none affect `fx ask`).
- Groq (`openai/gpt-oss-120b`): auth, catalog, streamed single-delta tool calls, `fx ask`, on-disk read → write → read round-trip (`ALPHA-FX`), multi-step tasks, 13k-char streams, interactive TUI, zero requests to a loopback gateway.
- OpenRouter (`z-ai/glm-5.3`, control `openai/gpt-oss-120b`): same set, including fragmented tool-call arguments and `: OPENROUTER PROCESSING` keepalives; HTTP-level errors surface as `fx ask: API request failed · HTTP 400 · …`.

### Known caveats

- OpenRouter pre-reserves credits for fx's `max_tokens` (65536): a low balance yields `HTTP 402 … requires more credits, or fewer max_tokens` on every request.
- Upstream P1s in PR #168, not patched here: Escape may not abort a streaming reply on the chat wire; a bare SSE EOF is treated as a completed turn; mid-stream `data: {"error": …}` events are not inspected.
- Interactive runs write sessions a stock fx 0.0.5 cannot read (`fx doctor` → `[fail] session … projection_invalid`). Use `--no-save` for throwaways, or keep the custom build's sessions separate.
- `status`/`doctor` report Gateway auth as missing under this env-only configuration.

### Contributing upstream

The right home for the fix is PR #168 itself (`boozedog/fx:feature/openai-compatible-transport`); a PR from `openai-compat` against `vercel-labs/fx` `main` would conflict (main is 100+ commits ahead and renamed the gateway modules PR #168 still imports).

---

## Upstream README (vercel-labs/fx)

```
 ⠀⠀⠀⠀⠀⠀⣠⣾⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀
 ⠀⠀⠀⠀⠀⢰⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
 ⠀⠀⠀⣠⣶⣿⣿⣷⣶⡶⣶⣶⣆⠀⠀⠀⣴⣶⣶⠆
 ⠀⠀⠀⠉⢹⣿⣿⠉⠉⠀⠘⢿⣿⣧⣀⣾⣿⡿⠃⠀             Tiny, open, embeddable, native coding agent.
 ⠀⠀⠀⠀⣼⣿⡏⠀⠀⠀⠀⠀⠻⣿⣿⣿⠟⠀⠀⠀
 ⠀⠀⠀⢀⣿⣿⠃⠀⠀⠀⠀⢠⣦⠘⢿⣿⣷⡀⠀⠀             curl -fsSL https://fx.sh/setup.sh | bash
 ⠀⠀⠀⣸⣿⡟⠀⠀⠀⠀⣰⣿⣿⠗⠀⠻⣿⣿⣄⠀
 ⠀⠀⠀⣿⣿⠇⠀⠀⠀⠾⠿⠿⠋⠀⠀⠀⠘⠿⠿⠦             ⚠ Status: Experimental. Use at your own risk.
  ⠀⣸⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
 ⣿⣿⣿⠟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
```

fx is a coding agent harness and CLI written in Zig, optimized for research and embeddability as part of larger systems.

It focuses on minimalism and performance across the board, from system prompt design to its tools, feature set, and 7.8 MiB binary.

For end users, its CLI output style and form factor aim to be closer to a Unix shell than a heavy "IDE in the terminal" TUI.

It's open source (Apache-2.0), model-agnostic, and suitable for both local and cloud inference.

## Install

```bash
curl -fsSL https://fx.sh/setup.sh | bash
```

## Run fx

Sign in with Vercel AI Gateway:

```bash
fx login
```

Or use an eligible ChatGPT subscription through OpenAI Codex OAuth:

```bash
fx login codex
fx
```

`fx login codex` selects Codex and a model from its authenticated catalog. Use `/logout codex` to remove the Codex session without affecting Vercel access.

To use a direct OpenAI or OpenAI-compatible API instead of Vercel AI Gateway, set `OPENAI_API_KEY` (or `LITELLM_API_KEY` for LiteLLM proxies) and optionally configure the endpoint in `~/.fx/settings.json`:

```json
{
  "openai_api_key": "sk-...",
  "openai_base_url": "https://api.openai.com/v1",
  "openai_api_style": "chat",
  "openai_model": "gpt-4o"
}
```

Use `openai_api_style` `responses` for servers that expose the OpenAI Responses API instead of Chat Completions. When Gateway credentials are absent and an OpenAI key is configured, fx auto-selects the OpenAI-compatible provider. Run `fx provider openai` to switch explicitly.

Or use an eligible Grok subscription through xAI OAuth:

```bash
fx login grok
fx
```

`fx login codex` and `fx login grok` select that provider and a model from its authenticated catalog. Inside fx, open `/setup` and choose **Switch provider** to move between Gateway, Codex, Grok, and OpenAI-compatible. `/model` lists the active provider's fetched models. Subscription model IDs are the raw IDs returned by each authenticated catalog. Use `/logout codex` or `/logout grok` to remove that subscription session without affecting other providers; choosing it again from **Switch provider** starts sign-in.

The OpenAI Codex route uses ChatGPT subscription access directly and never sends its OAuth token to Vercel AI Gateway. The session is stored privately at `~/.fx/chatgpt-auth.json` and refreshed when needed. On supported Codex models, `/fast` requests OpenAI's priority service tier and consumes ChatGPT credits at the higher Fast mode rate.

The Grok route uses subscription access directly at xAI and never sends its OAuth token to Vercel AI Gateway or OpenAI. Its session is stored privately at `~/.fx/grok-auth.json`, refreshed when needed, and used only with the authenticated xAI catalog and Responses API.

To use an AI Gateway API key instead:

```bash
fx setup
```

Run fx from a project:

```bash
cd your_project
fx
```

The current directory becomes the primary workspace. Enter a prompt, or run `/help` to browse interactive commands.

The status line hides the workspace path and Git branch by default. Enable the `Status line workspace` option in `/settings`, run `/statusline workspace`, or set it in `~/.fx/settings.json`:

```json
{
  "statusLine": {
    "workspace": true
  }
}
```

List saved sessions with `fx sessions`. Resume the latest session for the current workspace, or select an exact session ID, through the same command group:

```bash
fx session resume last
fx session resume --id <id>
```

Each interactive session names its terminal tab. The title prefers the session name, falls back to the workspace name, and keeps the active model as secondary context. Renaming or resuming a session updates the tab, and exiting clears the fx-owned title. Noninteractive commands do not emit terminal-title controls.

Run `/feedback` to open the feedback form at `fx.sh/feedback`. It does not create a diagnostic or change the clipboard.

Run `/trace` to create a private Markdown diagnostic with logs, session context, runtime state, permissions, and recent activity. On macOS, fx copies the `.md` file to the clipboard; on other platforms, it saves the file and prints its path. Review and redact the trace before sharing it.

Use `fx ask` for a single request:

```bash
fx ask "explain the changes in this repository"
```

fx starts in `auto` permission mode. Routine understood development actions run directly; unresolved sensitive actions receive one bounded automatic review. A blocked action may return an exact approval request that the agent can send to fx's real permission screen. Ordinary question text never grants permission. See [Permissions](https://fx.sh/docs/configure-fx/permissions) for other modes and persistent rules.

JSON and quiet requests stay noninteractive by default. Add `--prompt-permissions` to allow the existing Y/N approval prompt when stdin is a TTY. Prompt text is written to stderr, so JSON stdout stays parseable and quiet stdout stays empty. Piped or redirected stdin remains noninteractive and fails instead of waiting for approval.

Inside a saved session, `/permissions remember <allow|deny> <tool-name> <arguments-json>` stores an exact confirmed rule without running the action. `/permissions` lists stable rule IDs, and `/permissions revoke <rule-id>` removes a stored rule even when its original workspace or file state has changed.

## Embed fx

fx builds as a native binary or WebAssembly. Applications embedding fx can provide network transport, session storage, configuration, permission handling, and terminal I/O.

| Surface | Use |
| --- | --- |
| `fx acp` | Connect the native agent to editors and other Agent Client Protocol clients. |
| `createFxAgent()` | Embed the agent core in a JavaScript host with `fx-core.wasm`. |
| `createFxTerminal()` | Embed the interactive terminal with `fx-term.wasm`. |

The WebAssembly SDK is experimental. See the [WebAssembly SDK](sdk/README.md) and [ACP documentation](https://fx.sh/docs/using-fx/acp).

## Extend fx

Add reusable instructions with [skills](https://fx.sh/docs/capabilities/skills), connect external tools through [MCP](https://fx.sh/docs/capabilities/mcp), or delegate independent work to [subagents](https://fx.sh/docs/capabilities/subagents). Project instruction files may link within their scope, and read-only workspace or compatibility skill directories and their primary `SKILL.md` files may link within their owning workspace or home; managed skills, secondary resources, and escaping links remain no-follow. Skills installed via symlinks that resolve outside home or workspace (e.g. Nix store paths) are loaded when their resolved target is inside a directory listed in the `FX_SKILL_SYMLINK_AUTHORITIES` environment variable (colon-separated absolute paths). `fx status` and `fx doctor` report an invalid trusted MCP profile without starting its servers.

## Documentation

Read the [fx documentation](https://fx.sh/docs).

## Build from source

Building fx requires [Zig 0.16.0+](https://ziglang.org/download/):

```bash
git clone https://github.com/vercel-labs/fx.git
cd fx
zig build -Doptimize=ReleaseSafe
./zig-out/bin/fx
```

Run the test suite with `zig build test`. See [CONTRIBUTING.md](CONTRIBUTING.md) for development and contribution guidelines.

## License

[Apache-2.0](LICENSE)

Third-party licenses and attributions are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Credits

Interface sounds by [cuelume](https://github.com/Danilaa1/cuelume).
