# AGENTS.md

Surge 与 Clash Verge Rev 共用的代理规则源：`surge/*.list` 规则文件双方共享，客户端各走各的接线。

## 结构

- `surge/` — 全部 `.list` 规则文件（blocked/unblock/openai/claude/google/netflix/telegram 等），被 raw.githubusercontent.com 直连消费
- `scripts/sub.rkt` — 订阅转 Surge 全量配置生成器（Racket），支持多订阅：`.env` 写 `SUB_<NAME>_URL=<url>`，出现顺序 = 优先级（主用 → fallback 备用）；兼容旧 `SURGE_SUB_URL`
- `scripts/clash-verge.js` — Clash Verge Rev 的 Global Extend Script（区域分组 + rule-provider 接线）；多订阅走 Merge 的 `proxy-providers`（键名 ssrdog/mitce）
- 两侧地区识别 pattern（`raw-region-map` / `REGIONS`）共用同一正则源串，改动必须两侧同步

## 常用命令

```bash
racket scripts/sub.rkt              # 从 .env 订阅生成 Surge 配置（需 .env 与模板，见下）
racket scripts/test-sub.rkt         # sub.rkt 单元测试
node scripts/test-clash-verge.mjs   # clash-verge.js 单元测试
```

## 验证与发版

- 无 CI、无发版：改 `.list` 后直接 push master（默认分支是 master），客户端拉 raw 立即生效——**推送即发布，改规则要克制**。
- 改 `scripts/` 后必须跑上面两条测试再 push；改动涉及地区识别时额外核对两侧 pattern 同步。
- 策略组名（OpenAI/Claude/Google/Netflix/Telegram，以及 provider 组名 SSRDOG/MITCE）须与 `sub.rkt` 生成的分组名保持一致。

## 仓库特定规矩

- `scripts/.env`、`scripts/surge-template.conf`、`surge/surge.conf` 均被 gitignore，只存在于本机——缺失属正常，勿提交占位文件；`scripts/.env.example` 是模板，随仓库提交。
- 规则条目改动保持最小增量：只加确认需要的域名，不做批量重构（历史事故教训：误伤面大）。
