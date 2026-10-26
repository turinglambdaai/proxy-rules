#lang racket

;; sub.rkt 单元测试：racket scripts/test-sub.rkt（或 raco test scripts/test-sub.rkt）
(require rackunit "sub.rkt")

;; ============ 地区识别 ============

(check-equal? (get-region "🇺🇸 US-01") "🇺🇸 United States")
(check-equal? (get-region "美国 IEPL-02") "🇺🇸 United States")
(check-equal? (get-region "美国->日本 中转") "🇯🇵 Japan")          ;; 双地区名，取 region-map 先命中的
(check-equal? (get-region "Los Angeles 01") "🇺🇸 United States")
(check-equal? (get-region "香港 01") "🇭🇰 Hong Kong")
(check-equal? (get-region "狮城 02") "🇸🇬 Singapore")
(check-equal? (get-region "🇬🇧 London 01") "🇬🇧 Great Britain")
(check-equal? (get-region "🇯🇵 JP-01") "🇯🇵 Japan")
(check-equal? (get-region "AUS-01") "🇦🇺 Australia")              ;; 边界回归：不得误判为 US
(check-equal? (get-region "TR-Edge-01") "🇹🇷 Turkey")
(check-false (get-region "IPLC专线"))

;; ============ 信息节点过滤 ============

(check-false (parse-proxy-line "剩余流量：100 GB | 50 = ss, 1.2.3.9, 8388"))
(check-false (parse-proxy-line "Expire: 2026-12-31 = ss, 1.2.3.9, 8388"))
(check-false (parse-proxy-line "Traffic Reset = ss, 1.2.3.9, 8388"))
(check-false (parse-proxy-line "套餐到期 = ss, 1.2.3.9, 8388"))
(check-not-false (parse-proxy-line "🇺🇸 US-01 = ss, 1.2.3.4, 8388, encrypt-method=aes-256-gcm, password=abc"))

;; ============ 订阅解析 ============

(define sub-ssrdog
  #<<EOF
[Proxy]
🇺🇸 US-01 = ss, 1.2.3.4, 8388, encrypt-method=aes-256-gcm, password=abc
🇺🇸 US-02 = ss, 1.2.3.5, 8388, encrypt-method=aes-256-gcm, password=abc
🇭🇰 HK-01 = ss, 1.2.3.6, 8388, encrypt-method=aes-256-gcm, password=abc
剩余流量：100 GB = ss, 1.2.3.9, 8388

[Proxy Group]
Proxy = select, DIRECT
EOF
  )

(define sub-mitce
  #<<EOF
[Proxy]
🇺🇸 US-01 = ss, 5.6.7.8, 8388, encrypt-method=chacha20-ietf-poly1305, password=xyz
美国 02 = ss, 5.6.7.9, 8388, encrypt-method=chacha20-ietf-poly1305, password=xyz
🇯🇵 JP-01 = vmess, 5.6.7.10, 443, username=u1, tls=true
Expire: 2026-12-31 = ss, 5.6.7.11, 8388
EOF
  )

(define p1 (parse-subscription sub-ssrdog))
(define p2 (parse-subscription sub-mitce))
(check-equal? (length p1) 3)  ;; 信息行被过滤
(check-equal? (length p2) 3)
(check-equal? (proxy-name (first p2)) "🇺🇸 US-01")
(check-equal? (proxy-name (second p2)) "美国 02")

;; ============ 合并与生成 ============

(define merged (merge-proxies (list (cons "SSRDog" p1) (cons "Mitce" p2))))
(check-equal? (length merged) 6)
;; 首个订阅的名称保持原样，第二个订阅的重名节点改名
(check-equal? (map proxy-name merged)
              '("🇺🇸 US-01" "🇺🇸 US-02" "🇭🇰 HK-01"
                "🇺🇸 US-01 | Mitce" "美国 02" "🇯🇵 JP-01"))
(check-equal? (proxy-provider (fourth merged)) "Mitce")

(define conf (generate-surge-config merged))
(define conf-lines (string-split conf "\n"))

(define (expect-line line)
  (check-not-false (member line conf-lines) (format "missing line: ~a" line)))

;; 节点：主订阅在前、名称保持原样；备用订阅重名节点已改名
(expect-line "🇺🇸 US-01 = ss, 1.2.3.4, 8388, encrypt-method=aes-256-gcm, password=abc")
(expect-line "🇺🇸 US-01 | Mitce = ss, 5.6.7.8, 8388, encrypt-method=chacha20-ietf-poly1305, password=xyz")

