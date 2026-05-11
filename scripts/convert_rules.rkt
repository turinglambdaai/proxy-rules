#lang racket

;; Convert Surge .list rule files → Clash .yml rule-provider files
;; Run from repo root:  racket scripts/convert_rules.rkt
;; Run from scripts/:   racket convert_rules.rkt

(require racket/file
         racket/path
         racket/string
         racket/runtime-path)

(define-runtime-path script-dir ".")
(define repo-root (build-path script-dir ".."))

(define (convert-surge-to-clash)
  (define root    repo-root)
  (define surge-d (build-path root "surge"))
  (define clash-d (build-path root "clash"))

  (unless (directory-exists? clash-d)
    (make-directory clash-d)
    (printf "Created directory: ~a\n" clash-d))

  (define list-files (filter (λ (f) (string-suffix? (path->string f) ".list"))
                             (directory-list surge-d)))
  (unless (pair? list-files)
    (printf "No .list files found in ~a\n" surge-d)
    (void))

  (printf "Found ~a files to convert...\n" (length list-files))

  (for ([file-name (in-list list-files)])
    (define in-path  (build-path surge-d file-name))
    (define out-name (string-replace (path->string file-name) ".list" ".yml"))
    (define out-path (build-path clash-d out-name))
    (printf "Converting ~a -> ~a\n" file-name out-name)

    (define lines (file->lines in-path))

    ;; Separate header (leading comments/blank lines) from body (rules)
    (define-values (header body)
      (let loop ([ls lines] [in-header? #t] [hdr '()])
        (cond
          [(null? ls) (values (reverse hdr) '())]
          [in-header?
           (define stripped (string-trim (car ls)))
           (cond
             [(equal? stripped "")        (loop (cdr ls) #t (cons (car ls) hdr))]
             [(string-prefix? stripped "#") (loop (cdr ls) #t (cons (car ls) hdr))]
             [(string-prefix? stripped ";") (loop (cdr ls) #t (cons (car ls) hdr))]
             [else                        (values (reverse hdr) ls)])]
          [else (values (reverse hdr) ls)])))

    (call-with-output-file out-path
      #:exists 'replace
      (λ (out)
        ;; Write header as-is (file->lines strips newlines, add them back)
        (for ([line (in-list header)])
          (display line out)
          (newline out))
        ;; Write payload block
        (display "payload:\n" out)
        (for ([line (in-list body)])
          (define stripped (string-trim line))
          (cond
            [(equal? stripped "") (newline out)]
            [(or (string-prefix? stripped "#")
                 (string-prefix? stripped ";"))
             (fprintf out "  ~a\n" stripped)]
            [(or (string-prefix? stripped "PROCESS-NAME")
                 (string-prefix? stripped "USER-AGENT"))
             (printf "  [WARN] Skipping unsupported rule: ~a\n" stripped)
             (fprintf out "  # [SKIPPED] ~a\n" stripped)]
            [else
             (fprintf out "  - '~a'\n" stripped)])))))

  (printf "Conversion complete.\n"))

(module+ main
  (convert-surge-to-clash))
