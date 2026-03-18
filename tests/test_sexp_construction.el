;;; test_sexp_construction.el --- ERT tests for daemon sexp builders -*- lexical-binding: t -*-

;;; Commentary:
;;
;; Validates that emcp-stdio--daemon-build-sexp produces valid Elisp
;; s-expressions for each daemon tool.  Tests cover:
;;   - Each builder produces a string that (read ...) can parse
;;   - Special characters in args are properly escaped
;;   - Nil/empty args handled gracefully (no crash, though may produce
;;     runtime errors in the daemon)
;;
;; Usage:
;;   emacs --batch -Q -l src/emcp-stdio.el -l tests/test_sexp_construction.el -f ert-run-tests-batch-and-exit
;;
;; These tests do NOT require a running daemon.  They only test sexp
;; string construction, not evaluation.

;;; Code:

(require 'ert)

;; Load the module under test
(let ((project-dir (file-name-directory
                    (directory-file-name
                     (file-name-directory
                      (or load-file-name buffer-file-name))))))
  (load (expand-file-name "src/emcp-stdio.el" project-dir) nil t))

;;; ---- Helper ----

(defun test-sexp-readable-p (sexp-string)
  "Return non-nil if SEXP-STRING can be parsed by `read'.
Also returns the parsed form."
  (condition-case err
      (progn (read sexp-string) t)
    (error nil)))

(defun test-sexp-read (sexp-string)
  "Parse SEXP-STRING with `read'.  Signal error if unparseable."
  (read sexp-string))

;;; ---- emcp-data-buffer-list (0 args) ----

(ert-deftest test-build-sexp/buffer-list/basic ()
  "buffer-list sexp is parseable."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-buffer-list" nil)))
    (should (stringp sexp))
    (should (test-sexp-readable-p sexp))))

(ert-deftest test-build-sexp/buffer-list/ignores-args ()
  "buffer-list ignores any args passed."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-buffer-list" '("extra"))))
    (should (stringp sexp))
    (should (test-sexp-readable-p sexp))))

;;; ---- emcp-data-buffer-read (1 arg: buffer-name) ----

(ert-deftest test-build-sexp/buffer-read/basic ()
  "buffer-read sexp with simple name is parseable."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-buffer-read" '("*scratch*"))))
    (should (test-sexp-readable-p sexp))
    ;; Verify the buffer name appears in the sexp
    (should (string-match-p "scratch" sexp))))

(ert-deftest test-build-sexp/buffer-read/special-chars ()
  "buffer-read with quotes in buffer name is safely escaped."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-buffer-read"
                                              '("buf\"with\"quotes"))))
    (should (test-sexp-readable-p sexp))
    ;; After reading, the string in the sexp should contain the original quotes
    (let ((form (test-sexp-read sexp)))
      ;; form is (with-current-buffer "buf\"with\"quotes" ...)
      (should (equal (nth 1 form) "buf\"with\"quotes")))))

(ert-deftest test-build-sexp/buffer-read/backslash ()
  "buffer-read with backslashes is safely escaped."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-buffer-read"
                                              '("path\\to\\buf"))))
    (should (test-sexp-readable-p sexp))
    (let ((form (test-sexp-read sexp)))
      (should (equal (nth 1 form) "path\\to\\buf")))))

(ert-deftest test-build-sexp/buffer-read/nil-arg ()
  "buffer-read with nil args produces parseable sexp."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-buffer-read" nil)))
    (should (test-sexp-readable-p sexp))
    ;; (nth 0 nil) -> nil, so %S produces "nil"
    (let ((form (test-sexp-read sexp)))
      (should (eq (nth 1 form) nil)))))

(ert-deftest test-build-sexp/buffer-read/newline-in-name ()
  "buffer-read with newline in buffer name is safely escaped."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-buffer-read"
                                              '("line1\nline2"))))
    (should (test-sexp-readable-p sexp))))

;;; ---- emcp-data-buffer-insert (2 args: buffer-name, text) ----

(ert-deftest test-build-sexp/buffer-insert/basic ()
  "buffer-insert sexp with simple args is parseable."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-buffer-insert"
                                              '("*scratch*" "hello world"))))
    (should (test-sexp-readable-p sexp))))

(ert-deftest test-build-sexp/buffer-insert/text-with-quotes ()
  "buffer-insert with quoted text is safely escaped."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-buffer-insert"
                                              '("buf" "He said \"hello\""))))
    (should (test-sexp-readable-p sexp))))

(ert-deftest test-build-sexp/buffer-insert/multiline-text ()
  "buffer-insert with newlines in text is safely escaped."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-buffer-insert"
                                              '("buf" "line1\nline2\nline3"))))
    (should (test-sexp-readable-p sexp))))

(ert-deftest test-build-sexp/buffer-insert/empty-text ()
  "buffer-insert with empty text is parseable."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-buffer-insert"
                                              '("buf" ""))))
    (should (test-sexp-readable-p sexp))))

