# Paseo 前端产物发布需求

目标是在个人 fork `1996fanrui/paseo` 中发布 Paseo `v0.1.59` 的 web 前端构建产物。

## 背景

有外部系统需要固定消费 Paseo `v0.1.59` 的 web 前端 dist。官方仓库有 web 构建和部署流程，但没有可直接稳定下载的官方 web dist release asset。

这个仓库只负责生成并发布 artifact，不负责下游系统如何下载、缓存或部署。

## 决策

使用个人 fork 的 GitHub Release asset，不把 dist 目录提交到源码分支。

推荐 release tag：

```text
web-my-0.1.59
```

原因：

- 不复用 Paseo 正式版本 tag 名，避免把个人用途 artifact 和官方发版混在一起。
- 后续升级时延续同一命名：`web-my-0.1.60`、`web-my-0.1.61`。
- release asset 比把 dist 目录提交进源码分支更干净。

## 目标产物

在 `1996fanrui/paseo` 的 GitHub Release `web-my-0.1.59` 上发布两个 asset：

```text
paseo-app-web-my-0.1.59.tar.gz
paseo-app-web-my-0.1.59.sha256
```

tar 包解压后应直接得到前端 dist 内容，至少包含：

```text
index.html
assets/
```

不要让 tar 包多包一层随机目录；解压后应直接能看到 `index.html`。

## 执行方式

这不是 Paseo 官方产品 release，不走 `npm run release:patch`，也不 bump 版本或发布 npm 包。

仓库提供独立的 web artifact release 通道：

- 先用 `bash scripts/web-artifact-release/create-source-tag.sh <source-tag> [ref]` 创建并推送 source tag；tag 必须手动输入，例如 `my-0.1.59`，`ref` 不传时默认使用当前 commit。
- GitHub Actions：手动触发 `Web Artifact Release` workflow。
- `source_tag` 留空时，流程自动选择当前仓库最新的 `v*` tag；需要补发指定版本时，手动输入当前仓库已有 tag，例如 `my-0.1.59`。
- GitHub Actions 原生 `workflow_dispatch` 不支持动态读取仓库 tag 作为下拉选项；因此 `source_tag` 保持可选文本输入，流程会在运行时校验输入 tag 必须存在于当前仓库。
- 实现位于 `scripts/web-artifact-release/`，其中 `README.md` 是日常使用入口，`release.sh` 是 workflow 调用的执行脚本。

该流程会自动完成：

- 从当前仓库 tag 中确定 source tag；
- 确认 artifact tag `web-my-0.1.59` 指向 source tag 对应 commit；
- 确认构建 worktree 的 `HEAD` 与 source tag 一致；
- 在临时 worktree 中安装依赖并构建 `packages/app/dist/`；
- 打包并上传 release asset；
- 下载 release asset，验证 sha256、`index.html` 和 `assets/`。

## 关键命令

GitHub Actions 执行：

```bash
gh workflow run web-artifact-release.yml \
  --repo 1996fanrui/paseo \
  -f source_tag=my-0.1.59
```

不传 `source_tag` 时发布当前仓库最新 `v*` tag：

```bash
gh workflow run web-artifact-release.yml \
  --repo 1996fanrui/paseo
```

## 验收

完成后必须验证：

```bash
tmpdir="$(mktemp -d /tmp/agent-tmp/paseo-web-dist.XXXXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

gh release download web-my-0.1.59 \
  --repo 1996fanrui/paseo \
  --pattern 'paseo-app-web-my-0.1.59.*' \
  --dir "$tmpdir"

cd "$tmpdir"
sha256sum -c paseo-app-web-my-0.1.59.sha256
mkdir dist-check
tar -xzf paseo-app-web-my-0.1.59.tar.gz -C dist-check
test -f dist-check/index.html
test -d dist-check/assets
```

## 清理测试发布

如果测试阶段发布的 release 有问题，可以删除 release 和 tag 后重新跑 workflow：

```bash
gh release delete web-my-0.1.58 \
  --repo 1996fanrui/paseo \
  --cleanup-tag \
  --yes
```
