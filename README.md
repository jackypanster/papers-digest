# papers-digest

> **⚠️ 已退役（2026-04-21）**：本系统于 2026-04-21 被 [my-blog](../my-blog) pipeline v2（`my-blog/scripts/cycle.sh`，commit `53170f9b`）取代后主动下线，cron 条目同日移除，此后本地与 spark 均无实例运行。功能被 v2 完整覆盖且更深（HF Daily → arxiv 全文 → 博客发布 → 评分 → 内网分发）。**2026-08-10 决策：保持退役，不恢复、不追平历史缺口。** 调查结论见 notes `87.38`。本仓库保留作历史参考。

每天自动从 [HuggingFace Daily Papers](https://huggingface.co/papers) 拉论文 → Hermes + Gemma4 摘要 + 分类 → 写入 `~/workspace/notes/00 Inbox/papers-YYYY-MM-DD.md`。

人在路径之外，纯旁路观察。

## 架构

```
HF Daily → pick.sh (HTML scrape) → arxiv API (fetch.sh) → Hermes+Gemma4 (process.sh)
        → lint.sh (YAML schema) → publish.sh (写 notes inbox + git push)
```

复用 [`notes/87.37 file-passing-pipeline 通用骨架`](../notes) 模式：
- LLM 只做创造（摘要+分类）
- 脚本做决策（lint 硬规则）
- 文件系统即 memory（drafts/ rejected/）
- cron 无状态触发

## 输出示例

```markdown
# Papers Digest 2026-04-17

共 12 篇 · READ 3 · SKIM 5 · SKIP 4

## 🔥 READ — 推荐细读 (3)

### 论文中文标题
> Original English Title
- arxiv: <https://arxiv.org/abs/2604.xxxxx>
- tags: [LLM, RAG, agent]
- why: <一句中文理由>

  <200 字中文摘要>
```

## 运行

**已退役，不在任何机器上运行。** 最后一次 cycle 为 2026-04-21 11:01（正常结束，非故障）。历史上的 cron（spark 每日 09:00 + 本地 hourly watchdog）均已随 v2 接管移除；后继系统为 my-blog `scripts/cycle.sh`（本机 hourly cron）。

手动触发（仅调试用，无维护保障）：
```bash
./scripts/cycle.sh
```

## 配置

- `topics-of-interest.txt`: 你关注的方向，决定 verdict 优先级
- ALLOWLIST/BLOCKLIST: 不需要（论文领域无敏感词风险）

## 依赖

- `curl`、`awk`、`grep`、`sed`、`bash`
- `hermes` CLI（v0.9+）配置好 OpenAI-compatible 端点
- 本机存在 `~/workspace/notes` git clone

## 已知限制

- 用 HF Daily 而非 monthly：单日 5-15 篇，质量信号还不成熟（但每天有反馈）
- Gemma4 偶发幻觉判 verdict，但比"主观打分 1-10"靠谱很多
- arxiv API 偶发 timeout（curl 20s 限），失败的论文记入 FAILED 章节