(ert-deftest test-build-sexp/buffer-insert/missing-second-arg ()
  "buffer-insert with missing text arg still produces parseable sexp."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-buffer-insert"
                                              '("buf"))))
    (should (test-sexp-readable-p sexp))))

;;; ---- emcp-data-find-file (1 arg: filename) ----

(ert-deftest test-build-sexp/find-file/basic ()
  "find-file sexp with simple path is parseable."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-find-file"
                                              '("/tmp/test.txt"))))
    (should (test-sexp-readable-p sexp))
    (let ((form (test-sexp-read sexp)))
      ;; (buffer-name (find-file-noselect "/tmp/test.txt"))
      (should (eq (car form) 'buffer-name)))))

(ert-deftest test-build-sexp/find-file/path-with-spaces ()
  "find-file with spaces in path is safely escaped."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-find-file"
                                              '("/tmp/my file.txt"))))
    (should (test-sexp-readable-p sexp))
    (let ((form (test-sexp-read sexp)))
      ;; The nested form is (find-file-noselect "/tmp/my file.txt")
      (should (equal (nth 1 (nth 1 form)) "/tmp/my file.txt")))))

(ert-deftest test-build-sexp/find-file/path-with-parens ()
  "find-file with parentheses in path is safely escaped."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-find-file"
                                              '("/tmp/file(1).txt"))))
    (should (test-sexp-readable-p sexp))))

;;; ---- emcp-data-org-headings (1 arg: filename) ----

(ert-deftest test-build-sexp/org-headings/basic ()
  "org-headings sexp is parseable."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-org-headings"
                                              '("/tmp/test.org"))))
    (should (test-sexp-readable-p sexp))
    ;; Should contain require 'org
    (should (string-match-p "require" sexp))))

(ert-deftest test-build-sexp/org-headings/path-with-quotes ()
  "org-headings with quotes in path is safely escaped."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-org-headings"
                                              '("/tmp/\"quoted\".org"))))
    (should (test-sexp-readable-p sexp))))

;;; ---- emcp-data-org-set-todo (3 args: filename, heading, new-state) ----

(ert-deftest test-build-sexp/org-set-todo/basic ()
  "org-set-todo sexp with simple args is parseable."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-org-set-todo"
                                              '("/tmp/test.org" "My Task" "DONE"))))
    (should (test-sexp-readable-p sexp))
    ;; Should contain regexp-quote for safe heading search
    (should (string-match-p "regexp-quote" sexp))
    ;; Should contain save-buffer
    (should (string-match-p "save-buffer" sexp))))

(ert-deftest test-build-sexp/org-set-todo/heading-with-special-chars ()
  "org-set-todo with regex metacharacters in heading is safe."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-org-set-todo"
                                              '("/tmp/test.org"
                                                "Task [1/3] (important)"
                                                "DONE"))))
    (should (test-sexp-readable-p sexp))))

(ert-deftest test-build-sexp/org-set-todo/state-with-spaces ()
  "org-set-todo with spaces in state is parseable."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-org-set-todo"
                                              '("/tmp/test.org"
                                                "Task"
                                                "IN PROGRESS"))))
    (should (test-sexp-readable-p sexp))))

;;; ---- emcp-data-org-table (2 args: filename, table-name) ----

(ert-deftest test-build-sexp/org-table/basic ()
  "org-table sexp is parseable."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-org-table"
                                              '("/tmp/test.org" "#+NAME: data"))))
    (should (test-sexp-readable-p sexp))
    (should (string-match-p "org-table-to-lisp" sexp))))

(ert-deftest test-build-sexp/org-table/name-with-special-chars ()
  "org-table with special chars in table name is safely escaped."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-org-table"
                                              '("/tmp/test.org"
                                                "#+NAME: \"special\" table"))))
    (should (test-sexp-readable-p sexp))))

;;; ---- emcp-data-org-capture (3 args: file, heading, body) ----

(ert-deftest test-build-sexp/org-capture/basic ()
  "org-capture sexp is parseable."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-org-capture"
                                              '("/tmp/test.org"
                                                "Inbox"
                                                "New item to capture"))))
    (should (test-sexp-readable-p sexp))
    ;; Should contain save-buffer (both branches)
    (should (string-match-p "save-buffer" sexp))
    ;; Should contain regexp-quote for heading search
    (should (string-match-p "regexp-quote" sexp))))

(ert-deftest test-build-sexp/org-capture/body-with-org-syntax ()
  "org-capture with org syntax in body is safely escaped."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-org-capture"
                                              '("/tmp/test.org"
                                                "Inbox"
                                                "** Subheading\n- item 1\n- item 2"))))
    (should (test-sexp-readable-p sexp))))

(ert-deftest test-build-sexp/org-capture/body-with-quotes ()
  "org-capture with quotes in body is safely escaped."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-org-capture"
                                              '("/tmp/test.org"
                                                "Inbox"
                                                "He said \"hello\" and left"))))
    (should (test-sexp-readable-p sexp))))

