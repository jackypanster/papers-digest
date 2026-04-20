#!/usr/bin/env bash
# Usage: ./publish.sh <papers-list-file>
# 1) 把 drafts/*.yaml 合成一份 markdown 日报 → ~/workspace/notes/00 Inbox/papers-YYYY-MM-DD.md
# 2) 为每篇 read/skim 论文创建独立 JD-ID 笔记 → 40-49 技术知识/<category>/
#    独立笔记供 my-blog pipeline（spark Gemma4）选题写博客
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

# ========== Part 1: 聚合日报 ==========

{
  cat <<HEAD
---
title: "Papers Digest ${DATE}"
created: ${DATE}
tags: [papers-digest, arxiv, hf-papers, automated]
status: 当前有效
intent: HuggingFace Daily Papers 自动摘要（m3 Hermes + Qwen3.6-35B 处理）
---

# Papers Digest ${DATE}

来源: HuggingFace Daily Papers · 处理: Hermes + Qwen3.6-35B

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
    why="$(grep -E '^relevance:' "$yaml" | head -1 | sed 's/^relevance:[[:space:]]*//; s/^"\(.*\)"$/\1/; s/[[:space:]]*$//')"
    tags="$(grep -E '^tags:' "$yaml" | head -1 | sed 's/^tags:[[:space:]]*//; s/[[:space:]]*$//')"
    summary="$(awk '/^summary: \|/{cap=1; next} cap && /^[a-zA-Z_]+:/{exit} cap {print}' "$yaml")"

    {
      echo "### ${title_zh}"
      echo ""
      echo "> ${title_en}"
      echo ""
      echo "- arxiv: <https://arxiv.org/abs/${id}>"
      echo "- tags: ${tags}"
      echo "- relevance: ${why}"
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

if (( ${#failed_ids[@]} > 0 )); then
  {
    echo "## ⚠️ FAILED (${#failed_ids[@]})"
    echo ""
    for id in ${failed_ids[@]+"${failed_ids[@]}"}; do
      _t="$(grep "^${id}	" "$LIST" | head -1 | cut -f2)"; echo "- ${id}: ${_t:-(no title)}"
    done
  } >> "$OUT"
fi

echo "✅ Aggregate: $OUT"

# ========== Part 2: 单篇论文笔记（JD-ID 命名，供 my-blog pipeline 选题） ==========

INDIVIDUAL_COUNT=0

for id in ${read_ids[@]+"${read_ids[@]}"} ${skim_ids[@]+"${skim_ids[@]}"}; do
  yaml="$WORK_DIR/drafts/${id}.yaml"
  [[ ! -f "$yaml" ]] && continue

  p_title_zh="$(grep -E '^title_zh:' "$yaml" | head -1 | sed 's/^title_zh:[[:space:]]*//; s/^"//; s/"$//; s/[[:space:]]*$//')"
  p_title_en="$(grep "^${id}	" "$LIST" | head -1 | cut -f2)"
  p_tags="$(grep -E '^tags:' "$yaml" | head -1 | sed 's/^tags:[[:space:]]*//; s/[[:space:]]*$//')"
  p_verdict="$(grep -E '^verdict:' "$yaml" | head -1 | sed 's/^verdict:[[:space:]]*//; s/[[:space:]]*$//')"
  p_relevance="$(grep -E '^relevance:' "$yaml" | head -1 | sed 's/^relevance:[[:space:]]*//; s/^"//; s/"$//; s/[[:space:]]*$//')"
  p_summary="$(awk '/^summary: \|/{cap=1; next} cap && /^[a-zA-Z_]+:/{exit} cap {print}' "$yaml" | sed 's/^[[:space:]]*//')"

  [[ -z "$p_title_zh" ]] && continue

  # tag → JD 目录映射（默认 42 AI-ML）
  p_cat="42 AI-ML"
  if echo "$p_tags" | grep -qiE 'agent|tool.use|code.gen|prompt|orchestrat|function.call'; then
    p_cat="41 AI工具和技术"
  elif echo "$p_tags" | grep -qiE 'infra|deploy|vllm|llama|quantiz|serving|optim'; then
    p_cat="43 基础设施"
  elif echo "$p_tags" | grep -qiE 'code.review|compiler|IDE|editor'; then
    p_cat="44 编程开发"
  fi
  p_prefix="${p_cat%% *}"
  p_dir="40-49 技术知识/${p_cat}"

  # 按 arxiv ID 去重（已有则跳过）
  if find "$NOTES_DIR/$p_dir" -maxdepth 1 -name "*.md" 2>/dev/null | xargs grep -l "source:.*${id}" 2>/dev/null | grep -q .; then
    continue
  fi

  # 下一个 JD 序号
  p_max=$(ls "$NOTES_DIR/$p_dir/" 2>/dev/null | grep -oE "^${p_prefix}\.[0-9]+" | sort -t. -k2 -n | tail -1 | cut -d. -f2)
  p_jd="${p_prefix}.$(( ${p_max:-0} + 1 ))"

  # 文件名消毒（去掉文件系统危险字符）
  p_safe="$(echo "$p_title_zh" | tr -d '/:*?"<>|')"
  p_file="$NOTES_DIR/$p_dir/${p_jd} ${p_safe}.md"

  mkdir -p "$NOTES_DIR/$p_dir"

  {
    echo "---"
    echo "title: \"${p_title_zh}\""
    echo "created: ${DATE}"
    echo "tags: ${p_tags}"
    echo "source: \"arxiv:${id}\""
    echo "status: papers-digest"
    echo "---"
    echo ""
    echo "# ${p_title_zh}"
    echo ""
    echo "> ${p_title_en}"
    echo ""
    echo "- arxiv: <https://arxiv.org/abs/${id}>"
    echo "- verdict: ${p_verdict}"
    echo "- relevance: ${p_relevance}"
    echo ""
    echo "$p_summary"
  } > "$p_file"

  echo "📝 ${p_jd} ${p_safe}"
  INDIVIDUAL_COUNT=$((INDIVIDUAL_COUNT + 1))
done

echo "📄 ${INDIVIDUAL_COUNT} individual paper notes"

# ========== Git commit ==========

cd "$NOTES_DIR"
git pull --rebase --autostash 2>&1 | tail -2 || true
git add "00 Inbox/papers-${DATE}.md" "40-49 技术知识/" 2>/dev/null || true
git commit -m "papers: ${DATE} digest (${#read_ids[@]}r/${#skim_ids[@]}s/${#skip_ids[@]}skip/${#failed_ids[@]}fail) + ${INDIVIDUAL_COUNT} notes" 2>&1 | tail -3 || echo "(nothing to commit)"
git push 2>&1 | tail -3 || echo "(push failed)"
