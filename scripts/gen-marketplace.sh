#!/usr/bin/env bash
# 由 skills/ 与 registry.txt 生成 Claude Code 插件市场清单 .claude-plugin/marketplace.json（派生产物，勿手改）。
# 每个 Skill 一个 plugin：本仓 Skill 用相对路径 source；外部 Skill 用 github source，并以 "skills": ["./"] 把仓库根声明为 Skill 目录。
# 用法：scripts/gen-marketplace.sh [--check]
#   --check  只比对，生成结果与仓内文件不一致时退出码为 1
set -euo pipefail

case "${1:-}" in
  "") ;;
  --check) ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=registry.sh
. "$ROOT/scripts/registry.sh"
OUT="$ROOT/.claude-plugin/marketplace.json"

command -v jq >/dev/null 2>&1 || { echo "FAIL  需要 jq" >&2; exit 1; }

# 从 SKILL.md frontmatter 取 description（兼容单行、引号与 >- 折叠块）
skill_description() {
  awk '
    NR==1 && $0=="---" {in_fm=1; next}
    in_fm && $0=="---" {exit}
    in_fm && /^description:/ {
      v=$0; sub(/^description:[[:space:]]*/, "", v)
      if (v ~ /^[>|]/) {block=1; next}
      gsub(/^["\047]|["\047]$/, "", v); print v; exit
    }
    in_fm && block && /^[[:space:]]+/ {line=$0; sub(/^[[:space:]]+/, "", line); out = out (out=="" ? "" : " ") line; next}
    in_fm && block {print out; exit}
    END {if (block && out!="") print out}
  ' "$1" | head -1
}

entries=()
while IFS= read -r name; do
  d="$(skill_description "$ROOT/skills/$name/SKILL.md")"
  entries+=("$(jq -cn --arg n "$name" --arg d "$d" '{name:$n, description:$d, source:("./skills/" + $n)}')")
done < <(local_skills)

reg_out="$(registry_entries)" || { echo "FAIL  registry.txt 格式不合规" >&2; exit 1; }
CO_ROOT="$(checkout_root)"
while read -r name repo; do
  [ -n "${name:-}" ] || continue
  d=""
  # description 只取远端默认分支已提交的版本（检出在特性分支或带未提交改动时，不把未发布文案烘进清单）
  db="$(default_branch "$name" "$CO_ROOT/$name")"
  if [ -n "$db" ] && git -C "$CO_ROOT/$name" cat-file -e "$db:SKILL.md" 2>/dev/null; then
    d="$(git -C "$CO_ROOT/$name" show "$db:SKILL.md" | skill_description /dev/stdin)"
  elif [ -f "$CO_ROOT/$name/SKILL.md" ]; then
    d="$(skill_description "$CO_ROOT/$name/SKILL.md")"
  fi
  [ -n "$d" ] || { echo "FAIL  ${name}：读不到本机检出的 SKILL.md description（${CO_ROOT}/${name}），先 clone 再生成" >&2; exit 1; }
  entries+=("$(jq -cn --arg n "$name" --arg d "$d" --arg r "$repo" \
    '{name:$n, description:$d, source:{source:"github", repo:$r}, skills:["./"]}')")
done <<< "$reg_out"

json="$(printf '%s\n' "${entries[@]+"${entries[@]}"}" | jq -s '{
  name: "threefish-skills",
  description: "ThreeFish-AI 自研 Agent Skills：每个 Skill 一个 plugin，本仓 Skill 与独立 Skill 仓统一从这里安装",
  owner: {name: "ThreeFish-AI", url: "https://github.com/ThreeFish-AI"},
  plugins: .
}')"

if [ "${1:-}" = "--check" ]; then
  if [ -f "$OUT" ] && [ "$json" = "$(cat "$OUT")" ]; then
    echo "ok  marketplace.json 与 skills/、registry.txt 一致"
    exit 0
  fi
  echo "FAIL  marketplace.json 与 skills/、registry.txt 不一致，运行 scripts/gen-marketplace.sh 重新生成" >&2
  exit 1
fi
mkdir -p "$(dirname "$OUT")"
printf '%s\n' "$json" > "$OUT"
echo "wrote $OUT"
