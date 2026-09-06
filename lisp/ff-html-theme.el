;;; ff-html-theme.el --- Minimal HTML export theme -*- lexical-binding: t; -*-
;;; Commentary:
;; Provides a small, self-contained HTML theme for the non-reveal pages.
;; No external template files required.
;;; Code:

(require 'ff-config)

(defvar ff/html-head-extra
  (concat
   "<style>"
   "body{max-width:960px;margin:2em auto;padding:0 1em;"
   "font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;"
   "line-height:1.55;color:#222;}"
   "h1,h2,h3{font-weight:600;line-height:1.2;}"
   "h1{border-bottom:2px solid #444;padding-bottom:.3em;}"
   "h2{border-bottom:1px solid #ddd;padding-bottom:.2em;margin-top:2em;}"
   "a{color:#0645ad;text-decoration:none;}a:hover{text-decoration:underline;}"
   "pre,code{font-family:'SF Mono',Menlo,Consolas,monospace;font-size:.92em;}"
   "pre{background:#f6f8fa;padding:1em;border-radius:6px;overflow-x:auto;}"
   "code{background:#f6f8fa;padding:.15em .35em;border-radius:3px;}"
   "pre code{background:none;padding:0;}"
   "table{border-collapse:collapse;margin:1em 0;}"
   "th,td{border:1px solid #ccc;padding:.4em .7em;}"
   "th{background:#f0f0f0;}"
   "blockquote{border-left:4px solid #ccc;margin:1em 0;padding:.3em 1em;color:#555;}"
   "footer{margin-top:3em;padding-top:1em;border-top:1px solid #ddd;font-size:.9em;color:#666;}"
   "</style>"))

(defvar ff/html-postamble
  (format "<footer>Public — CC0-1.0 · %s · %s</footer>"
          ff/user-full-name ff/copyright-year))

(setq org-html-validation-link nil
      org-html-head-include-scripts nil
      org-html-head-include-default-style nil
      org-html-head-extra ff/html-head-extra
      org-html-htmlize-output-type 'css
      org-html-postamble t
      org-html-postamble-format
      `(("en" ,ff/html-postamble)
        ("de" ,ff/html-postamble)))

(provide 'ff-html-theme)
;;; ff-html-theme.el ends here
