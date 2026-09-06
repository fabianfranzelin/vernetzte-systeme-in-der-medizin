;;; ff-org-config.el --- Org-mode and babel configuration -*- lexical-binding: t; -*-
;;; Commentary:
;; Configures org-mode settings and babel languages.  Pyvenv is intentionally
;; NOT required here so the build can run in a minimal Docker container.
;;; Code:

(require 'ff-config)
(require 'org)
(require 'org-attach)

(setq user-full-name ff/user-full-name
      user-mail-address ff/user-mail-address
      org-export-allow-bind-keywords t
      org-confirm-babel-evaluate nil
      org-use-sub-superscripts '{}
      org-attach-dir-relative t
      org-link-file-path-type 'adaptive
      org-export-with-broken-links 'mark)

;; Replace attachment: links with relative file: links for publishing so that
;; org-html can inline images (and org-publish's static rule copies them).
(remove-hook 'org-export-before-parsing-functions 'org-attach-expand-links)

(defun ff/attachment-expand-links (_backend)
  "Replace attachment: links with relative file: links for publishing."
  (let ((file-dir (file-name-directory (buffer-file-name))))
    (let ((links (org-element-map (org-element-parse-buffer) 'link
                   (lambda (link)
                     (when (string-equal "attachment" (org-element-property :type link))
                       link)))))
      (dolist (link (nreverse links))
        (goto-char (org-element-begin link))
        (when-let* ((attach-dir (org-attach-dir))
                    (file (org-element-property :path link))
                    (target (expand-file-name file attach-dir))
                    (rel-path (file-relative-name target file-dir)))
          (let ((desc (and (org-element-contents-begin link)
                           (buffer-substring-no-properties
                            (org-element-contents-begin link)
                            (org-element-contents-end link))))
                (end (progn (goto-char (org-element-end link))
                            (skip-chars-backward " \t")
                            (point))))
            (delete-region (org-element-begin link) end)
            ;; Drop description for image files so they are inlined rather than linked.
            (when (and desc (org-file-image-p rel-path))
              (setq desc nil))
            (insert (org-link-make-string (concat "file:" rel-path) desc))))))))

(add-hook 'org-export-before-parsing-functions #'ff/attachment-expand-links)

;; Babel languages (kept minimal; add more if needed).
(org-babel-do-load-languages
 'org-babel-load-languages
 '((emacs-lisp . t)
   (python . t)
   (shell . t)
   (plantuml . t)
   (org . t)))

;; PlantUML: prefer the system executable (Debian package installs
;; /usr/bin/plantuml and /usr/share/plantuml/plantuml.jar) so blocks are
;; regenerated automatically during export.
(setq org-plantuml-exec-mode 'plantuml
      org-plantuml-executable-path (or (executable-find "plantuml")
                                       "/usr/bin/plantuml")
      org-plantuml-jar-path (or (getenv "PLANTUML_JAR_PATH")
                                "/home/frf2lr/.cache/emacs/var/plantuml/plantuml-1.2026.2.jar"))

(provide 'ff-org-config)
;;; ff-org-config.el ends here
