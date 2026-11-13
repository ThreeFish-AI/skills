#!/usr/bin/env bash
# 仓内静态检查：frontmatter 合规、README 索引与目录一致、无人工占位；有 uv 时再跑官方 skills-ref 校验。
# 用法：tests/check_skills.sh（失败时退出码为 1）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fail=0
err() { echo "FAIL  $*" >&2; fail=1; }

count=0
shopt -s nullglob
for skill_md in "$ROOT"/skills/*/SKILL.md; do
  dir="$(dirname "$skill_md")"
  name="$(basename "$dir")"
  count=$((count + 1))

  [ "$(sed -n '1p' "$skill_md")" = "---" ] || err "$name: SKILL.md 首行不是 frontmatter 起始 ---"
  fm="$(awk 'NR==1 && $0=="---" {in_fm=1; next} in_fm && $0=="---" {exit} in_fm {print}' "$skill_md")"
  [ "$(printf '%s\n' "$fm" | sed -n 's/^name: //p')" = "$name" ] || err "$name: frontmatter name 与目录名不一致"
  printf '%s\n' "$name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' || err "$name: 名称须为小写字母、数字与连字符，且不以连字符起止、不含连续连字符"
  [ "${#name}" -le 64 ] || err "$name: 名称超过 64 字符"
  printf '%s\n' "$fm" | grep -q '^description:' || err "$name: 缺少 description"
  grep -q "\`$name\`" "$ROOT/README.md" || err "$name: README 索引表未登记"
  if grep -rn 'TODO(human)' "$dir" >/dev/null 2>&1; then err "$name: 含 TODO(human) 占位"; fi
done

[ "$count" -gt 0 ] || err "skills/ 下没有任何 skill"

# 官方参考校验器 skills-ref（PyPI，agentskills.io，命令名 agentskills）：校验 name/description 等字段约束，固定版本，临时环境运行，不装全局
if command -v uv >/dev/null 2>&1; then
  for skill_md in "$ROOT"/skills/*/SKILL.md; do
    dir="$(dirname "$skill_md")"
    uv run --quiet --no-project --with skills-ref==0.1.1 agentskills validate "$dir" || err "$(basename "$dir"): agentskills validate 未通过"
  done
else
  echo "skip  未找到 uv，跳过官方 skills-ref 校验"
fi

[ "$fail" -eq 0 ] && echo "ok  $count skills passed"
exit "$fail"
