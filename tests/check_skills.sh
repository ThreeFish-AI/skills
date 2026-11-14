#!/usr/bin/env bash
# 仓内静态检查：本仓 skills/ 的 frontmatter 合规、README 索引与目录一致、无人工占位；registry.txt 格式合规且已登记进 README；
# marketplace.json 与清单一致；有 uv 时再对本仓 Skill 与本机已检出的外部 Skill 跑官方 skills-ref 校验。
# 用法：tests/check_skills.sh（失败时退出码为 1）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../scripts/registry.sh
. "$ROOT/scripts/registry.sh"
fail=0
err() { echo "FAIL  $*" >&2; fail=1; }

count=0
VALIDATE_DIRS=()
while IFS= read -r name; do
  skill_md="$ROOT/skills/$name/SKILL.md"
  dir="$ROOT/skills/$name"
  count=$((count + 1))
  VALIDATE_DIRS+=("$dir")

  [ "$(sed -n '1p' "$skill_md")" = "---" ] || err "$name: SKILL.md 首行不是 frontmatter 起始 ---"
  fm="$(awk 'NR==1 && $0=="---" {in_fm=1; next} in_fm && $0=="---" {exit} in_fm {print}' "$skill_md")"
  [ "$(printf '%s\n' "$fm" | sed -n 's/^name: //p')" = "$name" ] || err "$name: frontmatter name 与目录名不一致"
  printf '%s\n' "$name" | grep -Eq "$NAME_RE" || err "$name: 名称须为小写字母、数字与连字符，且不以连字符起止、不含连续连字符"
  [ "${#name}" -le 64 ] || err "$name: 名称超过 64 字符"
  printf '%s\n' "$fm" | grep -q '^description:' || err "$name: 缺少 description"
  grep -q "\`$name\`" "$ROOT/README.md" || err "$name: README 索引表未登记"
  if grep -rn 'TODO(human)' "$dir" >/dev/null 2>&1; then err "$name: 含 TODO(human) 占位"; fi
done < <(local_skills)

[ "$count" -gt 0 ] || err "skills/ 下没有任何 skill"

# registry.txt：格式合规、与本仓 Skill 不重名、已登记进 README；本机已检出的外部 Skill 检查 name 一致并纳入官方校验
reg_out="$(registry_entries)" || err "registry.txt 格式不合规（见上）"
CO_ROOT="$(checkout_root)"
ext=0
while read -r name repo; do
  [ -n "${name:-}" ] || continue
  ext=$((ext + 1))
  [ ! -d "$ROOT/skills/$name" ] || err "$name: 同时出现在 skills/ 与 registry.txt"
  grep -q "\`$name\`" "$ROOT/README.md" || err "$name: README 索引表未登记"
  co="$CO_ROOT/$name"
  if [ -f "$co/SKILL.md" ]; then
    [ "$(frontmatter_name "$co/SKILL.md")" = "$name" ] || err "$name: 本机检出 $co 的 frontmatter name 与登记名不符"
    VALIDATE_DIRS+=("$co")
  else
    echo "skip  $name: 本机未检出（${co}），跳过外部 Skill 校验"
  fi
done <<< "$reg_out"

# marketplace.json 是派生产物，须与 skills/、registry.txt 一致（外部 Skill 未全部检出时无法生成，跳过）
if command -v jq >/dev/null 2>&1; then
  if out="$("$ROOT/scripts/gen-marketplace.sh" --check 2>&1)"; then
    echo "$out"
  elif printf '%s\n' "$out" | grep -q '读不到本机检出'; then
    echo "skip  marketplace.json 比对：外部 Skill 未全部检出"
  else
    printf '%s\n' "$out" >&2; fail=1
  fi
else
  echo "skip  未找到 jq，跳过 marketplace.json 比对"
fi

# 官方参考校验器 skills-ref（PyPI，agentskills.io，命令名 agentskills）：校验 name/description 等字段约束，固定版本，临时环境运行，不装全局
if command -v uv >/dev/null 2>&1; then
  for dir in "${VALIDATE_DIRS[@]}"; do
    uv run --quiet --no-project --with skills-ref==0.1.1 agentskills validate "$dir" || err "$(basename "$dir"): agentskills validate 未通过"
  done
else
  echo "skip  未找到 uv，跳过官方 skills-ref 校验"
fi

[ "$fail" -eq 0 ] && echo "ok  $count 个本仓 skill、$ext 个外部 skill 通过"
exit "$fail"
