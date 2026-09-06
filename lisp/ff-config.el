;;; ff-config.el --- Shared configuration variables -*- lexical-binding: t; -*-
;;; Commentary:
;; Central place for directory paths and user identity used across build modules.
;;; Code:

(defvar ff/user-full-name "Fabian Franzelin"
  "Author name used in exports.")

(defvar ff/user-mail-address "fabian.franzelin@gmail.com"
  "Author email used in exports.")

(defvar ff/repo-root
  (or (locate-dominating-file default-directory ".git")
      default-directory)
  "Repository root directory.")

(defvar ff/base-dir (expand-file-name "docs/content" ff/repo-root)
  "Source directory for org content.")

(defvar ff/public-dir (expand-file-name "docs/public" ff/repo-root)
  "Output directory for published files.")

(defvar ff/copyright-year
  (or (getenv "COPYRIGHT_YEAR")
      (format-time-string "%Y"))
  "Year used in exported footers.")

(provide 'ff-config)
;;; ff-config.el ends here
