#!/usr/bin/env bash
# weirdbb91/claude-mem = latest upstream release + fork/patches, rebuilt and tested (see FORK.md).
# .github/workflows/fork-sync.yml runs this daily from a clean main checkout. Every failure exits
# non-zero before the push, so the last good build stays what Claude Code installs.
# FORK_SYNC_TARGET=<commit> pins the upstream release to sync to (tests and manual runs).
set -euo pipefail

# .github/workflows stays the fork's own: upstream's workflows are disabled here anyway, and the Actions token
# may not push workflow changes (upstream v13.28.0 touched ci.yml and every sync push was rejected).
FORK_PATHS=(FORK.md fork scripts/fork-sync.sh tests/fork .github/workflows)
# Each fork/patches/<name>.patch has its check tests/fork/<name>.test.ts and a "Marker: <text>" header
# line: text that shows up in a built bundle only when that patch is compiled in.

[ "$(git branch --show-current)" = main ] && [ -z "$(git status --porcelain)" ] ||
  { echo "fork-sync: needs a clean main checkout" >&2; exit 1; }
git remote get-url upstream >/dev/null 2>&1 || git remote add upstream https://github.com/thedotmack/claude-mem.git
git fetch --quiet upstream main

# Follow upstream releases: the newest commit that bumped the plugin version (its bundles match its source).
target=${FORK_SYNC_TARGET:-$(git log -1 --format=%H -G'"version"' upstream/main -- plugin/.claude-plugin/plugin.json)}
[ -n "$target" ] || { echo "fork-sync: no upstream release commit found" >&2; exit 1; }
# Rebuild when upstream released, or when the fork's own files changed since the last sync commit.
last_sync=$(git log -1 --first-parent --format=%H --grep='^sync: upstream' HEAD)
if git merge-base --is-ancestor "$target" HEAD && [ -n "$last_sync" ] &&
  git diff --quiet "$last_sync" HEAD -- "${FORK_PATHS[@]}"; then
  echo "fork-sync: already on upstream release ${target:0:9}, fork files unchanged"
  exit 0
fi
version=$(git show "$target:plugin/.claude-plugin/plugin.json" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -1)
echo "fork-sync: syncing to upstream ${target:0:9} (v$version)"

trap 'git merge --abort 2>/dev/null || true; echo "fork-sync: failed, nothing pushed" >&2' ERR
# Merge commit (a plain commit when only fork files changed) whose tree is built here: the upstream release, plus the fork's own files and patches.
git merge --quiet --no-commit --no-ff -s ours "$target"
git read-tree -u --reset "$target"
git rm -rqf --ignore-unmatch -- .github/workflows # drops workflows only upstream has; HEAD's come back below
git checkout HEAD -- "${FORK_PATHS[@]}"

# Upstream keeps no lockfile: install what existed at release time, and the Agent SDK its bundle embeds.
sdk=$(git show "$target:plugin/scripts/worker-service.cjs" | grep -o 'CLAUDE_AGENT_SDK_VERSION="[^"]*"' | head -1 | cut -d'"' -f2)
[ -n "$sdk" ] || { echo "fork-sync: Agent SDK version not found in the upstream bundle" >&2; exit 1; }
npm install --no-audit --no-fund --before="$(git log -1 --format=%cI "$target")"
npm install --no-save --no-audit --no-fund "@anthropic-ai/claude-agent-sdk@$sdk"

# A patch whose check already passes on upstream has been fixed there: stop carrying it.
applied=() markers=()
for p in fork/patches/*.patch; do
  name=$(basename "$p" .patch)
  [ -f "tests/fork/$name.test.ts" ] || { echo "fork-sync: tests/fork/$name.test.ts missing" >&2; exit 1; }
  marker=$(sed -n 's/^Marker: //p' "$p" | head -1)
  [ -n "$marker" ] || { echo "fork-sync: $p has no Marker: line" >&2; exit 1; }
  if bun test "tests/fork/$name.test.ts" >/dev/null 2>&1; then
    echo "fork-sync: upstream passes tests/fork/$name.test.ts — dropping $name"
  else
    echo "fork-sync: applying $name"
    git apply --index --3way "$p"
    applied+=("$name") markers+=(-e "$marker")
  fi
done

npm run build
# Rebuilt files without the patch go back to upstream's bytes: rebuilding them only adds dependency drift.
changed=$(git diff --name-only -- plugin/) # listed up front: git checkout below needs the index lock
while IFS= read -r f; do
  [ -z "$f" ] || { [ ${#markers[@]} -gt 0 ] && grep -qF "${markers[@]}" "$f" 2>/dev/null; } || git checkout "$target" -- "$f"
done <<<"$changed"
git ls-files -z --others --exclude-standard -- plugin/ | while IFS= read -r -d '' f; do rm -- "$f"; done
for name in "${applied[@]}"; do
  marker=$(sed -n 's/^Marker: //p' "fork/patches/$name.patch" | head -1)
  grep -rqF -- "$marker" plugin/scripts || { echo "fork-sync: patched build is missing $name" >&2; exit 1; }
done

npm run typecheck
bun test tests

git add -A -- plugin/
if ! git diff --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  git status --short >&2
  echo "fork-sync: build left changes outside the expected set" >&2
  exit 1
fi
if [ ${#applied[@]} -gt 0 ]; then note="+ ${applied[*]}"; else note='— no patch left'; fi
git commit --quiet -m "sync: upstream v$version (${target:0:9}) $note"
trap - ERR
git push --quiet origin HEAD:main
echo "fork-sync: pushed $(git rev-parse --short HEAD) ($note)"
