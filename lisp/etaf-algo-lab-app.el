;;; etaf-algo-lab-app.el --- Catalog, buffer and lifecycle -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; The application layer owns the catalog bar, the buffer and the mount
;; lifecycle.  Switching laboratories replaces the keyed laboratory player, so
;; the previous session is disposed (timer included) before the next one plays.

;;; Code:

(require 'etaf)
(require 'etaf-ui)
(require 'etaf-algo-lab-theme)
(require 'etaf-algo-lab-player)
(require 'etaf-algo-lab-pathfinding)
(require 'etaf-algo-lab-sorting)

(defcustom etaf-algo-lab-buffer-name "*算法实验室*"
  "Default buffer name of the mounted workspace."
  :type 'string
  :group 'etaf)

(defcustom etaf-algo-lab-default-lab 'pathfinding
  "Laboratory opened when no other one is requested."
  :type 'symbol
  :group 'etaf)

(defvar etaf-algo-lab--initial-lab nil
  "Laboratory selected by the mount currently in progress.")

(defun etaf-algo-lab--catalog-options ()
  "Return the catalog as select options."
  (mapcar (lambda (pair)
            (cons (car pair) (etaf-algo-lab--lab-title (cdr pair))))
          etaf-algo-lab--catalog))

(defun etaf-algo-lab--resolve (lab)
  "Return the laboratory identifier named by LAB."
  (cond
   ((null lab) etaf-algo-lab-default-lab)
   ((assq lab etaf-algo-lab--catalog) lab)
   ((stringp lab)
    (or (cl-loop for pair in etaf-algo-lab--catalog
                 when (equal lab (etaf-algo-lab--lab-title (cdr pair)))
                 return (car pair))
        (intern lab)))
   (t lab)))

(etaf-define-component etaf-algo-lab--app ()
  "Render the workspace: catalog bar plus the selected laboratory."
  :bindings ((current (etaf-ref (or etaf-algo-lab--initial-lab
                                    etaf-algo-lab-default-lab))))
  :view
  ;; The page owns the scroll region, the page background and the centred
  ;; measure.  The content column is capped at 98 columns so an ultra-wide
  ;; frame keeps one readable composition centred in the window instead of a
  ;; stretched strip; a narrow frame shrinks it to the viewport.  The page
  ;; padding belongs to the capped inner column, so the scroll owner spans
  ;; the whole window.
  (column :width '(vw 100) :height '(vh 100) :overflow 'scroll
          :cross-align 'center
          :color (etaf-algo-lab-token :fg)
          :background-color (etaf-algo-lab-token :bg)
    (column :width '(vw 100) :max-width '(ch 110) :box-sizing 'border-box
            :padding '((lh 1) (ch 1)) :item-gap '(lh 1)
      ;; One bar: the workspace name and the laboratory switcher.  The
      ;; switcher needs no redundant "实验室" label because the title already
      ;; names the workspace, and the bar stays left-aligned at the capped
      ;; measure because flex lines cannot stretch to their container here.
      (flex :flex-wrap 'wrap :gap '((lh 0) (ch 2))
            :align-items 'center
        (text :font-weight 'bold "算法实验室")
        (etaf-select :ref 'al-catalog :hide-label t
                     :value (etaf-value current)
                     :options (etaf-algo-lab--catalog-options)
                     :presentation 'chips
                     :on-change (lambda (next) (setf (etaf-value current) next))))
      (expr (etaf-node 'etaf-algo-lab--player
                       (list :key (etaf-value current)
                             :lab-id (etaf-value current))
                       nil)))))

(defun etaf-algo-lab-open (&optional lab buffer-name)
  "Open the laboratory workspace in BUFFER-NAME, selecting LAB.

LAB is a laboratory identifier or its displayed title.  BUFFER-NAME defaults
to `etaf-algo-lab-buffer-name'.  An existing runtime in that buffer is replaced."
  (interactive
   (list (when current-prefix-arg
           (completing-read "实验室："
                            (mapcar (lambda (pair)
                                      (cons (etaf-algo-lab--lab-title (cdr pair))
                                            (car pair)))
                                    etaf-algo-lab--catalog)
                            nil t))
         nil))
  (let* ((id (etaf-algo-lab--resolve lab))
         (_ (etaf-algo-lab--lab id))
         (buffer (get-buffer-create (or buffer-name etaf-algo-lab-buffer-name))))
    (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
      (with-current-buffer buffer (etaf-unmount runtime)))
    (with-current-buffer buffer
      (let ((etaf-algo-lab--initial-lab id))
        (etaf-mount buffer (etaf-view (etaf-algo-lab--app))))
      (when (called-interactively-p 'interactive) (pop-to-buffer buffer)))
    buffer))

(defun etaf-algo-lab-close (&optional buffer-name)
  "Unmount and kill the laboratory workspace in BUFFER-NAME."
  (interactive)
  (let ((buffer (get-buffer (or buffer-name etaf-algo-lab-buffer-name))))
    (when buffer
      (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
        (with-current-buffer buffer (etaf-unmount runtime)))
      (when (buffer-live-p buffer) (kill-buffer buffer))))
  nil)

(defun etaf-algo-lab-labs ()
  "Return the registered laboratories in display order."
  (etaf-algo-lab--labs))

(provide 'etaf-algo-lab-app)
;;; etaf-algo-lab-app.el ends here
