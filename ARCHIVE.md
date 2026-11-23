# 工作区档案归档说明（ARCHIVE）

## 1. 总述：发布物 vs 本地留档

本仓库只有两类内容：

- **发布物（入库上线）**：被 Git 跟踪、推送到 `main` 后由 GitHub Pages 发布的成品文件。当前发布物只有三个 `index.html`（根索引、Symphony of War 攻略、深空当铺工具）、`README.md`、`CONTRIBUTING.md`、`scripts/gates.json`、`fonts/`、`tools/`、`og*.png`、`probably-stolen/` 与 `.gitignore` / `.nojekyll`。这些文件不能随意删除或移动，删了就是线上事故。
- **本地留档（gitignored 不上线）**：调研抓取的网页原件、过程稿、翻译中间产物、图片、笔记、构建脚本与临时依赖。它们被 `.gitignore` 明文排除，只在本机留档，随时可从上游重新抓取或用保留的构建链重建，**不属于发布物，也不会进公开仓库**。

本次整理把散落在根目录的本地留档按用途归入 `_archive/` 四个子目录；`_archive/` 整目录已加入 `.gitignore`，不会上线。根目录只保留发布物、构建链与工具目录。

## 2. 分类清单

| 类别 | 目录 / 文件 | 是什么 | 是否入库 | 能否安全删除 |
| --- | --- | --- | --- | --- |
| 发布物 | `index.html`、`Symphony of War/index.html`、`深空当铺/index.html` | 三张零依赖单页：工具索引、攻略成品、酿酒合成谱；用户实际访问的就是它们 | 是（已跟踪） | 否，删除即破坏线上 |
| 发布物 | `README.md`、`CONTRIBUTING.md`、`scripts/gates.json` | 仓库说明、贡献流程、门禁清单 | 是 / `CONTRIBUTING.md` 与 `scripts/` 当前为未跟踪新增，待主控统一收口 | 否 |
| 发布物 | `fonts/`、`tools/`、`og.png`、`og-brew.png`、`probably-stolen/` | 自托管字体、字体构建/校验脚本、社交预览图、参考截图 | 是 | 否 |
| 构建链 | `_*.py`、`_*.sh`、`_pydeps/`、`__pycache__/` | 抓取→解析→翻译→替换→校验→建页的可复现脚本链与临时依赖；仍在根目录，供以后复跑 | 否（gitignored） | 否，删了无法复现构建/翻译流程 |
| 笔记 | `_archive/notes/` | 社区指南与 Steam 指南的中文笔记、分批次术语笔记、`最终攻略/` 分章草稿 | 否（gitignored） | 可删，但建议保留：是源攻略 md 的主要素材来源 |
| 抓取原件 | `_archive/raw-guides/` | `g*.html`、`guide_*.html`、`guide_*.txt`、`_txt_*.txt`、`_g*.html`：Steam 指南网页抓取原件与解析文本 | 否（gitignored） | 可删，需要时可从 Steam 重新抓取 |
| 中间稿 | `_archive/intermediate/` | `_final*.md`、`_translated*.md`、`_refined.md`、`_backup_original.md`、`_decoded.txt`、`_diag.txt`、`_dupcheck*.txt`、`_replace_report.txt`、`_residual*.txt`、`_terms_count.txt`、`_match_terms.txt`、`_official_terms.txt`、`_multi_terms.txt`、`_stats.txt`、`_prog.txt`、`_wrapped.txt`、`_extract_report.txt` 等翻译、去重、校验的过程稿 | 否（gitignored） | 可删，最终成果已并入下面的源攻略 md 与网页 |
| 图片 | `_archive/images/` | `_img/` 目录与 `_img_*.jpg`：指南截图、职业树图、军队图 | 否（gitignored） | 可删，网页成品已内嵌所需图片 |
| 源攻略 | `Symphony of War 详尽中文攻略.md` | 真正的内容源头（七章、约 3243 行），网页由它生成；本地留档、不入库 | 否（gitignored） | 否，这是源内容，删除后无法重建网页 |

## 3. 成品定位

- **Symphony of War 攻略成品**：`Symphony of War/index.html`（自包含单页，含侧栏目录，已发布到 GitHub Pages 的 `/Symphony of War/` 路径）。
- **全站索引页**：根目录 `index.html`（`/game-atlas/` 首页，挂两张工具卡片）。
- **深空当铺工具成品**：`深空当铺/index.html`（酿酒合成谱，`/game-atlas/深空当铺/`）。
- **源攻略 md**：根目录 `Symphony of War 详尽中文攻略.md`，是上面攻略网页的文字源头；笔记与分章草稿在 `_archive/notes/`。源 md 本地留档、不入库，网页成品才是发布物。

## 4. 构建链保留说明

根目录的下划线开头脚本（`_build_page.py`、`_build_terms.py`、`_translate.py`、`_refine*.py`、`_fix_*.py`、`_dupcheck.py`、`_residual*.py`、`_check*.py`、`_collect.sh`、`_commit.sh` 等）以及 `_pydeps/`、`__pycache__/` 目录全部**原地保留**，不随本次归档移动。它们构成「Steam 指南抓取 → 文本解析 → 术语替换 → 去重修正 → 生成网页」的可复现链条；需要重建网页或核对译文时，直接从根目录运行即可。`_archive/` 里只放数据产物，不放可执行脚本。

## 5. 归档统计

- 归档目录：`_archive/{notes,raw-guides,intermediate,images}` 四个子目录。
- 归档条目数：notes 6（含 `最终攻略/` 整个目录）、raw-guides 21、intermediate 27、images 5（含 `_img/` 整个目录），合计 **59 个顶层条目**。
- 根目录条目数：整理前 142 → 整理后约 95。下降来自本次归档；整理后并行线（Issue #1）又新增了若干 `_task1_*.py` 临时脚本，故非严格等于「142 − 59」。
- `.gitignore` 末尾新增一行 `/_archive/`，整目录排除，不进入公开仓库。

## 6. 回滚

如需恢复原布局：把 `_archive/` 各子目录中的文件按上表移回根目录，删除 `_archive/` 与 `ARCHIVE.md`，并撤销 `.gitignore` 末尾新增的 `/_archive/` 一行。发布物与构建链未受影响，无需回滚。
