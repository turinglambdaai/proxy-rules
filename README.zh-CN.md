# Proxy Rules

代理规则列表，支持 **Surge**（iOS/macOS）和 **Clash Verge Rev**（Windows）。两个客户端共用 `surge/` 下的 `.list` 规则文件。

![Surge](https://img.shields.io/badge/Proxy_Rules-9F1D20?logo=protonvpn&logoColor=white) [![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

[English](README.md) · **中文**

## 规则分类

| 文件 | 说明 |
|------|------|
| `blocked.list` | 需要代理的域名（社交媒体、AI 服务等） |
| `unblock.list` | 直连的国内域名 |
| `openai.list` | OpenAI / ChatGPT 域名 |
| `claude.list` | Anthropic Claude 域名 |
| `google.list` | Google 服务 |
| `telegram.list` | Telegram 即时通讯（跟随 `Proxy`） |

## 快速开始

### 1. 克隆仓库

```bash
git clone https://github.com/turlamai/proxy-rules.git
cd proxy-rules
```

### 2. Surge (iOS / macOS)

在 `[Rule]` 中引用规则集：

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/turlamai/proxy-rules/master/surge/unblock.list,DIRECT
RULE-SET,https://raw.githubusercontent.com/turlamai/proxy-rules/master/surge/openai.list,OpenAI
RULE-SET,https://raw.githubusercontent.com/turlamai/proxy-rules/master/surge/claude.list,Claude
RULE-SET,https://raw.githubusercontent.com/turlamai/proxy-rules/master/surge/google.list,Google
RULE-SET,https://raw.githubusercontent.com/turlamai/proxy-rules/master/surge/telegram.list,Proxy
RULE-SET,https://raw.githubusercontent.com/turlamai/proxy-rules/master/surge/blocked.list,Proxy
GEOIP,CN,DIRECT
FINAL,Proxy
```

其中 `OpenAI` / `Claude` / `Google` / `Netflix` / `Telegram` 与 `scripts/sub.rkt` 生成的策略组同名；手动维护配置的话按自己策略组名调整。

### 3. Clash Verge Rev (Windows)

订阅照常手动添加，然后将 `scripts/clash-verge.js` 的内容粘贴到 **订阅 > 全局扩展脚本** 中。脚本会自动按地区分组代理节点，并配置 rule-providers 指向本仓库的 `surge/*.list` 文件——除此之外无需任何配置。（可选的双机场自动切换见[多订阅备份切换](#多订阅备份切换)。）

### 订阅转换

通过 `scripts/sub.rkt`（Racket 语言）从一个或多个订阅链接生成完整的 Surge 配置：

1. 复制 `scripts/.env.example` 为 `scripts/.env`，填入订阅地址。**出现顺序 = 优先级**：排前面的 provider 主用，其余按序做自动备用：
   ```
   SUB_SSRDOG_URL=https://ssrdog-订阅地址
   SUB_MITCE_URL=https://mitce-订阅地址
   ```
   旧的单订阅写法 `SURGE_SUB_URL=<url>` 仍然兼容。

2. 在 `scripts/` 下创建 `surge-template.conf` 模板文件，包含 Surge 的静态配置段（General、Rule、Host、Rewrite、MITM 等），用 `{{PROXY_SECTION}}` 占位标记代理节点插入位置。

3. 运行转换脚本：
   ```bash
   racket scripts/sub.rkt
   ```

   输出完整 Surge 配置到 `surge/surge.conf`。单个订阅下载/解析失败只告警跳过，全部失败才中止。

**临时订阅链接**：部分面板不提供长期订阅，只给手动激活后短时效的分享链接（如 mitce 激活后 60 秒、ssrdog 5 分钟）。生成器对此的处理：`scripts/.env` 里的 URL 保持不变——先跑 `racket scripts/sub.rkt`，再去各面板点激活，脚本每 6 秒自动重试约 90 秒，抓取会自动落在激活窗口内，不用复制粘贴链接。

### 多订阅备份切换（可选）

**默认接线用不到本节**——单个手动订阅 + 脚本即可覆盖上面的全部内容。本节只用于在一个 Clash 配置内实现跨机场自动切换；不配置的话，直接手动切换订阅 profile 即可。

通过全局扩展配置（Merge）把订阅定义为 `proxy-providers` 后，`clash-verge.js`（Clash Verge）会生成与 Surge 同构的策略组：

| 策略组 | 类型 | 成员 |
|--------|------|------|
| `Proxy` | select | `Auto`、各 provider 组、各地区、`DIRECT` |
| `Auto` | fallback | 各地区——第一个健康地区优先 |
| `SSRDOG` / `MITCE` | url-test | 该订阅全部节点 |
| `OpenAI` / `Claude` | select | 默认 🇺🇸 United States（不对香港开放的服务），其后 `Proxy`、各地区、`DIRECT` |
| `Google` | select | `Proxy`、各地区、`DIRECT` |
| 各地区组（🇭🇰/🇺🇸/…） | fallback | 节点按 provider 优先级排序 |

地区组是 `fallback`：主用 provider 的节点全部排在备用 provider 节点之前，只有主用节点全部健康检查失败才切到备用，恢复后自动切回。ssrdog 美国节点全挂时，mitce 的美国节点自动顶上，无需手动重接。

**Clash Verge Rev 多订阅**：Verge 一次只合并一个订阅 profile，所以把两个订阅写进全局扩展配置（Merge）的 `proxy-providers`（键名建议用小写 `ssrdog` 和 `mitce`，策略组显示为全大写 `SSRDOG`/`MITCE`；链接只存在本机 Merge 文件里，不入仓库）：

```yaml
proxy-providers:
  ssrdog:
    url: "https://ssrdog-订阅地址"
    path: ./providers/ssrdog.yaml
    interval: 86400
    override:
      additional-prefix: "[SSRDOG] "
    health-check: { enable: true, url: "http://cp.cloudflare.com/generate_204", interval: 300 }
  mitce:
    url: "https://mitce-订阅地址"
    path: ./providers/mitce.yaml
    interval: 86400
    override:
      additional-prefix: "[MITCE] "
    health-check: { enable: true, url: "http://cp.cloudflare.com/generate_204", interval: 300 }
```

全局扩展脚本随后通过 `use` + `filter` 跨 provider 构建地区组，与 Surge 侧组结构一致。

## 项目结构

```
proxy-rules/
├── surge/               # 规则文件（手动维护）
│   ├── blocked.list     # 需代理的域名
│   ├── unblock.list     # 直连的国内域名
│   ├── openai.list      # OpenAI / ChatGPT
│   ├── claude.list      # Anthropic Claude
│   ├── google.list      # Google 服务
│   └── telegram.list    # Telegram
└── scripts/
    ├── clash-verge.js         # Clash Verge Rev 全局扩展脚本
    ├── sub.rkt                # 订阅链接转 Surge 配置（Racket）
    ├── .env.example           # 订阅地址模板（多订阅）
    ├── test-sub.rkt           # sub.rkt 单元测试
    └── test-clash-verge.mjs   # clash-verge.js 单元测试
```

## 维护

直接编辑 `surge/` 下的 `.list` 文件，提交后 Surge 和 Clash Verge 会在下次规则更新时自动拉取。

改动 `scripts/` 下的脚本后跑一遍测试（地区识别 pattern 由 `sub.rkt` 与 `clash-verge.js` 共用，必须两侧同步）：

```bash
racket scripts/test-sub.rkt
node scripts/test-clash-verge.mjs
```

## 环境要求

- **Surge** 或 **Clash Verge Rev** 作为代理客户端
- **Racket**（`sub.rkt` 订阅转换）、**Node.js**（跑测试）

## 许可证

基于 [MIT 许可证](LICENSE) 授权。
