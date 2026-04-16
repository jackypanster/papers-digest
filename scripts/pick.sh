#!/usr/bin/env bash
# stdout: 一行一个 paper，TAB 分隔: <arxiv_id>\t<title>
# 来源: https://huggingface.co/papers (HF Daily Papers，社区 upvote 已筛)
set -euo pipefail

URL="https://huggingface.co/papers"

# 自动从 HTTPS_PROXY 推导 curl 代理参数（socks5 需 --socks5-hostname，http(s) 走默认）
PROXY_ARG=()
if [[ "${HTTPS_PROXY:-}" == socks* ]]; then
  P="${HTTPS_PROXY#*://}"
  PROXY_ARG=(--socks5-hostname "${P%%/*}")
fi

# 兼容 macOS bash 3.2 (set -u + 空数组报 unbound) 的标准 idiom
HTML="$(curl ${PROXY_ARG[@]+"${PROXY_ARG[@]}"} -sS --max-time 30 -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36' "$URL")"

if [[ -z "$HTML" ]]; then
  echo "ERROR: empty response from $URL" >&2
  exit 1
fi

# HF 页面里每篇 paper 的 link 形如:
#   href="/papers/2604.14148" class="line-clamp-3 cursor-pointer text-balance">Seedance 2.0: Advancing...
# 提 (id, title)，去重保留首次出现顺序
echo "$HTML" | \
  grep -oE 'href="/papers/[0-9]{4}\.[0-9]{4,5}"[^>]*>[^<]+' | \
  sed -E 's|^href="/papers/([0-9]{4}\.[0-9]{4,5})"[^>]*>(.+)$|\1\t\2|' | \
  awk -F'\t' '!seen[$1]++ {print}'
