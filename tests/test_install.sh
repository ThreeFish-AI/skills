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
# 固定 PATH，只放 install.sh 用到的几个工具，避免本机真实的 gemini 命令影响探测；run_gemini 额外放一个假的 gemini
TOOLS="$TMP/tools"; mkdir -p "$TOOLS"
for t in dirname basename readlink mkdir ln awk sed grep tr head sort comm cut git; do ln -s "$(command -v "$t")" "$TOOLS/$t"; done
GEMINI_BIN="$TMP/gemini-bin"; mkdir -p "$GEMINI_BIN"
printf '#!/bin/sh\nexit 0\n' > "$GEMINI_BIN/gemini"; chmod +x "$GEMINI_BIN/gemini"

# 用仓库副本跑测试：registry.txt 换成测试夹具，外部 Skill 检出放在临时目录，不碰本机真实检出
REPO="$TMP/hub"; mkdir -p "$REPO/scripts"
cp -R "$ROOT/skills" "$REPO/"; cp "$ROOT/scripts/install.sh" "$ROOT/scripts/registry.sh" "$REPO/scripts/"
INSTALL="$REPO/scripts/install.sh"
CO="$TMP/checkouts"; mkdir -p "$CO"
make_ext() { # make_ext <name> [frontmatter-name]：造一个外部 Skill 检出
  mkdir -p "$CO/$1"; printf -- '---\nname: %s\ndescription: test skill\n---\n' "${2:-$1}" > "$CO/$1/SKILL.md"
}
make_ext ext-alpha; make_ext ext-beta
printf '# 夹具\next-alpha  owner/ext-alpha\next-beta   owner/ext-beta   # 行尾注释\n' > "$REPO/registry.txt"

# 在给定 HOME 下运行 install.sh，并清掉外部可能带入的目标覆盖；离线运行，不访问远端
run() { local h="$1"; shift; env -u THREEFISH_SKILLS_TARGETS HOME="$h" PATH="$TOOLS" THREEFISH_SKILLS_CHECKOUT_ROOT="$CO" THREEFISH_SKILLS_OFFLINE=1 "$BASH" "$INSTALL" "$@"; }
run_gemini() { local h="$1"; shift; env -u THREEFISH_SKILLS_TARGETS HOME="$h" PATH="$GEMINI_BIN:$TOOLS" THREEFISH_SKILLS_CHECKOUT_ROOT="$CO" THREEFISH_SKILLS_OFFLINE=1 "$BASH" "$INSTALL" "$@"; }

