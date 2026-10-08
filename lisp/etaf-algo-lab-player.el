;;; etaf-algo-lab-player.el --- Laboratory contract and playback -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; A laboratory is data plus one single step.  The player owns play, pause,
;; single step, reset, finish, speed, the bounded timer, the narration lines, the
;; comparison run, the keymap and cleanup, so a laboratory only describes its
;; algorithm and its cells.  Nothing here starts a timer during rendering.
;;
;; Performance contract: every visible value the player publishes lives in its
;; own fixed-height Host or its own ref, so one algorithm step dirties only the
;; changed cells plus the counter line.  Boards keep identity-stable props and
;; update through per-cell (grid) or per-column (bars) refs.

;;; Code:

(require 'cl-lib)
(require 'etaf)
(require 'etaf-ui)
(require 'etaf-algo-lab-theme)

(cl-defstruct (etaf-algo-lab--lab (:constructor etaf-algo-lab--make-lab))
  "Description of one algorithm laboratory."
  id title summary intro create step terminal reset narration counters memory
  board controls legend keys keys-hint reset-notice compare)

(cl-defstruct (etaf-algo-lab--session (:constructor etaf-algo-lab--session-create))
  "Live playing state of one mounted laboratory."
  lab model status speed timer counters narration memory notice research
  runtime disposed (ticks 0))

(defconst etaf-algo-lab--speeds '((5 . "慢速") (15 . "正常") (30 . "快速"))
  "Available step rates in steps per second.")

(defvar etaf-algo-lab--catalog nil
  "Registered laboratories in display order, as (ID . LAB) pairs.")

(defvar-local etaf-algo-lab--session nil
  "Laboratory session owned by the current buffer.")

(defvar-local etaf-algo-lab--command-maps nil
  "Buffer-local player keymap entry for `emulation-mode-map-alists'.")

(defun etaf-algo-lab--register-lab (lab)
  "Register LAB in the catalog and return it."
  (setq etaf-algo-lab--catalog
        (append (assq-delete-all (etaf-algo-lab--lab-id lab) etaf-algo-lab--catalog)
                (list (cons (etaf-algo-lab--lab-id lab) lab))))
  lab)

(defun etaf-algo-lab--lab (id)
  "Return the registered laboratory named ID."
  (or (cdr (assq id etaf-algo-lab--catalog))
      (error "Unknown laboratory: %S" id)))

(defun etaf-algo-lab--labs ()
  "Return the registered laboratory identifiers in display order."
  (mapcar #'car etaf-algo-lab--catalog))

(defun etaf-algo-lab--session-make (lab)
  "Create a ready-to-play session for LAB."
  (let ((session (etaf-algo-lab--session-create
                  :lab lab :model (funcall (etaf-algo-lab--lab-create lab))
                  :status (etaf-ref 'ready) :speed (etaf-ref 15)
                  :counters (etaf-ref "") :narration (etaf-ref "")
                  :memory (etaf-ref "") :notice (etaf-ref "")
                  :research (etaf-ref ""))))
    (etaf-algo-lab--refresh session)
    session))

(defun etaf-algo-lab--refresh (session)
  "Publish SESSION's counters, narration and memory lines in one batch."
  (let ((lab (etaf-algo-lab--session-lab session))
        (model (etaf-algo-lab--session-model session)))
    (etaf-batch
      (setf (etaf-value (etaf-algo-lab--session-counters session))
            (funcall (etaf-algo-lab--lab-counters lab) model)
            (etaf-value (etaf-algo-lab--session-narration session))
            (funcall (etaf-algo-lab--lab-narration lab) model)
            (etaf-value (etaf-algo-lab--session-memory session))
            (funcall (etaf-algo-lab--lab-memory lab) model)))))

(defun etaf-algo-lab--stop-timer (session)
  "Cancel SESSION's sole pending timer."
  (when (timerp (etaf-algo-lab--session-timer session))
    (cancel-timer (etaf-algo-lab--session-timer session)))
  (setf (etaf-algo-lab--session-timer session) nil))

(defun etaf-algo-lab--arm (session)
  "Schedule one future step in SESSION, without catch-up bursts."
  (etaf-algo-lab--stop-timer session)
  (when (and (not (etaf-algo-lab--session-disposed session))
             (eq (etaf-value (etaf-algo-lab--session-status session)) 'running))
    (setf (etaf-algo-lab--session-timer session)
          (run-at-time (/ 1.0 (etaf-value (etaf-algo-lab--session-speed session)))
                       nil #'etaf-algo-lab--tick session))))

(defun etaf-algo-lab--advance (session)
  "Run one laboratory step for SESSION and refresh its lines."
  (let* ((lab (etaf-algo-lab--session-lab session))
         (model (etaf-algo-lab--session-model session)))
    (unless (funcall (etaf-algo-lab--lab-terminal lab) model)
      (etaf-batch
        (funcall (etaf-algo-lab--lab-step lab) model)
        (when (funcall (etaf-algo-lab--lab-terminal lab) model)
          (setf (etaf-value (etaf-algo-lab--session-status session)) 'finished))
        (etaf-algo-lab--refresh session)))))

(defun etaf-algo-lab--tick (session)
  "Advance a live, visible SESSION once, or stop at its safety bound."
  (setf (etaf-algo-lab--session-timer session) nil)
  (let* ((runtime (etaf-algo-lab--session-runtime session))
         (buffer (and runtime (etaf-runtime-buffer runtime))))
    (when (and (not (etaf-algo-lab--session-disposed session))
               (buffer-live-p buffer)
               (eq runtime (etaf-runtime-for-buffer buffer))
               (eq (etaf-value (etaf-algo-lab--session-status session)) 'running))
      (cond
       ((not (get-buffer-window buffer t))
        (etaf-batch
          (setf (etaf-value (etaf-algo-lab--session-status session)) 'paused
                (etaf-value (etaf-algo-lab--session-notice session))
                "窗口隐藏，已暂停；回来后按 p 继续。")
          (etaf-algo-lab--refresh session)))
       ((>= (cl-incf (etaf-algo-lab--session-ticks session)) 5000)
        (etaf-batch
          (setf (etaf-value (etaf-algo-lab--session-status session)) 'paused
                (etaf-value (etaf-algo-lab--session-notice session))
                "达到安全步数上限，已暂停；请重置后再试。")
          (etaf-algo-lab--refresh session)))
       (t
        (condition-case problem
            (progn (etaf-algo-lab--advance session) (etaf-algo-lab--arm session))
          (error
           (etaf-algo-lab--stop-timer session)
           (setf (etaf-value (etaf-algo-lab--session-status session)) 'paused)
           (message "实验室已暂停：%s" (error-message-string problem)))))))))

(defun etaf-algo-lab--restart (session notice)
  "Reset SESSION's model and return it to the ready state with NOTICE."
  (etaf-algo-lab--stop-timer session)
  (setf (etaf-algo-lab--session-ticks session) 0)
  (etaf-batch
    (funcall (etaf-algo-lab--lab-reset (etaf-algo-lab--session-lab session))
             (etaf-algo-lab--session-model session))
    (setf (etaf-value (etaf-algo-lab--session-status session)) 'ready
          (etaf-value (etaf-algo-lab--session-notice session)) notice)
    (etaf-algo-lab--refresh session)))

(defun etaf-algo-lab--act (session action)
  "Apply ACTION to SESSION: start, pause, step or reset."
  (let* ((lab (etaf-algo-lab--session-lab session))
         (model (etaf-algo-lab--session-model session)))
    (pcase action
      ('start
       (when (eq (etaf-value (etaf-algo-lab--session-status session)) 'finished)
         (funcall (etaf-algo-lab--lab-reset lab) model)
         (setf (etaf-algo-lab--session-ticks session) 0)
         (etaf-algo-lab--refresh session))
       (etaf-batch
         (setf (etaf-value (etaf-algo-lab--session-status session)) 'running)
         (etaf-algo-lab--refresh session))
       (etaf-algo-lab--arm session))
      ('pause
       (etaf-algo-lab--stop-timer session)
       (unless (eq (etaf-value (etaf-algo-lab--session-status session)) 'finished)
         (etaf-batch
           (setf (etaf-value (etaf-algo-lab--session-status session)) 'paused)
           (etaf-algo-lab--refresh session))))
      ('step
       (etaf-algo-lab--act session 'pause)
       (etaf-algo-lab--advance session))
      ('finish
       (etaf-algo-lab--finish session))
      ('reset
       (etaf-algo-lab--restart
        session (or (etaf-algo-lab--lab-reset-notice lab) "已重置。")))
      ('compare
       (etaf-algo-lab--compare session)))))

(defun etaf-algo-lab--finish (session)
  "Run SESSION to completion without animation, then publish once."
  (let ((lab (etaf-algo-lab--session-lab session))
        (model (etaf-algo-lab--session-model session)))
    (etaf-algo-lab--stop-timer session)
    (etaf-batch
      (let ((guard 20000))
        (while (and (> guard 0)
                    (not (funcall (etaf-algo-lab--lab-terminal lab) model)))
          (cl-decf guard)
          (funcall (etaf-algo-lab--lab-step lab) model)))
      (when (funcall (etaf-algo-lab--lab-terminal lab) model)
        (setf (etaf-value (etaf-algo-lab--session-status session)) 'finished)
        (setf (etaf-value (etaf-algo-lab--session-notice session))
              "已跳到完成：只发布了最后一步。"))
      (etaf-algo-lab--refresh session))))

(defun etaf-algo-lab--compare (session)
  "Run SESSION's headless comparison and publish its rows."
  (let* ((lab (etaf-algo-lab--session-lab session))
         (compare (etaf-algo-lab--lab-compare lab))
         (rows (and compare (funcall compare (etaf-algo-lab--session-model session)))))
    (etaf-batch
      (setf (etaf-value (etaf-algo-lab--session-research session))
            (if rows (mapconcat #'cdr rows "\n") "本实验室还没有批量对比。")
            (etaf-value (etaf-algo-lab--session-notice session))
            "对比完成：只计算、不播动画，结果来自当前地图或数据。"))))

;;; Commands owned by the player, bound in the mounted buffer.

(defun etaf-algo-lab--toggle ()
  "Toggle the current buffer's laboratory."
  (interactive)
  (etaf-algo-lab--act
   etaf-algo-lab--session
   (if (eq (etaf-value (etaf-algo-lab--session-status etaf-algo-lab--session))
           'running)
       'pause 'start)))

(defun etaf-algo-lab--step-command ()
  "Single-step the current buffer's laboratory."
  (interactive)
  (etaf-algo-lab--act etaf-algo-lab--session 'step))

(defun etaf-algo-lab--reset-command ()
  "Reset the current buffer's laboratory."
  (interactive)
  (etaf-algo-lab--act etaf-algo-lab--session 'reset))

(defun etaf-algo-lab--compare-command ()
  "Compare this laboratory's algorithms without animation."
  (interactive)
  (etaf-algo-lab--act etaf-algo-lab--session 'compare))

(defun etaf-algo-lab--finish-command ()
  "Run the current laboratory to completion without animation."
  (interactive)
  (etaf-algo-lab--act etaf-algo-lab--session 'finish))

(defun etaf-algo-lab--close-command ()
  "Close only the current buffer's laboratory."
  (interactive)
  (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
    (etaf-unmount runtime))
  (kill-buffer (current-buffer)))

(defun etaf-algo-lab--install (session)
  "Attach SESSION to its runtime, keymap and disposal hook."
  (let ((runtime (etaf-current-runtime)))
    (setf (etaf-algo-lab--session-runtime session) runtime)
    (with-current-buffer (etaf-runtime-buffer runtime)
      (setq-local etaf-algo-lab--session session)
      (let ((map (make-sparse-keymap)))
        (define-key map (kbd "p") #'etaf-algo-lab--toggle)
        (define-key map (kbd "n") #'etaf-algo-lab--step-command)
        (define-key map (kbd "r") #'etaf-algo-lab--reset-command)
        (define-key map (kbd "c") #'etaf-algo-lab--compare-command)
        (define-key map (kbd "f") #'etaf-algo-lab--finish-command)
        (define-key map (kbd "q") #'etaf-algo-lab--close-command)
        (dolist (binding (etaf-algo-lab--lab-keys (etaf-algo-lab--session-lab session)))
          (define-key map (car binding) (cdr binding)))
        (setq-local etaf-algo-lab--command-maps
                    (list (cons 'etaf-algo-lab--session map)))
        (setq-local emulation-mode-map-alists
                    (cons 'etaf-algo-lab--command-maps
                          (remq 'etaf-algo-lab--command-maps
                                emulation-mode-map-alists)))))
    (etaf-on-unmounted (lambda () (etaf-algo-lab--dispose session)))))

(defun etaf-algo-lab--dispose (session)
  "Release SESSION without touching another mounted laboratory."
  (etaf-algo-lab--stop-timer session)
  (setf (etaf-algo-lab--session-disposed session) t)
  (when-let* ((runtime (etaf-algo-lab--session-runtime session))
              (buffer (etaf-runtime-buffer runtime)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (eq etaf-algo-lab--session session)
          (setq etaf-algo-lab--session nil)
          (setq-local emulation-mode-map-alists
                      (remq 'etaf-algo-lab--command-maps
                            emulation-mode-map-alists)))))))

;;; Presentation shared by the player and every laboratory.

(defun etaf-algo-lab--status-text (status)
  "Return the user-visible word for STATUS."
  (pcase status
    ('running "运行中") ('paused "已暂停") ('finished "已完成") (_ "准备就绪")))

(defun etaf-algo-lab--status-color (status)
  "Return the accent color for STATUS."
  (pcase status
    ('running "#4ADE80") ('finished "#60A5FA") ('paused "#FBBF24") (_ "#9CADC1")))

(defun etaf-algo-lab--keys-text (lab)
  "Return LAB's player key hint line."
  (ignore lab)
  "p 开始/暂停 · n 单步 · f 跳到完成 · r 重置 · c 批量对比 · q 关闭")

(defun etaf-algo-lab--keys-hint-text (lab)
  "Return LAB's laboratory-specific key hint line, or an empty string."
  (or (etaf-algo-lab--lab-keys-hint lab) ""))

(defun etaf-algo-lab--board-view (lab session)
  "Return LAB's board component for SESSION."
  (etaf-node (etaf-algo-lab--lab-board lab) (list :session session) nil))

(defun etaf-algo-lab--controls-view (lab session)
  "Return LAB's own controls for SESSION."
  (etaf-node (etaf-algo-lab--lab-controls lab) (list :session session) nil))

(defun etaf-algo-lab--intro-view (lab)
  "Return LAB's introduction lines."
  (mapcar (lambda (line)
            (etaf-view
             (etaf-label :width 'stretch :wrap-mode 'word :variant 'muted
                         :text line)))
          (etaf-algo-lab--lab-intro lab)))

(etaf-define-component etaf-algo-lab--player (&key lab-id)
  "Render one laboratory: header, adaptive workspace, board and legend.

A wide window becomes two columns (controls and live data left, the board as
the visual anchor right); a narrow or short window wraps back into one column
in the same reading order, so the board never pushes the controls off screen."
  :bindings ((lab (etaf-algo-lab--lab lab-id))
             (session (etaf-algo-lab--session-make lab)))
  :setup (progn
           (etaf-theme-provide etaf-algo-lab-palette)
           (etaf-algo-lab--install session))
  :view
  ;; The application above owns the page chrome (the scroll owner, the page
  ;; background, the centred capped measure and the page padding); the player
  ;; renders one section stack with exactly one blank line between sections.
  ;; Every panel shares one surface, padding and inner gap, and the chart
  ;; panel hugs its fixed-width chart instead of leaving an empty strip.
  (column :width 'stretch :overflow 'hidden :item-gap '(lh 1)
      (flex :flex-wrap 'wrap :gap '((lh 0) (ch 2))
            :align-items 'baseline
        (text :font-weight 'bold (expr (etaf-algo-lab--lab-title lab)))
        (text :ref 'al-status
              :color (etaf-algo-lab--status-color
                      (etaf-value (etaf-algo-lab--session-status session)))
              (expr (etaf-algo-lab--status-text
                     (etaf-value (etaf-algo-lab--session-status session))))))
      (column :width 'stretch :item-gap '(lh 0)
        (expr (etaf-algo-lab--intro-view lab)))
      (flex :flex-wrap 'wrap :gap '((lh 1) (ch 2))
            :align-items 'flex-start
        (column :flex-basis '(ch 48) :flex-grow 1 :min-width '(ch 30)
                :item-gap '(lh 1)
          (box :width 'stretch :background-color (etaf-algo-lab-token :surface)
               :box-sizing 'border-box :padding '((lh 1) (ch 2))
            (column :item-gap '(lh 1)
              (flex :flex-wrap 'wrap :gap '((lh 0) (ch 1)) :align-items 'center
                (etaf-button :label "开始/继续" :ref 'al-start :on-press
                             (lambda () (etaf-algo-lab--act session 'start)))
                (etaf-button :label "暂停" :ref 'al-pause :variant 'secondary :on-press
                             (lambda () (etaf-algo-lab--act session 'pause)))
                (etaf-button :label "单步" :ref 'al-step :variant 'secondary :on-press
                             (lambda () (etaf-algo-lab--act session 'step)))
                (etaf-button :label "跳到完成" :ref 'al-finish :variant 'secondary
                             :help-echo "一秒算完并直接看结果，不播动画"
                             :on-press (lambda () (etaf-algo-lab--act session 'finish))))
              (flex :flex-wrap 'wrap :gap '((lh 0) (ch 2)) :align-items 'center
                (etaf-button :label "重置" :ref 'al-reset :variant 'ghost :on-press
                             (lambda () (etaf-algo-lab--act session 'reset)))
                (etaf-button :if (etaf-algo-lab--lab-compare lab)
                             :label "批量对比" :ref 'al-compare :variant 'ghost
                             :help-echo "只计算、不播动画，用当前地图或数据一次跑完所有算法"
                             :on-press (lambda () (etaf-algo-lab--act session 'compare))))
              (flex :flex-wrap 'wrap :gap '((lh 0) (ch 1)) :align-items 'center
                (etaf-select :label "速度" :ref 'al-speed
                             :value (etaf-value (etaf-algo-lab--session-speed session))
                             :options etaf-algo-lab--speeds :presentation 'chips
                             :on-change (lambda (next)
                                          (setf (etaf-value (etaf-algo-lab--session-speed session))
                                                next)
                                          (etaf-algo-lab--arm session))))
              (expr (etaf-algo-lab--controls-view lab session))))
          (box :width 'stretch :background-color (etaf-algo-lab-token :surface)
               :box-sizing 'border-box :padding '((lh 1) (ch 2))
            (column :item-gap '(lh 1)
              (box :width 'stretch :height '(lh 1) :wrap-mode 'none :overflow 'hidden
                (text :ref 'al-counters
                      (expr (etaf-value (etaf-algo-lab--session-counters session)))))
              (box :width 'stretch :height '(lh 1) :wrap-mode 'none :overflow 'hidden
                (text :ref 'al-memory :color (etaf-algo-lab-token :muted)
                      (expr (etaf-value (etaf-algo-lab--session-memory session)))))))
          (etaf-label :if (not (equal "" (etaf-value (etaf-algo-lab--session-research session))))
                      :width 'stretch :wrap-mode 'word :variant 'success
                      :text (etaf-algo-lab--session-research session))
          (etaf-label :if (not (equal "" (etaf-value (etaf-algo-lab--session-notice session))))
                      :width 'stretch :wrap-mode 'word :variant 'muted
                      :text (etaf-algo-lab--session-notice session)))
        (column :flex-basis '(ch 58) :flex-grow 0 :min-width '(ch 0)
                :item-gap '(lh 1)
          ;; The chart panel is exactly the chart width plus its padding, so
          ;; the panel never shows a lopsided empty strip beside the board.
          ;; A longer legend wraps inside this fixed measure.
          (box :width '(ch 58) :background-color (etaf-algo-lab-token :surface)
               :box-sizing 'border-box :padding '((lh 1) (ch 2))
            (column :item-gap '(lh 1)
              (expr (etaf-algo-lab--board-view lab session))
              (expr (funcall (etaf-algo-lab--lab-legend lab) session))))
          (box :width 'stretch :height '(lh 1) :wrap-mode 'none :overflow 'hidden
            (text :ref 'al-narration :color "#FBBF24"
                  (expr (etaf-value (etaf-algo-lab--session-narration session)))))))
      ;; Two short hint lines instead of one long one: a label keeps its
      ;; intrinsic width here, so an over-long line would be clipped by the
      ;; scroll container instead of wrapping.
      (etaf-label :variant 'muted :width 'stretch :wrap-mode 'word
                  :text (etaf-algo-lab--keys-text lab))
      (etaf-label :if (not (equal "" (etaf-algo-lab--keys-hint-text lab)))
                  :variant 'muted :width 'stretch :wrap-mode 'word
                  :text (etaf-algo-lab--keys-hint-text lab))))

(provide 'etaf-algo-lab-player)
;;; etaf-algo-lab-player.el ends here
