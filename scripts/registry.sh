# shellcheck shell=bash
# install.sh、gen-marketplace.sh 与 tests/check_skills.sh 共用的 Skill 清单读取函数（source 引入，不单独执行）。
# 调用方须先设置 ROOT（本仓物理路径）。

NAME_RE='^[a-z0-9]+(-[a-z0-9]+)*$'
REPO_RE='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'

# 外部 Skill 检出的父目录：默认是本仓的父目录，可用 THREEFISH_SKILLS_CHECKOUT_ROOT 覆盖
checkout_root() {
  local r="${THREEFISH_SKILLS_CHECKOUT_ROOT:-$(dirname "$ROOT")}"
  (cd "$r" 2>/dev/null && pwd -P) || printf '%s\n' "$r"
}

# 本仓 skills/ 下的 Skill 名，每行一个，按名称排序
local_skills() {
  local f
  for f in "$ROOT"/skills/*/SKILL.md; do
    [ -f "$f" ] && basename "$(dirname "$f")"
  done
  return 0
}

# registry.txt 的有效行，输出「name repo」；格式不合规与重复的行报到 stderr 并令返回码为 1
registry_entries() {
  local file="$ROOT/registry.txt" rc=0 n=0 name repo extra seen=""
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line%%$'\r'}"
    line="${line%%#*}"
    read -r name repo extra <<< "$line" || true
    [ -n "${name:-}" ] || continue
    if [ -z "${repo:-}" ] || [ -n "${extra:-}" ]; then
      echo "registry.txt:${n}: 每行须恰好两列（name repo）" >&2; rc=1; continue
    fi
    if ! printf '%s\n' "$name" | grep -Eq "$NAME_RE" || [ "${#name}" -gt 64 ]; then
      echo "registry.txt:${n}: Skill 名「${name}」须为小写字母、数字与单个连字符，且不超过 64 字符" >&2; rc=1; continue
    fi
    if ! printf '%s\n' "$repo" | grep -Eq "$REPO_RE"; then
      echo "registry.txt:${n}: 仓库「${repo}」须为 owner/repo 形式" >&2; rc=1; continue
    fi
    if printf '%s\n' "$seen" | grep -qxF "$name"; then
      echo "registry.txt:${n}: 「${name}」重复登记" >&2; rc=1; continue
    fi
    seen="${seen}${name}
"
    printf '%s %s\n' "$name" "$repo"
  done < "$file"
  return "$rc"
}

# 外部 Skill 的默认分支：以 rsi 注册表 repos/<name>.md 的 default_branch 为准（单一事实源），没有登记时退回本地 origin/HEAD
default_branch() {
  local name="$1" co="$2" adapter b
  adapter="$(checkout_root)/rsi/repos/$name.md"
  if [ -f "$adapter" ]; then
    b="$(sed -n 's/^default_branch:[[:space:]]*//p' "$adapter" | sed 's/#.*//' | sed 's/[[:space:]]*$//' | tr -d "\"'" | head -1)"
    [ -n "$b" ] && { printf '%s\n' "$b"; return 0; }
  fi
  b="$(git -C "$co" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  printf '%s\n' "${b#origin/}"
}

# SKILL.md frontmatter 里 name 字段的值
frontmatter_name() {
  awk 'NR==1 && $0=="---" {in_fm=1; next} in_fm && $0=="---" {exit} in_fm' "$1" | sed -n 's/^name:[[:space:]]*//p' | tr -d "\"'" | head -1
}
