# Web Artifact Release

This directory publishes Paseo web frontend dist assets to the `1996fanrui/paseo` fork.

This is not the official Paseo product release flow. It does not bump versions, publish npm packages, or deploy the app.

## Create a Source Tag

Create and push a source tag from the current commit:

```bash
bash scripts/web-artifact-release/create-source-tag.sh v0.1.59
```

To tag a branch or commit instead:

```bash
bash scripts/web-artifact-release/create-source-tag.sh v0.1.59 main
```

The tag name is always explicit.

## Run from GitHub Actions

Open GitHub Actions and run `Web Artifact Release`.

Leave `source_tag` empty to build the latest current repository `v*` tag. To rebuild a specific version, enter a current repository tag such as:

```text
v0.1.59
```

The workflow will:

- resolve the selected current repository tag;
- verify the build checkout commit matches the selected tag;
- create `envtools-web-v0.1.59` in `1996fanrui/paseo`;
- upload `paseo-app-web-v0.1.59.tar.gz` and `paseo-app-web-v0.1.59.sha256`;
- download the uploaded assets and verify sha256, `index.html`, and `assets/`.

## Verify a Release

```bash
tmpdir="$(mktemp -d /tmp/agent-tmp/paseo-web-dist.XXXXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

gh release download envtools-web-v0.1.59 \
  --repo 1996fanrui/paseo \
  --pattern 'paseo-app-web-v0.1.59.*' \
  --dir "$tmpdir"

cd "$tmpdir"
sha256sum -c paseo-app-web-v0.1.59.sha256
mkdir dist-check
tar -xzf paseo-app-web-v0.1.59.tar.gz -C dist-check
test -f dist-check/index.html
test -d dist-check/assets
du -sh dist-check
```

The `.tar.gz` file is compressed. For example, the `v0.1.58` asset was about 2 MB compressed and 8.3 MB after extraction.

## Delete a Bad Test Release

```bash
gh release delete envtools-web-v0.1.59 \
  --repo 1996fanrui/paseo \
  --cleanup-tag \
  --yes
```
