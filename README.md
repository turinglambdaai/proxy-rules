# Proxy Rules

## 项目简介

代理规则列表，支持 **Surge** (iOS/macOS) 和 **Clash Verge** (Windows)。

以 Surge `.list` 格式为核心维护，通过脚本自动生成 Clash 兼容的 `.yml` 规则集。

## 目录结构

```
proxy-rules/
├── surge/            # Surge 规则列表（源文件，手动维护）
│   ├── blocked.list
│   ├── unblock.list
│   ├── openai.list
│   ├── claude.list
│   ├── google.list
│   ├── netflix.list
│   └── telegram.list
├── clash/            # Clash 规则列表（由 convert_rules.rkt 自动生成）
│   └── *.yml
├── scripts/          # 工具脚本
│   ├── convert_rules.rkt         # Surge .list → Clash .yml 转换
│   ├── clash-verge.js            # Clash Verge 全局扩展脚本（自动分组节点 + 规则）
│   └── subscription-convert.rkt  # 订阅转换脚本（从订阅链接生成 Surge / Clash 配置）
└── README.md
```

## 使用方法

### Surge (iOS / macOS)

在配置文件的 `[Rule]` 字段中引用 `surge/` 目录下的 `.list` 文件：

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/jrtxio/proxy-rules/main/surge/openai.list,Proxy
RULE-SET,https://raw.githubusercontent.com/jrtxio/proxy-rules/main/surge/google.list,Proxy
RULE-SET,https://raw.githubusercontent.com/jrtxio/proxy-rules/main/surge/blocked.list,Proxy
RULE-SET,https://raw.githubusercontent.com/jrtxio/proxy-rules/main/surge/unblock.list,DIRECT
```

### Clash Verge (Windows)

使用 `scripts/clash-verge.js` 作为**全局扩展脚本**，会自动：
1. 按地区分组订阅节点
2. 配置 rule-providers 指向本仓库
3. 设置分流规则

在 Clash Verge 中：**订阅** → **全局扩展脚本** → 粘贴 `clash-verge.js` 内容。

### 订阅转换

如果你需要从 Surge 订阅链接生成配置文件：

```bash
# 编辑 subscription-convert.rkt，填入你的订阅地址
racket scripts/subscription-convert.rkt
```

## 维护与更新

修改规则时，只需编辑 `surge/` 下的 `.list` 文件，然后运行：

```bash
racket scripts/convert_rules.rkt
```

这会自动更新 `clash/` 下的 `.yml` 文件。改动由 GitHub Actions 持续集成保证一致性。

提交后，Surge 和 Clash Verge 都会在下次规则更新时自动拉取最新规则。
