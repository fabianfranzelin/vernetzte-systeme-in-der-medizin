;;; ff-presentations.el --- Reveal.js presentation publishing -*- lexical-binding: t; -*-
;;; Commentary:
;; Discovers org files with #+REVEAL_ROOT: in docs/content/, generates a
;; presentations.org index, and configures reveal.js export with a CC0 footer.
;;; Code:

(require 'ff-config)
(require 'ox-reveal)

(defvar ff/reveal--footer-html nil
  "Footer HTML injected before </body> for the current reveal export.")

(defun ff/reveal--build-footer ()
  "Return the footer HTML string.  Uses #+CONFIDENCE if present."
  (let ((confidence
         (or (save-excursion
               (goto-char (point-min))
               (when (re-search-forward
                      "^#\\+CONFIDENCE:\\s-*\\(.+\\)" nil t)
                 (string-trim (match-string 1))))
             "Public — CC0-1.0"))
        (year
         (or (save-excursion
               (goto-char (point-min))
               (when (re-search-forward
                      "^#\\+DATE:\\s-*\\([0-9]\\{4\\}\\)" nil t)
                 (match-string 1)))
             ff/copyright-year)))
    (concat
     "<style>"
      "#ff-reveal-footer{position:fixed;bottom:10px;left:10px;right:10px;"
     "display:flex;justify-content:space-between;align-items:center;"
     "font-size:18px;color:#666;z-index:1000;pointer-events:none;font-family:sans-serif;}"
     ".reveal .slide-number{display:none!important;}"
     "</style>"
     (format "<div id=\"ff-reveal-footer\"><span>%s · %s · %s</span>"
             confidence ff/user-full-name year)
     "<span id=\"ff-reveal-footer-page\"></span></div>"
     "<script>"
     "document.addEventListener('DOMContentLoaded',function(){"
     "if(typeof Reveal!=='undefined'){"
     "var K='ff-reveal-pos:'+location.pathname;"
     "function u(){var el=document.getElementById('ff-reveal-footer-page');"
     "if(el){el.textContent=Reveal.getIndices().h+1;}"
     "try{var i=Reveal.getIndices();"
     "sessionStorage.setItem(K,JSON.stringify([i.h,i.v,i.f]));}catch(e){}}"
     "function restore(){"
     "try{var s=sessionStorage.getItem(K);if(!s)return;"
     "var a=JSON.parse(s);var sh=a[0]||0,sv=a[1]||0,"
     "sf=(typeof a[2]==='number'&&!isNaN(a[2]))?a[2]:undefined;"
     "if(!sh&&!sv&&sf===undefined)return;"
     "var i=Reveal.getIndices();"
     "var hasHash=location.hash&&location.hash!=='#'&&location.hash!=='#/';"
     "var landedZero=(i.h===0&&i.v===0);"
     ;; Restore when no hash, or when hash was present but reveal landed
     ;; at 0/0 (named slide IDs changed after a rebuild).
     "if(!hasHash||landedZero){Reveal.slide(sh,sv,sf);}"
     "}catch(e){}}"
     "Reveal.on('slidechanged',u);Reveal.on('fragmentshown',u);Reveal.on('fragmenthidden',u);"
     "Reveal.on('ready',function(){restore();u();});}});"
     "</script>")))

(defun ff/reveal-inject-footer (contents _backend _info)
   "Inject `ff/reveal--footer-html' before </body> in CONTENTS."
  (if (and ff/reveal--footer-html
           (string-match "</body>" contents))
      (replace-match (concat ff/reveal--footer-html "</body>") t t contents)
     contents))

(defun ff/reveal--org-links-to-html (text)
  "Convert Org links [[URL][DESC]] and [[URL]] in TEXT to HTML anchors."
  (let ((s text))
    (setq s (replace-regexp-in-string
             "\\[\\[\\([^]]+\\)\\]\\[\\([^]]+\\)\\]\\]"
             (lambda (m)
               (save-match-data
                 (string-match "\\[\\[\\([^]]+\\)\\]\\[\\([^]]+\\)\\]\\]" m)
                 (format "<a href=\"%s\">%s</a>"
                         (match-string 1 m) (match-string 2 m))))
             s t t))
    (setq s (replace-regexp-in-string
             "\\[\\[\\([^]]+\\)\\]\\]"
             (lambda (m)
               (save-match-data
                 (string-match "\\[\\[\\([^]]+\\)\\]\\]" m)
                 (format "<a href=\"%s\">%s</a>"
                         (match-string 1 m) (match-string 1 m))))
             s t t))
    s))

(defun ff/reveal--parse-footnote-definitions (org-file)
  "Return an alist (LABEL . HTML) of footnote defs from ORG-FILE."
  (let ((defs nil))
    (when (and org-file (file-readable-p org-file))
      (with-temp-buffer
        (insert-file-contents org-file)
        (goto-char (point-min))
        (while (re-search-forward "^\\[fn:\\([^]]+\\)\\][ \t]*" nil t)
          (let ((label (match-string 1))
                (body-start (point))
                (body-end nil))
            (forward-line 1)
            (while (and (not body-end) (not (eobp)))
              (cond
               ((looking-at "^[ \t]*$")
                (setq body-end (point)))
               ((looking-at "^\\[fn:")
                (setq body-end (point)))
               ((looking-at "^#\\+")
                (setq body-end (point)))
               (t (forward-line 1))))
            (unless body-end (setq body-end (point)))
            (let ((body (string-trim
                         (buffer-substring-no-properties body-start body-end))))
              (push (cons label (ff/reveal--org-links-to-html body)) defs))))))
    (nreverse defs)))

(defun ff/reveal--transform-slide (slide defs)
  "Inject footnote definitions used in SLIDE, using DEFS alist."
  (let ((refs nil)
        (numbers (make-hash-table :test #'equal))
        (pos 0))
    (while (string-match
            "<a id=\"fnr\\.\\([^\".]+\\)\\(?:\\.[0-9]+\\)?\" class=\"footref\" href=\"#fn\\.[^\"]+\" role=\"doc-backlink\">\\([0-9]+\\)</a>"
            slide pos)
      (let ((label (match-string 1 slide))
            (num (match-string 2 slide)))
        (unless (gethash label numbers)
          (puthash label num numbers)
          (push label refs)))
      (setq pos (match-end 0)))
    (setq refs (nreverse refs))
    (if (null refs)
        slide
      (let* ((items
              (mapconcat
               (lambda (label)
                 (let ((def (cdr (assoc label defs)))
                       (num (gethash label numbers)))
                   (if def
                       (format
                        "<div class=\"footdef\"><sup><a id=\"fn.%s\" href=\"#fnr.%s\" class=\"footnum\" role=\"doc-backlink\">%s</a></sup> <span class=\"footpara\">%s</span></div>"
                        label label num def)
                     "")))
               refs ""))
             (block-html (format "<div class=\"footnotes\">%s</div>" items)))
        (with-temp-buffer
          (insert slide)
          (goto-char (point-min))
          (if (re-search-forward
               "<div class=\"footnotes\"[^>]*>[ \t\n]*</div>" nil t)
              (replace-match block-html t t)
            (goto-char (point-max))
            (when (re-search-backward "</section>" nil t)
              (goto-char (match-beginning 0))
              (insert block-html)))
          (buffer-string))))))

(defun ff/reveal-inline-footnotes (contents backend info)
  "Inject Org footnote definitions into the Reveal slide that cites them."
  (if (not (org-export-derived-backend-p backend 'reveal))
      contents
    (let* ((input-file (plist-get info :input-file))
           (defs (ff/reveal--parse-footnote-definitions input-file)))
      (if (null defs)
          contents
        (with-temp-buffer
          (insert contents)
          (goto-char (point-min))
          (while (re-search-forward
                  "<section id=\"slide-[^\"]+\"[^>]*>" nil t)
            (let* ((section-start (match-beginning 0))
                   (depth 1)
                   (section-end nil))
              (while (and (> depth 0)
                          (re-search-forward
                           "<section\\b\\|</section>" nil t))
                (if (string-prefix-p "</" (match-string 0))
                    (setq depth (1- depth))
                  (setq depth (1+ depth))))
              (setq section-end (point))
              (let* ((slide (buffer-substring-no-properties
                             section-start section-end))
                     (new-slide (ff/reveal--transform-slide slide defs)))
                (unless (string= slide new-slide)
                  (delete-region section-start section-end)
                  (goto-char section-start)
                  (insert new-slide)))))
          (buffer-string))))))

(add-to-list 'org-export-filter-final-output-functions
              #'ff/reveal-inject-footer)
(add-to-list 'org-export-filter-final-output-functions
             #'ff/reveal-inline-footnotes)

(defun ff/reveal-export-setup (orig-fun &rest args)
  "Prepare the footer for reveal export."
  (kill-local-variable 'org-reveal-slide-footer)
  (kill-local-variable 'org-reveal-global-footer)
  (let ((org-html-head nil)
        (org-html-head-extra nil)
        (org-reveal-slide-footer nil)
        (org-reveal-global-footer nil)
        (ff/reveal--footer-html (ff/reveal--build-footer)))
    (apply orig-fun args)))

(advice-add 'org-reveal-export-to-html :around #'ff/reveal-export-setup)
(advice-add 'org-reveal-publish-to-reveal :around #'ff/reveal-export-setup)

(defun ff/publish-to-reveal-no-header (plist filename pub-dir)
  "Publish FILENAME as reveal.js."
  (org-reveal-publish-to-reveal plist filename pub-dir))

(defun ff/find-presentation-files ()
  "Return relative paths of all org files under `ff/base-dir' containing #+REVEAL_ROOT:."
  (cl-loop for f in (directory-files-recursively ff/base-dir "\\.org$")
           when (with-temp-buffer
                  (insert-file-contents f)
                  (re-search-forward "^#\\+REVEAL_ROOT:" nil t))
           collect (file-relative-name f ff/base-dir)))

(defun ff/setup-presentations (project-alist)
  "Find presentations in content/ and configure PROJECT-ALIST."
  (let ((pres-files (ff/find-presentation-files)))
    (when pres-files
      (message "Found %d presentation(s)" (length pres-files))
      (setf (plist-get (cdr (assoc "org:presentations" project-alist)) :include) pres-files
            (plist-get (cdr (assoc "org:presentations" project-alist)) :exclude) ".*")))
  project-alist)

(provide 'ff-presentations)
;;; ff-presentations.el ends here
