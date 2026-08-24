You are responsible for producing a **working local installation of Vercel Labs `fx` that talks directly to either Groq or OpenRouter using their OpenAI-compatible API**.

Do the complete job yourself from discovery through verification.

Do not merely explain commands to the user. Inspect the system, install/build what is required, configure it, test it against the real provider, and leave the user with a working command they can run.

Repository:

```text
https://github.com/vercel-labs/fx
```

## Goal

Starting from a fresh environment:

1. Inspect the currently installed `fx`, if any.
2. Clone a fresh local copy of `vercel-labs/fx`.
3. Inspect the current upstream state.
4. Determine whether generic OpenAI-compatible provider support has already landed in `main`.
5. If not, inspect the relevant upstream PRs, especially:
   - PR #168 — `Add OpenAI-compatible client transport`
   - PR #159 — `Support any OpenAI-compatible provider`
6. Prefer the current implementation from PR #168 unless:
   - its feature has already landed in `main`, or
   - repository history/current upstream clearly indicates another implementation superseded it.
7. Build `fx` locally.
8. Ask the user whether they want:
   - **Groq**
   - **OpenRouter**
9. Ask for the API key for the selected provider.
10. Configure the local fx build for that provider.
11. Discover an appropriate model.
12. Verify:
   - authentication
   - model listing or model availability
   - ordinary completion
   - streaming
   - actual fx agent execution
   - at least one local tool call
   - a complete tool round-trip
13. Leave a simple local command the user can use normally.

The final result should behave like:

```bash
fx-groq
```

or:

```bash
fx-openrouter
```

depending on the user's choice.

---

# Important behavioral requirements

You are an implementation agent, not a tutorial writer.

Do not stop after cloning.

Do not stop after compiling.

Do not stop after getting a plain LLM response.

Do not declare success until `fx` itself performs a genuine agent/tool round-trip using the selected provider.

You have permission to inspect the machine, clone repositories, create local build directories, install ordinary build dependencies when necessary, edit local configuration, compile the software, create launch scripts, and execute tests.

Do not modify the upstream GitHub repository.

Do not create a PR unless explicitly asked.

Do not overwrite or destroy the user's existing stable `fx` installation.

Keep the custom build separately identifiable.

Do not put the user's API key into:

- Git
- repository files
- shell history when avoidable
- command output
- logs
- test fixtures
- commit messages

Never print the complete API key after receiving it.

Mask it when reporting configuration.

---

# PHASE 1 — Reconnaissance

Start by gathering facts.

Run things such as:

```bash
uname -a
uname -m
command -v fx || true
fx --version || true
command -v git || true
git --version || true
command -v zig || true
zig version || true
```

Determine:

- OS
- architecture
- shell
- existing fx installation
- existing fx version
- Git availability
- Zig availability/version
- user home directory
- appropriate local binary location

Do not remove an existing `fx`.

If an existing release binary exists, preserve it.

---

# PHASE 2 — Fresh upstream clone

Use a fresh clone.

Prefer a sane source location such as:

```bash
mkdir -p ~/src
cd ~/src
git clone https://github.com/vercel-labs/fx.git fx-openai-compat
cd fx-openai-compat
```

If that directory already exists, do not blindly reuse potentially dirty state.

Inspect it first or create a new uniquely named clean clone.

Then:

```bash
git remote -v
git status
git branch --show-current
git log -1 --oneline
```

Fetch everything needed:

```bash
git fetch origin --prune
```

---

# PHASE 3 — Determine current upstream compatibility state

Do not blindly assume the situation described in this prompt is still current.

First inspect current `main`.

Look for generic OpenAI-compatible transport/provider support.

Relevant indicators include names such as:

```text
openai_compatible
openai-compatible
OpenAiCompatibleConfig
FX_OPENAI_BASE_URL
OPENAI_API_KEY
FX_OPENAI_API_STYLE
openai_api_key
openai_base_url
openai_api_style
ProviderId.openai
/v1/chat/completions
```

Search with `git grep`, for example:

