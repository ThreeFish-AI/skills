#!/usr/bin/env bash
# 把 skills/* 以软链接装到本机已安装 Agent 的全局 skills 目录（幂等）。
# 用法：scripts/install.sh [--check]
#   --check  只核对不改动，有缺失或冲突时退出码为 1
# 探测已安装的 Agent，未安装的跳过，且不创建其目录（Gemini CLI 看 gemini 命令是否在 PATH 上，其余看根目录是否存在）：
#   Claude Code   ~/.claude                                  -> ~/.claude/skills
#   Codex 与通用   ~/.codex 或 ~/.agents                      -> ~/.agents/skills
#   Antigravity   ~/.gemini/antigravity 或 ~/.gemini/config   -> ~/.gemini/config/skills
#   Gemini CLI    命令 gemini                                 -> ~/.gemini/skills
# THREEFISH_SKILLS_TARGETS=dir1:dir2 可跳过探测，显式指定目标目录。
# 只新建软链接，不覆盖也不删除已有的真实目录或指向别处的软链接，冲突时报告并跳过。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MODE="install"
case "${1:-}" in
  "") ;;
  --check) MODE="check" ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
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

shopt -s nullglob
for skill_md in "$ROOT"/skills/*/SKILL.md; do
  count=$((count + 1))
  src="$(dirname "$skill_md")"
  name="$(basename "$src")"
  for target in "${TARGETS[@]}"; do
    dest="$target/$name"
    if [ -L "$dest" ]; then
      if [ "$(cd "$dest" 2>/dev/null && pwd -P)" = "$src" ]; then
        echo "ok        $dest"
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
    else
      mkdir -p "$target"
      ln -s "$src" "$dest"
      echo "linked    $dest -> $src"
    fi
  done
done

if [ "$count" -eq 0 ]; then
  echo "FAIL  skills/ 下没有任何 skill" >&2
  exit 1
fi
exit "$bad"
