#!/usr/bin/env bash
# Keep this fork current with upstream RELEASES, not upstream dev.
#
#   ./openai-compat/sync-upstream.sh            # report only: latest upstream release, where main stands, PR #168 state
#   ./openai-compat/sync-upstream.sh --apply    # rebase the fork-only commits of `main` onto the latest release tag,
#                                               # push main (--force-with-lease) and the tag to origin
#
# Policy: `main` = latest upstream release tag + this fork's docs/tooling commits. `openai-compat` (PR #168 head +
# the TUI fix) is never rebased automatically; the script only reports whether PR #168 moved or merged upstream.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

APPLY=0
case "${1:-}" in --apply) APPLY=1 ;; "") ;; *) echo "usage: $0 [--apply]" >&2; exit 2 ;; esac

UPSTREAM_URL=https://github.com/vercel-labs/fx.git
PR168_BASE=f0c131c40a2516d024ab96776bc6211598743e16   # the PR #168 head openai-compat was built from

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"
git fetch -q upstream --tags --prune

# "latest" = GitHub's latest release (upstream re-versioned from v0.4.x to v0.0.x in 2026-08, so a numeric
# tag sort is wrong); fall back to the most recently created v* tag when gh is unavailable.
latest="$(gh api repos/vercel-labs/fx/releases/latest --jq .tag_name 2>/dev/null || true)"
[ -n "$latest" ] || latest="$(git tag -l 'v*' --sort=-creatordate | head -1)"
[ -n "$latest" ] || { echo "no upstream release tag found" >&2; exit 1; }
git rev-parse -q --verify "$latest^{commit}" >/dev/null || { echo "tag $latest not fetched from upstream" >&2; exit 1; }
tag_sha="$(git rev-parse "$latest^{commit}")"
echo "upstream latest release : $latest  ($(git log -1 --format=%cs "$tag_sha"), $(git rev-parse --short "$tag_sha"))"
echo "upstream dev (main)     : $(git rev-parse --short upstream/main)  ($(git log -1 --format=%cs upstream/main))"

fork_base="$(git merge-base main upstream/main)"
fork_only="$(git rev-list --count "$fork_base..main")"
echo "fork main               : $(git rev-parse --short main) = upstream $(git rev-parse --short "$fork_base") + $fork_only fork commit(s)"
if [ "$fork_base" = "$tag_sha" ]; then
  echo "status                  : main already sits on $latest"
elif git merge-base --is-ancestor "$tag_sha" "$fork_base"; then
  echo "status                  : main sits on upstream DEV ($(git rev-list --count "$tag_sha..$fork_base") commits past $latest); --apply moves it back onto the release"
else
  echo "status                  : $latest is newer than main's base; --apply brings it in"
fi

if command -v gh >/dev/null 2>&1; then
  pr="$(gh api repos/vercel-labs/fx/pulls/168 --jq '"state=\(.state) merged=\(.merged) head=\(.head.sha[0:7]) updated=\(.updated_at[0:10])"' 2>/dev/null || echo "unavailable")"
  echo "upstream PR #168        : $pr  (openai-compat is built on ${PR168_BASE:0:7})"
  case "$pr" in
    *merged=true*) echo "                          -> PR #168 landed upstream: the openai-compat branch can be retired once a release contains it" ;;
    *head=${PR168_BASE:0:7}*) ;;
    unavailable) ;;
    *) echo "                          -> PR #168 head moved: consider rebuilding openai-compat on its new head (manual)" ;;
  esac
fi

[ "$APPLY" = 1 ] || { echo; echo "dry run. Re-run with --apply to rebase main onto $latest and push."; exit 0; }
[ "$fork_base" != "$tag_sha" ] || exit 0

# Re-create main as: release tag + ONE commit carrying every path this fork changed (README, openai-compat/, the
# skill). No rebase, so upstream README edits can never conflict. Done in a throwaway worktree; the current checkout
# and any uncommitted work in it are never touched.
old_main="$(git rev-parse main)"
paths="$(git diff --name-only "$fork_base" main)"
[ -n "$paths" ] || { echo "nothing fork-specific on main to carry over" >&2; exit 1; }
wt="$(mktemp -d)/main"
echo; echo "re-creating main = $latest + fork files ($(printf '%s\n' "$paths" | wc -l | tr -d ' ') paths) in a temporary worktree ..."
git worktree add -q --detach "$wt" "$tag_sha"   # detached: works even when main is checked out elsewhere
printf '%s\n' "$paths" | while IFS= read -r f; do
  if git cat-file -e "$old_main:$f" 2>/dev/null; then git -C "$wt" checkout -q "$old_main" -- "$f"; git -C "$wt" add -f -- "$f"; else git -C "$wt" rm -q --ignore-unmatch -- "$f"; fi
done
git -C "$wt" commit -q -m "fx-open: docs and tooling on $latest

Carried over from $(git rev-parse --short "$old_main") (fork commits squashed onto the upstream release tag)." \
  || { git worktree remove --force "$wt"; git worktree prune; echo "nothing to commit" >&2; exit 1; }
git -C "$wt" push --force-with-lease=main:"$old_main" origin HEAD:refs/heads/main
git -C "$wt" push -q origin "refs/tags/$latest"
git worktree remove --force "$wt"; git worktree prune
git fetch -q origin
if [ "$(git branch --show-current)" = main ]; then
  if [ -z "$(git status --porcelain --untracked-files=no)" ]; then git reset -q --hard origin/main; else echo "note: local main left untouched (uncommitted changes); run: git reset --hard origin/main" >&2; fi
else
  git branch -f main origin/main
fi
echo "done: origin/main = $latest + 1 fork commit -> $(git rev-parse --short origin/main); tag $latest pushed to origin"