```bash
git grep -n "FX_OPENAI_BASE_URL" origin/main || true
git grep -n "openai_compatible" origin/main || true
git grep -n "OPENAI_API_KEY" origin/main || true
git grep -n "chat/completions" origin/main || true
```

Also inspect:

```text
src/core/config/model_provider.zig
src/builtins/providers.zig
src/gateway/
README.md
```

## Decision

### Case A — compatibility is already merged

If current `main` contains the generic OpenAI-compatible provider with streaming tool calling:

Use fresh `main`.

```bash
git switch main
git pull --ff-only
```

Do not use an old PR branch unnecessarily.

### Case B — compatibility is not merged

Inspect PR #168 directly.

Fetch it:

```bash
git fetch origin pull/168/head:pr-168-openai-compatible
```

Inspect:

```bash
git log --oneline --decorate -10 pr-168-openai-compatible
git diff --stat origin/main...pr-168-openai-compatible
```

Also inspect the PR implementation areas.

Expected concepts from PR #168 include:

```text
OpenAI-compatible provider
Chat Completions wire
Responses API wire
OPENAI_API_KEY
FX_OPENAI_BASE_URL
FX_OPENAI_API_STYLE
openai model/provider
streaming tool calls
GET /v1/models
```

PR #168 historically implemented OpenAI-compatible inference as a distinct provider and supported the standard Chat Completions wire:

```text
/v1/chat/completions
```

as well as an optional Responses wire:

```text
/v1/responses
```

Prefer PR #168 for this task.

Switch to it:

```bash
git switch pr-168-openai-compatible
```

### PR #159

PR #159 is another OpenAI-compatible implementation.

Inspect it only if necessary:

```bash
git fetch origin pull/159/head:pr-159-openai-compatible
```

It historically implemented OpenAI Chat Completions for providers including OpenRouter, Ollama, vLLM and LM Studio.

Do not arbitrarily combine PR #159 and #168.

Do not cherry-pick pieces of both unless you first prove that it is required.

If #168 is obsolete/broken/superseded, establish that from current repository state before choosing #159 or implementing a small local fix.

---

# PHASE 4 — Build dependencies

Read the repository's current build instructions.

Do not assume the required Zig version from memory.

Inspect:

```bash
grep -n "Zig" README.md CONTRIBUTING.md 2>/dev/null || true
```

Determine the required version.

If the correct Zig version is already installed, use it.

If not, install the required Zig version using a normal platform-appropriate mechanism.

Do not downgrade or replace unrelated system tooling unnecessarily.

Verify:

```bash
zig version
```

---

# PHASE 5 — Build locally

Build the selected source tree.

Normally:

```bash
zig build -Doptimize=ReleaseSafe
```

Then verify:

```bash
./zig-out/bin/fx --version
./zig-out/bin/fx --help
```

Run relevant unit tests if practical:

```bash
zig build test
```

If the chosen branch contains OpenAI-compatible E2E tests, inspect and execute the relevant tests.

Look particularly for files resembling:

```text
tests/e2e/openai-compatible-fake.test.ts
tests/e2e/openai-responses-fake.test.ts
```

Do not hide failures.

Fix local build problems if they are straightforward compatibility issues.

Avoid broad unrelated source changes.

---

# PHASE 6 — Ask the user

Only after you understand the implementation and have a viable binary, ask:

> Which provider do you want this local fx to use?
>
> 1. Groq
> 2. OpenRouter

Wait for the answer.

Then ask only for the corresponding API key.

For Groq:

> Send me the Groq API key you want this local fx installation to use. I will treat it as a secret and will not print it back.

For OpenRouter:

> Send me the OpenRouter API key you want this local fx installation to use. I will treat it as a secret and will not print it back.

Do not ask the user to manually perform configuration that you can perform.

Do not ask the user what base URL to use.

You know the standard endpoints.

---

# PHASE 7 — Provider configuration

## Groq

Use:

```text
https://api.groq.com/openai/v1
```

Prefer OpenAI Chat Completions compatibility:

```text
chat
```

Conceptually the runtime configuration should become:

```bash
OPENAI_API_KEY="<secret>"
FX_OPENAI_BASE_URL="https://api.groq.com/openai/v1"
FX_OPENAI_API_STYLE="chat"
```

