;;; etaf-algo-lab-tests.el --- Public workspace acceptance -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Every case drives the mounted application through published Hosts and the
;; documented API only; models, refs and timers stay internal.

;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'subr-x)
(require 'etaf-algo-lab)
(require 'etaf)

(defun etaf-algo-lab-test--text (runtime &optional ref)
  "Read RUNTIME's plain text, optionally only the Host REF."
  (let ((bounds (and ref (etaf-host-ref-bounds runtime ref))))
    (with-current-buffer (etaf-runtime-buffer runtime)
      (buffer-substring-no-properties (if bounds (car bounds) (point-min))
                                      (if bounds (cdr bounds) (point-max))))))

(defun etaf-algo-lab-test--controls (runtime label &optional scope)
  "Return RUNTIME's controls labelled LABEL, optionally inside SCOPE."
  (let ((bounds (and scope (etaf-host-ref-bounds runtime scope))))
    (cl-remove-if-not
     (lambda (entry)
       (and (equal label (plist-get (cdr entry) :aria-label))
            (or (null bounds)
                (let ((position (etaf-host-ref-position runtime (car entry))))
                  (and position (<= (car bounds) position) (< position (cdr bounds)))))))
     (etaf-runtime-host-props-entries runtime))))

(defun etaf-algo-lab-test--choose (runtime field label)
  "Choose the visible LABEL chip inside RUNTIME's FIELD."
  (let ((controls (etaf-algo-lab-test--controls runtime label field)))
    (should (= 1 (length controls)))
    (etaf-dispatch-event runtime (caar controls) 'press)))

(defun etaf-algo-lab-test--press (runtime ref)
  "Press RUNTIME's public REF."
  (etaf-dispatch-event runtime ref 'press))

(defun etaf-algo-lab-test--finished-p (runtime)
  "Return non-nil when RUNTIME's laboratory reached a terminal state."
  (string-match-p "已找到\\|不可达\\|已完成"
                  (etaf-algo-lab-test--text runtime 'al-status)))

(defun etaf-algo-lab-test--finish (runtime &optional limit)
  "Fast-forward RUNTIME to its terminal state without animation.
LIMIT is accepted for call-site readability and bounds a stepping fallback."
  (ignore limit)
  (etaf-algo-lab-test--press runtime 'al-finish)
  (should (etaf-algo-lab-test--finished-p runtime)))

(defun etaf-algo-lab-test--counter (runtime label)
  "Read RUNTIME's displayed integer named LABEL."
  (let ((text (etaf-algo-lab-test--text runtime)))
    (should (string-match (concat label " +\\([0-9]+\\)") text))
    (string-to-number (match-string 1 text))))

(defun etaf-algo-lab-test--numbers (runtime ref)
  "Read RUNTIME's space-separated numbers in REF."
  (mapcar #'string-to-number
          (split-string (string-trim (etaf-algo-lab-test--text runtime ref)) " +")))

(cl-defmacro etaf-algo-lab-test--with ((buffer runtime) lab &rest body)
  "Run BODY in a fresh workspace BUFFER playing LAB."
  (declare (indent 2) (debug (form form form body)))
  `(let ((,buffer (generate-new-buffer " *algo-lab-acceptance*")))
     (unwind-protect
         (progn
           (etaf-algo-lab-open ,lab (buffer-name ,buffer))
           (let ((,runtime (etaf-runtime-for-buffer ,buffer))) ,@body))
       (etaf-algo-lab-close (buffer-name ,buffer))
       (when (buffer-live-p ,buffer) (kill-buffer ,buffer)))))

(ert-deftest etaf-algo-lab-tests-labs-and-lifecycle ()
  "The catalog lists both laboratories and closing releases the workspace."
  (should (equal (etaf-algo-lab-labs) '(pathfinding sorting)))
  (etaf-algo-lab-test--with (buffer runtime) nil
    (should runtime)
    (should (etaf-runtime-mounted-p runtime))
    (should (string-match-p "寻路实验台" (etaf-algo-lab-test--text runtime))))
  (should-not (etaf-runtime-for-buffer "*算法实验室*")))

(ert-deftest etaf-algo-lab-tests-player-controls-publish-status ()
  "Play, pause, single step and reset publish their visible state."
  (etaf-algo-lab-test--with (buffer runtime) 'pathfinding
    (ignore buffer)
    (should (string-match-p "准备就绪" (etaf-algo-lab-test--text runtime 'al-status)))
    (etaf-algo-lab-test--press runtime 'al-start)
    (should (string-match-p "运行中" (etaf-algo-lab-test--text runtime 'al-status)))
    (etaf-algo-lab-test--press runtime 'al-pause)
    (should (string-match-p "已暂停" (etaf-algo-lab-test--text runtime 'al-status)))
    (etaf-algo-lab-test--press runtime 'al-step)
    (should (= 1 (etaf-algo-lab-test--counter runtime "探索")))
    (etaf-algo-lab-test--press runtime 'al-reset)
    (should (string-match-p "准备就绪" (etaf-algo-lab-test--text runtime 'al-status)))
    (should (= 0 (etaf-algo-lab-test--counter runtime "探索")))))

(ert-deftest etaf-algo-lab-tests-pathfinding-finds-shortest-route ()
  "A*, Dijkstra and BFS all find the same five-step detour."
  (etaf-algo-lab-test--with (buffer runtime) 'pathfinding
    (ignore buffer)
    (etaf-algo-lab-test--press runtime 'pf-clear)
    (etaf-algo-lab-test--choose runtime 'pf-tool "终点")
    (etaf-algo-lab-test--press runtime 'pf-cell-2-5)
    (etaf-algo-lab-test--choose runtime 'pf-tool "障碍")
    (etaf-algo-lab-test--press runtime 'pf-cell-2-3)
    (dolist (algorithm '("A*" "Dijkstra" "BFS"))
      (etaf-algo-lab-test--choose runtime 'pf-algorithm algorithm)
      (etaf-algo-lab-test--finish runtime)
      (should (string-match-p "已完成" (etaf-algo-lab-test--text runtime 'al-status)))
      (should (string-match-p "完成" (etaf-algo-lab-test--text runtime 'al-narration)))
      (should (string-match-p "路径 +5 步" (etaf-algo-lab-test--text runtime 'al-counters))))))

(ert-deftest etaf-algo-lab-tests-pathfinding-copy-explains-phases-and-remembers ()
  "The intro, narration and memory line teach without jargon."
  (etaf-algo-lab-test--with (buffer runtime) 'pathfinding
    (ignore buffer)
    (let ((intro (etaf-algo-lab-test--text runtime)))
      (should (string-match-p "候选" intro))
      (should (string-match-p "走过的" intro))
      (should (string-match-p "Dijkstra" intro)))
    (should (string-match-p "单步" (etaf-algo-lab-test--text runtime 'al-narration)))
    (etaf-algo-lab-test--finish runtime)
    (should (string-match-p "完成" (etaf-algo-lab-test--text runtime 'al-narration)))
    (should (string-match-p "A\\* [0-9]+ 格" (etaf-algo-lab-test--text runtime 'al-memory)))))

(ert-deftest etaf-algo-lab-tests-pathfinding-unreachable-explains-why ()
  "An enclosed start terminates with plain-language advice."
  (etaf-algo-lab-test--with (buffer runtime) 'pathfinding
    (ignore buffer)
    (etaf-algo-lab-test--press runtime 'pf-clear)
    (dolist (ref '(pf-cell-2-1 pf-cell-2-3 pf-cell-1-2 pf-cell-3-2))
      (etaf-algo-lab-test--press runtime ref))
    (etaf-algo-lab-test--finish runtime)
    (should (string-match-p "已完成" (etaf-algo-lab-test--text runtime 'al-status)))
    (should (string-match-p "墙" (etaf-algo-lab-test--text runtime 'al-narration)))
    (should (string-match-p "路径 +-- 步" (etaf-algo-lab-test--text runtime 'al-counters)))))

(ert-deftest etaf-algo-lab-tests-compare-is-headless-and-explains-cost ()
  "Batch comparison reports every algorithm without touching the live run."
  (etaf-algo-lab-test--with (buffer runtime) 'pathfinding
    (ignore buffer)
    (etaf-algo-lab-test--press runtime 'al-compare)
    (let ((research (etaf-algo-lab-test--text runtime 'al-research)))
      (dolist (name '("A*" "Dijkstra" "BFS"))
        (should (string-match-p (regexp-quote name) research)))
      (should (string-match-p "探索 [0-9]+ 格" research)))
    (should (= 0 (etaf-algo-lab-test--counter runtime "探索")))))

(ert-deftest etaf-algo-lab-tests-sorting-finishes-sorted-for-every-algorithm ()
  "All four sorts end with ascending data and non-zero counters."
  (etaf-algo-lab-test--with (buffer runtime) 'sorting
    (ignore buffer)
    (dolist (algorithm '("冒泡" "插入" "选择" "归并"))
      (etaf-algo-lab-test--choose runtime 'sort-algorithm algorithm)
      (etaf-algo-lab-test--finish runtime)
      (let ((numbers (etaf-algo-lab-test--numbers runtime 'sort-values)))
        (should (equal numbers (sort (copy-sequence numbers) #'<)))
        (should (= 14 (length numbers))))
      (should (> (etaf-algo-lab-test--counter runtime "比较") 0))
      (etaf-algo-lab-test--press runtime 'al-reset))))

(ert-deftest etaf-algo-lab-tests-sorting-compare-ranks-the-algorithms ()
  "The comparison runs all four sorts and merge performs fewer comparisons."
  (etaf-algo-lab-test--with (buffer runtime) 'sorting
    (ignore buffer)
    (etaf-algo-lab-test--press runtime 'al-compare)
    (let ((research (etaf-algo-lab-test--text runtime 'al-research)))
      (dolist (name '("冒泡" "插入" "选择" "归并"))
        (should (string-match-p (format "%s：比较 [0-9]+ 次" name) research)))
      (let ((merge (progn (string-match "归并：比较 \\([0-9]+\\)" research)
                          (string-to-number (match-string 1 research))))
            (bubble (progn (string-match "冒泡：比较 \\([0-9]+\\)" research)
                           (string-to-number (match-string 1 research)))))
        (should (< merge bubble))))))

(ert-deftest etaf-algo-lab-tests-switching-laboratory-disposes-old-session ()
  "Switching laboratories replaces the player and its playing state."
  (etaf-algo-lab-test--with (buffer runtime) 'pathfinding
    (ignore buffer)
    (etaf-algo-lab-test--press runtime 'al-start)
    (should (string-match-p "运行中" (etaf-algo-lab-test--text runtime 'al-status)))
    (etaf-algo-lab-test--choose runtime 'al-catalog "排序实验台")
    (should (string-match-p "已完成\\|准备就绪" (etaf-algo-lab-test--text runtime 'al-status)))
    (should (etaf-host-ref-bounds runtime 'sort-values))
    (should-not (etaf-runtime-host-props-for runtime 'pf-cell-0-0))
    (etaf-algo-lab-test--press runtime 'al-step)
    (should (> (etaf-algo-lab-test--counter runtime "比较") 0))))

(provide 'etaf-algo-lab-tests)
;;; etaf-algo-lab-tests.el ends here
