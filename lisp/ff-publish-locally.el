;;; ff-publish-locally.el --- Local publish: project definition and execution -*- lexical-binding: t; -*-
;;; Commentary:
;; Defines the org-publish project alist and orchestrates the local build.
;;; Code:

(require 'ox-publish)
(require 'ff-config)
(require 'ff-presentations)

(setq org-publish-project-alist
      `(
        ("org:main"
         :recursive t
         :base-directory ,ff/base-dir
         :base-extension "org"
         :publishing-function org-html-publish-to-html
         :publishing-directory ,ff/public-dir
         :with-author t
         :with-email t
         :with-creator nil
         :with-toc nil
         :section-numbers nil
         :time-stamp-file t)
        ("org:static"
         :base-directory ,ff/base-dir
         :base-extension "js\\|json\\|html\\|css\\|txt\\|jpg\\|gif\\|png\\|pdf\\|svg\\|webm\\|mp4\\|woff\\|woff2\\|ttf\\|otf\\|eot\\|map"
         :recursive t
         :publishing-directory ,ff/public-dir
         :publishing-function org-publish-attachment)
        ("org:presentations"
         :recursive t
         :base-directory ,ff/base-dir
         :base-extension "org"
         :publishing-function ff/publish-to-reveal-no-header
         :publishing-directory ,ff/public-dir
         :exclude ".*"
         :include nil
         :with-author t
         :with-email t
         :with-toc nil
         :section-numbers nil)
        ("org" :components ("org:main" "org:static" "org:presentations"))))

(setq org-export-with-broken-links 'mark)

(defun ff/publish-locally ()
  "Run the full local site build."
  (ff/setup-presentations org-publish-project-alist)
  (make-directory ff/public-dir t)
  (org-publish "org" t)
  (message "HTML build complete: %s" ff/public-dir))

(provide 'ff-publish-locally)
;;; ff-publish-locally.el ends here
