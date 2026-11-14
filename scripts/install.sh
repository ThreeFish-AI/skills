#!/usr/bin/env bash
# 把 Skill 以软链接装到本机已安装 Agent 的全局 skills 目录（幂等）。
# Skill 来源两类：本仓 skills/<name>/（自动发现），以及 registry.txt 登记的外部 Skill 仓（本机检出在 <本仓父目录>/<name>）。
# 用法：scripts/install.sh [--check | --dry-run]
#   --check    只核对不改动：缺链、冲突、外部检出缺失或 SKILL.md name 不符时退出码为 1；另报告检出状态与 rsi 注册表对账（只提示）
#   --dry-run  只打印将要新建的链接与冲突，不写盘
#   --relink   在安装基础上，把悬空或仍指向该 Skill 旧外部检出路径（<检出父目录>/<name>）的软链接改写到当前源；真实目录与他处链接仍报 CONFLICT 不动
# 探测已安装的 Agent，未安装的跳过，且不创建其目录（Gemini CLI 看 gemini 命令是否在 PATH 上，其余看根目录是否存在）：
#   Claude Code   ~/.claude                                  -> ~/.claude/skills
#   Codex 与通用   ~/.codex 或 ~/.agents                      -> ~/.agents/skills
#   Antigravity   ~/.gemini/antigravity 或 ~/.gemini/config   -> ~/.gemini/config/skills
#   Gemini CLI    命令 gemini                                 -> ~/.gemini/skills
# THREEFISH_SKILLS_TARGETS=dir1:dir2 可跳过探测，显式指定目标目录。
# THREEFISH_SKILLS_CHECKOUT_ROOT=<dir> 可改外部 Skill 检出的父目录（默认本仓父目录）。
# 只新建软链接，不覆盖也不删除已有的真实目录或指向别处的软链接，冲突时报告并跳过；外部检出缺失时只提示 clone 命令，不自动 clone。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=registry.sh
. "$ROOT/scripts/registry.sh"

MODE="install"
case "${1:-}" in
  "") ;;
  --check) MODE="check" ;;
  --dry-run) MODE="dry-run" ;;
  --relink) MODE="relink" ;;
  *) echo "usage: $0 [--check | --dry-run | --relink]" >&2; exit 2 ;;
esac

TARGETS=()
if [ -n "${THREEFISH_SKILLS_TARGETS:-}" ]; then
  IFS=':' read -r -a TARGETS <<< "$THREEFISH_SKILLS_TARGETS"
else
  # 每项：标签|探测项（冒号分隔，任一满足即视为已安装；cmd=<命令> 表示该命令在 PATH 上，其余是目录）|skills 目录
  for entry in \
    "Claude Code|$HOME/.claude|$HOME/.claude/skills" \
    "Codex/通用|$HOME/.codex:$HOME/.agents|$HOME/.agents/skills" \
    "Antigravity|$HOME/.gemini/antigravity:$HOME/.gemini/config|$HOME/.gemini/config/skills" \
    "Gemini CLI|cmd=gemini|$HOME/.gemini/skills"
  do
    IFS='|' read -r label roots dir <<< "$entry"
    IFS=':' read -r -a root_list <<< "$roots"
    found=0
    for root in "${root_list[@]}"; do
      case "$root" in
        cmd=*) if command -v "${root#cmd=}" >/dev/null 2>&1; then found=1; fi ;;
        *) if [ -d "$root" ]; then found=1; fi ;;
      esac
    done
    if [ "$found" -eq 1 ]; then
      TARGETS+=("$dir")
    else
      echo "skip      ${label}（未检测到）"
    fi
  done
fi

if [ "${#TARGETS[@]}" -eq 0 ]; then
  echo "FAIL  未检测到任何已安装的 Agent；可用 THREEFISH_SKILLS_TARGETS 显式指定目标目录" >&2
  exit 1
fi

bad=0
count=0
CO_ROOT="$(checkout_root)"

# 汇总 Skill 清单：并行数组承载 name / 源目录 / repo（本仓 Skill 的 repo 记为 -），避免拼串后按空白拆分在路径含空格时失效
SK_NAME=(); SK_SRC=(); SK_REPO=()
while IFS= read -r name; do
  SK_NAME+=("$name"); SK_SRC+=("$ROOT/skills/$name"); SK_REPO+=("-")
