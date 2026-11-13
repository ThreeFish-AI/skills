#!/usr/bin/env bash
# scripts/install.sh 行为测试：在临时 HOME 下验证探测、幂等、冲突保护、显式目标与 --check 退出码。
# 用法：tests/test_install.sh（失败时退出码为 1）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
INSTALL="$ROOT/scripts/install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { echo "ok    $*"; }
bad() { echo "FAIL  $*" >&2; fail=1; }
check() { # check <描述> <命令...>：命令成功即通过
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else bad "$desc"; fi
}
linked() { [ -L "$1" ] && [ -f "$1/SKILL.md" ]; }
new_home() { mkdir -p "$TMP/$1"; echo "$TMP/$1"; }
# 在给定 HOME 下运行 install.sh，并清掉外部可能带入的目标覆盖
run() { local h="$1"; shift; env -u THREEFISH_SKILLS_TARGETS HOME="$h" "$INSTALL" "$@"; }

skills=()
for f in "$ROOT"/skills/*/SKILL.md; do skills+=("$(basename "$(dirname "$f")")"); done
first="${skills[0]}"

# 1. 只装了 Claude Code：只链它，不创建其他 Agent 的目录，并报告跳过
H="$(new_home only-claude)"; mkdir -p "$H/.claude"
rc=0; out="$(run "$H" 2>&1)" || rc=$?
check "只装 Claude Code: 退出码 0" test "$rc" -eq 0
for n in "${skills[@]}"; do check "只装 Claude Code: $n 已链接" linked "$H/.claude/skills/$n"; done
check "只装 Claude Code: 未创建 .agents" test ! -e "$H/.agents"
check "只装 Claude Code: 未创建 .gemini" test ! -e "$H/.gemini"
check "只装 Claude Code: 报告跳过 Codex 与 Antigravity" bash -c 'echo "$1" | grep -q "skip      Codex" && echo "$1" | grep -q "skip      Antigravity"' _ "$out"

# 2. 三者都装：各链到自己的目录；Codex 走 ~/.agents/skills，不建 ~/.codex/skills
H="$(new_home all-agents)"; mkdir -p "$H/.claude" "$H/.codex" "$H/.gemini/config"
rc=0; out="$(run "$H" 2>&1)" || rc=$?
check "全装: 退出码 0" test "$rc" -eq 0
for n in "${skills[@]}"; do
  check "全装: $n 链入 .claude/skills" linked "$H/.claude/skills/$n"
  check "全装: $n 链入 .agents/skills" linked "$H/.agents/skills/$n"
  check "全装: $n 链入 .gemini/config/skills" linked "$H/.gemini/config/skills/$n"
done
check "全装: 未创建 .codex/skills" test ! -e "$H/.codex/skills"

# 3. 幂等：重跑退出码 0 且不再新建链接
rc=0; out="$(run "$H" 2>&1)" || rc=$?
check "幂等: 重跑退出码 0" test "$rc" -eq 0
check "幂等: 重跑不再 linked" bash -c '! echo "$1" | grep -q "^linked"' _ "$out"

# 4. --check：已装退出码 0；缺失退出码 1 并报告 MISSING
rc=0; run "$H" --check >/dev/null 2>&1 || rc=$?
check "--check: 已装退出码 0" test "$rc" -eq 0
H="$(new_home check-missing)"; mkdir -p "$H/.claude"
rc=0; out="$(run "$H" --check 2>&1)" || rc=$?
check "--check: 缺失退出码 1" test "$rc" -eq 1
check "--check: 缺失时不新建链接" test ! -e "$H/.claude/skills"
check "--check: 报告 MISSING" bash -c 'echo "$1" | grep -q "^MISSING"' _ "$out"

# 5. 真实目录冲突：不覆盖、不删除，退出码 1，其余 skill 照常链接
H="$(new_home conflict-dir)"; mkdir -p "$H/.claude/skills/$first"; echo keep > "$H/.claude/skills/$first/keep.txt"
rc=0; out="$(run "$H" 2>&1)" || rc=$?
check "真实目录冲突: 退出码 1" test "$rc" -eq 1
check "真实目录冲突: 原目录与文件保持不变" bash -c '[ ! -L "$1" ] && [ "$(cat "$1/keep.txt")" = keep ]' _ "$H/.claude/skills/$first"
check "真实目录冲突: 报告 CONFLICT" bash -c 'echo "$1" | grep -q "^CONFLICT"' _ "$out"
for n in "${skills[@]}"; do
  [ "$n" = "$first" ] || check "真实目录冲突: 其余 skill $n 照常链接" linked "$H/.claude/skills/$n"
done

# 6. 指向别处的软链接冲突：不改动
H="$(new_home conflict-link)"; mkdir -p "$H/.claude/skills" "$TMP/elsewhere"
ln -s "$TMP/elsewhere" "$H/.claude/skills/$first"
rc=0; out="$(run "$H" 2>&1)" || rc=$?
check "异地软链冲突: 退出码 1" test "$rc" -eq 1
check "异地软链冲突: 软链目标不变" test "$(readlink "$H/.claude/skills/$first")" = "$TMP/elsewhere"

# 7. 没有任何已安装的 Agent：退出码 1，且不创建任何目录
H="$(new_home no-agents)"
rc=0; out="$(run "$H" 2>&1)" || rc=$?
check "无 Agent: 退出码 1" test "$rc" -eq 1
check "无 Agent: 提示未检测到" bash -c 'echo "$1" | grep -q "未检测到任何已安装的 Agent"' _ "$out"
check "无 Agent: 未创建任何目录" test -z "$(ls -A "$H")"

# 8. 显式目标：跳过探测，只装到指定目录
H="$(new_home explicit)"; mkdir -p "$H/.claude"
rc=0; env HOME="$H" THREEFISH_SKILLS_TARGETS="$H/custom" "$INSTALL" >/dev/null 2>&1 || rc=$?
check "显式目标: 退出码 0" test "$rc" -eq 0
for n in "${skills[@]}"; do check "显式目标: $n 链入 custom" linked "$H/custom/$n"; done
check "显式目标: 不碰探测到的 .claude/skills" test ! -e "$H/.claude/skills"

[ "$fail" -eq 0 ] && echo "ok  install.sh 全部用例通过"
exit "$fail"
