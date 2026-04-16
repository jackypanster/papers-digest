#!/usr/bin/env bash
# Usage: ./lint.sh <yaml-file>
# 纯确定性 schema 校验。Exit 0 = pass; 1 = fail
set -euo pipefail

F="${1:?usage: $0 <yaml-file>}"
[[ ! -f "$F" ]] && { echo "FAIL: file not found: $F"; exit 1; }

failures=()

# Rule 1: 必填字段
for field in title_zh arxiv_id url verdict why summary tags; do
  if ! grep -qE "^${field}:" "$F"; then
    failures+=("MISSING-FIELD: $field")
  fi
done

# Rule 2: verdict 必须是 read|skim|skip
verdict="$(grep -E '^verdict:' "$F" | head -1 | sed 's/^verdict:[[:space:]]*//; s/[[:space:]]*$//')"
case "$verdict" in
  read|skim|skip) ;;
  '') failures+=("EMPTY-VERDICT") ;;
  *) failures+=("BAD-VERDICT: '$verdict' not in {read|skim|skip}") ;;
esac

# Rule 3: arxiv_id 格式
arxiv_id="$(grep -E '^arxiv_id:' "$F" | head -1 | sed 's/^arxiv_id:[[:space:]]*//; s/[[:space:]]*$//')"
if ! [[ "$arxiv_id" =~ ^[0-9]{4}\.[0-9]{4,5}$ ]]; then
  failures+=("BAD-ARXIV-ID: '$arxiv_id'")
fi

# Rule 4: tags 必须是数组语法
tags="$(grep -E '^tags:' "$F" | head -1 | sed 's/^tags:[[:space:]]*//; s/[[:space:]]*$//')"
if ! [[ "$tags" =~ ^\[.+\]$ ]]; then
  failures+=("BAD-TAGS: tags 不是 [a, b] 数组语法 → '$tags'")
fi

# Rule 5: summary 字数 50-500（防止 Gemma4 输出空摘要或巨长）
summary_chars="$(awk '/^summary: \|/{cap=1; next} cap && /^[a-zA-Z_]+:/{exit} cap' "$F" | wc -m | tr -d ' ')"
if (( summary_chars < 50 )); then
  failures+=("SUMMARY-TOO-SHORT: ${summary_chars} 字节")
elif (( summary_chars > 1500 )); then
  failures+=("SUMMARY-TOO-LONG: ${summary_chars} 字节")
fi

if (( ${#failures[@]} == 0 )); then
  echo "✅ PASS: $F"
  exit 0
fi

echo "❌ FAIL: $F"
for f in "${failures[@]}"; do
  echo "  - $f"
done
exit 1