done < <(local_skills)
reg_out="$(registry_entries)" || { echo "FAIL  registry.txt 格式不合规（见上）" >&2; bad=1; }
while read -r name repo; do
  [ -n "${name:-}" ] || continue
  for s in "${SK_NAME[@]+"${SK_NAME[@]}"}"; do
    if [ "$s" = "$name" ]; then echo "FAIL  ${name} 同时出现在 skills/ 与 registry.txt，或 registry.txt 内重复登记" >&2; bad=1; continue 2; fi
  done
  SK_NAME+=("$name"); SK_SRC+=("$CO_ROOT/$name"); SK_REPO+=("$repo")
done <<< "$reg_out"
SK_COUNT=${#SK_NAME[@]}

i=0
while [ "$i" -lt "$SK_COUNT" ]; do
  name="${SK_NAME[$i]}"; src="${SK_SRC[$i]}"; repo="${SK_REPO[$i]}"
  count=$((count + 1))
  if [ ! -f "$src/SKILL.md" ]; then
    if [ "$repo" != "-" ]; then
      if [ -e "$src" ]; then
        echo "NOT-CLONED  ${name}：${src} 已存在但下没有 SKILL.md；先检查该目录（残留拷贝或不完整检出），确认无误后移除再 git clone https://github.com/${repo}.git \"${src}\""
      else
        echo "NOT-CLONED  ${name}：${src} 下没有 SKILL.md；先执行 git clone https://github.com/${repo}.git \"${src}\""
      fi
    else
      echo "FAIL  ${name}：${src}/SKILL.md 不存在" >&2
    fi
    bad=1
  else
    src="$(cd "$src" && pwd -P)"
    fm="$(frontmatter_name "$src/SKILL.md")"
    if [ "$fm" != "$name" ]; then
      echo "FAIL  ${name}：${src}/SKILL.md 的 frontmatter name 为「${fm}」，与登记名不符" >&2
      bad=1
    else
      for target in "${TARGETS[@]}"; do
        dest="$target/$name"
        if [ -L "$dest" ]; then
          cur="$(cd "$dest" 2>/dev/null && pwd -P || true)"
          if [ "$cur" = "$src" ]; then
            echo "ok        $dest"
          elif [ "$MODE" = "relink" ] && { [ -z "$cur" ] || [ "$cur" = "$CO_ROOT/$name" ]; }; then
            # --relink 只改写两类链接：悬空链接，或仍指向该 Skill 旧的外部检出路径（迁入本仓后由 registry.txt 移除）的链接；真实目录与他处链接一律不碰
            old="$(readlink "$dest")"
            ln -sfn "$src" "$dest"
            echo "relinked  $dest -> ${src}（原 ${old}）"
          else
            echo "CONFLICT  $dest -> $(readlink "$dest")（已指向别处，未改动）"
            bad=1
          fi
        elif [ -e "$dest" ]; then
          echo "CONFLICT  $dest 是真实目录或文件（未改动；先并入 $src 再手动移除）"
          bad=1
        elif [ "$MODE" = "check" ]; then
          echo "MISSING   $dest"
          bad=1
        elif [ "$MODE" = "dry-run" ]; then
          echo "would-link  $dest -> $src"
        else
          mkdir -p "$target"
          ln -s "$src" "$dest"
          echo "linked    $dest -> $src"
        fi
      done
    fi
  fi
  i=$((i + 1))
done

if [ "$count" -eq 0 ]; then
  echo "FAIL  skills/ 与 registry.txt 里没有任何 skill" >&2
  exit 1
fi

# 以下两项只在 --check 时报告，均为提示，不影响退出码：软链接把检出当前的分支与未提交改动直接暴露给全部 Agent
if [ "$MODE" = "check" ]; then
  while read -r name repo; do
    [ -n "${name:-}" ] || continue
    co="$CO_ROOT/$name"
    git -C "$co" rev-parse --git-dir >/dev/null 2>&1 || continue
    # 检出目录本身不是仓库根时（比如被拷进了某个外层 git 仓），分支与远端说的都是外层仓，直接跳过
    [ "$(git -C "$co" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$co" && pwd -P)" ] || continue
    branch="$(git -C "$co" branch --show-current 2>/dev/null || true)"
    default="$(default_branch "$name" "$co")"
    if [ -n "$default" ] && [ "$branch" != "$default" ]; then
      echo "note      ${name}：检出在 ${branch:-detached HEAD}，不在默认分支 ${default}"
    fi
    if [ -n "$(GIT_OPTIONAL_LOCKS=0 git -C "$co" status --porcelain 2>/dev/null)" ]; then
      echo "note      ${name}：检出有未提交改动"
    fi
    # 与远端默认分支对比只读 ls-remote，不 fetch、不改本地引用；离线或无 origin 时跳过
    if [ -z "${THREEFISH_SKILLS_OFFLINE:-}" ] && [ -n "$default" ]; then
      remote="$(GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=10' git -C "$co" ls-remote origin "refs/heads/$default" 2>/dev/null | cut -f1 || true)"
      if [ -n "$remote" ]; then
        local_def="$(git -C "$co" rev-parse --quiet --verify "refs/heads/$default" 2>/dev/null || true)"
        if [ -z "$local_def" ]; then
          echo "note      ${name}：本地没有 ${default} 分支（远端 ${remote:0:7}），需要时执行 git -C \"${co}\" pull --ff-only"
        elif [ "$remote" != "$local_def" ]; then
          if ! git -C "$co" cat-file -e "${remote}^{commit}" 2>/dev/null; then
            echo "note      ${name}：本地 ${default} 与远端不一致（远端 ${remote:0:7}，本地未取得该提交），需要时执行 git -C \"${co}\" pull --ff-only"
          else
            behind="$(git -C "$co" rev-list --count "$remote" --not "$local_def" 2>/dev/null || echo 0)"
            ahead="$(git -C "$co" rev-list --count "$local_def" --not "$remote" 2>/dev/null || echo 0)"
            if [ "$behind" -gt 0 ] && [ "$ahead" -eq 0 ]; then
              echo "note      ${name}：本地 ${default} 落后远端（远端 ${remote:0:7}），需要时执行 git -C \"${co}\" pull --ff-only"
            elif [ "$ahead" -gt 0 ] && [ "$behind" -eq 0 ]; then
              echo "note      ${name}：本地 ${default} 领先远端（有未推送提交），需要时执行 git -C \"${co}\" push"
            else
              echo "note      ${name}：本地 ${default} 与远端分叉（本地 ${local_def:0:7} / 远端 ${remote:0:7}），自行核对后处理"
            fi
          fi
        fi
      fi
    fi
  done <<< "$reg_out"

  # rsi 注册表对账：registry.txt 的外部 Skill 应与 rsi 的 repos/*.md 一一对应（agents.md 是规范仓、不是 Skill，不计入）
  RSI_REPOS="$CO_ROOT/rsi/repos"
  if [ -d "$RSI_REPOS" ]; then
    # skill_path 非 . 的档案是 monorepo 承载形态（Skill 随其上游仓安装，如本仓 skills/）：两侧对账都跳过
    mono_names="$(cd "$RSI_REPOS" && for f in *.md; do
      [ -e "$f" ] && grep -qE '^skill_path:[[:space:]]*[^.]' "$f" && basename "$f" .md
    done | sort || true)"
    reg_names="$(printf '%s\n' "$reg_out" | awk 'NF {print $1}' | sort | grep -vxF -f <(printf '%s\n' "$mono_names") || true)"
    rsi_names="$(cd "$RSI_REPOS" && for f in *.md; do
      [ -e "$f" ] || continue
      n="$(basename "$f" .md)"
      [ "$n" = "agents" ] && continue  # agents.md 是规范仓（agents.md 协作规约）、不是 Skill
      printf '%s\n' "$n"
    done | sort | grep -vxF -f <(printf '%s\n' "$mono_names") || true)"
    comm -23 <(printf '%s\n' "$reg_names") <(printf '%s\n' "$rsi_names") | while IFS= read -r n; do
      [ -n "$n" ] || continue
      echo "note      ${n}：在 registry.txt 登记，rsi 注册表没有对应的 repos/${n}.md（不走 RSI 回流）"
    done
    comm -13 <(printf '%s\n' "$reg_names") <(printf '%s\n' "$rsi_names") | while IFS= read -r n; do
      [ -n "$n" ] || continue
      echo "note      ${n}：rsi 注册表有 repos/${n}.md，registry.txt 未登记（本机不会安装）"
    done
  fi
fi

exit "$bad"
