#lang racket

;; 从多个 Surge 订阅提取节点，按 provider（订阅）优先级 + 地区分组，生成 Surge 代理配置。
;;
;; 订阅链接从环境变量或脚本同目录 .env 读取：
;;   SUB_<NAME>_URL=<url>  多订阅；.env 中出现顺序 = 优先级（排前者主用，其余按序备用）
;;   SURGE_SUB_URL=<url>   旧的单订阅写法，等价 SUB_SSRDOG_URL，仍兼容
;;
;; 生成的地区组与 Auto 均为 fallback：按优先级顺序取第一个可用节点——
;; 主用 provider（如 ssrdog）的节点全部失联才切到备用（如 mitce），恢复后自动切回。

(require net/http-client net/url racket/port)

;; 供 test-sub.rkt require 复用内部函数
(provide (all-defined-out))

;; ============ 配置 ============

(define service-groups '("OpenAI" "Claude" "Google" "Netflix" "Telegram"))

;; 健康检查参数（url-test / fallback 组共用）
(define test-params "url=http://cp.cloudflare.com/generate_204, interval=300")

;; provider 显示名映射（键为 SUB_<NAME>_URL 中的 NAME 大写形式，未列出的原样大写显示）
(define provider-display-map
  '(("SSRDOG" . "SSRDog")
    ("MITCE" . "Mitce")))

;; 地区识别 pattern（无 flag 的正则源串，与 scripts/clash-verge.js 的 REGIONS 共用，
;; 改动须两侧同步；Racket/mihomo 加 "(?i)" 前缀，JS 用 i flag。
;; 两字母代码带左右边界，防止 AUS→US、TR→Turkey 之类误判）
(define (make-region-pattern codes words)
  (format "(?:^|[^A-Za-z])(?:~a)(?: ?[0-9#-]|[^A-Za-z0-9]|$)|~a"
          (string-join codes "|")
          (string-join words "|")))

(define raw-region-map
  (list
   (cons (make-region-pattern '("HK" "HKG") '("Hong Kong" "香港" "🇭🇰")) "🇭🇰 Hong Kong")
   (cons (make-region-pattern '("TW" "TWN") '("Taiwan" "台北" "新北" "台中" "台湾" "台灣" "臺灣" "🇹🇼")) "🇨🇳 Taiwan")
   (cons (make-region-pattern '("SG" "SGP") '("Singapore" "新加坡" "狮城" "獅城" "🇸🇬")) "🇸🇬 Singapore")
   (cons (make-region-pattern '("JP" "JPN") '("Japan" "Tokyo" "Osaka" "东京" "大阪" "日本" "🇯🇵")) "🇯🇵 Japan")
   (cons (make-region-pattern '("US" "USA") '("United States" "Los Angeles" "San Jose" "Seattle" "New York" "Chicago" "美国" "美國" "美西" "美东" "北美" "洛杉矶" "圣何塞" "西雅图" "纽约" "芝加哥" "🇺🇸")) "🇺🇸 United States")
   (cons (make-region-pattern '("KR" "KOR") '("Korea" "Seoul" "首尔" "韩国" "韓國" "🇰🇷")) "🇰🇷 Korea")
   (cons (make-region-pattern '("CA" "CAN") '("Canada" "Toronto" "Vancouver" "加拿大" "多伦多" "温哥华" "🇨🇦")) "🇨🇦 Canada")
   (cons (make-region-pattern '("GB" "UK" "GBR") '("United Kingdom" "Great Britain" "London" "英国" "英國" "伦敦" "🇬🇧")) "🇬🇧 Great Britain")
   (cons (make-region-pattern '("TR" "TUR") '("Turkey" "Istanbul" "土耳其" "伊斯坦布尔" "🇹🇷")) "🇹🇷 Turkey")
   (cons (make-region-pattern '("IN" "IND") '("India" "Mumbai" "印度" "孟买" "🇮🇳")) "🇮🇳 India")
   (cons (make-region-pattern '("NL" "NLD") '("Netherlands" "Amsterdam" "荷兰" "荷蘭" "阿姆斯特丹" "🇳🇱")) "🇳🇱 Netherlands")
   (cons (make-region-pattern '("FR" "FRA") '("France" "Paris" "法国" "法國" "巴黎" "🇫🇷")) "🇫🇷 France")
   (cons (make-region-pattern '("DE" "DEU") '("Germany" "Frankfurt" "德国" "德國" "法兰克福" "🇩🇪")) "🇩🇪 Germany")
   (cons (make-region-pattern '("VN" "VNM") '("Vietnam" "越南" "河内" "🇻🇳")) "🇻🇳 Vietnam")
   (cons (make-region-pattern '("MY" "MYS") '("Malaysia" "吉隆坡" "马来西亚" "馬來西亞" "🇲🇾")) "🇲🇾 Malaysia")
   (cons (make-region-pattern '("TH" "THA") '("Thailand" "曼谷" "泰国" "泰國" "🇹🇭")) "🇹🇭 Thailand")
   (cons (make-region-pattern '("PH" "PHL") '("Philippines" "马尼拉" "菲律宾" "菲律賓" "🇵🇭")) "🇵🇭 Philippines")
   (cons (make-region-pattern '("AU" "AUS") '("Australia" "Sydney" "Melbourne" "澳大利亚" "澳洲" "澳大利亞" "悉尼" "墨尔本" "🇦🇺")) "🇦🇺 Australia")
   (cons (make-region-pattern '("BR" "BRA") '("Brazil" "巴西" "圣保罗" "🇧🇷")) "🇧🇷 Brazil")
   (cons (make-region-pattern '("AR" "ARG") '("Argentina" "阿根廷" "🇦🇷")) "🇦🇷 Argentina")))

