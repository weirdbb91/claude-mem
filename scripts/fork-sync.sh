#!/usr/bin/env bash
# weirdbb91/claude-mem = latest upstream release + fork/patches, rebuilt and tested (see FORK.md).
# .github/workflows/fork-sync.yml runs this hourly from a clean main checkout. Every failure exits
# non-zero before the push, so the last good build stays what Claude Code installs.
# FORK_SYNC_TARGET=<commit> pins the upstream release to sync to (tests and manual runs).
set -euo pipefail

FORK_PATHS=(FORK.md fork scripts/fork-sync.sh tests/fork .github/workflows/fork-sync.yml)
MARKER=unifiedWindows # shows up in a built bundle only when the quota-guard patch is compiled in

[ "$(git branch --show-current)" = main ] && [ -z "$(git status --porcelain)" ] ||
  { echo "fork-sync: needs a clean main checkout" >&2; exit 1; }
git remote get-url upstream >/dev/null 2>&1 || git remote add upstream https://github.com/thedotmack/claude-mem.git
git fetch --quiet upstream main

# Follow upstream releases: the newest commit that bumped the plugin version (its bundles match its source).
target=${FORK_SYNC_TARGET:-$(git log -1 --format=%H -G'"version"' upstream/main -- plugin/.claude-plugin/plugin.json)}
[ -n "$target" ] || { echo "fork-sync: no upstream release commit found" >&2; exit 1; }
if git merge-base --is-ancestor "$target" HEAD; then
  echo "fork-sync: already on upstream release ${target:0:9}"
  exit 0
fi
version=$(git show "$target:plugin/.claude-plugin/plugin.json" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -1)
echo "fork-sync: syncing to upstream ${target:0:9} (v$version)"

trap 'git merge --abort 2>/dev/null || true; echo "fork-sync: failed, nothing pushed" >&2' ERR
# Merge commit whose tree is built here: the upstream release, plus the fork's own files and patches.
git merge --quiet --no-commit --no-ff -s ours "$target"
git read-tree -u --reset "$target"
git checkout HEAD -- "${FORK_PATHS[@]}"

# Upstream keeps no lockfile: install what existed at release time, and the Agent SDK its bundle embeds.
sdk=$(git show "$target:plugin/scripts/worker-service.cjs" | grep -o 'CLAUDE_AGENT_SDK_VERSION="[^"]*"' | head -1 | cut -d'"' -f2)
[ -n "$sdk" ] || { echo "fork-sync: Agent SDK version not found in the upstream bundle" >&2; exit 1; }
npm install --no-audit --no-fund --before="$(git log -1 --format=%cI "$target")"
npm install --no-save --no-audit --no-fund "@anthropic-ai/claude-agent-sdk@$sdk"

if bun test tests/fork >/dev/null 2>&1; then
  patched=no
  echo "fork-sync: upstream passes tests/fork — carrying no patch"
else
  patched=yes
  echo "fork-sync: upstream still has #4068 — applying fork/patches"
  for p in fork/patches/*.patch; do git apply --index --3way "$p"; done
fi

npm run build
# Rebuilt files without the patch go back to upstream's bytes: rebuilding them only adds dependency drift.
changed=$(git diff --name-only -- plugin/) # listed up front: git checkout below needs the index lock
while IFS= read -r f; do
  [ -z "$f" ] || grep -q "$MARKER" "$f" 2>/dev/null || git checkout "$target" -- "$f"
done <<<"$changed"
git ls-files -z --others --exclude-standard -- plugin/ | while IFS= read -r -d '' f; do rm -- "$f"; done
if [ "$patched" = yes ] && ! grep -q "$MARKER" plugin/scripts/worker-service.cjs; then
  echo "fork-sync: patched build is missing the fix" >&2
  exit 1
fi

npm run typecheck
bun test tests

git add -A -- plugin/
if ! git diff --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  git status --short >&2
  echo "fork-sync: build left changes outside the expected set" >&2
  exit 1
fi
if [ "$patched" = yes ]; then note='+ fork/patches'; else note='— upstream fixed #4068, no patch'; fi
git commit --quiet -m "sync: upstream v$version (${target:0:9}) $note"
trap - ERR
git push --quiet origin HEAD:main
echo "fork-sync: pushed $(git rev-parse --short HEAD) ($note)"
