#!/usr/bin/env bash
#
# Create and push the source tag used by the web artifact release workflow.
#
# Usage:
#   bash scripts/web-artifact-release/create-source-tag.sh v0.1.59
#   bash scripts/web-artifact-release/create-source-tag.sh v0.1.59 main
#   bash scripts/web-artifact-release/create-source-tag.sh v0.1.59 <commit-sha>
#
# The tag name must be provided explicitly. The target ref defaults to HEAD. This
# script only creates and pushes the source tag; it does not build or upload the
# web artifact.
set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 1
}

remote_commit_for_tag() {
  local tag="$1"

  git ls-remote --tags origin "refs/tags/${tag}" "refs/tags/${tag}^{}" |
    awk '$2 ~ /\^\{\}$/ { peeled=$1 } $2 !~ /\^\{\}$/ { direct=$1 } END { print peeled ? peeled : direct }'
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  awk '
    /^set -euo pipefail$/ { exit }
    /^#!/ { next }
    /^#/ { sub(/^# ?/, ""); print }
  ' "$0"
  exit 0
fi

[[ $# -ge 1 ]] || die "source tag is required"
[[ $# -le 2 ]] || die "usage: create-source-tag.sh <source-tag> [ref]"

for command_name in git awk; do
  command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required"
done

SOURCE_TAG="$1"
REF="${2:-HEAD}"
SOURCE_COMMIT="$(git rev-parse --verify "${REF}^{commit}")"

if git rev-parse -q --verify "refs/tags/${SOURCE_TAG}" >/dev/null; then
  LOCAL_COMMIT="$(git rev-parse "refs/tags/${SOURCE_TAG}^{}")"
  [[ "$LOCAL_COMMIT" == "$SOURCE_COMMIT" ]] || die "local ${SOURCE_TAG} points at ${LOCAL_COMMIT}, expected ${SOURCE_COMMIT}"
else
  git tag -a "$SOURCE_TAG" "$SOURCE_COMMIT" -m "$SOURCE_TAG"
fi

REMOTE_COMMIT="$(remote_commit_for_tag "$SOURCE_TAG")"
if [[ -n "$REMOTE_COMMIT" ]]; then
  [[ "$REMOTE_COMMIT" == "$SOURCE_COMMIT" ]] || die "remote ${SOURCE_TAG} points at ${REMOTE_COMMIT}, expected ${SOURCE_COMMIT}"
  echo "Source tag ${SOURCE_TAG} already exists on origin at ${SOURCE_COMMIT}"
else
  git push origin "refs/tags/${SOURCE_TAG}:refs/tags/${SOURCE_TAG}"
  echo "Pushed source tag ${SOURCE_TAG} for ${SOURCE_COMMIT}"
fi
