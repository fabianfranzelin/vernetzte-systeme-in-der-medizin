#!/usr/bin/emacs -x
;;; build.el --- Build org content into HTML + reveal.js -*- lexical-binding: t; -*-
;;; Commentary:
;; Entrypoint script.  Loads modules from lisp/ and runs the build.
;;; Code:

(add-to-list 'load-path (expand-file-name "lisp" default-directory))

(require 'ff-packages)
(require 'ff-config)
(require 'ff-org-config)
(require 'ff-html-theme)
(require 'ff-presentations)
(require 'ff-publish-locally)

(ff/publish-locally)

;;; build.el ends here
