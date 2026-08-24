#!/usr/bin/env bash
# fx-open installer — builds fx (upstream PR #168 + the TUI fix) with a private Zig 0.16.0
# and installs the fx-groq / fx-openrouter launchers. Never touches a stock `fx` on PATH,
# never runs `fx upgrade`, never writes into ~/.fx/bin.
#
#   ./openai-compat/install.sh            # build, install, ask for your API key(s)
#   ./openai-compat/install.sh --no-keys  # same, but do not ask for keys
#
# Overrides (mainly for testing): FX_OPEN_PREFIX (default ~/.local), FX_OPEN_CONFIG (default ~/.config),
# FX_OPEN_ENV_FILE (default <repo>/.env), FX_OPEN_ZIG_DIR (default $FX_OPEN_PREFIX/lib/zig-0.16.0).
set -euo pipefail

ZIG_VERSION=0.16.0
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${FX_OPEN_PREFIX:-$HOME/.local}"
CONFIG_DIR="${FX_OPEN_CONFIG:-$HOME/.config}"
ENV_FILE="${FX_OPEN_ENV_FILE:-$REPO_DIR/.env}"
ZIG_DIR="${FX_OPEN_ZIG_DIR:-$PREFIX/lib/zig-$ZIG_VERSION}"
ZIG="$ZIG_DIR/zig"
NO_KEYS=0

usage() { sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
for arg in "$@"; do
  case "$arg" in
    --no-keys) NO_KEYS=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
note() { printf '\033[1;33mnote:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }
need git; need curl; need jq; need tar

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" | cut -d' ' -f1; fi
}

# ---------------------------------------------------------------- 1. Zig 0.16.0 (private, off PATH)
case "$(uname -s)" in Darwin) zos=macos ;; Linux) zos=linux ;; *) die "unsupported OS: $(uname -s)" ;; esac
case "$(uname -m)" in arm64|aarch64) zarch=aarch64 ;; x86_64|amd64) zarch=x86_64 ;; *) die "unsupported arch: $(uname -m)" ;; esac
platform="$zarch-$zos"

if [ -x "$ZIG" ] && [ "$("$ZIG" version 2>/dev/null || true)" = "$ZIG_VERSION" ]; then
  log "Zig $ZIG_VERSION present at $ZIG"
else
  log "Fetching Zig $ZIG_VERSION for $platform into $ZIG_DIR"
  index="$(curl -fsSL https://ziglang.org/download/index.json)"
  tarball="$(printf '%s' "$index" | jq -r --arg v "$ZIG_VERSION" --arg p "$platform" '.[$v][$p].tarball // empty')"
  expected="$(printf '%s' "$index" | jq -r --arg v "$ZIG_VERSION" --arg p "$platform" '.[$v][$p].shasum // empty')"
  [ -n "$tarball" ] && [ -n "$expected" ] || die "no Zig $ZIG_VERSION build for $platform in the ziglang.org index"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "$tmp/zig.tar.xz" "$tarball"
  actual="$(sha256_of "$tmp/zig.tar.xz")"
  [ "$actual" = "$expected" ] || die "Zig tarball sha256 mismatch (expected $expected, got $actual)"
  mkdir -p "$tmp/x" && tar -xJf "$tmp/zig.tar.xz" -C "$tmp/x"
  mkdir -p "$(dirname "$ZIG_DIR")" && rm -rf "$ZIG_DIR" && mv "$tmp"/x/zig-* "$ZIG_DIR"
  [ "$("$ZIG" version)" = "$ZIG_VERSION" ] || die "Zig install failed"
  log "Zig $ZIG_VERSION installed at $ZIG (not on PATH)"
fi

# ---------------------------------------------------------------- 2. build fx
cd "$REPO_DIR"
branch="$(git branch --show-current 2>/dev/null || echo '?')"
[ "$branch" = "openai-compat" ] || note "on branch '$branch'; the buildable branch is 'openai-compat'"
[ -f src/gateway/openai_compatible.zig ] || die "this checkout has no OpenAI-compatible provider — run: git switch openai-compat"
log "Building fx (ReleaseSafe) — a cold build takes 2-4 minutes"
"$ZIG" build -Doptimize=ReleaseSafe
./zig-out/bin/fx --help | grep -q 'provider <gateway|codex|grok|openai>' || die "the built fx does not list the openai provider"
log "Built fx $(./zig-out/bin/fx --version) with the OpenAI-compatible provider"

# ---------------------------------------------------------------- 3. install binary, launchers, key-free profiles
LIB="$PREFIX/lib/fx-openai-compat"; BIN="$PREFIX/bin"
mkdir -p "$LIB" "$BIN" "$CONFIG_DIR/fx-groq" "$CONFIG_DIR/fx-openrouter"
install -m 755 zig-out/bin/fx "$LIB/fx"
install -m 755 openai-compat/launchers/fx-groq openai-compat/launchers/fx-openrouter "$BIN/"
install -m 600 openai-compat/profiles/fx-groq.env "$CONFIG_DIR/fx-groq/env"
install -m 600 openai-compat/profiles/fx-openrouter.env "$CONFIG_DIR/fx-openrouter/env"
log "Installed $LIB/fx, $BIN/fx-groq, $BIN/fx-openrouter, profiles in $CONFIG_DIR/fx-{groq,openrouter}/env"
case ":$PATH:" in *":$BIN:"*) ;; *) note "$BIN is not on your PATH (this script does not edit shell rc files)" ;; esac
[ "$REPO_DIR" = "$HOME/dev/fx-open" ] || note "the launchers source \$HOME/dev/fx-open/.env; this repo is at $REPO_DIR — edit that line in the two launchers or symlink the repo"

# ---------------------------------------------------------------- 4. keys -> one private .env, never printed, never committed
if [ "$NO_KEYS" = 1 ]; then
  log "Skipping key setup (--no-keys); the launchers read $ENV_FILE"
elif [ -f "$ENV_FILE" ]; then
  log "Keeping existing $ENV_FILE"
else
  echo
  echo "An API key is required.  Groq: https://console.groq.com/keys   OpenRouter (prepaid): https://openrouter.ai/settings/keys"
  read -r -p "Provider [groq/openrouter/both]: " choice
  case "$choice" in groq|openrouter|both) ;; *) die "answer groq, openrouter or both" ;; esac
  umask 077; : > "$ENV_FILE"
  if [ "$choice" != openrouter ]; then read -r -s -p "Groq API key: " key; echo; [ -n "$key" ] && printf 'GROQ_API_KEY=%s\n' "$key" >> "$ENV_FILE"; fi
  if [ "$choice" != groq ]; then read -r -s -p "OpenRouter API key: " key; echo; [ -n "$key" ] && printf 'OPENROUTER_API_KEY=%s\n' "$key" >> "$ENV_FILE"; fi
  unset key; chmod 600 "$ENV_FILE"
  log "Wrote $ENV_FILE (mode 600). It is gitignored — never commit it."
fi

echo
log "Done. Next:"
echo "  fx-groq                            # interactive, on Groq   (or: fx-openrouter)"
echo "  ./openai-compat/test.sh fx-groq    # 30-second proof: one-shot answer + real on-disk tool round-trip"
