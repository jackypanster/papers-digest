#!/usr/bin/env bash
# Usage: ./publish.sh <papers-list-file>
# 把 drafts/*.yaml 合成一份 markdown，写到 ~/workspace/notes/00 Inbox/papers-YYYY-MM-DD.md
set -euo pipefail

LIST="${1:?usage: $0 <papers-list-file>}"
WORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NOTES_DIR="$HOME/workspace/notes"
DATE="$(date +%Y-%m-%d)"
OUT="$NOTES_DIR/00 Inbox/papers-${DATE}.md"

mkdir -p "$(dirname "$OUT")"

# 收集分类
read_ids=()
skim_ids=()
skip_ids=()
failed_ids=()

# 注意：不用 declare -A（macOS bash 3.2 不支持关联数组）
# title 查询改用 grep $LIST 文件
while IFS=$'\t' read -r id title; do
  [[ -z "$id" ]] && continue
  yaml="$WORK_DIR/drafts/${id}.yaml"
  if [[ ! -f "$yaml" ]]; then
    failed_ids+=("$id")
    continue
  fi
  verdict="$(grep -E '^verdict:' "$yaml" | head -1 | sed 's/^verdict:[[:space:]]*//; s/[[:space:]]*$//')"
  case "$verdict" in
    read) read_ids+=("$id") ;;
    skim) skim_ids+=("$id") ;;
    skip) skip_ids+=("$id") ;;
    *)    failed_ids+=("$id") ;;
  esac
done < "$LIST"

TOTAL="$(wc -l < "$LIST" | tr -d ' ')"

# 写 frontmatter + 头部
{
  cat <<HEAD
---
title: "Papers Digest ${DATE}"
created: ${DATE}
tags: [papers-digest, arxiv, hf-papers, automated]
status: 当前有效
intent: HuggingFace Daily Papers 自动摘要（m3 Hermes + Gemma4-26B-A4B 处理）
---

# Papers Digest ${DATE}

来源: HuggingFace Daily Papers · 处理: Hermes + Gemma4-26B-A4B

共 ${TOTAL} 篇 · READ ${#read_ids[@]} · SKIM ${#skim_ids[@]} · SKIP ${#skip_ids[@]} · FAIL ${#failed_ids[@]}

HEAD
} > "$OUT"

emit_section() {
  local label="$1"; local emoji="$2"; shift 2
  local arr=("$@")
  (( ${#arr[@]} == 0 )) && return 0
  echo "## ${emoji} ${label} (${#arr[@]})" >> "$OUT"
  echo "" >> "$OUT"
  for id in "${arr[@]}"; do
    yaml="$WORK_DIR/drafts/${id}.yaml"
    [[ ! -f "$yaml" ]] && continue
    title_zh="$(grep -E '^title_zh:' "$yaml" | head -1 | sed 's/^title_zh:[[:space:]]*//; s/^"\(.*\)"$/\1/; s/[[:space:]]*$//')"
    title_en="$(grep "^${id}	" "$LIST" | head -1 | cut -f2)"
    : "${title_en:=(no title)}"
    why="$(grep -E '^why:' "$yaml" | head -1 | sed 's/^why:[[:space:]]*//; s/^"\(.*\)"$/\1/; s/[[:space:]]*$//')"
    tags="$(grep -E '^tags:' "$yaml" | head -1 | sed 's/^tags:[[:space:]]*//; s/[[:space:]]*$//')"
    summary="$(awk '/^summary: \|/{cap=1; next} cap && /^[a-zA-Z_]+:/{exit} cap {print}' "$yaml")"

    {
      echo "### ${title_zh}"
      echo ""
      echo "> ${title_en}"
      echo ""
      echo "- arxiv: <https://arxiv.org/abs/${id}>"
      echo "- tags: ${tags}"
      echo "- why: ${why}"
      echo ""
      echo "${summary}" | sed 's/^[[:space:]]*/  /'
      echo ""
    } >> "$OUT"
  done
}

# bash 3.2 兼容：空数组展开用 ${arr[@]+"${arr[@]}"} 防 unbound
emit_section "READ — 推荐细读" "🔥" ${read_ids[@]+"${read_ids[@]}"}
emit_section "SKIM — 翻翻就好" "📑" ${skim_ids[@]+"${skim_ids[@]}"}
emit_section "SKIP — 跳过" "⏭️" ${skip_ids[@]+"${skip_ids[@]}"}

if (( ${#failed_ids[@]+${#failed_ids[@]}} > 0 )); then
  {
    echo "## ⚠️ FAILED (${#failed_ids[@]})"
    echo ""
    for id in ${failed_ids[@]+"${failed_ids[@]}"}; do
      _t="$(grep "^${id}	" "$LIST" | head -1 | cut -f2)"; echo "- ${id}: ${_t:-(no title)}"
    done
  } >> "$OUT"
fi

echo "✅ Wrote: $OUT"

# 提交到 notes 仓库
cd "$NOTES_DIR"
git pull --rebase --autostash 2>&1 | tail -2 || true
git add "00 Inbox/papers-${DATE}.md"
git commit -m "papers: ${DATE} digest (${#read_ids[@]}r/${#skim_ids[@]}s/${#skip_ids[@]}skip/${#failed_ids[@]}fail)" 2>&1 | tail -3 || echo "(nothing to commit)"
git push 2>&1 | tail -3 || echo "(push failed)"
