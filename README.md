# Proxy Rules

[![Language](https://img.shields.io/badge/language-Racket-red)]

[English](README.md) | [中文](README.zh-CN.md)

Proxy rule lists for **Surge** (iOS/macOS) and **Clash Verge Rev** (Windows). Both clients share the same `.list` rule files under `surge/`.

## Rule Categories

| File | Description |
|------|-------------|
| `blocked.list` | Domains requiring proxy access (social media, AI services, etc.) |
| `unblock.list` | Domestic domains routed directly |
| `openai.list` | OpenAI / ChatGPT domains |
| `claude.list` | Anthropic Claude domains |
| `google.list` | Google services |
| `netflix.list` | Netflix streaming |
| `telegram.list` | Telegram messaging |

## Usage

### Surge (iOS / macOS)

Reference the rule sets in your `[Rule]` section:

```ini
[Rule]
RULE-SET,https://raw.githubusercontent.com/jrtxio/proxy-rules/main/surge/openai.list,Proxy
RULE-SET,https://raw.githubusercontent.com/jrtxio/proxy-rules/main/surge/google.list,Proxy
RULE-SET,https://raw.githubusercontent.com/jrtxio/proxy-rules/main/surge/blocked.list,Proxy
RULE-SET,https://raw.githubusercontent.com/jrtxio/proxy-rules/main/surge/unblock.list,DIRECT
```

### Clash Verge Rev (Windows)

Paste the contents of `scripts/clash-verge.js` into **Subscription > Global Extend Script**. It automatically groups proxy nodes by region and configures rule-providers pointing to this repository's `surge/*.list` files.

### Subscription Conversion

Generate a full Surge configuration from a subscription URL using `scripts/sub.rkt` (Racket):

1. Create `scripts/.env` with your subscription URL:
   ```
   SURGE_SUB_URL=https://your-subscription-url
   ```

2. Create `scripts/surge-template.conf` with your static Surge sections (General, Rule, Host, Rewrite, MITM, etc.), using `{{PROXY_SECTION}}` as a placeholder for proxy nodes.

3. Run the converter:
   ```bash
   racket scripts/sub.rkt
   ```

   This outputs a complete Surge config to `surge/surge.conf`.

## Directory Structure

```
proxy-rules/
  surge/               # Rule files (manually maintained)
    blocked.list       # Proxy-required domains
    unblock.list       # Direct-connect domestic domains
    openai.list        # OpenAI / ChatGPT
    claude.list        # Anthropic Claude
    google.list        # Google services
    netflix.list       # Netflix
    telegram.list      # Telegram
  scripts/
    clash-verge.js     # Clash Verge Rev global extend script
    sub.rkt            # Subscription-to-Surge config converter (Racket)
```

## Maintenance

Edit the `.list` files under `surge/` directly. After committing, Surge and Clash Verge will pull the updated rules on their next refresh cycle.

## Requirements

- **Surge** or **Clash Verge Rev** as the proxy client
- **Racket** (optional, only needed for subscription conversion with `sub.rkt`)
