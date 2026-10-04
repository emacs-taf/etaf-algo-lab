;;; etaf-algo-lab-gui-scenarios.el --- Workspace GUI acceptance -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; One ordered scenario for the maintained workspace.  It drives real focus and
;; keys through the command loop, settles on visible text, and leaves every
;; screenshot in the shared verifier's evidence directory.

;;; Code:
(require 'cl-lib)
(require 'subr-x)
(require 'etaf-algo-lab)
(require 'emacs-gui-verifier)

(defun etaf-algo-lab-gui--runtime (context)
  "Return CONTEXT's mounted runtime."
  (etaf-runtime-for-buffer (etaf-gui-verifier-context-target-buffer context)))

(defun etaf-algo-lab-gui--text (context &optional ref)
  "Read CONTEXT's published text, optionally inside REF."
  (let* ((runtime (etaf-algo-lab-gui--runtime context))
         (bounds (and ref (etaf-host-ref-bounds runtime ref))))
    (with-current-buffer (etaf-runtime-buffer runtime)
      (buffer-substring-no-properties (if bounds (car bounds) (point-min))
                                      (if bounds (cdr bounds) (point-max))))))

(defun etaf-algo-lab-gui--press (context ref)
  "Focus and activate CONTEXT's REF through real keys."
  (etaf-focus (etaf-algo-lab-gui--runtime context) ref)
  (execute-kbd-macro (kbd "RET")))

(defun etaf-algo-lab-gui--choose (context field label)
  "Choose the visible LABEL chip inside CONTEXT's FIELD."
  (let* ((runtime (etaf-algo-lab-gui--runtime context))
         (bounds (etaf-host-ref-bounds runtime field))
         (entries (cl-remove-if-not
                   (lambda (entry)
                     (let ((position (etaf-host-ref-position runtime (car entry))))
                       (and (equal label (plist-get (cdr entry) :aria-label))
                            position bounds
                            (<= (car bounds) position) (< position (cdr bounds)))))
                   (etaf-runtime-host-props-entries runtime))))
    (unless (= 1 (length entries)) (error "Missing unique %s chip" label))
    (etaf-algo-lab-gui--press context (caar entries))))

(defun etaf-algo-lab-gui--bounds (context ref)
  "Return CONTEXT's runtime bounds for REF, or nil."
  (etaf-host-ref-bounds (etaf-algo-lab-gui--runtime context) ref))

(defun etaf-algo-lab-gui--cell-rc (context ref)
  "Return (COLUMN . ROW) in characters for REF, or nil when not displayed."
  (let* ((runtime (etaf-algo-lab-gui--runtime context))
         (window (get-buffer-window (etaf-runtime-buffer runtime) t))
         (position (etaf-host-ref-position runtime ref))
         (posn (and window position (posn-at-point position window))))
    (when posn (posn-col-row posn))))

(defun etaf-algo-lab-gui--numbers (context ref)
  "Read CONTEXT's space-separated numbers inside REF."
  (mapcar #'string-to-number
          (split-string (string-trim (etaf-algo-lab-gui--text context ref)) " +")))

(defun etaf-algo-lab-gui--action (id execute verify &optional timeout)
  "Create an ordered screenshot action ID with EXECUTE and VERIFY."
  (etaf-gui-verifier-action-create
   :id id :execute execute :screenshot t
   :settled-p verify
   :settle-timeout (or timeout 5)
   :assertions (lambda (context)
                 (list (etaf-gui-verifier-assert id (funcall verify context))))))

(defun etaf-algo-lab-gui--invariants (context)
  "Return CONTEXT's mounted, focused and row-height assertions."
  (append
   (list (etaf-gui-verifier-assert "workspace-mounted"
                                   (etaf-algo-lab-gui--runtime context))
         (etaf-gui-verifier-assert
          "target-selected"
          (eq (window-buffer (selected-window))
              (etaf-gui-verifier-context-target-buffer context)))
         (etaf-gui-verifier-assert
          "no-render-error"
          (not (string-match-p "runtime error\\|Wrong type argument\\|could not render"
                               (etaf-algo-lab-gui--text context)))))
   (etaf-gui-verifier-line-height-assertions
    (etaf-gui-verifier-context-target-buffer context))))

(defun etaf-algo-lab-gui--layout (width height)
  "Create a layout action for WIDTH and HEIGHT."
  (etaf-algo-lab-gui--action
   (format "layout-%dx%d" width height)
   (lambda (_context) (set-frame-size (selected-frame) width height))
   (lambda (context)
     (and (= (frame-width) width) (= (frame-height) height)
          (etaf-gui-verifier-canvas-filled-p
           (etaf-gui-verifier-context-target-buffer context))
          (etaf-host-ref-bounds (etaf-algo-lab-gui--runtime context) 'al-step)))))

(defun etaf-algo-lab-gui--scenario ()
  "Return the maintained workspace scenario."
  (etaf-gui-verifier-scenario-create
   :name "etaf-algo-lab"
   :claim "Two laboratories, real controls, batch comparison and layout; background GUI"
   :initialize
   (lambda (context)
     (let ((buffer (get-buffer-create "*算法实验室 GUI 验收*")))
       (setf (etaf-gui-verifier-context-target-buffer context) buffer)
       (etaf-algo-lab-open 'pathfinding (buffer-name buffer))
       (switch-to-buffer buffer)
       (delete-other-windows)
       (etaf-refit (etaf-algo-lab-gui--runtime context) (selected-window))))
   :invariants #'etaf-algo-lab-gui--invariants
   :adapter (lambda (context)
              (list (cons 'status (string-trim (etaf-algo-lab-gui--text context 'al-status)))
                    (cons 'counters (string-trim (etaf-algo-lab-gui--text context 'al-counters)))
                    (cons 'frame_width (frame-width))
                    (cons 'frame_height (frame-height))))
   :actions
   (append
    (list
     (etaf-algo-lab-gui--action
      "initial-board" #'ignore
      (lambda (c) (and (string-match-p "候选" (etaf-algo-lab-gui--text c))
                       (string-match-p "准备就绪" (etaf-algo-lab-gui--text c 'al-status)))))
     (etaf-algo-lab-gui--action
      "keyboard-single-step" (lambda (_c) (execute-kbd-macro (kbd "n")))
      (lambda (c) (string-match-p "探索 +1 格" (etaf-algo-lab-gui--text c 'al-counters))))
     (etaf-algo-lab-gui--action
      "paint-wall-and-erase"
      (lambda (c) (etaf-algo-lab-gui--press c 'pf-cell-0-0)
        (etaf-algo-lab-gui--choose c 'pf-tool "擦除")
        (etaf-algo-lab-gui--press c 'pf-cell-0-0))
      (lambda (c) (string-match-p "\\. *\\. *\\." (replace-regexp-in-string "\n" " " (etaf-algo-lab-gui--text c)))))
     (etaf-algo-lab-gui--action
      "move-start-and-goal"
      (lambda (c) (etaf-algo-lab-gui--choose c 'pf-tool "起点")
        (etaf-algo-lab-gui--press c 'pf-cell-1-1)
        (etaf-algo-lab-gui--choose c 'pf-tool "终点")
        (etaf-algo-lab-gui--press c 'pf-cell-2-5))
      (lambda (c) (and (etaf-algo-lab-gui--bounds c 'pf-cell-1-1)
                       (etaf-algo-lab-gui--bounds c 'pf-cell-2-5))))
     (etaf-algo-lab-gui--action
      "edit-restarts-the-search"
      (lambda (c) (etaf-algo-lab-gui--press c 'pf-cell-3-3))
      (lambda (c) (string-match-p "探索 +0 格" (etaf-algo-lab-gui--text c 'al-counters))))
     (etaf-algo-lab-gui--action
      "animate-astar-to-completion"
      (lambda (c) (etaf-algo-lab-gui--choose c 'al-speed "快速")
        (etaf-algo-lab-gui--press c 'al-start))
      (lambda (c) (string-match-p "已完成" (etaf-algo-lab-gui--text c 'al-status)))
      15)
     (etaf-algo-lab-gui--action
      "batch-compare-reports-every-algorithm"
      (lambda (c) (etaf-algo-lab-gui--press c 'al-compare))
      (lambda (c) (let ((research (etaf-algo-lab-gui--text c 'al-research)))
                    (and (string-match-p "A\\*：探索" research)
                         (string-match-p "Dijkstra：探索" research)
                         (string-match-p "BFS：探索" research)))))
     (etaf-algo-lab-gui--action
      "switch-algorithm-restarts"
      (lambda (c) (etaf-algo-lab-gui--choose c 'pf-algorithm "BFS"))
      (lambda (c) (string-match-p "探索 +0 格" (etaf-algo-lab-gui--text c 'al-counters))))
     (etaf-algo-lab-gui--action
      "jump-to-finish-without-animation"
      (lambda (c) (etaf-algo-lab-gui--press c 'al-finish))
      (lambda (c) (and (string-match-p "已完成" (etaf-algo-lab-gui--text c 'al-status))
                       (string-match-p "路径 +[0-9]+ 步" (etaf-algo-lab-gui--text c 'al-counters)))))
     (etaf-algo-lab-gui--action
      "reset-keeps-the-edited-map"
      (lambda (c) (etaf-algo-lab-gui--press c 'al-reset))
      (lambda (c) (string-match-p "准备就绪" (etaf-algo-lab-gui--text c 'al-status))))
     (etaf-algo-lab-gui--action
      "switch-laboratory-to-sorting"
      (lambda (c) (etaf-algo-lab-gui--choose c 'al-catalog "排序实验台"))
      (lambda (c) (and (etaf-algo-lab-gui--bounds c 'sort-values)
                       (string-match-p "比较 +0 次" (etaf-algo-lab-gui--text c 'al-counters)))))
     (etaf-algo-lab-gui--action
      "sorting-step-shows-a-comparison"
      (lambda (_c) (execute-kbd-macro (kbd "n")))
      (lambda (c) (string-match-p "比较 +1 次" (etaf-algo-lab-gui--text c 'al-counters))))
     (etaf-algo-lab-gui--action
      "sorting-bubble-finishes-sorted"
      (lambda (c) (etaf-algo-lab-gui--press c 'al-finish))
      (lambda (c) (let ((numbers (etaf-algo-lab-gui--numbers c 'sort-values)))
                    (and (= 14 (length numbers))
                         (equal numbers (sort (copy-sequence numbers) #'<))))))
     (etaf-algo-lab-gui--action
      "sorting-merge-finishes-sorted"
      (lambda (c) (etaf-algo-lab-gui--choose c 'sort-algorithm "归并")
        (etaf-algo-lab-gui--press c 'al-finish))
      (lambda (c) (let ((numbers (etaf-algo-lab-gui--numbers c 'sort-values)))
                    (and (= 14 (length numbers))
                         (equal numbers (sort (copy-sequence numbers) #'<))
                         (string-match-p "完成的\\|完成" (etaf-algo-lab-gui--text c 'al-narration))))))
     (etaf-algo-lab-gui--action
      "sorting-compare-ranks-algorithms"
      (lambda (c) (etaf-algo-lab-gui--press c 'al-compare))
      (lambda (c) (let ((research (etaf-algo-lab-gui--text c 'al-research)))
                    (and (string-match-p "冒泡：比较" research)
                         (string-match-p "归并：比较" research))))))
    (list
     (etaf-algo-lab-gui--action
      "wide-window-splits-into-two-columns"
      (lambda (_c) (set-frame-size (selected-frame) 130 50))
      (lambda (c)
        (let ((panel (etaf-algo-lab-gui--cell-rc c 'al-counters))
              (board (etaf-algo-lab-gui--cell-rc c 'sort-values)))
          (and panel board
               (> (car board) (car panel))
               (etaf-gui-verifier-canvas-filled-p
                (etaf-gui-verifier-context-target-buffer c))))))
     (etaf-algo-lab-gui--action
      "narrow-window-wraps-back-to-one-column"
      (lambda (_c) (set-frame-size (selected-frame) 60 50))
      (lambda (c)
        (let ((panel (etaf-algo-lab-gui--cell-rc c 'al-counters))
              (board (etaf-algo-lab-gui--cell-rc c 'sort-values)))
          (and panel board
               (<= (abs (- (car board) (car panel))) 3)
               (> (cdr board) (cdr panel)))))))
    (mapcar (lambda (size) (etaf-algo-lab-gui--layout (car size) (cdr size)))
            '((130 . 50) (90 . 50) (60 . 50) (60 . 32)))
    (list
     (etaf-algo-lab-gui--action
      "short-window-scrolls-keys-into-view"
      (lambda (_c) (execute-kbd-macro (kbd "C-v")))
      (lambda (c) (string-match-p "批量对比" (etaf-algo-lab-gui--text c))))
     (etaf-algo-lab-gui--layout 100 50)
     (etaf-algo-lab-gui--action
      "remount-starts-clean"
      (lambda (c)
        (etaf-algo-lab-open 'pathfinding
                            (buffer-name (etaf-gui-verifier-context-target-buffer c)))
        (etaf-refit (etaf-algo-lab-gui--runtime c)))
      (lambda (c) (and (string-match-p "准备就绪" (etaf-algo-lab-gui--text c 'al-status))
                       (string-match-p "探索 +0 格" (etaf-algo-lab-gui--text c 'al-counters)))))))
   :completion (lambda (context)
                 (and (etaf-algo-lab-gui--runtime context)
                      (string-match-p "准备就绪"
                                      (etaf-algo-lab-gui--text context 'al-status))))))

(defun etaf-algo-lab-gui-run (directory)
  "Run the maintained scenario into fresh evidence DIRECTORY."
  (etaf-gui-verifier-run (etaf-algo-lab-gui--scenario) directory))

(provide 'etaf-algo-lab-gui-scenarios)
;;; etaf-algo-lab-gui-scenarios.el ends here
