// clash-verge.js 单元测试：node scripts/test-clash-verge.mjs
import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const src = readFileSync(new URL("./clash-verge.js", import.meta.url), "utf8");
const mainRaw = vm.runInNewContext(src + "\n;({ main: main })", {}, { filename: "clash-verge.js" }).main;
// JSON 往返归一化：vm realm 的数组原型与宿主不同，deepStrictEqual 会误判
const main = (config, name) => JSON.parse(JSON.stringify(mainRaw(config, name)));

function byName(groups, n) {
  const g = groups.find((x) => x.name === n);
  assert.ok(g, `missing group: ${n}`);
  return g;
}

// ── A. 静态节点（单订阅回归） ──
const cfgA = main(
  {
    proxies: [
      { name: "🇭🇰 HK-01" },
      { name: "香港 02" },
      { name: "🇺🇸 US-01" },
      { name: "美国 IEPL-02" },
      { name: "🇯🇵 JP-01" },
      { name: "AUS-01" }, // 边界回归：必须进 Australia，不得误判为 US
      { name: "🇳🇬 NG-01" },
    ],
  },
  "test",
);

const groupsA = cfgA["proxy-groups"];
const usA = byName(groupsA, "🇺🇸 United States");
assert.equal(usA.type, "fallback");
assert.deepEqual(usA.proxies, ["🇺🇸 US-01", "美国 IEPL-02"]);
assert.equal(usA.use, undefined, "static-only group must not use providers");
assert.equal(usA.filter, undefined, "static-only group must not carry filter");

const auA = byName(groupsA, "🇦🇺 Australia");
assert.deepEqual(auA.proxies, ["AUS-01"]);

const ngA = byName(groupsA, "🇳🇬 Nigeria");
assert.deepEqual(ngA.proxies, ["🇳🇬 NG-01"]);

const autoA = byName(groupsA, "Auto");
assert.equal(autoA.type, "fallback");
assert.deepEqual(autoA.proxies, ["🇭🇰 Hong Kong", "🇯🇵 Japan", "🇺🇸 United States", "🇦🇺 Australia", "🇳🇬 Nigeria"]);

const proxyA = byName(groupsA, "Proxy");
assert.deepEqual(proxyA.proxies, ["Auto", "🇭🇰 Hong Kong", "🇯🇵 Japan", "🇺🇸 United States", "🇦🇺 Australia", "🇳🇬 Nigeria", "DIRECT"]);

const openaiA = byName(groupsA, "OpenAI");
assert.deepEqual(openaiA.proxies, ["🇺🇸 United States", "Proxy", "🇭🇰 Hong Kong", "🇯🇵 Japan", "🇦🇺 Australia", "🇳🇬 Nigeria", "DIRECT"]);

assert.equal(groupsA.find((g) => g.name === "SSRDOG"), undefined, "no provider groups in static-only mode");
assert.deepEqual(cfgA.rules[cfgA.rules.length - 1], "MATCH,Proxy");

// ── B. 仅 proxy-providers（双订阅） ──
const cfgB = main({ "proxy-providers": { ssrdog: {}, mitce: {} } }, "test");
const groupsB = cfgB["proxy-groups"];

const usB = byName(groupsB, "🇺🇸 United States");
assert.equal(usB.type, "fallback");
assert.deepEqual(usB.use, ["ssrdog", "mitce"], "provider order = priority");
assert.equal(usB.filter, "(?i)(?:^|[^A-Za-z])(?:US|USA)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|United States|Los Angeles|San Jose|Seattle|New York|Chicago|美国|美國|美西|美东|北美|洛杉矶|圣何塞|西雅图|纽约|芝加哥|🇺🇸");
assert.equal(usB.proxies, undefined);

const ssrB = byName(groupsB, "SSRDOG");
assert.equal(ssrB.type, "url-test");
assert.deepEqual(ssrB.use, ["ssrdog"]);
assert.equal(ssrB.interval, 300);

byName(groupsB, "MITCE");

const proxyB = byName(groupsB, "Proxy");
// providers-only 模式下脚本无法预知 provider 实际地区，为全部地区建组（filter 过滤，空组无害）
const allRegions = [
  "🇭🇰 Hong Kong", "🇨🇳 Taiwan", "🇸🇬 Singapore", "🇯🇵 Japan", "🇺🇸 United States",
  "🇰🇷 Korea", "🇨🇦 Canada", "🇬🇧 Great Britain", "🇹🇷 Turkey", "🇮🇳 India",
  "🇳🇱 Netherlands", "🇫🇷 France", "🇩🇪 Germany", "🇻🇳 Vietnam", "🇲🇾 Malaysia",
  "🇹🇭 Thailand", "🇵🇭 Philippines", "🇦🇺 Australia", "🇧🇷 Brazil", "🇦🇷 Argentina",
  "🇳🇬 Nigeria",
];
assert.deepEqual(proxyB.proxies, ["Auto", "SSRDOG", "MITCE", ...allRegions, "DIRECT"]);
assert.equal(proxyB.proxies.includes("🇦🇺 Australia"), true);
const autoB = byName(groupsB, "Auto");
assert.deepEqual(autoB.proxies, allRegions);

// ── C. 混合：静态节点 + providers ──
const cfgC = main(
  {
    proxies: [{ name: "🇺🇸 US-Static" }, { name: "剩余流量：100GB" }],
    "proxy-providers": { mitce: {} },
  },
  "test",
);
const groupsC = cfgC["proxy-groups"];
const usC = byName(groupsC, "🇺🇸 United States");
assert.deepEqual(usC.proxies, ["🇺🇸 US-Static"]);
assert.deepEqual(usC.use, ["mitce"]);
const mitceC = byName(groupsC, "MITCE");
assert.deepEqual(mitceC.use, ["mitce"]);

// ── D. 未知 provider 键名原样显示 ──
const cfgD = main({ "proxy-providers": { custom1: {} } }, "test");
byName(cfgD["proxy-groups"], "CUSTOM1");

// ── E. 交由 mihomo 的 filter 语法合法（括号平衡，可被 new RegExp 解析） ──
for (const g of groupsB) {
  if (g.filter) new RegExp(g.filter.slice("(?i)".length), "i"); // JS 端同源校验
  assert.ok(!("proxies" in g) || g.proxies.length > 0, "no empty proxies arrays");
}

console.log("clash-verge.js tests passed");
