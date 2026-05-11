#!/usr/bin/env bash
# Push the web/ prototype (flattened to repo root) to jjl-commits/repcut.
#
# Why this exists:
# - Local layout: web/ subdirectory holds the Vite prototype; the iOS app
#   lives next to it; PLAN.md sits inside web/.
# - jjl-commits/repcut is the Vercel deploy target — it wants the
#   prototype at the repo root so no "Root Directory" override is needed.
# - Subtree split extracts just web/ as a flat history and force-pushes
#   it as jjl-commits/repcut's main branch. The full repo (web/ + iOS
#   app) stays on origin (dalv/repcut) when you push there normally.
#
# Usage:
#   ./scripts/push-prototype.sh            # pushes current branch's web/ to jjl main
#   ./scripts/push-prototype.sh <branch>   # pushes <branch>'s web/ to jjl main
#
# One-time setup is below — the script does it on first run.
set -euo pipefail

REMOTE_NAME="jjl"
REMOTE_URL="https://github.com/jjl-commits/repcut.git"
REMOTE_BRANCH="main"
SUBTREE_PREFIX="web"
SPLIT_BRANCH="_jjl_split_$$"

cd "$(git rev-parse --show-toplevel)"

# One-time: add the remote if it doesn't exist yet.
if ! git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
  echo "Adding remote '$REMOTE_NAME' -> $REMOTE_URL"
  git remote add "$REMOTE_NAME" "$REMOTE_URL"
fi

SOURCE_BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"
echo "Splitting '$SUBTREE_PREFIX/' out of '$SOURCE_BRANCH'..."
git subtree split --prefix="$SUBTREE_PREFIX" --branch="$SPLIT_BRANCH" "$SOURCE_BRANCH" >/dev/null

echo "Force-pushing $SPLIT_BRANCH -> $REMOTE_NAME/$REMOTE_BRANCH"
git push --force "$REMOTE_NAME" "$SPLIT_BRANCH:$REMOTE_BRANCH"

git branch -D "$SPLIT_BRANCH" >/dev/null
echo "Done. Prototype pushed to $REMOTE_URL ($REMOTE_BRANCH)."
