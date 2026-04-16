#!/usr/bin/env bash
# 闭环协调器：pick → for-each(fetch + process + lint) → publish
# 由 cron 触发，完全自动化
set -euo pipefail
set +m  # 规避 Hermes #8340 terminal hang

WORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORK_DIR"

LOG_DIR="$WORK_DIR/.logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/cycle.log"

ts() { date +%Y-%m-%d_%H:%M:%S; }
log() { printf '[%s] %s\n' "$(ts)" "$*" | tee -a "$LOG"; }

log "▶️ cycle start"

# 0. 同步 notes 仓
( cd ~/workspace/notes && git pull --ff-only 2>&1 | tail -2 ) || log "⚠️ notes pull failed (continuing)"

DATE="$(date +%Y-%m-%d)"
LIST="/tmp/papers-list-${DATE}.txt"

# 1. pick
log "📚 picking from HF Daily Papers..."
if ! ./scripts/pick.sh > "$LIST"; then
  log "🔴 pick.sh failed"
  exit 1
fi
COUNT=$(wc -l < "$LIST" | tr -d ' ')
log "📌 got $COUNT papers"
(( COUNT == 0 )) && { log "🟡 no papers today"; exit 0; }

# 2. fetch + process + lint loop
mkdir -p abstracts drafts rejected
SUCCESS=0
FETCH_FAIL=0
PROCESS_FAIL=0
LINT_FAIL=0

while IFS=$'\t' read -r id title; do
  [[ -z "$id" ]] && continue
  log ""
  log "▶️ $id : $title"

  abstract_file="abstracts/${id}.txt"
  if [[ ! -s "$abstract_file" ]]; then
    if ! ./scripts/fetch.sh "$id" > "$abstract_file" 2>/dev/null; then
      log "  ⚠️ fetch failed (no abstract on arxiv)"
      rm -f "$abstract_file"
      FETCH_FAIL=$((FETCH_FAIL + 1))
      continue
    fi
  fi

  if ! ./scripts/process.sh "$id" "$title" 2>&1 | tail -2 >> "$LOG"; then
    log "  ❌ process failed"
    PROCESS_FAIL=$((PROCESS_FAIL + 1))
    continue
  fi

  if ! ./scripts/lint.sh "drafts/${id}.yaml" 2>&1 | tail -5 >> "$LOG"; then
    log "  ❌ lint failed"
    mv "drafts/${id}.yaml" "rejected/${id}.yaml" 2>/dev/null || true
    LINT_FAIL=$((LINT_FAIL + 1))
    continue
  fi

  log "  ✅ pass"
  SUCCESS=$((SUCCESS + 1))
done < "$LIST"

log ""
log "📊 stats: $SUCCESS pass / $FETCH_FAIL fetch-fail / $PROCESS_FAIL process-fail / $LINT_FAIL lint-fail"

# 3. publish (即使部分失败也输出当日 digest)
if (( SUCCESS > 0 )); then
  ./scripts/publish.sh "$LIST" 2>&1 | tee -a "$LOG"
else
  log "🟡 no successful drafts — skipping publish"
fi

log "🟢 cycle end"
