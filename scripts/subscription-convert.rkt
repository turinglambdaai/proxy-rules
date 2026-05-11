#lang racket

;; 订阅转换脚本 — 从 Surge 订阅链接提取节点，生成 Surge / Clash 配置
(require net/http-client net/url)

;; ============ 配置参数 ============
(struct config (subscription-url surge-output clash-output) #:transparent)

(define app-config
  (config
   "在此处填入订阅地址"
   "surge_updated.conf"
   "clash_updated.yaml"))

;; 地区映射表
(define region-map
  '(("Hong Kong" . "🇭🇰 Hong Kong")
    ("Taiwan" . "🇨🇳 Taiwan")
    ("Singapore" . "🇸🇬 Singapore")
    ("Japan" . "🇯🇵 Japan")
    ("United States" . "🇺🇸 United States")
    ("Korea" . "🇰🇷 Korea")
    ("Canada" . "🇨🇦 Canada")
    ("Great Britain" . "🇬🇧 Great Britain")
    ("Turkey" . "🇹🇷 Turkey")
    ("India" . "🇮🇳 India")
    ("Netherlands" . "🇳🇱 Netherlands")
    ("France" . "🇫🇷 France")
    ("Germany" . "🇩🇪 Germany")
    ("Vietnam" . "🇻🇳 Vietnam")
    ("Malaysia" . "🇲🇾 Malaysia")
    ("Thailand" . "🇹🇭 Thailand")
    ("Philippines" . "🇵🇭 Philippines")))

;; 要生成的代理组类型
(define proxy-group-types
  '("Proxy" "Auto" "OpenAI" "Claude" "Google" "Netflix" "Telegram"))

;; Clash 规则提供者配置 — 指向 proxy-rules 仓库
(define clash-rule-providers
  '(("Direct"  "https://raw.githubusercontent.com/jrtxio/proxy-rules/master/clash/unblock.yml" "./ruleset/unblock.yml")
    ("OpenAI"  "https://raw.githubusercontent.com/jrtxio/proxy-rules/master/clash/openai.yml"   "./ruleset/openai.yml")
    ("Claude"  "https://raw.githubusercontent.com/jrtxio/proxy-rules/master/clash/claude.yml"   "./ruleset/claude.yml")
    ("Google"  "https://raw.githubusercontent.com/jrtxio/proxy-rules/master/clash/google.yml"   "./ruleset/google.yml")
    ("Netflix" "https://raw.githubusercontent.com/jrtxio/proxy-rules/master/clash/netflix.yml" "./ruleset/netflix.yml")
    ("Telegram" "https://raw.githubusercontent.com/jrtxio/proxy-rules/master/clash/telegram.yml" "./ruleset/telegram.yml")
    ("Proxy"   "https://raw.githubusercontent.com/jrtxio/proxy-rules/master/clash/blocked.yml"  "./ruleset/blocked.yml")))

;; ============ 数据结构 ============
(struct proxy (name config-line region) #:transparent)

;; ============ HTTP 请求 ============
(define (build-path-string path-list)
  (string-append "/" (string-join (map path/param-path path-list) "/")))

(define (build-query-string query-list)
  (if (null? query-list)
      ""
      (string-append "?"
                     (string-join
                      (map (λ (pair) (format "~a=~a" (car pair) (cdr pair)))
                           query-list)
                      "&"))))

(define (fetch-url url-string)
  (define url (string->url url-string))
  (define path (build-path-string (url-path url)))
  (define query (build-query-string (url-query url)))

  (define-values (status headers in)
    (http-sendrecv (url-host url)
                   (string-append path query)
                   #:ssl? (string-prefix? url-string "https")
                   #:port (or (url-port url)
                             (if (string-prefix? url-string "https") 443 80))
                   #:version #"1.1"
                   #:headers '("User-Agent: Surge/5.0.0"
                              "Accept: */*")))
  (define content (port->string in))
  (close-input-port in)
  content)

;; ============ 解析逻辑 ============
(define (is-traffic-info? name)
  (or (string-contains? name "GB |")
      (string-contains? name "Traffic Reset")
      (string-contains? name "Expire Date")))

(define (get-region name)
  (for/or ([mapping region-map])
    (and (string-contains? name (car mapping))
         (cdr mapping))))

(define (parse-proxy-line line)
  (define parts (string-split line "="))
  (and (>= (length parts) 2)
       (let ([name (string-trim (car parts))])
         (and (not (is-traffic-info? name))
              (proxy name line (get-region name))))))