;; 预编译：Racket PCRE 要求模式作用域写法 (?i:...)（JS 用 i flag、mihomo/Go 用 "(?i)" 前缀，见 clash-verge.js）
(define region-map
  (for/list ([entry (in-list raw-region-map)])
    (cons (regexp (string-append "(?i:" (car entry) ")")) (cdr entry))))

;; 订阅附带的流量/到期信息行，不入节点列表
(define traffic-info-rx
  (regexp "(?i:GB \\||Traffic|Expire|剩余|流量|到期|過期|过期|官网|官網|套餐|重置)"))

(define script-dir
  (let-values ([(base name dir?) (split-path (path->complete-path (find-system-path 'run-file) (find-system-path 'orig-dir)))])
    base))

;; ============ 数据结构 ============
(struct proxy (name body region provider) #:transparent)
(struct sub (name display url) #:transparent)

;; ============ .env / 环境变量 ============

(define (string-idx str ch)
  (for/or ([c (in-string str)] [i (in-naturals)])
    (and (char=? c ch) i)))

;; 按出现顺序读取 scripts/.env 的 KEY=VAL（顺序即订阅优先级）
(define (read-env-entries)
  (define env-file (build-path script-dir ".env"))
  (define entries '())
  (when (file-exists? env-file)
    (for ([line (in-list (string-split (file->string env-file) "\n"))])
      (define trimmed (string-trim line))
      (when (and (> (string-length trimmed) 0)
                 (not (string-prefix? trimmed "#")))
        (define idx (string-idx trimmed #\=))
        (when idx
          (define key (string-trim (substring trimmed 0 idx)))
          (define val (string-trim (substring trimmed (+ idx 1))))
          (when (and (> (string-length key) 0) (> (string-length val) 0))
            (set! entries (append entries (list (cons key val)))))))))
  entries)

(define (provider-display name)
  (define up (string-upcase name))
  (cond [(assoc up provider-display-map) => cdr]
        [else up]))

(define sub-url-rx #rx"^SUB_(.+)_URL$")

;; 优先级 = .env 中 SUB_*_URL 的出现顺序；兼容旧 SURGE_SUB_URL（.env 或环境变量）
(define (collect-subs)
  (define entries (read-env-entries))
  (define from-file
    (for/list ([entry (in-list entries)] #:when (regexp-match sub-url-rx (car entry)))
      (define name (second (regexp-match sub-url-rx (car entry))))
      (sub name (provider-display name) (cdr entry))))
  (if (null? from-file)
      (let ([url (or (cond [(assoc "SURGE_SUB_URL" entries) => cdr] [else #f])
                     (getenv "SURGE_SUB_URL"))])
        (if url
            (list (sub "SSRDog" "SSRDog" url))
            (error "未设置订阅地址。请在 scripts/.env 中写 SUB_<NAME>_URL=<url>（多订阅，顺序即优先级），或旧写法 SURGE_SUB_URL=<url>")))
      from-file))

;; 命令行一次性覆盖订阅链接并写回 .env（ssrdog 分享链接过期后需整条换新）：
;;   racket scripts/sub.rkt ssrdog=https://新链接 mitce=https://新链接
;; 返回更新后的行列表（纯函数，便于测试）
(define (env-lines-with-key lines key val)
  (define matched (box #f))
  (define replaced
    (for/list ([line (in-list lines)])
      (if (and (not (unbox matched))
               (> (string-length line) 0)
               (string-prefix? (string-trim line) (format "~a=" key)))
          (begin (set-box! matched #t) (format "~a=~a" key val))
          line)))
  (if (unbox matched)
      replaced
      (append replaced (list (format "~a=~a" key val)))))

(define (apply-cli-overrides!)
  (define args (vector->list (current-command-line-arguments)))
  (for ([a (in-list args)] #:when (string-contains? a "="))
    (define idx (string-idx a #\=))
    (define key (string-upcase (string-trim (substring a 0 idx))))
    (define url (string-trim (substring a (+ idx 1))))
    (when (and (> (string-length key) 0)
               (> (string-length url) 0)
               (or (string-prefix? url "http://") (string-prefix? url "https://")))
      (define env-file (build-path script-dir ".env"))
      (define lines (string-split (if (file-exists? env-file) (file->string env-file) "") "\n"))
      (define new-lines (env-lines-with-key lines (format "SUB_~a_URL" key) url))
      (display-to-file (string-join new-lines "\n") env-file #:exists 'replace)
      (printf "订阅 [~a] 链接已更新到 .env\n" key))))

;; ============ HTTP ============
(define (fetch-url url-string)
  (define url (string->url url-string))
  (define path (string-append "/" (string-join (map path/param-path (url-path url)) "/")))
  (define query
    (if (null? (url-query url)) ""
        (string-append "?" (string-join
                            (map (λ (p) (format "~a=~a" (car p) (cdr p))) (url-query url))
                            "&"))))
  (define-values (status headers in)
    (http-sendrecv (url-host url)
                   (string-append path query)
                   #:ssl? (string-prefix? url-string "https")
                   #:port (or (url-port url)
                              (if (string-prefix? url-string "https") 443 80))
                   #:version #"1.1"
                   #:headers '("User-Agent: Surge/5.0.0 (iPhone; iOS 18.0)" "Accept: */*")))
  (define content (port->string in))
  (close-input-port in)
  ;; status 为完整状态行（如 #"HTTP/1.0 200 OK"），取第二段为状态码
  (define status-parts (string-split (string-trim (bytes->string/utf-8 status))))
  (unless (and (>= (length status-parts) 2)
               (string-prefix? (second status-parts) "2"))
    (error 'fetch-url "~a（检查订阅链接是否有效）" (string-trim (bytes->string/utf-8 status))))
  content)

;; ============ 解析 ============
(define (get-region name)
  (for/or ([entry (in-list region-map)])
    (and (regexp-match? (car entry) name) (cdr entry))))

(define (parse-proxy-line line)
  (define idx (string-idx line #\=))
  (and idx
       (let ([name (string-trim (substring line 0 idx))])
         (and (not (string=? name ""))
              (not (regexp-match? traffic-info-rx name))
              (proxy name (string-trim (substring line (+ idx 1))) (get-region name) #f)))))

(define (extract-section lines section-name)
  (define (is-section-header? line)
    (string-prefix? (string-trim line) "["))
  (define (find-start lines idx)
    (cond [(null? lines) #f]
          [(string-prefix? (string-trim (car lines)) section-name) idx]
          [else (find-start (cdr lines) (+ idx 1))]))
  (define start (find-start lines 0))
  (if start
      (let loop ([lines (drop lines (+ start 1))] [result '()])
        (cond [(null? lines) (reverse result)]
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

;; ============ 分组 ============
(define (uniq lst)
  (reverse (for/fold ([acc '()]) ([x (in-list lst)] #:unless (member x acc))
             (cons x acc))))

(define (group-by-region proxies)
  (define groups (make-hash))
  (define region-order '())
  (for ([p (in-list proxies)])
    (when (proxy-region p)
      (define r (proxy-region p))
      (unless (hash-has-key? groups r)
        (set! region-order (append region-order (list r))))
      (hash-update! groups r (λ (lst) (cons p lst)) '())))
  (for ([(k v) (in-hash groups)])
    (hash-set! groups k (reverse v)))
  (values groups region-order))

;; ============ 多订阅合并 ============
;; per-provider: list of (display . proxies)。统一打上 provider 标记；
;; 跨订阅重名的节点改名 "<原名> | <provider>"（同订阅内再次重名追加 #N），
;; 首次出现的名称保持原样，避免破坏 Surge 已保存的手动选择。
(define (merge-proxies per-provider)
  (define dup-count (make-hash))
  (for*/list ([entry (in-list per-provider)]
              [p (in-list (cdr entry))])
    (define display (car entry))
    (define tagged (struct-copy proxy p [provider display]))
    (define n (hash-ref dup-count (proxy-name tagged) 0))
    (hash-set! dup-count (proxy-name tagged) (add1 n))
    (if (= n 0)
        tagged
        (struct-copy proxy tagged
                     [name (format "~a | ~a~a"
                                   (proxy-name tagged) display
                                   (if (= n 1) "" (format " #~a" (add1 n))))]))))

;; ============ Surge 配置生成 ============
;; 组结构（与 scripts/clash-verge.js 同构）：
;;   Proxy      = select, Auto, <provider 组...>, <地区...>, DIRECT
;;   Auto       = fallback, <地区...>            —— 按地区优先级保活
;;   <Provider> = url-test, <该订阅全部节点>     —— 整体切换/兜底某个订阅
;;   <Service>  = select, Proxy, <地区...>, DIRECT
;;   <地区>     = fallback, <主用 provider 节点..., 备用 provider 节点...>
(define (generate-surge-config proxies)
  (define-values (groups regions) (group-by-region proxies))
  (when (null? regions)
    (error 'generate "没有识别出任何地区的节点；请检查节点命名或 region-map"))
  (define provider-names (uniq (map proxy-provider proxies)))
  (define (group-line name type members)
    (format "~a = ~a, ~a" name type (string-join members ", ")))
  (string-join
   (append
    (list "[Proxy]"
          "DIRECT = direct")
    (for/list ([p (in-list proxies)])
      (format "~a = ~a" (proxy-name p) (proxy-body p)))
    (list ""
          "[Proxy Group]")
    (list (group-line "Proxy" "select"
                      (append '("Auto") provider-names regions '("DIRECT"))))
    (list (group-line "Auto" "fallback" (append regions (list test-params))))
    (for/list ([pn (in-list provider-names)])
      (group-line pn "url-test"
                  (append (map proxy-name
                               (filter (λ (p) (string=? (proxy-provider p) pn)) proxies))
                          (list test-params))))
    (for/list ([svc (in-list service-groups)])
      (group-line svc "select" (append '("Proxy") regions '("DIRECT"))))
    (for/list ([r (in-list regions)])
      (group-line r "fallback"
                  (append (map proxy-name (hash-ref groups r)) (list test-params)))))
   "\n"))

;; ============ 统计 ============
(define (print-statistics proxies)
  (define-values (groups regions) (group-by-region proxies))
  (define provider-names (uniq (map proxy-provider proxies)))
  (printf "\nProvider 统计:\n")
  (for ([pn (in-list provider-names)])
    (printf "  ~a: ~a 个节点\n"
            pn
            (length (filter (λ (p) (string=? (proxy-provider p) pn)) proxies))))
  (printf "\n地区统计:\n")
  (for ([r (in-list regions)])
    (printf "  ~a: ~a 个节点\n" r (length (hash-ref groups r))))
  (printf "\n代理节点预览 (前 5 个):\n")
  (for ([p (in-list (take proxies (min 5 (length proxies))))]
        [i (in-naturals 1)])
    (printf "  ~a. [~a] ~a\n" i (proxy-provider p) (proxy-name p)))
  (when (> (length proxies) 5)
    (printf "  ... 还有 ~a 个节点\n" (- (length proxies) 5))))

;; ============ 重试 ============
;; 面板的三种失败都靠重试解决：多后端坏副本、限流 403、临时链接未激活。
;; 失败后间隔 interval 秒重试，最多 max-attempts 次（默认留出 ~90s 等待激活窗口）。
;; 全部失败返回 #f；thunk 成功时返回其结果。
(define (retry-with-backoff display max-attempts interval thunk)
  (let loop ([n 1])
    (with-handlers
        ([exn:fail?
          (λ (e)
            (if (< n max-attempts)
                (begin
                  (printf "   [~a] 未就绪，重试 (~a/~a): ~a\n" display n max-attempts (exn-message e))
                  (sleep interval)
                  (loop (add1 n)))
                (begin
                  (printf "   ⚠ [~a] 跳过: ~a\n" display (exn-message e))
                  #f)))])
      (thunk))))

;; ============ 模板 ============
(define (read-template)
  (define template-path (build-path script-dir "surge-template.conf"))
  (unless (file-exists? template-path)
    (error (format "模板文件不存在: ~a\n请创建包含 {{PROXY_SECTION}} 占位符的模板文件" template-path)))
  (file->string template-path))

;; ============ 主函数 ============
(define (main)
  (apply-cli-overrides!)
  (define subs (collect-subs))
  (define output-path (build-path script-dir ".." "surge" "surge.conf"))

  (printf "========================================\n")
  (printf "Surge 订阅更新\n")
  (printf "========================================\n\n")
  (for ([s (in-list subs)])
    (printf "订阅 [~a]: ~a\n" (sub-display s) (sub-url s)))
  (printf "\n")

  (printf "1. 正在下载并解析订阅...\n")
  (printf "   （临时订阅链接请先到面板激活；未激活/限流/坏副本会自动等待重试，约 90s 窗口）\n")
  ;; 长等待场景可用环境变量放宽：SUB_RETRY_ATTEMPTS / SUB_RETRY_INTERVAL（秒）
  (define retry-attempts (or (and (getenv "SUB_RETRY_ATTEMPTS") (string->number (getenv "SUB_RETRY_ATTEMPTS"))) 15))
  (define retry-interval (or (and (getenv "SUB_RETRY_INTERVAL") (string->number (getenv "SUB_RETRY_INTERVAL"))) 6))
  (define results
    (for/list ([s (in-list subs)])
      (retry-with-backoff (sub-display s) retry-attempts retry-interval
        (λ ()
          (printf "   [~a] 下载中...\n" (sub-display s))
          (define content (fetch-url (sub-url s)))
          (printf "   [~a] ✓ 下载完成 (~a 字节)\n" (sub-display s) (string-length content))
          (define proxies (parse-subscription content))
          (when (null? proxies)
            (error "未解析出节点（该订阅可能不是 Surge 格式，或链接未激活）"))
          (printf "   [~a] ✓ 解析出 ~a 个节点\n" (sub-display s) (length proxies))
          (cons (sub-display s) proxies)))))
  (define ok (filter values results))
  (when (null? ok)
    (error "全部订阅下载/解析失败，中止生成"))

  (printf "\n2. 正在合并生成配置...\n")
  (define proxies (merge-proxies ok))
  (define proxy-section (generate-surge-config proxies))
  (define template (read-template))
  (define output (string-replace template "{{PROXY_SECTION}}" proxy-section))
  (display-to-file output output-path #:exists 'replace)
  (printf "   ✓ 已保存到: ~a\n\n" output-path)

  (printf "========================================\n")
  (printf "更新完成！\n")
  (printf "========================================\n")
  (print-statistics proxies))

(module+ main
  (with-handlers ([exn:fail? (λ (e) (printf "\n发生错误:\n~a\n" (exn-message e)) (exit 1))])
    (main)))
