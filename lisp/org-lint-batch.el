;;; org-lint-batch.el --- Batch org-mode linter for CI -*- lexical-binding: t -*-
;;
;; Usage:
;;   emacs --batch -Q -l lisp/org-lint-batch.el -f emcp-org-lint-batch
;;
;; Checks:
;;   1. org-lint (built-in org 9+ syntax checks)
;;   2. Broken [[file:...]] links (target must exist on disk)
;;   3. Table alignment (org tables must parse correctly)
;;   4. Missing #+title: header
;;   5. Unmatched #+begin_src / #+end_src blocks
;;
;; Output: FILE:LINE: SEVERITY: MESSAGE
;; Exit 0 if no errors (warnings ok), exit 1 if errors found.

(require 'org)
(require 'ol)

;; org-lint is available as a separate feature in org 9+
(require 'org-lint nil t)

;;; --- state ---

(defvar emcp-lint-warnings 0 "Count of warnings found.")
(defvar emcp-lint-errors 0 "Count of errors found.")
(defvar emcp-lint-files 0 "Count of files checked.")

;;; --- output helpers ---

(defun emcp-lint-report (file line severity msg)
  "Print a lint finding in FILE:LINE: SEVERITY: MSG format."
  (message "%s:%d: %s: %s" file line severity msg)
  (pcase severity
    ("error" (setq emcp-lint-errors (1+ emcp-lint-errors)))
    ("warning" (setq emcp-lint-warnings (1+ emcp-lint-warnings)))))

;;; --- individual checks ---

(defun emcp-lint-check-org-lint (file)
  "Run org-lint on FILE and report findings."
  (when (fboundp 'org-lint)
    (with-current-buffer (find-file-noselect file t)
      (condition-case err
          (let ((results (org-lint)))
            ;; org-lint returns tabulated-list entries.
            ;; Each entry is (ID [LINE TRUST MESSAGE CHECKER-STRUCT]).
            ;; ID is an integer, the vector contains display columns.
            (dolist (entry results)
              (let (line msg)
                (cond
                 ;; Standard form: (ID . [LINE TRUST MESSAGE ...])
                 ((and (listp entry)
                       (vectorp (cdr entry))
                       (> (length (cdr entry)) 2))
                  (let ((vec (cdr entry)))
                    (setq line (string-to-number (aref vec 0))
                          msg (aref vec 2))))
                 ;; Tabulated-list form: (ID [LINE TRUST MESSAGE ...])
                 ((and (listp entry)
                       (vectorp (cadr entry))
                       (> (length (cadr entry)) 2))
                  (let ((vec (cadr entry)))
                    (setq line (string-to-number (aref vec 0))
                          msg (aref vec 2))))
                 ;; Flat vector form
                 ((and (vectorp entry) (> (length entry) 2))
                  (setq line (string-to-number (aref entry 0))
                        msg (aref entry 2)))
                 ;; Fallback: print what we got
                 (t
                  (setq line 0
                        msg (format "%S" entry))))
                (when msg
                  (emcp-lint-report file (or line 0) "warning"
                                   (format "org-lint: %s" msg))))))
        (error
         (emcp-lint-report file 0 "warning"
                          (format "org-lint failed: %s" (error-message-string err)))))
      (kill-buffer))))

(defun emcp-lint-check-title (file)
  "Check that FILE has a #+title: keyword."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (unless (re-search-forward "^#\\+title:" nil t)
      (emcp-lint-report file 1 "error" "missing #+title: header"))))

(defun emcp-lint-check-src-blocks (file)
  "Check that every #+begin_src has a matching #+end_src in FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((depth 0)
          (last-begin-line 0))
      ;; Scan for begin/end pairs
      (while (re-search-forward
              "^[ \t]*#\\+\\(begin_src\\|end_src\\)" nil t)
        (let ((kind (match-string 1))
              (line (line-number-at-pos (match-beginning 0))))
          (if (string-equal-ignore-case kind "begin_src")
              (progn
                (setq depth (1+ depth))
                (setq last-begin-line line))
            ;; end_src
            (if (= depth 0)
                (emcp-lint-report file line "error"
                                 "#+end_src without matching #+begin_src")
              (setq depth (1- depth))))))
      (when (> depth 0)
        (emcp-lint-report file last-begin-line "error"
                         (format "#+begin_src without matching #+end_src (%d unclosed)" depth))))))

