#!/usr/bin/env bash
# Usage: ./fetch.sh <arxiv_id>
# stdout: abstract 纯文本（多行）；失败/无内容 → 退出码 1
set -euo pipefail

ID="${1:?usage: $0 <arxiv_id>    example: $0 2604.14148}"
URL="https://export.arxiv.org/api/query?id_list=${ID}"

# 自动从 HTTPS_PROXY 推导 curl 代理参数（同 pick.sh）
PROXY_ARG=()
if [[ "${HTTPS_PROXY:-}" == socks* ]]; then
  P="${HTTPS_PROXY#*://}"
  PROXY_ARG=(--socks5-hostname "${P%%/*}")
fi

XML="$(curl "${PROXY_ARG[@]}" -sS --max-time 20 "$URL")"
[[ -z "$XML" ]] && { echo "ERROR: empty arxiv response for $ID" >&2; exit 1; }

# 必须 https，http 端点偶发 hang
# 提 <summary>...</summary> 之间的内容（可能跨多行）
ABSTRACT="$(echo "$XML" | awk '
  /<summary>/ { sub(/.*<summary>/, ""); inside=1 }
  inside && /<\/summary>/ { sub(/<\/summary>.*/, ""); print; exit }
  inside { print }
')"

if [[ -z "$ABSTRACT" ]]; then
  echo "ERROR: no abstract for $ID (paper may not exist on arxiv)" >&2
  exit 1
fi

# 清洗：trim leading/trailing whitespace per line
echo "$ABSTRACT" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | awk 'NF{p=1} p'
