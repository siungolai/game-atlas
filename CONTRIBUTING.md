# 游戏图鉴 · 贡献流程（issue-pr-loop）

本项目所有改动走 PR，不直推主干（`main`）。本文件是总纲，细则见本机 `~/.dsh/skills/issue-pr-loop/`。

## 红线

1. 主干只读：任何改动（含纯文档、错别字、空格）都必须开功能分支 + PR。
2. 门禁必跑：每个 PR 按 `scripts/gates.json` 跑全套，正文贴原始输出。
3. 禁用地名：所有发布物与仓库文档不得出现禁用地名（含繁体字形）；检测脚本只放本地 gitignored 区，不入库。
4. 凭据不入库：任何 token、密码、私钥不得进入被 git 跟踪的文件。
5. 回滚单位：一律 squash 合并，主干提交标题带单号。

## 八阶段

发现需求 → issue（四要素）→ plan 追评 → 分支 → PR（五段正文）→ 门禁 → 新上下文评审 → 串行合并 → 回签/关单。

## 当前门禁清单

见 `scripts/gates.json`（唯一事实源）。改动发布物时必须复跑其中全部条目。

## 分支命名

`<type>/<单号>-<slug>`，type 取 feat / fix / refactor / docs / test / chore。

## 关单

- 纯文档 / 纯重构：PR 正文首行声明，`Closes #<单号>`，免新上下文评审但 PR 照开。
- 改运行时行为：`Refs #<单号>` + 合后挂 `needs-live-verify`，换人真机回签。
