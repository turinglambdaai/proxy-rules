# Proxy Rules

[English](README.md) | [中文](README.zh-CN.md)

代理规则列表，支持 **Surge**（iOS/macOS）和 **Clash Verge Rev**（Windows）。两个客户端共用 `surge/` 下的 `.list` 规则文件。

## 规则分类

| 文件 | 说明 |
|------|------|
| `blocked.list` | 需要代理的域名（社交媒体、AI 服务等） |
| `unblock.list` | 直连的国内域名 |
| `openai.list` | OpenAI / ChatGPT 域名 |
| `claude.list` | Anthropic Claude 域名 |
| `google.list` | Google 服务 |
| `netflix.list` | Netflix 流媒体 |
| `telegram.list` | Telegram 即时通讯 |

## 使用方法

### Surge (iOS / macOS)

在 `[Rule]` 中引用规则集：

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/jrtxio/proxy-rules/main/surge/openai.list,Proxy
RULE-SET,https://raw.githubusercontent.com/jrtxio/proxy-rules/main/surge/google.list,Proxy
RULE-SET,https://raw.githubusercontent.com/jrtxio/proxy-rules/main/surge/blocked.list,Proxy
RULE-SET,https://raw.githubusercontent.com/jrtxio/proxy-rules/main/surge/unblock.list,DIRECT
```

### Clash Verge Rev (Windows)

将 `scripts/clash-verge.js` 的内容粘贴到 **订阅 > 全局扩展脚本** 中。脚本会自动按地区分组代理节点，并配置 rule-providers 指向本仓库的 `surge/*.list` 文件。

### 订阅转换

通过 `scripts/sub.rkt`（Racket 语言）从订阅链接生成完整的 Surge 配置：

1. 在 `scripts/` 下创建 `.env` 文件，填入订阅地址：
   ```
   SURGE_SUB_URL=https://your-subscription-url
   ```

2. 在 `scripts/` 下创建 `surge-template.conf` 模板文件，包含 Surge 的静态配置段（General、Rule、Host、Rewrite、MITM 等），用 `{{PROXY_SECTION}}` 占位标记代理节点插入位置。

3. 运行转换脚本：
   ```bash
   racket scripts/sub.rkt
   ```

   输出完整 Surge 配置到 `surge/surge.conf`。

## 目录结构

```
proxy-rules/
  surge/               # 规则文件（手动维护）
    blocked.list       # 需代理的域名
    unblock.list       # 直连的国内域名
    openai.list        # OpenAI / ChatGPT
    claude.list        # Anthropic Claude
    google.list        # Google 服务
    netflix.list       # Netflix
    telegram.list      # Telegram
  scripts/
    clash-verge.js     # Clash Verge Rev 全局扩展脚本
    sub.rkt            # 订阅链接转 Surge 配置（Racket）
```

## 维护

直接编辑 `surge/` 下的 `.list` 文件，提交后 Surge 和 Clash Verge 会在下次规则更新时自动拉取。

## 环境要求

- **Surge** 或 **Clash Verge Rev** 作为代理客户端
- **Racket**（可选，仅在使用 `sub.rkt` 进行订阅转换时需要）