(ert-deftest test-build-sexp/org-capture/heading-with-backslash ()
  "org-capture with backslash in heading is safely escaped."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-org-capture"
                                              '("/tmp/test.org"
                                                "C:\\Users\\Notes"
                                                "body text"))))
    (should (test-sexp-readable-p sexp))))

;;; ---- Unknown tool ----

(ert-deftest test-build-sexp/unknown-tool ()
  "Unknown tool name signals error."
  (should-error
   (emcp-stdio--daemon-build-sexp "emcp-data-nonexistent" '("arg"))
   :type 'error))

;;; ---- Cross-cutting: all builders produce parseable output ----

(ert-deftest test-build-sexp/all-tools-parseable ()
  "Every tool in daemon-tool-defs with :build type produces parseable sexp."
  (dolist (def emcp-stdio--daemon-tool-defs)
    (let ((name (nth 0 def))
          (handler-type (nth 3 def)))
      (when (eq handler-type :build)
        ;; Build args list of appropriate length with placeholder values
        (let* ((sig (nth 1 def))
               ;; Count args by counting words in the sig, excluding parens
               (arg-names (split-string
                           (replace-regexp-in-string "[()]" "" sig)
                           " " t))
               (args (mapcar (lambda (_) "test-value") arg-names)))
          (let ((sexp (emcp-stdio--daemon-build-sexp name args)))
            (should (test-sexp-readable-p sexp))))))))

;;; ---- Edge case: CJK and emoji in args ----

(ert-deftest test-build-sexp/buffer-read/cjk-name ()
  "buffer-read with CJK characters in buffer name is parseable."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-buffer-read"
                                              (list "\u4f60\u597d\u4e16\u754c"))))
    (should (test-sexp-readable-p sexp))))

(ert-deftest test-build-sexp/buffer-insert/emoji-text ()
  "buffer-insert with emoji in text is parseable."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-buffer-insert"
                                              '("buf" "hello \U0001F680 world"))))
    (should (test-sexp-readable-p sexp))))

(ert-deftest test-build-sexp/org-capture/combining-chars ()
  "org-capture with combining characters is parseable."
  (let ((sexp (emcp-stdio--daemon-build-sexp "emcp-data-org-capture"
                                              '("/tmp/test.org"
                                                "Inbox"
                                                "caf\u00e9 na\u00efve r\u00e9sum\u00e9"))))
    (should (test-sexp-readable-p sexp))))

;;; ---- daemon-call routing ----

(ert-deftest test-daemon-call/unknown-tool-signals-error ()
  "daemon-call with unknown tool name signals error."
  (should-error
   (emcp-stdio--daemon-call "emcp-data-nonexistent" '("arg"))
   :type 'error))

(ert-deftest test-daemon-tool-defs/all-have-four-elements ()
  "Every entry in daemon-tool-defs has exactly 4 elements."
  (dolist (def emcp-stdio--daemon-tool-defs)
    (should (= (length def) 4))
    (should (stringp (nth 0 def)))
    (should (stringp (nth 1 def)))
    (should (stringp (nth 2 def)))
    (should (memq (nth 3 def) '(:raw :build)))))

(ert-deftest test-daemon-tool-defs/only-eval-is-raw ()
  "Only emcp-data-eval has :raw handler type."
  (let ((raw-tools (seq-filter (lambda (def) (eq (nth 3 def) :raw))
                               emcp-stdio--daemon-tool-defs)))
    (should (= (length raw-tools) 1))
    (should (string= (nth 0 (car raw-tools)) "emcp-data-eval"))))

(ert-deftest test-daemon-tool-defs/count ()
  "There are exactly 9 daemon tool definitions."
  (should (= (length emcp-stdio--daemon-tool-defs) 9)))

;;; ---- build-daemon-tools MCP schema ----

(ert-deftest test-build-daemon-tools/returns-list ()
  "build-daemon-tools returns a list of alists."
  (let ((tools (emcp-stdio--build-daemon-tools)))
    (should (listp tools))
    (should (= (length tools) 9))))

(ert-deftest test-build-daemon-tools/each-has-name ()
  "Each daemon tool definition has a name field."
  (dolist (tool (emcp-stdio--build-daemon-tools))
    (should (assoc 'name tool))
    (should (stringp (alist-get 'name tool)))))

(ert-deftest test-build-daemon-tools/each-has-schema ()
  "Each daemon tool definition has an inputSchema."
  (dolist (tool (emcp-stdio--build-daemon-tools))
    (let ((schema (alist-get 'inputSchema tool)))
      (should schema)
      (should (string= (alist-get 'type schema) "object")))))

(ert-deftest test-build-daemon-tools/names-match-defs ()
  "Tool names from build-daemon-tools match daemon-tool-defs."
  (let ((built-names (mapcar (lambda (t) (alist-get 'name t))
                             (emcp-stdio--build-daemon-tools)))
        (def-names (mapcar #'car emcp-stdio--daemon-tool-defs)))
    (should (equal built-names def-names))))

(provide 'test_sexp_construction)
;;; test_sexp_construction.el ends here