(defun emcp-lint-check-file-links (file)
  "Check that all [[file:...]] links in FILE point to existing targets."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((dir (file-name-directory (expand-file-name file))))
      (goto-char (point-min))
      (while (re-search-forward "\\[\\[file:\\([^]]*\\)\\]" nil t)
        (let* ((raw-target (match-string 1))
               ;; Strip any ::line-number or search string suffix
               (target (if (string-match "::" raw-target)
                           (substring raw-target 0 (match-beginning 0))
                         raw-target))
               (line (line-number-at-pos (match-beginning 0)))
               (abs-target (expand-file-name target dir)))
          (unless (file-exists-p abs-target)
            (emcp-lint-report file line "error"
                             (format "broken file link: %s" raw-target))))))))

(defun emcp-lint-check-tables (file)
  "Check that org tables in FILE parse without error."
  (with-current-buffer (find-file-noselect file t)
    (condition-case err
        (org-element-map (org-element-parse-buffer) 'table
          (lambda (tbl)
            ;; If we can iterate the table, it parsed OK.
            ;; Check for obviously broken alignment by looking for
            ;; rows that don't start with |
            (let ((begin (org-element-property :begin tbl))
                  (end (org-element-property :end tbl)))
              (save-excursion
                (goto-char begin)
                (while (< (point) end)
                  (let ((content (buffer-substring-no-properties
                                  (line-beginning-position)
                                  (line-end-position))))
                    (when (and (not (string-empty-p (string-trim content)))
                               (not (string-prefix-p "|" (string-trim-left content)))
                               (not (string-prefix-p "+" (string-trim-left content)))
                               (not (string-prefix-p "#" (string-trim-left content))))
                      (emcp-lint-report file (line-number-at-pos) "warning"
                                       (format "table row not starting with |: %s"
                                               (string-trim content)))))
                  (forward-line 1))))))
      (error
       (emcp-lint-report file 0 "warning"
                        (format "table parse error: %s" (error-message-string err)))))
    (kill-buffer)))

;;; --- file discovery ---

(defun emcp-lint-find-org-files (root)
  "Find all .org files under ROOT, skipping .claude/ and .venv/ directories."
  (let ((files nil))
    (dolist (f (directory-files-recursively root "\\.org\\'"))
      (let ((rel (file-relative-name f root)))
        (unless (or (string-prefix-p ".claude/" rel)
                    (string-prefix-p ".venv/" rel)
                    (string-prefix-p ".git/" rel))
          (push f files))))
    (nreverse files)))

;;; --- main entry point ---

(defun emcp-org-lint-batch ()
  "Lint all org files in the project. For use with emacs --batch."
  (let* ((root (or (getenv "PROJECT_ROOT")
                   default-directory))
         (files (emcp-lint-find-org-files root)))
    (if (null files)
        (progn
          (message "emcp-org-lint: no .org files found in %s" root)
          (kill-emacs 0)))
    (dolist (file files)
      (setq emcp-lint-files (1+ emcp-lint-files))
      (message "--- checking %s ---" (file-relative-name file root))
      (emcp-lint-check-title file)
      (emcp-lint-check-src-blocks file)
      (emcp-lint-check-file-links file)
      (emcp-lint-check-tables file)
      ;; org-lint requires full org-mode setup, run it if available
      (when (fboundp 'org-lint)
        (emcp-lint-check-org-lint file)))
    ;; Summary
    (message "")
    (message "=== org-lint summary ===")
    (message "  files checked: %d" emcp-lint-files)
    (message "  warnings:      %d" emcp-lint-warnings)
    (message "  errors:        %d" emcp-lint-errors)
    (if (> emcp-lint-errors 0)
        (progn
          (message "  result:        FAIL")
          (kill-emacs 1))
      (message "  result:        PASS")
      (kill-emacs 0))))

(provide 'org-lint-batch)
;;; org-lint-batch.el ends here
