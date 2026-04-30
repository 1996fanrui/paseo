#!/usr/bin/env bash
#
# Build and publish the Paseo web frontend dist as a GitHub Release asset.
#
# Usage:
#   bash scripts/web-artifact-release/release.sh
#   bash scripts/web-artifact-release/release.sh v0.1.59
#
# This script is designed for GitHub Actions. It builds from a current repository
# tag, creates a dedicated artifact tag that points at the same source commit,
# uploads the web dist and its sha256 file, then downloads the assets back and
# verifies them. When no source tag is provided, the latest v* tag is used.
set -euo pipefail

RELEASE_REPO="1996fanrui/paseo"
RELEASE_REMOTE="origin"
RELEASE_TAG_PREFIX="envtools-web"

usage() {
  awk '
    /^set -euo pipefail$/ { exit }
    /^#!/ { next }
    /^#/ { sub(/^# ?/, ""); print }
  ' "$0"
}

die() {
  echo "error: $*" >&2
  exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

[[ $# -le 1 ]] || die "at most one source tag is allowed"
SOURCE_TAG="${1:-}"

for command_name in git gh node npm tar sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required"
done

mkdir -p /tmp/agent-tmp
TMPDIR="$(mktemp -d /tmp/agent-tmp/paseo-web-artifact.XXXXXXXX)"
WORKTREE="${TMPDIR}/worktree"
DOWNLOAD_DIR="${TMPDIR}/download"

cleanup() {
  if [[ -d "$WORKTREE" ]]; then
    git worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

remote_commit_for_tag() {
  local remote="$1"
  local tag="$2"

  git ls-remote --tags "$remote" "refs/tags/${tag}" "refs/tags/${tag}^{}" |
    awk '$2 ~ /\^\{\}$/ { peeled=$1 } $2 !~ /\^\{\}$/ { direct=$1 } END { print peeled ? peeled : direct }'
}

latest_source_tag() {
  git tag --list 'v[0-9]*' --sort=-version:refname | head -n 1
}

if [[ -z "$SOURCE_TAG" ]]; then
  SOURCE_TAG="$(latest_source_tag)"
  [[ -n "$SOURCE_TAG" ]] || die "no v* source tags found in the current repository"
  echo "No source tag provided; using latest current repository tag ${SOURCE_TAG}"
fi

git rev-parse -q --verify "refs/tags/${SOURCE_TAG}" >/dev/null || die "source tag ${SOURCE_TAG} was not found in the current repository"

RELEASE_TAG="${RELEASE_TAG_PREFIX}-${SOURCE_TAG}"
ASSET_BASENAME="paseo-app-web-${SOURCE_TAG}"
TARBALL="${TMPDIR}/${ASSET_BASENAME}.tar.gz"
SHA_FILE="${TMPDIR}/${ASSET_BASENAME}.sha256"
SOURCE_COMMIT="$(git rev-parse "refs/tags/${SOURCE_TAG}^{}")"

if git rev-parse -q --verify "refs/tags/${RELEASE_TAG}" >/dev/null; then
  LOCAL_RELEASE_COMMIT="$(git rev-parse "${RELEASE_TAG}^{}")"
  [[ "$LOCAL_RELEASE_COMMIT" == "$SOURCE_COMMIT" ]] || die "local ${RELEASE_TAG} points at ${LOCAL_RELEASE_COMMIT}, expected ${SOURCE_COMMIT}"
else
  git tag "$RELEASE_TAG" "$SOURCE_COMMIT"
fi

REMOTE_RELEASE_COMMIT="$(remote_commit_for_tag "$RELEASE_REMOTE" "$RELEASE_TAG")"
if [[ -n "$REMOTE_RELEASE_COMMIT" ]]; then
  [[ "$REMOTE_RELEASE_COMMIT" == "$SOURCE_COMMIT" ]] || die "remote ${RELEASE_TAG} points at ${REMOTE_RELEASE_COMMIT}, expected ${SOURCE_COMMIT}"
else
  git push "$RELEASE_REMOTE" "refs/tags/${RELEASE_TAG}:refs/tags/${RELEASE_TAG}"
fi

echo "Building web dist from ${SOURCE_TAG} (${SOURCE_COMMIT})"
git worktree add --detach "$WORKTREE" "$SOURCE_COMMIT"
(
  cd "$WORKTREE"
  WORKTREE_HEAD="$(git rev-parse HEAD)"
  [[ "$WORKTREE_HEAD" == "$SOURCE_COMMIT" ]] || die "worktree HEAD ${WORKTREE_HEAD} does not match source commit ${SOURCE_COMMIT}"

  echo "Verified ${SOURCE_TAG}: commit=${WORKTREE_HEAD}"
  npm ci
  npm run build:web --workspace=@getpaseo/app
  test -f packages/app/dist/index.html
  test -d packages/app/dist/assets
)

echo "Packaging ${ASSET_BASENAME}.tar.gz"
(
  cd "$WORKTREE/packages/app/dist"
  tar -czf "$TARBALL" .
)
(
  cd "$TMPDIR"
  sha256sum "${ASSET_BASENAME}.tar.gz" > "${ASSET_BASENAME}.sha256"
)

if gh release view "$RELEASE_TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
  gh release upload "$RELEASE_TAG" "$TARBALL" "$SHA_FILE" --repo "$RELEASE_REPO" --clobber
else
  gh release create "$RELEASE_TAG" "$TARBALL" "$SHA_FILE" \
    --repo "$RELEASE_REPO" \
    --title "Web dist for Paseo ${SOURCE_TAG}" \
    --notes "Web frontend dist built from current repository tag ${SOURCE_TAG}."
fi

echo "Verifying uploaded release assets"
mkdir -p "$DOWNLOAD_DIR"
gh release download "$RELEASE_TAG" \
  --repo "$RELEASE_REPO" \
  --pattern "${ASSET_BASENAME}.*" \
  --dir "$DOWNLOAD_DIR"
(
  cd "$DOWNLOAD_DIR"
  sha256sum -c "${ASSET_BASENAME}.sha256"
  mkdir dist-check
  tar -xzf "${ASSET_BASENAME}.tar.gz" -C dist-check
  test -f dist-check/index.html
  test -d dist-check/assets
)

echo "Published ${RELEASE_TAG} to ${RELEASE_REPO}"