## OpenRouter

Use:

```text
https://openrouter.ai/api/v1
```

Prefer OpenAI Chat Completions compatibility:

```text
chat
```

Conceptually:

```bash
OPENAI_API_KEY="<secret>"
FX_OPENAI_BASE_URL="https://openrouter.ai/api/v1"
FX_OPENAI_API_STYLE="chat"
```

Do not use OpenAI Responses mode unless the selected provider/model and fx implementation genuinely require it and you have verified support.

For Groq and OpenRouter, Chat Completions should be the default starting point.

---

# PHASE 8 — Handle the API key safely

Do not write the key into the cloned repository.

If the current fx compatibility implementation supports secure/private user-level configuration, use that.

For example, PR #168 historically supported user-level values resembling:

```json
{
  "openai_api_key": "...",
  "openai_base_url": "...",
  "openai_api_style": "chat",
  "openai_model": "..."
}
```

in:

```text
~/.fx/settings.json
```

But inspect the current implementation before relying on those exact field names.

If persisting the key in a user config file, ensure restrictive permissions:

```bash
chmod 600 ~/.fx/settings.json
```

If the selected implementation only supports environment variables, create a private provider-specific environment file outside the repository, for example:

```text
~/.config/fx-groq/env
```

or:

```text
~/.config/fx-openrouter/env
```

with:

```bash
chmod 600
```

Do not put the key directly into a globally readable shell script.

The launcher may source the private environment file.

---

# PHASE 9 — Validate provider API before blaming fx

Before testing the full agent, make a minimal authenticated provider request.

Do this without exposing the API key.

## Test model catalog

For Groq:

```text
GET https://api.groq.com/openai/v1/models
```

For OpenRouter:

```text
GET https://openrouter.ai/api/v1/models
```

Use Bearer authentication.

Inspect the result programmatically.

Do not dump an enormous model catalog to the user.

Confirm:

- HTTP authentication works
- endpoint is reachable
- models are returned

---

# PHASE 10 — Choose a model automatically

Do not burden the user with another question unless model selection genuinely cannot be resolved.

Discover models from the provider.

The model must support **tool/function calling**, because plain text completion is insufficient for a coding agent.

Selection priorities:

1. tool/function calling
2. reliable instruction following
3. adequate context window
4. coding ability
5. streaming
6. availability under the user's provider/account

For Groq, inspect the current model catalog and provider capabilities.

A historically useful candidate has been:

```text
openai/gpt-oss-120b
```

but DO NOT blindly hard-code it if the provider catalog has changed.

For OpenRouter, choose a currently available strong coding/reasoning model with tool support.

OpenRouter model IDs normally use:

```text
provider/model
```

Do not select a text-only or tool-incompatible model.

If several appropriate models exist, choose a sensible default and tell the user afterward which one you selected.

Only ask the user to select a model if automatic selection cannot be made responsibly.

---

# PHASE 11 — Test raw OpenAI-compatible Chat Completions

Before testing fx, verify the provider's OpenAI-compatible chat endpoint itself.

Use:

```text
POST /v1/chat/completions
```

Test:

1. simple non-streaming completion
2. streaming completion
3. function/tool-call request

For the tool test, define a harmless function such as:

```text
get_test_value
```

with a tiny JSON schema and ask the model to call it.

Verify the returned structure is compatible with OpenAI streamed tool calls.

This differentiates:

```text
provider/API problem
```

from:

```text
fx transport/parser problem
```

Do not stop here.

This is only transport validation.

---

# PHASE 12 — Configure fx's provider

Select the OpenAI-compatible provider using whatever interface the chosen source revision implements.

For PR #168 this has historically been equivalent to:

```bash
fx provider openai
```

and/or provider selection through:

```text
/setup
```

Inspect current help before assuming syntax:

```bash
./zig-out/bin/fx --help
./zig-out/bin/fx provider --help || true
```

Configure:

- provider = OpenAI-compatible
- base URL
- API style = chat
- selected model
- API credential

Then inspect status:

```bash
./zig-out/bin/fx status
```

If JSON status exists:

```bash
./zig-out/bin/fx status --json
```