;; 地区顺序 = 节点首次出现顺序
(expect-line "Proxy = select, Auto, SSRDog, Mitce, 🇺🇸 United States, 🇭🇰 Hong Kong, 🇯🇵 Japan, DIRECT")
(expect-line "Auto = fallback, 🇺🇸 United States, 🇭🇰 Hong Kong, 🇯🇵 Japan, url=http://cp.cloudflare.com/generate_204, interval=300")

;; provider 组 = 该订阅全部节点（url-test）
(expect-line "SSRDog = url-test, 🇺🇸 US-01, 🇺🇸 US-02, 🇭🇰 HK-01, url=http://cp.cloudflare.com/generate_204, interval=300")
(expect-line "Mitce = url-test, 🇺🇸 US-01 | Mitce, 美国 02, 🇯🇵 JP-01, url=http://cp.cloudflare.com/generate_204, interval=300")

;; 功能组默认跟随 Proxy，可手动钉地区，DIRECT 收尾
(expect-line "OpenAI = select, Proxy, 🇺🇸 United States, 🇭🇰 Hong Kong, 🇯🇵 Japan, DIRECT")
(expect-line "Claude = select, Proxy, 🇺🇸 United States, 🇭🇰 Hong Kong, 🇯🇵 Japan, DIRECT")

;; 地区组 = fallback：主订阅节点在前，备用订阅在后（核心备份语义）
(expect-line "🇺🇸 United States = fallback, 🇺🇸 US-01, 🇺🇸 US-02, 🇺🇸 US-01 | Mitce, 美国 02, url=http://cp.cloudflare.com/generate_204, interval=300")
(expect-line "🇭🇰 Hong Kong = fallback, 🇭🇰 HK-01, url=http://cp.cloudflare.com/generate_204, interval=300")
(expect-line "🇯🇵 Japan = fallback, 🇯🇵 JP-01, url=http://cp.cloudflare.com/generate_204, interval=300")

;; 备用订阅先于主订阅时，地区组节点顺序随之反转（.env 顺序即优先级）
(define merged2 (merge-proxies (list (cons "Mitce" p2) (cons "SSRDog" p1))))
(define conf2 (generate-surge-config merged2))
(check-true (string-contains? conf2
              "🇺🇸 United States = fallback, 🇺🇸 US-01, 美国 02, 🇺🇸 US-01 | SSRDog, 🇺🇸 US-02, url=http://cp.cloudflare.com/generate_204, interval=300"))
(check-true (string-contains? conf2 "Proxy = select, Auto, Mitce, SSRDog,"))

;; ============ 边界情况 ============

;; 无地区节点 → 报错而非生成坏配置
(check-exn (λ (e) (string-contains? (exn-message e) "没有识别出任何地区"))
           (λ () (generate-surge-config
                  (merge-proxies
                   (list (cons "SSRDog" (list (proxy "未知节点" "ss, 1.2.3.4, 8388" #f "SSRDog"))))))))

;; 同订阅内重名：第 2 份改名 "原名 | provider"，第 3 份起带出现序号
(define dup (merge-proxies
             (list (cons "SSRDog"
                         (list (proxy "US-01" "ss, 1.1.1.1, 8388" "🇺🇸 United States" #f)
                               (proxy "US-01" "ss, 2.2.2.2, 8388" "🇺🇸 United States" #f)
                               (proxy "US-01" "ss, 3.3.3.3, 8388" "🇺🇸 United States" #f))))))
(check-equal? (map proxy-name dup)
              '("US-01" "US-01 | SSRDog" "US-01 | SSRDog #3"))

;; ============ 重试（等待激活窗口） ============

(define attempts (box 0))
(check-equal?
 (retry-with-backoff "测试" 3 0
                     (λ ()
                       (set-box! attempts (add1 (unbox attempts)))
                       (if (< (unbox attempts) 3)
                           (error "模拟失败")
                           'ok)))
 'ok)  ;; 第 3 次成功
(check-equal? (unbox attempts) 3)
(check-false (retry-with-backoff "测试" 2 0 (λ () (error "始终失败"))))  ;; 耗尽后返回 #f

;; ============ 命令行链接覆盖（写回 .env） ============

(check-equal?
 (env-lines-with-key '("# 注释行" "SUB_SSRDOG_URL=https://old" "SUB_MITCE_URL=https://m")
                     "SUB_SSRDOG_URL" "https://new")
 '("# 注释行" "SUB_SSRDOG_URL=https://new" "SUB_MITCE_URL=https://m"))
(check-equal?
 (env-lines-with-key '("SUB_MITCE_URL=https://m") "SUB_SSRDOG_URL" "https://new")
 '("SUB_MITCE_URL=https://m" "SUB_SSRDOG_URL=https://new"))

(printf "sub.rkt tests passed\n")
