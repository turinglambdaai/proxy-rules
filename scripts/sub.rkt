#lang racket

;; 从 Surge 订阅链接提取节点，按地区分组，生成 Surge 代理配置
(require net/http-client net/url)

;; ============ 配置 ============
(struct config (subscription-url output) #:transparent)

(define app-config
  (config
   "在此处填入订阅地址"
   "surge_updated.conf"))

;; 地区映射
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

(define service-groups '("OpenAI" "Claude" "Google" "Netflix" "Telegram"))

;; ============ 数据结构 ============
(struct proxy (name config-line region) #:transparent)

;; ============ HTTP ============
(define (build-path-string path-list)
  (string-append "/" (string-join (map path/param-path path-list) "/")))

(define (build-query-string query-list)
  (if (null? query-list) ""
      (string-append "?" (string-join
                          (map (λ (p) (format "~a=~a" (car p) (cdr p))) query-list)
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
                   #:headers '("User-Agent: Surge/5.0.0" "Accept: */*")))
  (define content (port->string in))
  (close-input-port in)
  content)

;; ============ 解析 ============
(define (is-traffic-info? name)
  (or (string-contains? name "GB |")
      (string-contains? name "Traffic Reset")
      (string-contains? name "Expire Date")))

(define (get-region name)
  (for/or ([m region-map])
    (and (string-contains? name (car m)) (cdr m))))

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
(define (group-by-region proxies)
  (define groups (make-hash))
  (define region-order '())
  (for ([p proxies])
    (when (proxy-region p)
      (define r (proxy-region p))
      (unless (hash-has-key? groups r)
        (set! region-order (append region-order (list r))))
      (hash-update! groups r (λ (lst) (cons p lst)) '())))
  (for ([(k v) (in-hash groups)])
    (hash-set! groups k (reverse v)))
  (values groups region-order))

;; ============ Surge 配置生成 ============
(define (generate-surge-config proxies)
  (define-values (groups regions) (group-by-region proxies))
  (define (group name type region-list)
    (format "~a = ~a, ~a" name type (string-join region-list ", ")))

  (string-join
   (append
    (list "[Proxy]")
    (map proxy-config-line proxies)
    (list "" "[Proxy Group]")
    (list (group "Proxy" "select" (cons "Auto" regions))
          (group "Auto" "fallback" regions))
    (for/list ([svc service-groups])
      (group svc "select" regions))
    (for/list ([r regions])
      (define names (map proxy-name (hash-ref groups r)))
      (format "~a = select, ~a" r (string-join names ", ")))))
   "\n"))

;; ============ 统计 ============
(define (print-statistics proxies)
  (define-values (groups regions) (group-by-region proxies))
  (define total (length proxies))
  (printf "服务器统计:\n")
  (for ([r regions])
    (define count (length (hash-ref groups r)))
    (printf "  ~a: ~a 个节点\n" (~a r #:width 20 #:align 'left) (~r count #:min-width 2)))
  (printf "\n代理节点预览 (前 5 个):\n")
  (for ([p (take proxies (min 5 total))] [i (in-naturals 1)])
    (printf "  ~a. ~a\n" i (proxy-name p)))
  (when (> total 5)
    (printf "  ... 还有 ~a 个节点\n" (- total 5)))
  (printf "\n生成的代理组:\n")
  (for ([r regions])
    (printf "  ~a (~a 个节点)\n" r (length (hash-ref groups r)))))

;; ============ 主函数 ============
(define (main)
  (printf "========================================\n")
  (printf "Surge 订阅更新\n")
  (printf "========================================\n\n")
  (printf "订阅地址: ~a\n\n" (config-subscription-url app-config))

  (printf "1. 正在下载订阅...\n")
  (define content
    (with-handlers ([exn:fail? (λ (e) (printf "   ✗ 错误: ~a\n" (exn-message e)) (exit 1))])
      (fetch-url (config-subscription-url app-config))))
  (printf "   ✓ 下载完成 (~a 字节)\n\n" (string-length content))

  (printf "2. 正在解析...\n")
  (define proxies
    (with-handlers ([exn:fail? (λ (e) (printf "   ✗ 错误: ~a\n" (exn-message e)) (exit 1))])
      (parse-subscription content)))
  (when (null? proxies)
    (printf "   ✗ 错误: 未找到有效的代理配置\n") (exit 1))
  (printf "   ✓ 找到 ~a 个代理节点\n\n" (length proxies))

  (printf "3. 正在生成配置...\n")
  (define output (generate-surge-config proxies))
  (display-to-file output (config-output app-config) #:exists 'replace)
  (printf "   ✓ 已保存到: ~a\n\n" (config-output app-config))

  (printf "========================================\n")
  (printf "更新完成！\n")
  (printf "========================================\n\n")
  (print-statistics proxies))

(with-handlers ([exn:fail? (λ (e) (printf "\n发生错误:\n~a\n" (exn-message e)) (exit 1))])
  (main))