Verify that fx believes it is using the intended provider/model.

Absolutely verify that a Groq/OpenRouter key cannot accidentally be sent to Vercel AI Gateway.

The OpenAI-compatible path must be isolated from Vercel credentials.

---

# PHASE 13 — Test `fx ask`

First test a simple one-shot request:

```bash
./zig-out/bin/fx ask "Reply with exactly: FX_PROVIDER_OK"
```

Expected semantic result:

```text
FX_PROVIDER_OK
```

Then test reasoning over local project context:

```bash
./zig-out/bin/fx ask "Inspect this repository and tell me what language fx itself is primarily written in."
```

The answer should derive from the workspace, not simply hallucinate it.

---

# PHASE 14 — Mandatory real tool round-trip

This is the critical acceptance test.

Create a disposable test workspace outside the fx source tree:

```bash
tmpdir="$(mktemp -d)"
cd "$tmpdir"
git init
printf 'alpha\n' > input.txt
```

Run the locally built fx from this directory.

Give it a task that requires reading and writing local files, such as:

```text
Read input.txt. Create result.txt containing the original word in uppercase followed by "-FX". Then read result.txt and tell me its exact contents.
```

Expected resulting file:

```text
ALPHA-FX
```

Verify independently:

```bash
cat result.txt
```

The test succeeds only if all of these happened:

```text
user prompt
   ↓
fx
   ↓
Groq/OpenRouter
   ↓
model returns tool call
   ↓
fx executes local tool
   ↓
tool result returned to model
   ↓
model continues
   ↓
second action/final answer
```

A plain model response pretending that it edited the file does NOT count.

Check the filesystem yourself.

---

# PHASE 15 — Test streaming tool calls

Because coding agents rely heavily on streamed function calls, explicitly verify this.

Use a task with multiple operations, for example:

```text
Inspect the current directory, read input.txt, create another file named summary.txt, and then report both filenames.
```

Watch for:

- fragmented tool-call argument handling
- duplicate tool execution
- malformed JSON accumulation
- premature end-of-stream
- hanging stream
- cancellation problems

If using an unmerged PR, be aware that stream edge cases may still exist.

If a test hangs, investigate the OpenAI-compatible stream parser instead of merely increasing timeouts indefinitely.

---

# PHASE 16 — Create a clean local launcher

Do not replace the user's normal `fx`.

Create:

```text
~/.local/bin/fx-groq
```

or:

```text
~/.local/bin/fx-openrouter
```

The launcher should invoke the exact local custom build.

Prefer a stable location for the built binary, for example:

```text
~/.local/lib/fx-openai-compat/fx
```

Copy the verified build there:

```bash
mkdir -p ~/.local/lib/fx-openai-compat
cp ./zig-out/bin/fx ~/.local/lib/fx-openai-compat/fx
chmod 755 ~/.local/lib/fx-openai-compat/fx
```

Then create the appropriate launcher.

Conceptually:

```bash
#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.config/fx-groq/env"

exec "$HOME/.local/lib/fx-openai-compat/fx" "$@"
```

or:

```bash
#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.config/fx-openrouter/env"

exec "$HOME/.local/lib/fx-openai-compat/fx" "$@"
```

The secret file itself must be:

```bash
chmod 600
```

The launcher must not contain the literal key.

Make launcher executable:

```bash
chmod 755 ~/.local/bin/fx-groq
```

or:

```bash
chmod 755 ~/.local/bin/fx-openrouter
```

Ensure `~/.local/bin` is in PATH.

If it is not, configure the user's shell appropriately without damaging existing shell configuration.

---

# PHASE 17 — Verify the deployed launcher, not just the build tree

This is mandatory.

Change to an unrelated directory.

For Groq:

```bash
fx-groq --version
fx-groq status
fx-groq ask "Reply with exactly GROQ_FX_OK"
```

For OpenRouter:

```bash
fx-openrouter --version
fx-openrouter status
fx-openrouter ask "Reply with exactly OPENROUTER_FX_OK"
```

Then repeat the local-file tool round-trip using the deployed launcher.

Do not claim deployment success based solely on:

