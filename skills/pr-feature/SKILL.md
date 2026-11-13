---
name: pr-feature
description: "基于 origin/feature/1.x.x（用户可指定其他基线）为当前分支创建新 PR 并处理与基线的冲突：PR 标题与正文用中文，标题遵循 AGENTS.md 的 PR Title Convention，在 Orca 环境内创建后挂载到 workspace。仅在用户明确要求创建 PR 时使用；不用于提交代码（用 commit）、合并或关闭 PR。Use only when the user explicitly asks to open a PR against the feature base branch."
license: MIT
compatibility: 适用于 Claude Code、Codex、Antigravity 等支持 Agent Skills 的宿主；需 git 与已登录的 gh；挂载步骤仅在可用 orca CLI 的 Orca workspace 内执行。
---

# pr-feature

基于 origin/feature/1.x.x 创建新 PR，并处理可能存在的冲突。

始终遵循 AGENTS.md（项目与用户全局，或宿主等价的指令文件）中的原则。

## 约定

- 基线分支 `<base>` 默认是 `feature/1.x.x`（远程引用 `origin/feature/1.x.x`）；用户指定了其他基线就以用户为准，基线不存在时停下询问，不要猜。
- PR 标题与正文使用中文。标题写法遵循 AGENTS.md 里的 PR Title Convention（如目标仓库所属组织要求的标题前缀）。
- PR 的 head 分支优先用当前 workspace 已检出的分支，Orca 原生的自动挂载只认这条路径；不建议为了建 PR 另起隔离 worktree。

## Workflow

1. 核对现场：`git status --short`、当前分支名、`gh auth status`。有未提交变更就停止，建议先用 `commit`；当前分支就是基线分支时也停止。
2. 执行 `git fetch origin`，并确认基线存在：`git rev-parse --verify origin/<base>`。
3. 用 `git log origin/<base>..HEAD` 看本次 PR 包含哪些提交，没有提交就报告并停止。已有同 head 的 open PR（`gh pr list --head <当前分支> --state open`）时给出链接，不重复创建。
4. 处理冲突：执行 `git merge origin/<base>` 把基线合进当前分支，不用 rebase。有冲突就逐个解决并保留双方有效意图，拿不准取舍时停下询问；解决后跑与冲突相关的验证。merge commit 的信息按 `commit` 的 Commit Message 规范撰写。
5. 推送当前分支：`git push -u origin <当前分支>`。被拒时停止并报告，不要 force-push。
6. 创建 PR：`gh pr create --base <base> --head <当前分支> --title "<中文标题>" --body-file <正文文件>`。正文写清变更摘要、动机、验证结果与风险点，用 `--body-file` 传入（临时文件放 `.temp/`，用毕清理），避免 shell 转义问题。
7. 在 Orca workspace 内显式兜底挂载，见下节。

## Orca 挂载

PR 创建后挂载到当前 Orca workspace：

```bash
orca worktree set --pr <PR_NUMBER> --worktree path:<当前会话 cwd>
```

这是 Orca UI 右侧 PR 卡的唯一真链路。`orca reference add <PR_URL> --worktree path:<cwd>` 只挂引用层，右侧不显示，可作 agent 上下文补充。宿主已配置创建 PR 后自动挂载的 hook（如 Claude Code 的 PostToolUse hook）时，这一步幂等，只作显式兜底。没有 `orca` 命令，或当前目录不属于任何 Orca workspace，就跳过。PR head 分支若是从隔离 worktree 建的，用毕勿删前先确认挂载。
