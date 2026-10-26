// Clash Verge Rev 全局扩展脚本
// 多订阅（proxy-providers，配置方法见 README）与静态节点统一按地区分组，
// 与 scripts/sub.rkt 生成的 Surge 配置同构：
//   - 地区组 = fallback：主用 provider 的节点排前、备用排后，失联自动切换、恢复自动切回
//   - provider 组（url-test）：整体切换某个订阅
//   - Auto = fallback(地区)；Proxy / 功能组 = select
//
// REGIONS 的 pattern 与 sub.rkt 的 raw-region-map 共用（无 flag 正则源串），改动须两侧同步：
// JS 端用 i flag 编译；交给 mihomo 的 filter 时加 "(?i)" 前缀（Go 正则不支持 flag 参数）。
// 两字母代码带左右边界，防止 AUS→US、TR→Turkey 之类误判。

const REGIONS = [
  { name: "🇭🇰 Hong Kong",     pattern: "(?:^|[^A-Za-z])(?:HK|HKG)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|Hong Kong|香港|🇭🇰" },
  { name: "🇨🇳 Taiwan",        pattern: "(?:^|[^A-Za-z])(?:TW|TWN)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|Taiwan|台北|新北|台中|台湾|台灣|臺灣|🇹🇼" },
  { name: "🇸🇬 Singapore",     pattern: "(?:^|[^A-Za-z])(?:SG|SGP)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|Singapore|新加坡|狮城|獅城|🇸🇬" },
  { name: "🇯🇵 Japan",         pattern: "(?:^|[^A-Za-z])(?:JP|JPN)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|Japan|Tokyo|Osaka|东京|大阪|日本|🇯🇵" },
  { name: "🇺🇸 United States", pattern: "(?:^|[^A-Za-z])(?:US|USA)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|United States|Los Angeles|San Jose|Seattle|New York|Chicago|美国|美國|美西|美东|北美|洛杉矶|圣何塞|西雅图|纽约|芝加哥|🇺🇸" },
  { name: "🇰🇷 Korea",         pattern: "(?:^|[^A-Za-z])(?:KR|KOR)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|Korea|Seoul|首尔|韩国|韓國|🇰🇷" },
  { name: "🇨🇦 Canada",        pattern: "(?:^|[^A-Za-z])(?:CA|CAN)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|Canada|Toronto|Vancouver|加拿大|多伦多|温哥华|🇨🇦" },
  { name: "🇬🇧 Great Britain", pattern: "(?:^|[^A-Za-z])(?:GB|UK|GBR)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|United Kingdom|Great Britain|London|英国|英國|伦敦|🇬🇧" },
  { name: "🇹🇷 Turkey",        pattern: "(?:^|[^A-Za-z])(?:TR|TUR)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|Turkey|Istanbul|土耳其|伊斯坦布尔|🇹🇷" },
  { name: "🇮🇳 India",         pattern: "(?:^|[^A-Za-z])(?:IN|IND)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|India|Mumbai|印度|孟买|🇮🇳" },
  { name: "🇳🇱 Netherlands",   pattern: "(?:^|[^A-Za-z])(?:NL|NLD)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|Netherlands|Amsterdam|荷兰|荷蘭|阿姆斯特丹|🇳🇱" },
  { name: "🇫🇷 France",        pattern: "(?:^|[^A-Za-z])(?:FR|FRA)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|France|Paris|法国|法國|巴黎|🇫🇷" },
  { name: "🇩🇪 Germany",       pattern: "(?:^|[^A-Za-z])(?:DE|DEU)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|Germany|Frankfurt|德国|德國|法兰克福|🇩🇪" },
  { name: "🇻🇳 Vietnam",       pattern: "(?:^|[^A-Za-z])(?:VN|VNM)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|Vietnam|越南|河内|🇻🇳" },
  { name: "🇲🇾 Malaysia",      pattern: "(?:^|[^A-Za-z])(?:MY|MYS)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|Malaysia|吉隆坡|马来西亚|馬來西亞|🇲🇾" },
  { name: "🇹🇭 Thailand",      pattern: "(?:^|[^A-Za-z])(?:TH|THA)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|Thailand|曼谷|泰国|泰國|🇹🇭" },
  { name: "🇵🇭 Philippines",   pattern: "(?:^|[^A-Za-z])(?:PH|PHL)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|Philippines|马尼拉|菲律宾|菲律賓|🇵🇭" },
  { name: "🇦🇺 Australia",     pattern: "(?:^|[^A-Za-z])(?:AU|AUS)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|Australia|Sydney|Melbourne|澳大利亚|澳洲|澳大利亞|悉尼|墨尔本|🇦🇺" },
  { name: "🇧🇷 Brazil",        pattern: "(?:^|[^A-Za-z])(?:BR|BRA)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|Brazil|巴西|圣保罗|🇧🇷" },
  { name: "🇦🇷 Argentina",     pattern: "(?:^|[^A-Za-z])(?:AR|ARG)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|Argentina|阿根廷|🇦🇷" },
];

const TEST_URL = "http://cp.cloudflare.com/generate_204";
const INTERVAL = 300;

