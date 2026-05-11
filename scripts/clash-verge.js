// Clash Verge Rev 全局扩展脚本
// 自动从订阅节点中按地区分组，无需硬编码节点名

// ── 地区匹配规则（正则） ──
const REGIONS = [
  { name: "🇭🇰 Hong Kong",    regex: /香港|HK|Hong Kong/i },
  { name: "🇨🇳 Taiwan",      regex: /台湾|TW|Taiwan/i },
  { name: "🇯🇵 Japan",       regex: /日本|JP|Japan/i },
  { name: "🇰🇷 Korea",       regex: /韩国|KR|Korea|South Korea/i },
  { name: "🇸🇬 Singapore",   regex: /新加坡|SG|Singapore/i },
  { name: "🇺🇸 United States", regex: /美国|US|United States/i },
  { name: "🇨🇦 Canada",      regex: /加拿大|CA|Canada/i },
  { name: "🇬🇧 Great Britain", regex: /英国|GB|United Kingdom|Great Britain/i },
  { name: "🇹🇷 Turkey",      regex: /土耳其|TR|Turkey/i },
  { name: "🇳🇱 Netherlands",  regex: /荷兰|NL|Netherlands/i },
  { name: "🇫🇷 France",      regex: /法国|FR|France/i },
  { name: "🇩🇪 Germany",     regex: /德国|DE|Germany/i },
  { name: "🇻🇳 Vietnam",     regex: /越南|VN|Vietnam/i },
  { name: "🇲🇾 Malaysia",    regex: /马来西亚|MY|Malaysia/i },
  { name: "🇹🇭 Thailand",    regex: /泰国|TH|Thailand/i },
  { name: "🇵🇭 Philippines",  regex: /菲律宾|PH|Philippines/i },
  { name: "🇦🇺 Australia",   regex: /澳大利亚|AU|Australia/i },
  { name: "🇮🇳 India",       regex: /印度|IN|India/i },
  { name: "🇧🇷 Brazil",      regex: /巴西|BR|Brazil/i },
  { name: "🇦🇷 Argentina",   regex: /阿根廷|AR|Argentina/i },
];

const TEST_URL = "http://cp.cloudflare.com/generate_204";
const INTERVAL = 300;

// ── 从所有代理中筛选匹配某正则的节点名 ──
function getProxies(config, regex) {
  var names = [];
  if (Array.isArray(config.proxies)) {
    config.proxies.forEach(function (p) {
      if (regex.test(p.name)) names.push(p.name);
    });
  }
  return names;
}

// ── 构建一个 select 代理组 ──
function selectGroup(name, proxies, extra) {
  var group = {
    name: name,
    type: "select",
    proxies: proxies.slice(),
  };
  if (extra) group.proxies = extra.concat(group.proxies);
  return group;
}

// ── 构建一个 fallback 代理组 ──
function fallbackGroup(name, proxies) {
  return {
    name: name,
    type: "fallback",
    proxies: proxies.slice(),
    url: TEST_URL,
    interval: INTERVAL,
  };
}

// ── 构建一个 url-test 代理组 ──
function urlTestGroup(name, proxies) {
  return {
    name: name,
    type: "url-test",
    proxies: proxies.slice(),
    url: TEST_URL,
    interval: INTERVAL,
    tolerance: 50,
  };
}

function main(config, name) {
  // 1. 收集所有地区的节点
  var regionGroups = [];
  var regionNames = [];

  REGIONS.forEach(function (r) {
    var proxies = getProxies(config, r.regex);
    if (proxies.length > 0) {
      regionGroups.push(selectGroup(r.name, proxies));
      regionNames.push(r.name);
    }
  });

  // 2. 构建功能代理组
  var groups = [];

  // Auto: fallback 自动选择（所有地区节点）
  if (regionNames.length > 0) {
    groups.push(fallbackGroup("Auto", regionNames));
  }

  // Proxy: 手动选择 + Auto
  groups.push(selectGroup("Proxy", regionNames, ["Auto"]));

  // 功能分组: OpenAI / Claude / Google / Netflix / Telegram
  var serviceNames = ["OpenAI", "Claude", "Google", "Netflix", "Telegram"];
  serviceNames.forEach(function (svc) {
    groups.push(selectGroup(svc, regionNames, ["Proxy"]));
  });

  // 3. 添加地区分组
  regionGroups.forEach(function (g) {
    groups.push(g);
  });

  // 4. 覆盖 proxy-groups
  config["proxy-groups"] = groups;

  // 5. 设置 rule-providers
  config["rule-providers"] = {
    Direct: {
      type: "http",
      behavior: "classical",
      url: "https://raw.githubusercontent.com/jrtxio/proxy-rules/master/clash/unblock.yml",
      interval: 86400,
      path: "./ruleset/unblock.yml",
    },
    OpenAI: {
      type: "http",
      behavior: "classical",
      url: "https://raw.githubusercontent.com/jrtxio/proxy-rules/master/clash/openai.yml",
      interval: 86400,
      path: "./ruleset/openai.yml",
    },
    Claude: {
      type: "http",
      behavior: "classical",
      url: "https://raw.githubusercontent.com/jrtxio/proxy-rules/master/clash/claude.yml",
      interval: 86400,
      path: "./ruleset/claude.yml",
    },
    Google: {
      type: "http",
      behavior: "classical",
      url: "https://raw.githubusercontent.com/jrtxio/proxy-rules/master/clash/google.yml",
      interval: 86400,
      path: "./ruleset/google.yml",
    },
    Netflix: {
      type: "http",
      behavior: "classical",
      url: "https://raw.githubusercontent.com/jrtxio/proxy-rules/master/clash/netflix.yml",
      interval: 86400,
      path: "./ruleset/netflix.yml",
    },
    Telegram: {
      type: "http",
      behavior: "classical",
      url: "https://raw.githubusercontent.com/jrtxio/proxy-rules/master/clash/telegram.yml",
      interval: 86400,
      path: "./ruleset/telegram.yml",
    },
    Proxy: {
      type: "http",
      behavior: "classical",
      url: "https://raw.githubusercontent.com/jrtxio/proxy-rules/master/clash/blocked.yml",
      interval: 86400,
      path: "./ruleset/blocked.yml",
    },
  };

  // 6. 设置 rules
  config.rules = [
    "RULE-SET,Direct,DIRECT",
    "RULE-SET,OpenAI,OpenAI",
    "RULE-SET,Claude,Claude",
    "RULE-SET,Google,Google",
    "RULE-SET,Netflix,Netflix",
    "RULE-SET,Telegram,Telegram",
    "GEOIP,CN,DIRECT",
    "MATCH,Proxy",
  ];

  return config;
}
