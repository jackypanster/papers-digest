#!/usr/bin/env bash
# Usage: ./process.sh <arxiv_id> <title>
# 读 abstracts/<id>.txt → Hermes+Qwen3.6 → drafts/<id>.yaml
set -euo pipefail

ID="${1:?usage: $0 <arxiv_id> <title>}"
TITLE="${2:?usage: $0 <arxiv_id> <title>}"

WORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ABSTRACT_FILE="$WORK_DIR/abstracts/${ID}.txt"

[[ ! -f "$ABSTRACT_FILE" ]] && { echo "ERROR: abstract not found: $ABSTRACT_FILE" >&2; exit 1; }

# 解析 abstract 文件（第一行 authors:，空行后是 abstract 正文）
if head -1 "$ABSTRACT_FILE" | grep -q '^authors:'; then
  AUTHORS="$(head -1 "$ABSTRACT_FILE" | sed 's/^authors:[[:space:]]*//')"
  ABSTRACT="$(tail -n +3 "$ABSTRACT_FILE")"
else
  # 兼容旧格式（纯 abstract，无 authors 行）
  AUTHORS="unknown"
  ABSTRACT="$(cat "$ABSTRACT_FILE")"
fi

# 用户兴趣关键词
TOPICS_FILE="$WORK_DIR/topics-of-interest.txt"
TOPICS="$(cat "$TOPICS_FILE" 2>/dev/null || echo 'local LLM, agent, RAG, fine-tuning, inference optimization, MoE, code generation')"

TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

cat > "$TMPFILE" <<PROMPT_EOF
你是 papers-digest 分析师。读下面这篇 arxiv 论文的元数据和摘要，输出**结构化 YAML** 深度分析。

# 任务
1. 用 300-500 字中文，**结构化**总结论文（必须覆盖以下四点）：
   a. **核心贡献** — 这篇论文要解决什么问题？现有方案的痛点是什么？
   b. **关键方法** — 怎么做的？核心 insight / 创新点是什么？（不要只说"提出了 XX 方法"，要说清楚方法的核心思路）
   c. **实验结论** — 主要实验结果，关键数字和对比基线（如有）
   d. **局限与展望** — 方法的局限性、适用边界、或值得关注的后续方向（如有）
2. 给出 verdict（必须三选一）：
   - read = 方向新颖、和我兴趣高度相关、值得读全文
   - skim = 方向有意思但 abstract 已经够用
   - skip = 灌水 / 重复别人工作 / 与我兴趣无关
3. 提取 3-5 个 tag（英文领域名，例如 LLM, RAG, agent, fine-tuning）
4. 一句中文说明为什么给这个 verdict（面向第三方读者，说明跟 LLM/agent 工程实践的关系）

# 我的兴趣方向（判 verdict 时优先考虑）
${TOPICS}

# 硬约束（违反 = 整篇作废）
1. 输出**严格** YAML 格式
2. verdict 必须是 read / skim / skip 三个值之一
3. summary 必须**中文**，300-500 字，含上述四点结构
4. tags 必须是合法 YAML 数组（方括号格式）
5. 不要用 markdown 代码块包装输出（不要 \`\`\`yaml \`\`\`）
6. 中文术语首次出现可带英文原文括号
7. 输出完毕后必须在单独一行输出 <<END_OF_DIGEST>>

# 论文输入
title: ${TITLE}
arxiv_id: ${ID}
url: https://arxiv.org/abs/${ID}
authors: ${AUTHORS}

abstract: |
${ABSTRACT}

# 输出格式（严格遵守，无前言无解释）
title_zh: <中文标题翻译>
title_en: "${TITLE}"
arxiv_id: ${ID}
url: https://arxiv.org/abs/${ID}
authors: "${AUTHORS}"
verdict: read|skim|skip
relevance: <一句中文理由>
summary: |
  **核心贡献：**...
  **关键方法：**...
  **实验结论：**...
  **局限与展望：**...
tags: [tag1, tag2, tag3]

现在直接输出 YAML，不要任何前言/解释/markdown 包装。写完必须输出 <<END_OF_DIGEST>>。
PROMPT_EOF

OUT_RAW="$WORK_DIR/drafts/${ID}.raw.yaml"
OUT="$WORK_DIR/drafts/${ID}.yaml"
mkdir -p "$WORK_DIR/drafts"

# 调 hermes 非交互
hermes chat -Q --yolo --max-turns 1 -q "$(cat "$TMPFILE")" > "$OUT_RAW" 2>&1 || {
  echo "ERROR: hermes call failed for $ID" >&2
  exit 2
}

# 清洗：去 banner box / session_id / END marker / markdown 包装 / 复读
awk '
  BEGIN { arxiv_count = 0 }
  /^╭/ || /^╰/ { next }
  /^[[:space:]]*session_id:/ { next }
  /<<END_OF_DIGEST>>/ { sub(/<<END_OF_DIGEST>>.*/, ""); if (length($0) > 0) print; exit }
  /^[[:space:]]*```/ { next }
  /^arxiv_id:/ {
    arxiv_count++
    if (arxiv_count == 2) exit
  }
  { print }
' "$OUT_RAW" > "$OUT"

# 去前后空行
awk 'NF{p=1} p' "$OUT" | awk '{lines[NR]=$0} END {last=NR; while(last>0 && lines[last] !~ /[^[:space:]]/) last--; for(i=1;i<=last;i++) print lines[i]}' > "${OUT}.tmp" && mv "${OUT}.tmp" "$OUT"

echo "✅ $ID processed → $OUT"