// proxy-providers 键名 → 策略组显示名；未列出的键原样显示
// （provider 在 Merge 里的书写顺序 = 优先级，与 Surge 侧 .env 顺序对应）
const PROVIDER_DISPLAY = { ssrdog: "SSRDog", mitce: "Mitce" };

function providerDisplayName(key) {
  return PROVIDER_DISPLAY[String(key).toLowerCase()] || String(key);
}

// ── 从静态节点中筛选匹配某正则的节点名 ──
function getProxies(config, regex) {
  var names = [];
  if (Array.isArray(config.proxies)) {
    config.proxies.forEach(function (p) {
      if (regex.test(p.name)) names.push(p.name);
    });
  }
  return names;
}

// ── 地区组：fallback 保活；静态节点直接列名，provider 节点走 use + filter ──
function regionGroup(r, staticNames, providers) {
  var g = { name: r.name, type: "fallback", url: TEST_URL, interval: INTERVAL };
  if (staticNames.length > 0) g.proxies = staticNames;
  if (providers.length > 0) {
    g.use = providers.slice();
    g.filter = "(?i)" + r.pattern;
  }
  return g;
}

function main(config, name) {
  var providers = Object.keys(config["proxy-providers"] || {});
  var providerNames = providers.map(providerDisplayName);

  // 1. 地区组 + Auto（按地区优先级保活）
  var regionGroups = [];
  var regionNames = [];
  REGIONS.forEach(function (r) {
    var staticNames = getProxies(config, new RegExp(r.pattern, "i"));
    if (staticNames.length === 0 && providers.length === 0) return;
    regionGroups.push(regionGroup(r, staticNames, providers));
    regionNames.push(r.name);
  });

  var groups = [];

  if (regionNames.length > 0) {
    groups.push({ name: "Auto", type: "fallback", proxies: regionNames.slice(), url: TEST_URL, interval: INTERVAL });
  }

  // 2. provider 组（url-test 该订阅全部节点，便于整体切换/兜底某订阅）
  providers.forEach(function (p, i) {
    groups.push({
      name: providerNames[i],
      type: "url-test",
      use: [p],
      url: TEST_URL,
      interval: INTERVAL,
      tolerance: 50,
    });
  });

  // 3. Proxy：默认 Auto，provider 组次之，DIRECT 收尾；功能组默认跟随 Proxy
  groups.push({
    name: "Proxy",
    type: "select",
    proxies: ["Auto"].concat(providerNames).concat(regionNames).concat(["DIRECT"]),
  });
  ["OpenAI", "Claude", "Google", "Netflix", "Telegram"].forEach(function (svc) {
    groups.push({
      name: svc,
      type: "select",
      proxies: ["Proxy"].concat(regionNames).concat(["DIRECT"]),
    });
  });

  // 4. 地区组
  regionGroups.forEach(function (g) {
    groups.push(g);
  });

  // 5. 覆盖 proxy-groups
  config["proxy-groups"] = groups;

  // 6. 设置 rule-providers
  config["rule-providers"] = {
    Direct: {
      type: "http",
      behavior: "classical",
      format: "text",
      url: "https://raw.githubusercontent.com/turinglambdaai/proxy-rules/master/surge/unblock.list",
      interval: 86400,
      path: "./ruleset/unblock.yml",
    },
    OpenAI: {
      type: "http",
      behavior: "classical",
      format: "text",
      url: "https://raw.githubusercontent.com/turinglambdaai/proxy-rules/master/surge/openai.list",
      interval: 86400,
      path: "./ruleset/openai.yml",
    },
    Claude: {
      type: "http",
      behavior: "classical",
      format: "text",
      url: "https://raw.githubusercontent.com/turinglambdaai/proxy-rules/master/surge/claude.list",
      interval: 86400,
      path: "./ruleset/claude.yml",
    },
    Google: {
      type: "http",
      behavior: "classical",
      format: "text",
      url: "https://raw.githubusercontent.com/turinglambdaai/proxy-rules/master/surge/google.list",
      interval: 86400,
      path: "./ruleset/google.yml",
    },
    Netflix: {
      type: "http",
      behavior: "classical",
      format: "text",
      url: "https://raw.githubusercontent.com/turinglambdaai/proxy-rules/master/surge/netflix.list",
      interval: 86400,
      path: "./ruleset/netflix.yml",
    },
    Telegram: {
      type: "http",
      behavior: "classical",
      format: "text",
      url: "https://raw.githubusercontent.com/turinglambdaai/proxy-rules/master/surge/telegram.list",
      interval: 86400,
      path: "./ruleset/telegram.yml",
    },
    Proxy: {
      type: "http",
      behavior: "classical",
      format: "text",
      url: "https://raw.githubusercontent.com/turinglambdaai/proxy-rules/master/surge/blocked.list",
      interval: 86400,
      path: "./ruleset/blocked.yml",
    },
  };

  // 7. 设置 rules
  config.rules = [
    "RULE-SET,Direct,DIRECT",
    "RULE-SET,OpenAI,OpenAI",
    "RULE-SET,Claude,Claude",
    "RULE-SET,Google,Google",
    "RULE-SET,Netflix,Netflix",
    "RULE-SET,Telegram,Telegram",
    "RULE-SET,Proxy,Proxy",
    "GEOIP,CN,DIRECT",
    "MATCH,Proxy",
  ];

  return config;
}
