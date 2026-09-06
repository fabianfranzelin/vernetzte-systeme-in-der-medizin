;;; ff-packages.el --- Package management and dependency installation -*- lexical-binding: t; -*-
;;; Commentary:
;; Sets up straight.el and installs required dependencies.
;;; Code:

(customize-set-variable 'straight-check-for-modifications nil)
(customize-set-variable 'straight-repository-branch "develop")
(customize-set-variable 'straight-repository-user "radian-software")

(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el" user-emacs-directory))
      (bootstrap-version 5))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

(straight-use-package 'htmlize)
(straight-use-package '(org :type built-in))
(straight-use-package 'ox-reveal)

(provide 'ff-packages)
;;; ff-packages.el ends here
