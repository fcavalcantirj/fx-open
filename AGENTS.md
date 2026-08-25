# AGENTS.md

Instructions for AI coding agents working in this directory.

## Project Overview

`/Users/fcavalcanti/dev/fx-open` is the **working and deployment directory** for a
custom, locally-built `fx` binary that talks to **Groq** and **OpenRouter** via
their OpenAI-compatible Chat Completions APIs.

This directory itself is **not** the source tree. It holds configuration, a
verification ledger, and a task spec. All actual code, builds, and tests live in
the source checkout at `~/src/fx-openai-compat/` (a clone of
`vercel-labs/fx`, branch `pr-168-openai-compatible`). See
[Source Checkout](#source-checkout) below.

`fx` is a tiny, open, embeddable, native coding agent and CLI written in
**Zig 0.16.0** by Vercel Labs. The stock fx defaults to Vercel AI Gateway
authentication (`fx login`). This deployment instead uses the **OpenAI-compatible
provider** from upstream PR #168, which supports the `/v1/chat/completions`
wire and the `/v1/responses` wire, with streaming tool calls.

### Provider/model configuration

| Provider | Base URL | API style | Model | Env profile | Launcher |
|---|---|---|---|---|---|
| Groq | `https://api.groq.com/openai/v1` | `chat` | `openai/gpt-oss-120b` | `~/.config/fx-groq/env` | `fx-groq` |
| OpenRouter | `https://openrouter.ai/api/v1` | `chat` | `z-ai/glm-5.3` | `~/.config/fx-openrouter/env` | `fx-openrouter` |

Both launchers unset `AI_GATEWAY_API_KEY`, `VERCEL_OIDC_TOKEN`, `FX_PROVIDER`,
and `OPENAI_API_KEY` before sourcing, then source `.env` and the provider
profile. This guarantees the OpenAI-compatible path is isolated from Vercel
Gateway credentials.

### What lives here

| Path | Purpose |
|---|---|
| `.env` | **Secret store** (mode `600`). Contains `GROQ_API_KEY` and `OPENROUTER_API_KEY`. Never `cat`; never copy; never commit. The only file permitted to hold the keys. |
| `openai-compat/fx-openai-compat-spec.json` | A 49-task verification ledger (all `passes: true`) recorded during the 2026-08-24 spike. Each entry has `category`, `description`, `steps`, `passes`. Read before re-deriving anything. |
| `Local_fx_with_Groq_OpenRouter.md` | The original 19-phase task specification that the ledger tracks (not present in this checkout; referenced for context only). |
| `~/notes/gw-capture.py` | Python 3 `http.server` loopback listener proving no provider key reaches a Vercel gateway URL. |
| `AGENTS.md` | This file. |

### What lives elsewhere (but you must know about)

| Path | Purpose |
|---|---|
| `~/src/fx-openai-compat/` | The fx source checkout. Branch `pr-168-openai-compatible`, HEAD `f0c131c40a2516d024ab96776bc6211598743e16`. Contains one local source modification to `src/main.zig` (the TUI null-context fix). Do all source work here. |
| `~/.local/lib/fx-openai-compat/fx` | The deployed custom binary (ReleaseSafe). Copy of `zig-out/bin/fx` from the checkout. |
| `~/.local/lib/fx-openai-compat/BUILD_INFO` | Non-secret build provenance (repository, commit, models, URLs, shas, known defects, known test failures). |
| `~/.local/lib/fx-openai-compat/BUILD_INFO.patch` | The local source patch (TUI null-context panic fix, `src/main.zig` +16/-2). |
| `~/.local/lib/fx-openai-compat/baseline-main-3e96d2c.test.log` | Unit-test baseline from stock main, for regression comparison. |
| `~/.local/lib/fx-openai-compat/sessions-relocated/` | Sessions created by the custom build that stock fx 0.0.5 cannot read, relocated out of `~/.fx/sessions/`. |
| `~/.local/bin/fx-groq` | Groq launcher script. |
| `~/.local/bin/fx-openrouter` | OpenRouter launcher script. |
| `~/.fx/` | Shared fx profile. `settings.json` contains only `{"yolo_acknowledged":true}`. Stock-compatible. |
| `~/.local/bin/fx` | Stock fx v0.0.5 (sha256 `caad628680cd2af24d79063f109965b71c24f69c7b06318b50178c76cc40d0c9`). Never overwrite, never touch. |
| `~/.local/lib/zig-0.16.0/zig` | Zig 0.16.0 compiler. Not on PATH; invoke by full path. |

## Source Checkout

All source code, builds, and tests happen in **`~/src/fx-openai-compat`**. This
directory is not a git repository. The checkout is.

```bash
cd ~/src/fx-openai-compat
git remote -v              # https://github.com/vercel-labs/fx.git
git branch --show-current  # pr-168-openai-compatible
git rev-parse HEAD         # f0c131c40a2516d024ab96776bc6211598743e16
```

### Local source patch

The checkout has exactly one local modification: **`src/main.zig`**, the TUI
null-context panic fix (+16/-2). It adds `catalogProviderForSelected()`, which
attaches the OpenAI-compatible config context to the catalog provider for `.openai`
before async TUI preload, preventing the `attempt to use null value` panic
(exit 134).

Before making any further source changes, run `git diff` to confirm only
`src/main.zig` is modified. After changing, regenerate the patch:

```bash
cd ~/src/fx-openai-compat
~/.local/lib/zig-0.16.0/zig fmt src/
~/.local/lib/zig-0.16.0/zig build -Doptimize=ReleaseSafe
git diff > ~/src/fx-openai-compat.local.patch
cp ~/src/fx-openai-compat.local.patch ~/.local/lib/fx-openai-compat/BUILD_INFO.patch
```

Never merge or rebase this branch onto `main`: GitHub reports
mergeable=CONFLICTING because `main` renamed
`src/core/gateway/gateway_json.zig` to `src/gateway/vercel_protocol.zig`, which
the PR's new files still import. The PR head tree is self-consistent and is what
gets built.

## Build and Test Commands

### Prerequisites

- **Zig 0.16.0** at `~/.local/lib/zig-0.16.0/zig` (not on PATH).
  Do not `brew install zig`; it pulls `llvm@21` and `lld@21` and is not
  version-pinned.

### Build

```bash
cd ~/src/fx-openai-compat
~/.local/lib/zig-0.16.0/zig build -Doptimize=ReleaseSafe
```

After building:

```bash
./zig-out/bin/fx --version          # 0.0.5
./zig-out/bin/fx --help             # confirm "provider <gateway|codex|grok|openai>"
./zig-out/bin/fx provider 2>&1 | head -1   # usage: fx provider <gateway|codex|grok|openai>
```

### Run unit tests

```bash
cd ~/src/fx-openai-compat
H=$(mktemp -d)
HOME=$H ~/.local/lib/zig-0.16.0/zig build test -Doptimize=ReleaseSafe 2>&1 | tee test.log
```

Takes ~7 minutes. Exit code 1 is expected due to known pre-existing failures.
Expected baseline: **8491 pass / 4 skip / 8 fail / 1 crash** (8504 total), identical
to stock `origin/main` 3e96d2c. New failing test names beyond the 9 recorded in
`BUILD_INFO` (`known_unit_test_failures_*`) are regressions.

### Run e2e tests (TypeScript, Bun)

The fake-server tests for the OpenAI-compatible wires:

```bash
cd ~/src/fx-openai-compat/tests/e2e
bun install
bun test --max-concurrency 1 ./openai-compatible-fake.test.ts ./openai-responses-fake.test.ts 2>&1 | tee ../../e2e-openai.log
```

Expected: **5 pass, 0 fail** with Bun 1.3.13+. These are the template for
headless runs: isolated HOME, `OPENAI_API_KEY` set, `AI_GATEWAY_API_KEY` and
`VERCEL_OIDC_TOKEN` unset, `FX_MODEL` set, `FX_SKIP_ONBOARDING=1`,
`FX_OPENAI_BASE_URL` set, invoked as `fx ask --yolo --json --no-save`.

Full e2e suite (TUI tests require `tmux`):

```bash
cd ~/src/fx-openai-compat/tests/e2e
bun install
bun test                    # all e2e tests
bun test cli.test.ts        # CLI only
bun test acp.test.ts        # ACP protocol only
bun test tui-*.test.ts      # TUI tests (require tmux)
```

### Format source

```bash
cd ~/src/fx-openai-compat
~/.local/lib/zig-0.16.0/zig fmt src/
~/.local/lib/zig-0.16.0/zig fmt --check src/   # check without writing
```

## How to Use the Deployed Launchers

```bash
# Groq
cd /path/to/project
fx-groq

# OpenRouter
cd /path/to/project
fx-openrouter
```

Both are on PATH via `~/.local/bin`. The existing stock `fx` at `~/.local/bin/fx`
(v0.0.5) is untouched and independent.

### Verification commands

```bash
fx-groq --version                                       # 0.0.5
fx-groq status --json | jq -c '{model, build_revision}' # openai/gpt-oss-120b, f0c131c40a25
fx-groq ask --yolo --no-save "Reply with exactly: GROQ_FX_OK"  # GROQ_FX_OK

fx-openrouter --version                                 # 0.0.0
fx-openrouter status --json | jq -c '{model, build_revision}' # z-ai/glm-5.3, f0c131c40a25
fx-openrouter ask --yolo --no-save "Reply with exactly: OPENROUTER_FX_OK" # OPENROUTER_FX_OK
```

Under env-only configuration (no persisted provider in `~/.fx/settings.json`),
`fx status`/`fx doctor` report `auth: "missing"` — this is expected and does
not affect `fx ask`, which auto-selects the OpenAI-compatible provider when
`OPENAI_API_KEY` is set and no Gateway credential is present.

### Always use the built binary for verification

When verifying source changes, always use the freshly-built binary at
`~/src/fx-openai-compat/zig-out/bin/fx`, not bare `fx` from PATH (which may be
stock v0.0.5 from `~/.local/bin/fx`).

## Testing Instructions (Acceptance Criteria)

The spike verification ledger (`fx-openai-compat-spec.json`) encodes 49 tasks, all
passing. Key acceptance tests:

### 1. Provider API first

Authenticate and list models via raw `curl` before testing fx:

```bash
# Groq (using the env profile)
source ~/.config/fx-groq/env
curl -s -o /dev/null -w '%{http_code}' https://api.groq.com/openai/v1/models   # 401 without key
curl -s -H "Authorization: Bearer $OPENAI_API_KEY" https://api.groq.com/openai/v1/models | jq '.data|length'  # 13

# OpenRouter
source ~/.config/fx-openrouter/env
curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $OPENAI_API_KEY" https://openrouter.ai/api/v1/key  # 200
curl -s https://openrouter.ai/api/v1/models | jq '.data|length'  # 417
```

Verify the chosen model supports tool calling:

```bash
# Groq: check supported_features
jq -r '.data[] | select(.active==true) | select(has("supported_features") and (.supported_features|index("tools"))) | .id' /tmp/groq-models.json

# OpenRouter: check supported_parameters (filter client-side)
jq -r '.data[] | select(.supported_parameters != null) | select((.supported_parameters|index("tools")) and (.supported_parameters|index("tool_choice"))) | select(.id | test("^~|^openrouter/|:free$|:batch$") | not) | .id' /tmp/or-models.json
```

### 2. Raw Chat Completions

For each provider, test:
- Non-streaming completion
- Streaming completion
- Tool/function-call request with `tool_choice:"auto"`

Groq chunks use single-delta tool arguments; OpenRouter uses fragmented arguments.
Both are handled by fx's SSE parser. Never use `tool_choice:"required"` — Groq
returns HTTP 400 with `code: tool_use_failed`.

The tool definition used for testing:

```json
{"type":"function","function":{"name":"get_test_value","description":"Return the test value for a key","parameters":{"type":"object","properties":{"key":{"type":"string"}},"required":["key"]}}}
```

### 3. Key isolation (loopback capture)

```bash
: > /tmp/gw-capture.log
python3 ~/src/fx-openai-compat/notes/gw-capture.py 18080 /tmp/gw-capture.log &
# then run fx ask with FX_GATEWAY_CHAT_URL and FX_GATEWAY_BASE_URL pointing at the listener:
FX_GATEWAY_CHAT_URL=http://127.0.0.1:18080/v3/ai/language-model \
FX_GATEWAY_BASE_URL=http://127.0.0.1:18080 \
fx-groq ask --yolo --no-save "Reply with exactly: ISOLATION_OK"
# Verify: stdout contains ISOLATION_OK, and:
wc -l < /tmp/gw-capture.log   # must be 0
kill %1
```

Reference: `src/builtins/gateway.zig` hard-fails with `error.OpenAiCredentialCannotAuthorizeGateway`
if an OpenAI credential ever reaches the gateway path.

### 4. Tool round-trip on disk

```bash
T=$(mktemp -d) && cd "$T" && git init -q
printf 'alpha\n' > input.txt
fx-groq ask --yolo --no-save --json \
  "Read input.txt. Create result.txt containing the original word in uppercase followed by -FX. Then read result.txt and tell me its exact contents." > run.json
cat result.txt   # must be exactly: ALPHA-FX
```

The JSON output's `tool_calls` must contain `read_file:success` and
`write_file:success`. A model that claims success but leaves `result.txt`
missing is a FAIL.

### 5. Interactive TUI

Requires the TUI fix (already applied). In a tmux session:

```bash
W=$(mktemp -d); cd "$W"; git init -q
tmux new -d -s fxgroq -x 140 -y 40 -c "$W"
tmux send-keys -t fxgroq "fx-groq 2>$W/err" Enter
sleep 8
tmux capture-pane -pt fxgroq   # expect "fx v0.0.5 · Run /help for commands" and footer with model
tmux send-keys -t fxgroq "Reply with exactly: TUI_OK" Enter
sleep 25
tmux capture-pane -pt fxgroq   # expect TUI_OK
tmux send-keys -t fxgroq "/quit" Enter
cat "$W/err"   # must be empty (no panic)
tmux kill-session -t fxgroq
```

### 6. Launcher independence

```bash
fx-groq status --json | jq -r .model; fx-openrouter status --json | jq -r .model
# expect: openai/gpt-oss-120b then z-ai/glm-5.3

# Poisoned ambient env must be overridden:
OPENAI_API_KEY=wrong AI_GATEWAY_API_KEY=wrong FX_PROVIDER=gateway \
  fx-groq ask --yolo --no-save "Reply with exactly: ENV_OK"   # ENV_OK

# Must work from empty environment:
env -i HOME=$HOME PATH=$PATH fx-openrouter ask --yolo --no-save "Reply with exactly: ENV_OK"  # ENV_OK
```

### 7. Regression

```bash
shasum -a 256 ~/.local/bin/fx   # must remain caad628680cd2af24d79063f109965b71c24f69c7b06318b50178c76cc40d0c9
cat ~/.fx/settings.json        # must NOT contain "provider" or "openai_model"
```

## Configuration and State

fx's profile configuration and runtime state lives under `~/.fx/`. The shared
`~/.fx/settings.json` contains only `{"yolo_acknowledged":true}`.

**Do not** run `fx provider openai` or select a provider in `/setup` against the
real `HOME` — persistently writing `"provider":"openai"` into `settings.json`
causes stock fx 0.0.5 to print `fx: config user: malformed_settings` and ignore
the entire settings file.

The OpenAI-compatible provider is activated via environment variables:

```
OPENAI_API_KEY=<provider key, sourced from .env via the profile>
FX_OPENAI_BASE_URL=<https://api.groq.com/openai/v1 or https://openrouter.ai/api/v1>
FX_OPENAI_API_STYLE=chat
FX_MODEL=<model id>
```

Env-file precedence (highest wins):

1. Environment variables (`FX_MODEL`, `FX_PERMISSION_MODE`, `FX_MAX_AGENT_STEPS`)
2. `~/.fx/settings.json` → `workspaces["<workspace_path>"]`
3. `~/.fx/settings.json` top-level
4. `<workspace>/.fx.json` (committed project defaults)
5. Built-in defaults

## Code Style Guidelines

This directory contains no Zig source code. Source work happens in
`~/src/fx-openai-compat/`. The relevant conventions (carried forward from the
upstream fx `AGENTS.md`) are:

- Run `zig fmt src/` before any change. Do not ignore format failures.
- Use `snake_case` for Zig identifiers; `PascalCase` for types.
- CLI flags use kebab-case (e.g. `--no-save`, `--json`). Never use camelCase.
- Do not use emojis in code, output, or documentation. Unicode symbols are acceptable.
- In documentation, never use double hyphens (`--`) as a dash. Use an emdash
  sparingly, or rewrite to avoid dashes.
- Keep `pub` surface area minimal. Only mark declarations `pub` when used
  outside the file.

### Adding a feature

1. Which module owns the behavior?
2. What is the typed contract?
3. Does it need persistence?
4. Does it need both text and JSON output?
5. What docs and tests land with it?

### Adding a command

1. Add the spec to `src/core/slash_commands/command_specs.zig`
2. Add dispatch wiring in `src/core/cli/cli_surface.zig`
3. Add a snapshot type if it has structured output
4. Render text and JSON from the same snapshot via `src/core/output/output_contracts.zig`

Do not scatter help text or argument parsing across multiple files.

## Architecture (of the fx source tree)

- `src/main.zig` — composition root. Do not add leaf feature logic here.
- `src/core/` — contracts, runtimes, config, sessions, permissions, MCP, skills.
- `src/tools/` — built-in tool implementations.
- `src/ui/` — terminal rendering, event loop, input, transcript.
- `src/gateway/` — provider transport (must not absorb product-state logic).
- `src/acp/` — ACP JSON-RPC 2.0 server.
- `src/builtins/` — default tool specs and gateway wiring.

## Zig-Specific Patterns (from upstream AGENTS.md)

### Memory

- Allocators are passed explicitly. Never use a global allocator.
- Free what you allocate. Use `defer` for cleanup at the call site.
- Prefer `ArenaAllocator` for request-scoped work that can be freed in bulk.
- When a function returns allocated memory, document who owns it (caller or callee).

### Error Handling

- Return errors rather than panicking. `@panic` is for programmer bugs, not
  runtime conditions.
- Use `errdefer` to clean up partial state on error paths.
- Prefer specific error sets over `anyerror` when the set is bounded.

### Strings and JSON

- Zig strings are `[]const u8`. No implicit null termination.
- For JSON serialization, use `std.json.Stringify.value` with an allocating writer.
- For JSON string escaping, use the project's `writeJsonStr` helper in
  `src/acp/jsonrpc.zig`.
- Zig 0.16 uses `std.Io.File.stdin()` / `.stdout()` / `.stderr()`, not
  `std.io.getStdIn()`.

### I/O (Zig 0.16 "Juicy Main")

- `main` uses `pub fn main(init: std.process.Init) !void`.
- All I/O goes through `std.Io`, passed explicitly or via
  `src/core/shared/io.zig` (`io_mod.getIo()`).
- File operations use `std.Io.Dir` and `std.Io.File` (not `std.fs`).
- Environment variables: use `io_mod.getenv(key)`, not `std.process.getEnvVarOwned`.
- `std.mem` renames: `trimLeft`→`trimStart`, `trimRight`→`trimEnd`,
  `indexOf`→`find`, `indexOfScalar`→`findScalar`.
- `ArrayList(T)` initializes with `.empty` (not `.{}`).

### Testing

- Zig unit tests go inside the source file they test: `test "description" { ... }`.
- Use `std.testing.expect`, `std.testing.expectEqual`, `std.testing.expectEqualStrings`.
- In test blocks, use `std.testing.io` for the `Io` parameter.

## Pull Request Classification

Every PR must have exactly one `type:` label:

- `type: bug` — fixes incorrect behavior
- `type: feature` — adds a new user-facing capability
- `type: improvement` — improves existing user-facing behavior
- `type: docs` — changes documentation only
- `type: maintenance` — internal tooling, dependencies, CI, no user-facing change
- `type: release` — prepares or repairs a release
- `type: security` — fixes or hardens a security boundary

Keep PR titles as clean imperative sentences (e.g. `Restore feedback report file`).
Do not add bracketed prefixes. Type belongs in the label, not the title.

## Security Considerations

**Read this section in full before running anything.** This directory handles
live API keys.

### Secret store

- `/Users/fcavalcanti/dev/fx-open/.env` (mode `600`) holds `GROQ_API_KEY` and
  `OPENROUTER_API_KEY`. It is the **only** file permitted to contain the keys.
- This directory is **not** a git repository, so the keys cannot be committed
  via `git add`. However, backup tools, rsync targets, and editor swap files
  could still leak it. Treat it as strictly secret.
- **Never** `cat` the `.env` file. To verify key names without exposing values:

```bash
cut -d= -f1 /Users/fcavalcanti/dev/fx-open/.env | sort
# expect exactly: GROQ_API_KEY and OPENROUTER_API_KEY
```

### Key isolation rules

- The launcher scripts (`~/.local/bin/fx-groq`, `~/.local/bin/fx-openrouter`)
  **never contain literal keys**:

```bash
grep -cE 'gsk_|sk-or-|OPENAI_API_KEY=' ~/.local/bin/fx-groq          # expect 0
grep -cE 'gsk_|sk-or-|OPENAI_API_KEY=' ~/.local/bin/fx-openrouter   # expect 0
```

- The env profiles (`~/.config/fx-groq/env`, `~/.config/fx-openrouter/env`)
  reference the keys via shell variable expansion (`"${GROQ_API_KEY:?...}"`),
  never by embedding them:

```bash
grep -c 'gsk_' ~/.config/fx-groq/env            # expect 0
grep -c 'sk-or-' ~/.config/fx-openrouter/env   # expect 0
```

- Keys are loaded purely by sourcing — never typed into shell history or
  command arguments. `grep -c "$KEY8" ~/.zsh_history` must be 0 for both keys.

### Verifier for no leakage

Compute the first 8 characters of a key in memory (never echo it) and grep for
that prefix across the checkout, env profiles, launchers, notes, and `/tmp`:

```bash
KEY8=$(bash -c 'set +a; source /Users/fcavalcanti/dev/fx-open/.env; printf "%s" "$GROQ_API_KEY"' | cut -c1-8)
grep -rl "$KEY8" ~/src/fx-openai-compat ~/.config/fx-groq ~/.local/bin/fx-groq ~/notes /tmp 2>/dev/null | wc -l
# expect 0 (the only allowed file is /Users/fcavalcanti/dev/fx-open/.env itself)
```

### Gateway isolation

The OpenAI-compatible provider path must never send the Groq/OpenRouter key to a
Vercel gateway URL. `src/builtins/gateway.zig` enforces this at the source level
(`error.OpenAiCredentialCannotAuthorizeGateway`). The loopback capture test in
[Testing Instructions](#testing-instructions) proves it at runtime.

### OpenRouter credit note

OpenRouter enforces output token limits per request. If `fx ask` returns HTTP 402
(`You requested up to 65536 tokens, but can only afford N`), the fix is to add
OpenRouter credits to the account — fx reserves 65536 output tokens per request.

## Known Upstream Defects (Not Patched)

These are reproduced defects in PR #168. Documented for transparency; do not
patch unless a specific task directs it.

1. **Escape-cancel P1**: TUI-level Escape shows `System: cancelled` and the local
   prompt returns, but the chat SSE handler has no API-level cancellation watcher,
   so the HTTP stream may continue in the background.
2. **EOF-as-success P1**: A bare SSE EOF with no `finish_reason` is committed as a
   successful turn.
3. **Missing error-key check P1**: The chat SSE handler does not inspect a
   top-level `"error"` key in `data:` events (OpenRouter mid-stream errors);
   HTTP-level errors ARE handled and produce a clean error message.
4. **9 known unit-test failures** (6 environmental, 3 PR-specific) — full list in
   `~/.local/lib/fx-openai-compat/BUILD_INFO` under
   `known_unit_test_failures_*`. None affects `fx ask`.

## Known Session Incompatibility

Sessions written by the custom PR #168 build (which include
`"provider":"openai"`) are unreadable by stock fx 0.0.5
(`InvalidSessionFormat` / `doctor [fail] session ... projection_invalid`). These
were relocated to `~/.local/lib/fx-openai-compat/sessions-relocated/` during the
spike. Future interactive runs of the custom build will continue creating such
sessions in `~/.fx/sessions/`; stock fx cannot read them. This is a known
trade-off of running a custom-built provider branch alongside a stock binary.

## Build Provenance

Recorded in `~/.local/lib/fx-openai-compat/BUILD_INFO`:

```
repository=https://github.com/vercel-labs/fx
source=PR-168
branch=feature/openai-compatible-transport
commit=f0c131c40a2516d024ab96776bc6211598743e16
merge_base=df7e6245e1992758d4060c97477ceafa27770551
zig=0.16.0
fx_version=0.0.5
api_style=chat
binary=~/.local/lib/fx-openai-compat/fx
binary_sha256=5816047132912658eccd2a27369ef7aac383c53ffc0dbdcaa940775921836827
launchers=~/.local/bin/fx-groq,~/.local/bin/fx-openrouter
secret_store=/Users/fcavalcanti/dev/fx-open/.env (never committed)
checkout=~/src/fx-openai-compat
built=2026-08-24T20:38:15Z
```

Never include the API key in provenance. Verify:

```bash
grep -ciE 'gsk_|sk-or-|api_key=' ~/.local/lib/fx-openai-compat/BUILD_INFO   # expect 0
```
