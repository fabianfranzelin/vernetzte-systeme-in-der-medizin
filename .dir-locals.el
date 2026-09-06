;;; Directory Local Variables for vernetzte-systeme-in-der-medizin
;;;
;;; Provides `run-command' recipes for the trial-lecture workflow:
;;;   build slides + docs, serve them, run the demo, regenerate data,
;;;   build the Docker image, publish to gh-pages.

((nil . ((compile-command . "make html")
         (eval . (pyvenv-deactivate))
         ;; Scope org-roam to this project's notes only:
         ;; retarget `org-roam-directory' (and dailies + db) to
         ;; docs/content/talks/roam via `ff/org-set-roam-directory'
         ;; (see ff-organize-life.el), so `org-roam-node-find' only
         ;; shows one directory at a time.
         (eval . (defun ff/scope-org-roam ()
                   (when-let* ((root (locate-dominating-file
                                      default-directory ".git"))
                               (roam (expand-file-name
                                      "docs/content/talks/roam" root)))
                     (with-eval-after-load 'org-roam
                       (ff/org-set-roam-directory roam)))))
         (eval . (ff/scope-org-roam))
         (eval . (defun run-command-recipe-vsm/local ()
                   (when-let* ((project-dir (locate-dominating-file
                                             default-directory ".git"))
                               (demo-dir (expand-file-name "demo" project-dir)))
                     (list
                      ;; ---------------- documentation & slides ----------------
                      (list :command-name "sh:build html (slides + docs)"
                            :command-line "make html"
                            :working-dir project-dir)
                      (list :command-name "sh:build glossar (Handout PDF)"
                            :command-line "make glossar"
                            :working-dir project-dir)
                      (list :command-name "sh:build all (html + glossar)"
                            :command-line "make all"
                            :working-dir project-dir)
                      (list :command-name "sh:serve on :8080"
                            :command-line "make serve"
                            :working-dir project-dir)
                      (list :command-name "sh:build and serve"
                            :command-line "make html && make serve"
                            :working-dir project-dir)
                      (list :command-name "sh:clean build artifacts"
                            :command-line "make clean"
                            :working-dir project-dir)

                      ;; ---------------- demo (SDC provider + consumer) ----------------
                      (list :command-name "sh:demo (provider + consumer + dashboard)"
                            :command-line "make demo"
                            :working-dir demo-dir)
                      (list :command-name "sh:demo provider only"
                            :command-line "make provider"
                            :working-dir demo-dir)
                      (list :command-name "sh:demo consumer only"
                            :command-line "make consumer"
                            :working-dir demo-dir)
                      (list :command-name "sh:regenerate synthetic gait csv"
                            :command-line "make data"
                            :working-dir demo-dir)
                      (list :command-name "sh:uv sync demo venv"
                            :command-line "uv sync"
                            :working-dir demo-dir)
                      (list :command-name "sh:clean demo (venv + csv + pid)"
                            :command-line "make clean"
                            :working-dir demo-dir)

                      ;; ---------------- Docker image ----------------
                      (list :command-name "sh:docker build image"
                            :command-line "make image"
                            :working-dir project-dir)
                      (list :command-name "sh:docker shell"
                            :command-line "make shell"
                            :working-dir project-dir)

                      ;; ---------------- publishing ----------------
                      (list :command-name "sh:git push (triggers CI + gh-pages)"
                            :command-line "git push"
                            :working-dir project-dir)))))
         (run-command-recipes . (list run-command-recipe-vsm/local))))
 (org-mode . ((eval . (progn
                        (let ((default-directory
                               (locate-dominating-file default-directory ".git")))
                          (add-to-list 'load-path
                                       (expand-file-name "lisp" default-directory))
                          (require 'ff-packages)
                          (require 'ff-config)
                          (require 'ff-org-config)
                          (require 'ff-html-theme)
                          (require 'ff-presentations)
                          (require 'ff-publish-locally)))))))