(define (extract-section lines section-name)
  (define (is-section-header? line)
    (string-prefix? (string-trim line) "["))

  (define (find-start lines idx)
    (cond
      [(null? lines) #f]
      [(string-prefix? (string-trim (car lines)) section-name) idx]
      [else (find-start (cdr lines) (+ idx 1))]))

  (define start (find-start lines 0))
  (if start
      (let loop ([lines (drop lines (+ start 1))] [result '()])
        (cond
          [(null? lines) (reverse result)]
          [(is-section-header? (car lines)) (reverse result)]
          [(not (string=? (string-trim (car lines)) ""))
           (loop (cdr lines) (cons (car lines) result))]
          [else (loop (cdr lines) result)]))
      '()))

(define (parse-subscription content)
  (when (string-prefix? (string-trim content) "<!DOCTYPE")
    (error "订阅返回了 HTML 页面，可能是链接失效或需要认证"))

  (define lines (string-split content "\n"))
  (define proxy-lines (extract-section lines "[Proxy]"))
  (filter identity (map parse-proxy-line proxy-lines)))

;; ============ 代理组生成 ============
(define (group-by-region proxies)
  (define groups (make-hash))
  (define region-order '())

  (for ([p proxies])
    (when (proxy-region p)
      (define region (proxy-region p))
      (unless (hash-has-key? groups region)
        (set! region-order (append region-order (list region))))
      (hash-update! groups region
                    (λ (lst) (cons p lst))
                    '())))

  (for ([(k v) (in-hash groups)])
    (hash-set! groups k (reverse v)))

  (values groups region-order))

;; ============ Surge 格式生成 ============
(define (generate-surge-proxy-groups proxies)
  (define-values (groups regions) (group-by-region proxies))

  (define (make-group name type regions)
    (format "~a = ~a, ~a" name type (string-join regions ", ")))

  (append
   (list (make-group "Proxy" "select" (cons "Auto" regions))
         (make-group "Auto" "fallback" regions))
   (for/list ([service (drop proxy-group-types 2)])
     (make-group service "select" regions))
   (for/list ([region regions])
     (define proxy-names (map proxy-name (hash-ref groups region)))
     (format "~a = select, ~a" region (string-join proxy-names ", ")))))

(define (generate-surge-config proxies)
  (string-join
   (append (list "[Proxy]")
           (map proxy-config-line proxies)
           (list "" "[Proxy Group]")
           (generate-surge-proxy-groups proxies))
   "\n"))

;; ============ Clash 格式生成 ============
(define (surge-to-clash-proxy line)
  (define parts (string-split line "="))
  (when (>= (length parts) 2)
    (define name (string-trim (car parts)))
    (define config-parts (string-split (cadr parts) ","))
    (when (>= (length config-parts) 4)
      (define type (string-trim (car config-parts)))
      (define server (string-trim (cadr config-parts)))
      (define port (string-trim (caddr config-parts)))

      (define params (make-hash))
      (for ([part (drop config-parts 3)])
        (define kv (string-split part "="))
        (when (= (length kv) 2)
          (hash-set! params (string-trim (car kv)) (string-trim (cadr kv)))))

      (format "  - { name: '~a', type: ~a, server: ~a, port: ~a, cipher: ~a, password: '~a', udp: ~a }"
              name
              type
              server
              port
              (hash-ref params "encrypt-method" "aes-256-gcm")
              (hash-ref params "password" "")
              (if (hash-ref params "udp-relay" #f) "true" "false")))))

(define (generate-clash-proxy-groups proxies)
  (define-values (groups regions) (group-by-region proxies))

  (define (quote-if-needed str)
    (if (string-contains? str " ") (format "'~a'" str) str))

  (define (make-group name type proxy-list . extra)
    (define base (format "    - { name: ~a, type: ~a, proxies: [~a]"
                         (quote-if-needed name)
                         type
                         (string-join (map quote-if-needed proxy-list) ", ")))
    (if (null? extra)
        (string-append base " }")
        (string-append base ", " (car extra) " }")))

  (append
   (list (make-group "Proxy" "select"
                     (cons "Auto" regions)
                     "url: 'http://cp.cloudflare.com/generate_204', interval: 300")
         (make-group "Auto" "fallback"
                     regions
                     "url: 'http://cp.cloudflare.com/generate_204', interval: 300"))
   (for/list ([service (drop proxy-group-types 2)])
     (make-group service "select" regions
                 "url: 'http://cp.cloudflare.com/generate_204', interval: 300"))
   (for/list ([region regions])
     (define proxy-names (map proxy-name (hash-ref groups region)))
     (make-group region "select" proxy-names))))

(define (generate-clash-rule-providers)
  (for/list ([provider clash-rule-providers])
    (match-define (list name url path) provider)
    (format "    ~a: { type: http, behavior: classical, url: '~a', interval: 86400, path: ~a }"
            name url path)))

(define (generate-clash-rules)
  '("  - \"GEOIP,CN,DIRECT\""
    "  - \"RULE-SET,Direct,DIRECT\""
    "  - \"RULE-SET,OpenAI,OpenAI\""
    "  - \"RULE-SET,Claude,Claude\""
    "  - \"RULE-SET,Google,Google\""
    "  - \"RULE-SET,Netflix,Netflix\""
    "  - \"RULE-SET,Telegram,Telegram\""
    "  - \"MATCH,Proxy\""))

(define (generate-clash-config proxies)
  (string-join
   (append (list "proxies:")
           (filter identity (map (λ (p) (surge-to-clash-proxy (proxy-config-line p))) proxies))
           (list "" "proxy-groups:")
           (generate-clash-proxy-groups proxies)
           (list "" "rule-providers:")
           (generate-clash-rule-providers)
           (list "rules:")
           (generate-clash-rules))
   "\n"))

;; ============ 统计信息 ============
(define (print-statistics proxies)
  (define-values (groups regions) (group-by-region proxies))
  (define total (length proxies))

  (printf "服务器统计:\n")
  (for ([region regions])
    (define count (length (hash-ref groups region)))
    (printf "  ~a: ~a 个节点\n"
            (~a region #:width 20 #:align 'left)
            (~r count #:min-width 2)))

  (printf "\n代理节点预览 (前 5 个):\n")
  (for ([p (take proxies (min 5 total))]
        [i (in-naturals 1)])
    (printf "  ~a. ~a\n" i (proxy-name p)))
  (when (> total 5)
    (printf "  ... 还有 ~a 个节点\n" (- total 5)))

  (printf "\n生成的代理组 (按出现顺序):\n")
  (for ([region regions])
    (printf "  ~a (~a 个节点)\n" region (length (hash-ref groups region)))))

;; ============ 主函数 ============
(define (main)
  (printf "========================================\n")
  (printf "Surge & Clash 订阅更新脚本\n")
  (printf "========================================\n\n")

  (printf "订阅地址: ~a\n\n" (config-subscription-url app-config))

  ;; 下载订阅
  (printf "1. 正在下载订阅...\n")
  (define content
    (with-handlers ([exn:fail?
                     (λ (e)
                       (printf "   ✗ 错误: ~a\n" (exn-message e))
                       (exit 1))])
      (fetch-url (config-subscription-url app-config))))
  (printf "   ✓ 下载完成 (~a 字节)\n\n" (string-length content))

  ;; 解析配置
  (printf "2. 正在解析订阅配置...\n")
  (define proxies
    (with-handlers ([exn:fail?
                     (λ (e)
                       (printf "   ✗ 错误: ~a\n" (exn-message e))
                       (exit 1))])
      (parse-subscription content)))

  (when (null? proxies)
    (printf "   ✗ 错误: 未找到有效的代理配置\n")
    (exit 1))

  (printf "   ✓ 找到 ~a 个代理节点\n\n" (length proxies))

  ;; 生成 Surge 配置
  (printf "3. 正在生成 Surge 配置...\n")
  (define surge-output (generate-surge-config proxies))
  (printf "   ✓ 已生成 Surge Proxy 配置\n")
  (printf "   ✓ 已生成 Surge Proxy Group 配置\n\n")

  ;; 生成 Clash 配置
  (printf "4. 正在生成 Clash 配置...\n")
  (define clash-output (generate-clash-config proxies))
  (printf "   ✓ 已生成 Clash Proxies 配置\n")
  (printf "   ✓ 已生成 Clash Proxy Groups 配置\n")
  (printf "   ✓ 已生成 Clash Rules 配置\n\n")

  ;; 保存文件
  (printf "5. 正在保存配置...\n")
  (display-to-file surge-output (config-surge-output app-config) #:exists 'replace)
  (printf "   ✓ Surge 配置已保存到: ~a\n" (config-surge-output app-config))
  (display-to-file clash-output (config-clash-output app-config) #:exists 'replace)
  (printf "   ✓ Clash 配置已保存到: ~a\n\n" (config-clash-output app-config))

  ;; 显示统计
  (printf "========================================\n")
  (printf "更新完成！\n")
  (printf "========================================\n\n")
  (print-statistics proxies)
  (printf "\n提示:\n")
  (printf "  - Surge 配置: ~a\n" (config-surge-output app-config))
  (printf "  - Clash 配置: ~a\n" (config-clash-output app-config))
  (printf "  请检查文件内容，确认无误后使用\n"))

;; 运行
(with-handlers ([exn:fail?
                 (λ (e)
                   (printf "\n发生错误:\n~a\n" (exn-message e))
                   (exit 1))])
  (main))