skills=()
for f in "$REPO"/skills/*/SKILL.md; do skills+=("$(basename "$(dirname "$f")")"); done
first="${skills[0]}"
skills+=(ext-alpha ext-beta)

# 1. 只装了 Claude Code：只链它，不创建其他 Agent 的目录，并报告跳过
H="$(new_home only-claude)"; mkdir -p "$H/.claude"
rc=0; out="$(run "$H" 2>&1)" || rc=$?
check "只装 Claude Code: 退出码 0" test "$rc" -eq 0
for n in "${skills[@]}"; do check "只装 Claude Code: $n 已链接" linked "$H/.claude/skills/$n"; done
check "只装 Claude Code: 未创建 .agents" test ! -e "$H/.agents"
check "只装 Claude Code: 未创建 .gemini" test ! -e "$H/.gemini"
check "只装 Claude Code: 报告跳过 Codex、Antigravity 与 Gemini CLI" bash -c 'echo "$1" | grep -q "skip      Codex" && echo "$1" | grep -q "skip      Antigravity" && echo "$1" | grep -q "skip      Gemini CLI"' _ "$out"

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
check "全装: PATH 上没有 gemini 时未创建 .gemini/skills" test ! -e "$H/.gemini/skills"

# 2b. gemini 命令在 PATH 上：补链到 ~/.gemini/skills；与 Antigravity 并存时两处都链
H="$(new_home gemini-cli)"; mkdir -p "$H/.gemini/config"
rc=0; out="$(run_gemini "$H" 2>&1)" || rc=$?
check "Gemini CLI: 退出码 0" test "$rc" -eq 0
for n in "${skills[@]}"; do
  check "Gemini CLI: $n 链入 .gemini/skills" linked "$H/.gemini/skills/$n"
  check "Gemini CLI: $n 与 Antigravity 并存时仍链入 .gemini/config/skills" linked "$H/.gemini/config/skills/$n"
done
check "Gemini CLI: 未创建 .claude" test ! -e "$H/.claude"

# 2c. 只有 gemini 命令：只链 ~/.gemini/skills
H="$(new_home gemini-only)"
rc=0; out="$(run_gemini "$H" 2>&1)" || rc=$?
check "只有 gemini 命令: 退出码 0" test "$rc" -eq 0
check "只有 gemini 命令: 链入 .gemini/skills" linked "$H/.gemini/skills/$first"
check "只有 gemini 命令: 未创建 .gemini/config" test ! -e "$H/.gemini/config"

# 3. 幂等：对第 2 步的全装环境重跑，退出码 0 且不再新建链接
H="$TMP/all-agents"
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
rc=0; env HOME="$H" THREEFISH_SKILLS_TARGETS="$H/custom" THREEFISH_SKILLS_CHECKOUT_ROOT="$CO" THREEFISH_SKILLS_OFFLINE=1 "$INSTALL" >/dev/null 2>&1 || rc=$?
check "显式目标: 退出码 0" test "$rc" -eq 0
for n in "${skills[@]}"; do check "显式目标: $n 链入 custom" linked "$H/custom/$n"; done
check "显式目标: 不碰探测到的 .claude/skills" test ! -e "$H/.claude/skills"

# 9. 外部 Skill：链接目标是检出目录的物理路径
H="$TMP/all-agents"
check "外部 Skill: ext-alpha 指向检出目录" test "$(cd "$H/.claude/skills/ext-alpha" && pwd -P)" = "$(cd "$CO/ext-alpha" && pwd -P)"

# 10. --dry-run：只打印 would-link，不写盘，退出码 0
H="$(new_home dry-run)"; mkdir -p "$H/.claude"
rc=0; out="$(run "$H" --dry-run 2>&1)" || rc=$?
check "--dry-run: 退出码 0" test "$rc" -eq 0
check "--dry-run: 报告 would-link" bash -c 'echo "$1" | grep -q "^would-link"' _ "$out"
check "--dry-run: 不创建 skills 目录" test ! -e "$H/.claude/skills"

# 11. 外部检出缺失：报告 NOT-CLONED 并给出 clone 命令，退出码 1，不自动 clone，其余 Skill 照常链接
H="$(new_home not-cloned)"; mkdir -p "$H/.claude"
printf 'ext-alpha owner/ext-alpha\next-gamma owner/ext-gamma\n' > "$REPO/registry.txt"
rc=0; out="$(run "$H" 2>&1)" || rc=$?
check "外部未检出: 退出码 1" test "$rc" -eq 1
check "外部未检出: 报告 NOT-CLONED 与 clone 命令" bash -c 'echo "$1" | grep -q "^NOT-CLONED  ext-gamma.*git clone https://github.com/owner/ext-gamma.git"' _ "$out"
check "外部未检出: 不自动 clone" test ! -e "$CO/ext-gamma"
check "外部未检出: 不建悬空链接" test ! -e "$H/.claude/skills/ext-gamma" -a ! -L "$H/.claude/skills/ext-gamma"
check "外部未检出: 其余 Skill 照常链接" linked "$H/.claude/skills/ext-alpha"

# 12. SKILL.md 的 name 与登记名不符：FAIL，不建链接
make_ext ext-delta wrong-name
printf 'ext-delta owner/ext-delta\n' > "$REPO/registry.txt"
H="$(new_home name-mismatch)"; mkdir -p "$H/.claude"
rc=0; out="$(run "$H" 2>&1)" || rc=$?
check "name 不符: 退出码 1" test "$rc" -eq 1
check "name 不符: 报告 frontmatter name" bash -c 'echo "$1" | grep -q "frontmatter name 为「wrong-name」"' _ "$out"
check "name 不符: 不建链接" test ! -L "$H/.claude/skills/ext-delta"

# 13. 与本仓 Skill 重名：FAIL
printf '%s owner/%s\n' "$first" "$first" > "$REPO/registry.txt"
H="$(new_home duplicate)"; mkdir -p "$H/.claude"
rc=0; out="$(run "$H" 2>&1)" || rc=$?
check "重名: 退出码 1" test "$rc" -eq 1
check "重名: 报告同时出现" bash -c 'echo "$1" | grep -q "同时出现在 skills/ 与 registry.txt"' _ "$out"

# 14. 格式不合规的行：FAIL 并指出行号，合规行照常处理
printf 'ext-alpha owner/ext-alpha\nBad_Name owner/x\next-beta not-a-repo\next-beta owner/ext-beta extra\n' > "$REPO/registry.txt"
H="$(new_home malformed)"; mkdir -p "$H/.claude"
rc=0; out="$(run "$H" 2>&1)" || rc=$?
check "格式不合规: 退出码 1" test "$rc" -eq 1
check "格式不合规: 报告非法名的行号" bash -c 'echo "$1" | grep -q "registry.txt:2:"' _ "$out"
check "格式不合规: 报告非法仓库的行号" bash -c 'echo "$1" | grep -q "registry.txt:3:"' _ "$out"
check "格式不合规: 报告多余列的行号" bash -c 'echo "$1" | grep -q "registry.txt:4:"' _ "$out"
check "格式不合规: 合规行照常链接" linked "$H/.claude/skills/ext-alpha"

# 15. --check 与 rsi 注册表对账：两侧差集只提示（note），不改退出码
printf 'ext-alpha owner/ext-alpha\next-beta owner/ext-beta\n' > "$REPO/registry.txt"
mkdir -p "$CO/rsi/repos"; for n in ext-alpha agents ext-omega; do echo "default_branch: main" > "$CO/rsi/repos/$n.md"; done
H="$TMP/all-agents"
rc=0; out="$(run "$H" --check 2>&1)" || rc=$?
check "rsi 对账: 退出码仍为 0" test "$rc" -eq 0
check "rsi 对账: 提示仅在 registry 的 ext-beta" bash -c 'echo "$1" | grep -q "^note      ext-beta：在 registry.txt 登记"' _ "$out"
check "rsi 对账: 提示仅在 rsi 的 ext-omega" bash -c 'echo "$1" | grep -q "^note      ext-omega：rsi 注册表有"' _ "$out"
check "rsi 对账: agents（规范仓）不计入" bash -c '! echo "$1" | grep -q "note      agents："' _ "$out"
echo "skill_path: skills/ext-alpha" > "$CO/rsi/repos/ext-alpha.md"
rc=0; out2="$(run "$H" --check 2>&1)" || rc=$?
check "rsi 对账: skill_path≠. 的档案不再要求登记 registry" bash -c '! echo "$1" | grep -q "note      ext-alpha"' _ "$out2"
rm -rf "$CO/rsi"

# 16. --check 检出状态：不在默认分支、有未提交改动只提示，不改退出码
git -C "$CO/ext-alpha" init -q -b main && git -C "$CO/ext-alpha" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
git -C "$CO/ext-alpha" update-ref refs/remotes/origin/main HEAD && git -C "$CO/ext-alpha" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "$CO/ext-alpha" switch -q -c topic; echo dirty > "$CO/ext-alpha/dirty.txt"
rc=0; out="$(run "$H" --check 2>&1)" || rc=$?
check "检出状态: 退出码仍为 0" test "$rc" -eq 0
check "检出状态: 提示不在默认分支" bash -c 'echo "$1" | grep -q "^note      ext-alpha：检出在 topic，不在默认分支 main"' _ "$out"
check "检出状态: 提示未提交改动" bash -c 'echo "$1" | grep -q "^note      ext-alpha：检出有未提交改动"' _ "$out"


# 17. --relink：改写悬空与旧外部检出路径的链接；他处链接与真实目录不动
printf 'ext-beta owner/ext-beta\n' > "$REPO/registry.txt"
mkdir -p "$REPO/skills/ext-alpha"; printf -- '---\nname: ext-alpha\ndescription: x\n---\n' > "$REPO/skills/ext-alpha/SKILL.md"
H="$(new_home relink)"; mkdir -p "$H/.claude/skills" "$CO/elsewhere3"
ln -s "$CO/ext-alpha" "$H/.claude/skills/ext-alpha"           # 旧外部检出路径（该 Skill 已迁入本仓）
ln -s "$CO/ext-beta-gone" "$H/.claude/skills/ext-beta"        # 悬空
ln -s "$CO/elsewhere3" "$H/.claude/skills/${skills[0]}"       # 他处链接（本仓 skill 名）
rc=0; out="$(run "$H" --relink 2>&1)" || rc=$?
check "--relink: 旧外部检出路径链接改写到本仓源" bash -c '[ "$(cd "$1/.claude/skills/ext-alpha" && pwd -P)" = "$2" ]' _ "$H" "$(cd "$REPO/skills/ext-alpha" && pwd -P)"
check "--relink: 悬空链接改写到当前源" bash -c '[ "$(cd "$1/.claude/skills/ext-beta" && pwd -P)" = "$2" ]' _ "$H" "$(cd "$CO/ext-beta" && pwd -P)"
check "--relink: 他处链接报 CONFLICT 且未动" bash -c 'echo "$1" | grep -q "^CONFLICT.*-> $2/elsewhere3"' _ "$out" "$CO"
check "--relink: 报告 relinked" bash -c 'echo "$1" | grep -q "^relinked"' _ "$out"
check "--relink: 退出码 1（存在 CONFLICT）" test "$rc" -eq 1
[ "$fail" -eq 0 ] && echo "ok  install.sh 全部用例通过"
exit "$fail"
