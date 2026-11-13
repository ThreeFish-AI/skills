# skills

ThreeFish-AI 通用 Agent Skills 的统一维护仓库，遵循 [Agent Skills 规范](https://agentskills.io/specification)，同一份 `SKILL.md` 可在 Claude Code、Codex、Antigravity 等宿主中使用。本仓是这些 Skill 的唯一事实源，本机各 Agent 的 skills 目录里只放指向本仓的软链接，不放副本。

## Skills

| Skill | 作用 | 依赖 |
| --- | --- | --- |
| [`commit`](./skills/commit/SKILL.md) | 向 Git 提交变更：先 `git pull`，按内容类别分批以「type(Topic): 中文摘要;」格式提交，再 `git push` | `git` |
| [`pr-feature`](./skills/pr-feature/SKILL.md) | 基于 `origin/feature/1.x.x`（可指定其他基线）为当前分支创建新 PR 并处理冲突，标题与正文用中文 | `git`、`gh`；挂载步骤另需 `orca` |

## 安装

```bash
scripts/install.sh           # 为每个 skill 建软链接，幂等
scripts/install.sh --check   # 只核对，缺失或冲突时退出码为 1
```

按 Agent 根目录是否存在探测已安装的 Agent，未安装的直接跳过，不创建其目录：

| Agent | 探测目录 | 软链接位置 |
| --- | --- | --- |
| Claude Code | `~/.claude` | `~/.claude/skills` |
| Codex 与其他读取通用目录的 Agent | `~/.codex` 或 `~/.agents` | `~/.agents/skills` |
| Antigravity | `~/.gemini/antigravity` 或 `~/.gemini/config` | `~/.gemini/config/skills` |

可用 `THREEFISH_SKILLS_TARGETS=dir1:dir2` 跳过探测、显式指定目标目录。目标位置已有真实目录或指向别处的软链接时只报告 `CONFLICT`，不覆盖也不删除。

## 新增或修改 Skill

1. 在 `skills/<name>/SKILL.md` 维护，目录名与 frontmatter 的 `name` 一致，`description` 写清触发场景与不适用场景，只用规范内的 frontmatter 字段。
2. 在上方索引表登记，运行 `scripts/install.sh` 建链接。
3. 运行 `tests/check_skills.sh` 与 `tests/test_install.sh`。
4. 基于工作分支提交，经 PR 合入默认分支，不直接推送主分支。

## 目录

```text
skills/<name>/SKILL.md   Skill 本体（可带 agents/openai.yaml、references/、scripts/）
scripts/install.sh       软链接安装与核对
tests/check_skills.sh    仓内静态检查（含官方 skills-ref 校验）
tests/test_install.sh    安装脚本行为测试
```
