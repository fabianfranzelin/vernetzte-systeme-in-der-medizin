#!/usr/bin/emacs -x
;;; serve.el --- Serve docs/public via a local web server -*- lexical-binding: t; -*-
;;; Commentary:
;;  Starts a simple HTTP server on port 8080 serving the docs/public directory.
;;  Usage: emacs -Q --script serve.el
;;; Code:

(require 'simple-httpd nil t)

(unless (featurep 'simple-httpd)
  (require 'package)
  (setq package-user-dir (expand-file-name ".packages-serve" (temporary-file-directory)))
  (setq package-archives '(("melpa" . "https://melpa.org/packages/")))
  (package-initialize)
  (package-refresh-contents)
  (unless (package-installed-p 'simple-httpd)
    (package-install 'simple-httpd))
  (require 'simple-httpd))

(setq httpd-root (expand-file-name "docs/public" default-directory))
(setq httpd-port 8080)
(setq httpd-host "0.0.0.0")

(add-to-list 'httpd-mime-types '("json" . "application/json"))

(let ((kill-cmd (format "fuser -k %d/tcp 2>/dev/null" httpd-port)))
  (shell-command kill-cmd)
  (sleep-for 0.5))

(httpd-start)
(message "Serving docs at http://localhost:%d" httpd-port)
(message "Document root: %s" httpd-root)

(while t
  (sleep-for 1))

(provide 'serve)
;;; serve.el ends here
