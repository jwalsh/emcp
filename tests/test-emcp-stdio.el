;;; test-emcp-stdio.el --- ERT tests for emcp-stdio -*- lexical-binding: t -*-

;;; Commentary:
;;
;; Comprehensive test suite for the pure-Elisp MCP server.
;; Run with:
;;   emacs --batch -Q -l src/emcp-stdio.el -l tests/test-emcp-stdio.el \
;;         -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
;; emcp-stdio must be loaded before this file (via -l src/emcp-stdio.el)

;;; ---- Helper: capture stdout from emcp-stdio--send ----

(defun test-emcp--capture-send (alist)
  "Call `emcp-stdio--send' with ALIST, return the string that would go to stdout."
  (with-temp-buffer
    (let ((standard-output (current-buffer)))
      (emcp-stdio--send alist)
      (buffer-string))))

;;; ---- I/O layer tests ----

(ert-deftest emcp-test-send-produces-valid-json ()
  "emcp-stdio--send output is valid JSON followed by newline."
  (let ((output (test-emcp--capture-send '((test . "value") (num . 42)))))
    ;; Must end with newline
    (should (string-suffix-p "\n" output))
    ;; Must be parseable JSON
    (let ((parsed (json-parse-string (string-trim output) :object-type 'alist)))
      (should (equal (alist-get 'test parsed) "value"))
      (should (equal (alist-get 'num parsed) 42)))))

(ert-deftest emcp-test-send-handles-unicode ()
  "Non-ASCII survives json-serialize -> decode-coding-string -> princ."
  (let ((output (test-emcp--capture-send '((text . "hello")))))
    (let ((parsed (json-parse-string (string-trim output) :object-type 'alist)))
      (should (equal (alist-get 'text parsed) "hello"))))
  ;; CJK characters
  (let ((output (test-emcp--capture-send '((text . "\u6F22\u5B57")))))
    (let ((parsed (json-parse-string (string-trim output) :object-type 'alist)))
      (should (equal (alist-get 'text parsed) "\u6F22\u5B57"))))
  ;; Emoji
  (let ((output (test-emcp--capture-send '((text . "\U0001F600")))))
    (let ((parsed (json-parse-string (string-trim output) :object-type 'alist)))
      (should (equal (alist-get 'text parsed) "\U0001F600")))))

(ert-deftest emcp-test-respond-structure ()
  "Response has jsonrpc, id, and result fields."
  (let* ((output (with-temp-buffer
                   (let ((standard-output (current-buffer)))
                     (emcp-stdio--respond 1 '((foo . "bar")))
                     (buffer-string))))
         (parsed (json-parse-string (string-trim output) :object-type 'alist)))
    (should (equal (alist-get 'jsonrpc parsed) "2.0"))
    (should (equal (alist-get 'id parsed) 1))
    (should (alist-get 'result parsed))
    (should (equal (alist-get 'foo (alist-get 'result parsed)) "bar"))))

(ert-deftest emcp-test-respond-error-structure ()
  "Error response has jsonrpc, id, and error.code + error.message."
  (let* ((output (with-temp-buffer
                   (let ((standard-output (current-buffer)))
                     (emcp-stdio--respond-error 99 -32601 "Method not found")
                     (buffer-string))))
         (parsed (json-parse-string (string-trim output) :object-type 'alist)))
    (should (equal (alist-get 'jsonrpc parsed) "2.0"))
    (should (equal (alist-get 'id parsed) 99))
    (let ((err (alist-get 'error parsed)))
      (should err)
      (should (equal (alist-get 'code err) -32601))
      (should (equal (alist-get 'message err) "Method not found")))))

;;; ---- Tool collection tests ----

(ert-deftest emcp-test-collect-tools-nonempty ()
  "collect-tools returns a non-empty vector."
  (let ((tools (emcp-stdio--collect-tools)))
    (should (vectorp tools))
    (should (> (length tools) 0))))

(ert-deftest emcp-test-tool-schema-valid ()
  "Every tool has name, description, inputSchema with required fields."
  (let ((tools (emcp-stdio--collect-tools)))
    (dotimes (i (min 50 (length tools)))  ;; check first 50 to keep test fast
      (let ((tool (aref tools i)))
        (should (stringp (alist-get 'name tool)))
        (should (stringp (alist-get 'description tool)))
        (let ((schema (alist-get 'inputSchema tool)))
          (should schema)
          (should (equal (alist-get 'type schema) "object"))
          (should (alist-get 'properties schema))
          (should (alist-get 'required schema)))))))

(ert-deftest emcp-test-no-internal-tools-exposed ()
  "No tool name starts with emcp-stdio-."
  (let ((tools (emcp-stdio--collect-tools)))
    (dotimes (i (length tools))
      (let ((name (alist-get 'name (aref tools i))))
        (should-not (string-prefix-p "emcp-stdio-" name))))))

(ert-deftest emcp-test-description-length ()
  "All descriptions are <= 500 chars."
  (let ((tools (emcp-stdio--collect-tools)))
    (dotimes (i (length tools))
      (let ((desc (alist-get 'description (aref tools i))))
        (should (<= (length desc) 500))))))

(ert-deftest emcp-test-text-consumer-heuristic ()
  "Known text functions pass the filter; known non-text functions don't."
  ;; These should pass the text-consumer heuristic (arglist contains
  ;; string/buffer/object/text keywords)
  (should (emcp-stdio--text-consumer-p 'string-trim))
  (should (emcp-stdio--text-consumer-p 'concat))
  (should (emcp-stdio--text-consumer-p 'substring))
  ;; These should NOT pass (numeric/no-string args)
  (should-not (emcp-stdio--text-consumer-p '+))
  (should-not (emcp-stdio--text-consumer-p 'car)))

;;; ---- Dispatch tests ----

(ert-deftest emcp-test-dispatch-initialize ()
  "Initialize returns protocolVersion, capabilities, serverInfo."
  ;; Ensure tool cache is populated
  (unless emcp-stdio--tools-cache
    (setq emcp-stdio--tools-cache (emcp-stdio--collect-tools)))
  (let* ((output (with-temp-buffer
                   (let ((standard-output (current-buffer)))
                     (emcp-stdio--dispatch
                      '((jsonrpc . "2.0") (id . 1) (method . "initialize")
                        (params . ((protocolVersion . "2024-11-05")))))
                     (buffer-string))))
         (parsed (json-parse-string (string-trim output) :object-type 'alist))
         (result (alist-get 'result parsed)))
    (should (equal (alist-get 'protocolVersion result) "2024-11-05"))
    (should (alist-get 'capabilities result))
    (let ((info (alist-get 'serverInfo result)))
      (should info)
      (should (stringp (alist-get 'name info)))
      (should (stringp (alist-get 'version info))))))

(ert-deftest emcp-test-dispatch-notification-silent ()
  "Notifications (no id) produce no output."
  (unless emcp-stdio--tools-cache
    (setq emcp-stdio--tools-cache (emcp-stdio--collect-tools)))
  (let ((output (with-temp-buffer
                  (let ((standard-output (current-buffer)))
                    (emcp-stdio--dispatch
                     '((jsonrpc . "2.0") (method . "notifications/initialized")))
                    (buffer-string)))))
    (should (string-empty-p output))))

(ert-deftest emcp-test-dispatch-unknown-method ()
  "Unknown method returns -32601 error."
  (unless emcp-stdio--tools-cache
    (setq emcp-stdio--tools-cache (emcp-stdio--collect-tools)))
  (let* ((output (with-temp-buffer
                   (let ((standard-output (current-buffer)))
                     (emcp-stdio--dispatch
                      '((jsonrpc . "2.0") (id . 7) (method . "nonexistent/method")))
                     (buffer-string))))
         (parsed (json-parse-string (string-trim output) :object-type 'alist))
         (err (alist-get 'error parsed)))
    (should err)
    (should (equal (alist-get 'code err) -32601))))

(ert-deftest emcp-test-dispatch-ping ()
  "Ping returns empty object, not an error."
  (unless emcp-stdio--tools-cache
    (setq emcp-stdio--tools-cache (emcp-stdio--collect-tools)))
  (let* ((output (with-temp-buffer
                   (let ((standard-output (current-buffer)))
                     (emcp-stdio--dispatch
                      '((jsonrpc . "2.0") (id . 2) (method . "ping")))
                     (buffer-string))))
         (parsed (json-parse-string (string-trim output) :object-type 'alist)))
    ;; Must have jsonrpc and id
    (should (equal (alist-get 'jsonrpc parsed) "2.0"))
    (should (equal (alist-get 'id parsed) 2))
    ;; Must NOT have an error field
    (should-not (alist-get 'error parsed))
    ;; The result key must be present in the raw JSON (even if {} parses to nil as alist).
    ;; Verify by checking raw output contains "result"
    (should (string-match-p "\"result\"" output))))

(ert-deftest emcp-test-tools-list ()
  "tools/list returns a result with a tools array."
  (unless emcp-stdio--tools-cache
    (setq emcp-stdio--tools-cache (emcp-stdio--collect-tools)))
  (let* ((output (with-temp-buffer
                   (let ((standard-output (current-buffer)))
                     (emcp-stdio--dispatch
                      '((jsonrpc . "2.0") (id . 3) (method . "tools/list")))
                     (buffer-string))))
         (parsed (json-parse-string (string-trim output) :object-type 'alist))
         (result (alist-get 'result parsed))
         (tools (alist-get 'tools result)))
    (should tools)
    (should (> (length tools) 0))))

(ert-deftest emcp-test-tools-call-local ()
  "tools/call with string-trim returns trimmed string."
  (unless emcp-stdio--tools-cache
    (setq emcp-stdio--tools-cache (emcp-stdio--collect-tools)))
  (let* ((output (with-temp-buffer
                   (let ((standard-output (current-buffer)))
                     (emcp-stdio--dispatch
                      `((jsonrpc . "2.0") (id . 4) (method . "tools/call")
                        (params . ((name . "string-trim")
                                   (arguments . ((args . ["  hello  "])))))))
                     (buffer-string))))
         (parsed (json-parse-string (string-trim output) :object-type 'alist))
         (result (alist-get 'result parsed))
         (content (alist-get 'content result)))
    (should content)
    (should (> (length content) 0))
    (let ((text (alist-get 'text (aref content 0))))
      (should (equal text "hello")))))

(ert-deftest emcp-test-tools-call-unknown ()
  "tools/call with nonexistent function returns error in content."
  (unless emcp-stdio--tools-cache
    (setq emcp-stdio--tools-cache (emcp-stdio--collect-tools)))
  (let* ((output (with-temp-buffer
                   (let ((standard-output (current-buffer)))
                     (emcp-stdio--dispatch
                      `((jsonrpc . "2.0") (id . 5) (method . "tools/call")
                        (params . ((name . "absolutely-no-such-function-xyz")
                                   (arguments . ((args . [])))))))
                     (buffer-string))))
         (parsed (json-parse-string (string-trim output) :object-type 'alist))
         (result (alist-get 'result parsed))
         (content (alist-get 'content result)))
    (should content)
    (let ((text (alist-get 'text (aref content 0))))
      (should (string-match-p "error" text)))))

(ert-deftest emcp-test-tools-call-unicode ()
  "tools/call preserves non-ASCII through the full pipeline."
  (unless emcp-stdio--tools-cache
    (setq emcp-stdio--tools-cache (emcp-stdio--collect-tools)))
  (let* ((output (with-temp-buffer
                   (let ((standard-output (current-buffer)))
                     (emcp-stdio--dispatch
                      `((jsonrpc . "2.0") (id . 6) (method . "tools/call")
                        (params . ((name . "upcase")
                                   (arguments . ((args . ["\u00e9\u00e0\u00fc"])))))))
                     (buffer-string))))
         (parsed (json-parse-string (string-trim output) :object-type 'alist))
         (result (alist-get 'result parsed))
         (content (alist-get 'content result)))
    (should content)
    (let ((text (alist-get 'text (aref content 0))))
      (should (equal text "\u00c9\u00c0\u00dc")))))

;;; ---- Build-tool shape tests ----

(ert-deftest emcp-test-build-tool-shape ()
  "emcp-stdio--build-tool returns well-formed alist for a known function."
  (let ((tool (emcp-stdio--build-tool 'concat)))
    (should (equal (alist-get 'name tool) "concat"))
    (should (stringp (alist-get 'description tool)))
    (let ((schema (alist-get 'inputSchema tool)))
      (should (equal (alist-get 'type schema) "object"))
      (let ((props (alist-get 'properties schema)))
        (should (alist-get 'args props))
        (let ((args-schema (alist-get 'args props)))
          (should (equal (alist-get 'type args-schema) "array")))))))

;;; ---- Daemon tool definitions ----

(ert-deftest emcp-test-daemon-tool-defs-well-formed ()
  "Each daemon tool definition has 4 elements: name, arglist, doc, handler-type."
  (dolist (def emcp-stdio--daemon-tool-defs)
    (should (= (length def) 4))
    (should (stringp (nth 0 def)))
    (should (stringp (nth 1 def)))
    (should (stringp (nth 2 def)))
    (should (memq (nth 3 def) '(:raw :build)))))

(ert-deftest emcp-test-build-daemon-tools-shape ()
  "emcp-stdio--build-daemon-tools returns well-formed tool definitions."
  (let ((tools (emcp-stdio--build-daemon-tools)))
    (should (listp tools))
    (should (> (length tools) 0))
    (dolist (tool tools)
      (should (stringp (alist-get 'name tool)))
      (should (string-prefix-p "emcp-data-" (alist-get 'name tool)))
      (should (stringp (alist-get 'description tool)))
      (should (alist-get 'inputSchema tool)))))

(provide 'test-emcp-stdio)
;;; test-emcp-stdio.el ends here
