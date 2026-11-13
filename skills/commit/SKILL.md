---
name: commit
description: "向 Git 提交工作区变更并推送：先 git pull 同步当前分支，再按内容类别分批、以「type(Topic): 中文摘要;」格式提交，最后 git push。用户要求提交、commit、提交并推送，或任务进入可提交阶段时使用。不用于创建 PR（用 pr-feature）、改写已有提交（amend、rebase、force-push）或直接向 master/main 推送。Use when asked to commit and push changes."
license: MIT
compatibility: 适用于 Claude Code、Codex、Antigravity 等支持 Agent Skills 的宿主；需 git，且当前目录是已配置 origin 的 Git 仓库。
---

# commit

向 Git 提交项目文件中的变更，并维护清晰、简洁的 Commit Message。

## Workflow

1. 先看清要提交什么：`git status --short` 与 `git diff`，据此规划批次与 Commit Message。没有任何变更就报告并停止。
2. 提交前先拉取当前分支在远程的最新版本，用 merge 方式，不 rebase：

   ```bash
   git pull --no-rebase
   ```

   当前分支还没有远程分支（提示无 tracking 信息）时跳过这一步。`git pull` 中止或有冲突时，停止并报告现场（冲突文件与双方改动），不要 stash、reset 或擅自覆盖。
3. 按合理的批次与准备好的 Commit Message 提交变更。
4. 执行 `git push` 把当前分支推送到 GitHub 远程仓库；分支还没有上游时用 `git push -u origin <当前分支>`。推送被拒时停止并报告，不要 force-push。

## 注意事项

- 此时不要再修改 Repo 的内容；任何时候都不允许删除 Repo 中的内容（或文件）。
- 必要时按内容类别分多个批次提交；若存在移动文件的操作，不要拆成删除与新增两个操作，直接按一次文件移动提交。
- 不提交疑似密钥或凭证的文件（`.env`、`*.pem`、`*.key` 等），发现时停止并提醒。
- 不用 `--no-verify` 绕过 hooks；hooks 自动修复了文件导致提交中断时，审阅修复内容后重新暂存并提交。
- 遵循项目与用户全局 AGENTS.md（或宿主等价的指令文件）里的分支与提交规则；当前在 master/main 且规则禁止直接推送主分支时，先切出工作分支再提交。
- Commit Message 使用中文，每次提交的信息末尾附上签名，格式：

  ```
  🤖 Generated with [Claude Code](https://github.com/claude), [CodeX](https://openai.com), [Gemini](https://github.com/apps/gemini-code-assist)
  Co-Authored-By: Aurelius Huang<threefish.ai@gmail.com>
  ```

## Commit Message 规范

```
{Header}({Topic}): Commit Message;
```

- Header（必填）：变更类型的标识
  - feat 新功能
  - fix 修复 bug
  - docs 文档更新
  - style 代码风格变更，不影响功能
  - refactor 原逻辑更改
  - perf 性能优化
  - test 更新测试用例
  - build 依赖更新
  - ci 持续集成相关配置变更
  - chore 除源码和测试代码外的变更
  - revert 撤销之前的 commits
- Topic（必填）：变更内容的主题、模块、特性名称等，使用英文简称
- Commit Message：变更内容的摘要说明，使用中文描述

示例：

```
ci(Jenkins): 修改配置文件以支持 staging 环境;
```