```text
./zig-out/bin/fx
```

The installed launcher itself must work.

---

# PHASE 18 — Preserve reproducibility

Keep the source checkout.

Record:

- upstream repository
- selected branch
- commit SHA
- whether code came from main or PR #168/#159
- Zig version
- fx version
- provider
- base URL
- API style
- selected model
- local deployed binary path

Create a small NON-SECRET metadata file, for example:

```text
~/.local/lib/fx-openai-compat/BUILD_INFO
```

Example:

```text
repository=https://github.com/vercel-labs/fx
source=PR-168
commit=<sha>
provider=groq
base_url=https://api.groq.com/openai/v1
api_style=chat
model=<model>
zig=<version>
built=<timestamp>
```

Never include the API key.

---

# PHASE 19 — Failure handling

If anything fails, diagnose it systematically.

Separate failures into:

```text
1. DNS/network
2. TLS
3. authentication
4. provider model availability
5. OpenAI compatibility
6. tool-call support
7. SSE streaming format
8. fx request serialization
9. fx stream parsing
10. fx tool execution
11. model behavior
```

Do not randomly patch the agent.

First reproduce the failing layer independently.

Examples:

If raw `/models` fails:

```text
not an fx problem
```

If raw chat works but tool calls fail:

```text
model/provider/tool compatibility problem
```

If raw streamed tool calls work but fx fails:

```text
fx compatibility transport/parser problem
```

If fx receives the tool call but cannot execute it:

```text
fx agent/tool runtime problem
```

Make the smallest local correction necessary.

Keep any source modifications visible with:

```bash
git diff
```

Do not silently modify upstream code.

---

# Definition of Done

Do not say "done" until ALL applicable checks pass:

- [ ] Fresh `vercel-labs/fx` repository cloned locally.
- [ ] Current upstream `main` inspected.
- [ ] PR #168 inspected if compatibility is not already merged.
- [ ] PR #159 considered only as an alternative, not mixed blindly.
- [ ] Correct source revision selected.
- [ ] Correct Zig/build dependencies installed.
- [ ] `fx` builds successfully.
- [ ] User chose Groq or OpenRouter.
- [ ] User supplied API key.
- [ ] API key stored/used without exposing it.
- [ ] Correct OpenAI-compatible base URL configured.
- [ ] Chat Completions mode configured.
- [ ] Provider `/models` endpoint authenticated successfully.
- [ ] Suitable tool-capable model selected.
- [ ] Raw chat request succeeds.
- [ ] Raw streaming succeeds.
- [ ] Raw tool/function call succeeds.
- [ ] `fx ask` succeeds through selected provider.
- [ ] fx performs a genuine local tool call.
- [ ] fx successfully receives the tool result and continues the turn.
- [ ] File-writing test verified independently on disk.
- [ ] Deployed `fx-groq` or `fx-openrouter` launcher works outside the source checkout.
- [ ] Existing normal `fx` installation remains untouched.
- [ ] Build provenance recorded without secrets.

---

# Final report

When everything works, give the user a concise report containing:

```text
Provider:
Model:
fx source:
Commit:
API mode:
Base URL:
Binary:
Launcher:
Tests:
```

Example:

```text
Provider: Groq
Model: <actual selected model>
fx source: vercel-labs/fx PR #168
Commit: abc1234
API mode: OpenAI Chat Completions
Base URL: https://api.groq.com/openai/v1
Binary: ~/.local/lib/fx-openai-compat/fx
Launcher: ~/.local/bin/fx-groq

Verified:
✓ authentication
✓ model discovery
✓ streaming completion
✓ streamed tool calling
✓ fx ask
✓ local read tool
✓ local write tool
✓ tool-result continuation
✓ deployed launcher
```

Then show the only command the user normally needs:

For Groq:

```bash
cd /path/to/project
fx-groq
```

For OpenRouter:

```bash
cd /path/to/project
fx-openrouter
```

## Start now

Begin with machine reconnaissance and upstream inspection.

Once the local build path is proven viable, ask the user:

> **Groq or OpenRouter?**

Then request the corresponding API key and carry the deployment through to a verified working local fx installation.