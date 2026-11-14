# skills

ThreeFish-AI 自研 Agent Skills 的统一入口，遵循 [Agent Skills 规范](https://agentskills.io/specification)，同一份 `SKILL.md` 可在 Claude Code、Codex、Antigravity、Gemini CLI 等宿主中使用。本仓负责两件事：维护体量小的通用 Skill（`skills/` 下，本仓即其唯一事实源），以及登记在独立仓库维护的 Skill（`registry.txt`，各仓自身是唯一事实源）。两类 Skill 用同一个安装脚本装进本机各 Agent，Agent 目录里只放指向检出目录的软链接，不放副本。

## Skills

| Skill | 维护位置 | 作用 | 依赖 |
| --- | --- | --- | --- |
| [`commit`](./skills/commit/SKILL.md) | 本仓 | 向 Git 提交变更：先 `git pull`，按内容类别分批以「type(Topic): 中文摘要;」格式提交，再 `git push`（可只提交不推送）；含 merge commit 信息格式 | `git` |
| [`pr-feature`](./skills/pr-feature/SKILL.md) | 本仓 | 基于 `origin/feature/1.x.x`（可指定其他基线）为当前分支创建新 PR 并处理冲突，标题与正文用中文 | `git`、`gh`；挂载步骤另需 `orca` |
| [`guided-learn`](https://github.com/ThreeFish-AI/guided-learn) | 独立仓 | 通读论文、文档、代码库等一手材料，写成外行也能读懂的《精读与通俗拆解》，含最小原型与破坏性实验 | 联网；Python 3（优先 `uv`） |
| [`vibe-video`](https://github.com/ThreeFish-AI/vibe-video) | 独立仓 | 把论文、文档、代码库或精读产物做成动效图解科普视频的十阶段流水线 | macOS、`uv`、`pnpm`、Node.js；运行时依赖 `vibe-tts` |
| [`vibe-tts`](https://github.com/ThreeFish-AI/vibe-tts) | 独立仓 | 把一段文字配成 `.mp3`：edge 预置音色或本地 IndexTTS 声音克隆 | `uv`、联网；克隆引擎另需 macOS 与本地服务 |
| [`vibe-stock`](https://github.com/ThreeFish-AI/vibe-stock) | 独立仓 | A 股、港股诊股与决策报告流水线，含后验自校准与盯盘 | `uv`；联网模式需 PyPI 可达 |
| [`preening-substrate`](https://github.com/ThreeFish-AI/preening-substrate) | 独立仓 | 对代码模块做结构性重构与熵减：正交分解、死代码清减、命名规范化与对抗核验 | `git`、目标项目测试工具链 |
| [`review-once`](https://github.com/ThreeFish-AI/review-once) | 独立仓 | 有界、循证的 review-fix 收敛循环，仅在显式点名时触发 | `git` |
| [`rsi`](https://github.com/ThreeFish-AI/rsi) | 独立仓 | 统一 RSI 经验沉淀回路：把上述 Skill 与规约自身的缺陷经门禁核验后以 PR 回流对应仓库 | `git`、`gh` |

独立仓 Skill 的默认分支、RSI 回流路由等以 [ThreeFish-AI/rsi](https://github.com/ThreeFish-AI/rsi) 的注册表为准，本仓不重复登记；`scripts/install.sh --check` 会核对 `registry.txt` 与 rsi 注册表的 Skill 集合是否一致。

## 安装

### 本机维护（软链接）

外部 Skill 默认检出在本仓的父目录下，与本仓并列（`<父目录>/<name>`）；放在别处时用 `THREEFISH_SKILLS_CHECKOUT_ROOT` 指定父目录。

```bash
scripts/install.sh --dry-run   # 只打印将要新建的链接与冲突，不写盘
scripts/install.sh             # 为每个 skill 建软链接，幂等
scripts/install.sh --check     # 只核对：缺链、冲突、检出缺失或 name 不符时退出码为 1
```

外部 Skill 尚未检出时，脚本报告 `NOT-CLONED` 并给出 `git clone` 命令，不自动 clone（安装与 `--check` 的退出码均为 1）。`--check` 另外提示（不影响退出码）：检出不在默认分支、有未提交改动、本地默认分支与远端不一致（只读 `git ls-remote`，`THREEFISH_SKILLS_OFFLINE=1` 时跳过），以及 `registry.txt` 与 rsi 注册表的差集。软链接会把检出当前的分支与未提交改动直接暴露给全部 Agent，这些提示用于发现这类状态。

探测已安装的 Agent，未安装的直接跳过，不创建其目录：

| Agent | 探测依据 | 软链接位置 |
| --- | --- | --- |
| Claude Code | 目录 `~/.claude` | `~/.claude/skills` |
| Codex 与其他读取通用目录的 Agent | 目录 `~/.codex` 或 `~/.agents` | `~/.agents/skills` |
| Antigravity | 目录 `~/.gemini/antigravity` 或 `~/.gemini/config` | `~/.gemini/config/skills` |
| Gemini CLI | 命令 `gemini` 在 `PATH` 上 | `~/.gemini/skills` |

Codex 同时读取 `~/.codex/skills` 与 `~/.agents/skills`，本脚本只装后者，前者留给 Codex 自带与其他工具安装的 Skill。Gemini CLI 只读 `~/.gemini/skills`。Antigravity 2.32.1 只把 `~/.gemini/config/skills` 下的 Skill 列为 Global（含软链接），同名 Skill 同时装在 `~/.gemini/skills` 时不会重复列出。

可用 `THREEFISH_SKILLS_TARGETS=dir1:dir2` 跳过探测、显式指定目标目录。目标位置已有真实目录或指向别处的软链接时只报告 `CONFLICT`，不覆盖也不删除。

### Claude Code 插件市场

不想 clone 的用户可在 Claude Code 里从本仓的插件市场按 Skill 安装，每个 Skill 是一个 plugin：

```text
/plugin marketplace add ThreeFish-AI/skills
/plugin install guided-learn@threefish-skills
```

插件形态安装的 Skill 以 `/<plugin>:<skill>` 调用（如 `/guided-learn:guided-learn`），已用软链接装过同名 Skill 的不必再装。市场清单 `.claude-plugin/marketplace.json` 由 `scripts/gen-marketplace.sh` 从 `skills/` 与 `registry.txt` 生成，勿手改。

### 其他宿主

单个 Skill 也可用 [skills CLI](https://github.com/vercel-labs/skills) 直接安装，例如 `pnpm dlx skills add ThreeFish-AI/guided-learn`，本仓 Skill 用 `pnpm dlx skills add ThreeFish-AI/skills --skill commit`。

## 新增或修改 Skill

1. 体量小、无独立运行时与测试的通用 Skill 放本仓：在 `skills/<name>/SKILL.md` 维护，目录名与 frontmatter 的 `name` 一致，`description` 写清触发场景与不适用场景，只用规范内的 frontmatter 字段。
2. 有独立运行时、测试或发布节奏的 Skill 放独立仓：仓库名等于 Skill 名、`SKILL.md` 在仓库根，在 `registry.txt` 登记一行；需要 RSI 回流的，另向 [ThreeFish-AI/rsi](https://github.com/ThreeFish-AI/rsi) 提 PR 新增适配档案。
3. 在上方索引表登记，运行 `scripts/gen-marketplace.sh` 更新市场清单，运行 `scripts/install.sh` 建链接。
4. 运行 `tests/check_skills.sh` 与 `tests/test_install.sh`。
5. 基于工作分支提交，经 PR 合入默认分支，不直接推送主分支。

## 目录

```text
skills/<name>/SKILL.md          本仓 Skill 本体（可带 agents/openai.yaml、references/、scripts/）
registry.txt                    独立仓 Skill 登记表（name 与 GitHub 仓库）
.claude-plugin/marketplace.json Claude Code 插件市场清单（由 gen-marketplace.sh 生成）
scripts/install.sh              软链接安装与核对
scripts/gen-marketplace.sh      生成与比对插件市场清单
scripts/registry.sh             上述脚本共用的清单读取函数
tests/check_skills.sh           静态检查（含官方 skills-ref 校验与市场清单比对）
tests/test_install.sh           安装脚本行为测试
```
