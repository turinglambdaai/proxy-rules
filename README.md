# Proxy Rules

代理规则列表，支持 **Surge** (iOS/macOS) 和 **Clash Verge** (Windows)。

Surge 和 Clash Verge 共用 `surge/` 下的 `.list` 规则文件。

## 目录结构

```
proxy-rules/
├── surge/               # 规则文件（手动维护）
│   ├── blocked.list     # 需代理的域名
│   ├── unblock.list     # 直连的国内域名
│   ├── openai.list
│   ├── claude.list
│   ├── google.list
│   ├── netflix.list
│   └── telegram.list
├── scripts/
│   ├── clash-verge.js   # Clash Verge 全局扩展脚本
│   └── sub.rkt          # 从订阅链接生成完整 Surge 配置
└── README.md
```

## 使用方法

### Surge (iOS / macOS)

在 `[Rule]` 中引用：

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/jrtxio/proxy-rules/main/surge/openai.list,Proxy
RULE-SET,https://raw.githubusercontent.com/jrtxio/proxy-rules/main/surge/google.list,Proxy
RULE-SET,https://raw.githubusercontent.com/jrtxio/proxy-rules/main/surge/blocked.list,Proxy
RULE-SET,https://raw.githubusercontent.com/jrtxio/proxy-rules/main/surge/unblock.list,DIRECT
```

代理节点配置通过 `sub.rkt` 从订阅链接生成。

### Clash Verge (Windows)

在 **订阅 → 全局扩展脚本** 中粘贴 `scripts/clash-verge.js`，会自动按地区分组节点并配置 rule-providers 指向本仓库的 `surge/*.list`。

### 订阅转换

在 `scripts/` 下创建 `.env` 文件填入订阅地址（已 gitignore）：

```
SURGE_SUB_URL=https://your-subscription-url
```

在 `scripts/` 下创建 `surge-template.conf` 模板文件（已 gitignore），包含 Surge 的静态配置段（General、Rule、Host、Rewrite、MITM 等），用 `{{PROXY_SECTION}}` 占位标记代理节点插入位置。

然后运行：

```bash
racket scripts/sub.rkt
```

输出完整 Surge 配置到 `/tmp/surge.conf`，可直接用于 Surge。

## 维护

直接编辑 `surge/` 下的 `.list` 文件，提交后 Surge 和 Clash Verge 会在下次规则更新时自动拉取。
