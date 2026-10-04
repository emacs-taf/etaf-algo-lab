;;; performance-scenarios.el --- Workspace interaction workloads -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; One visible animation step per laboratory, measured through the shared
;; driver.  Setup, sampling, profiling and source freshness stay in the driver.

;;; Code:
(require 'cl-lib)
(require 'etaf-algo-lab)
(require 'etaf)
(declare-function taf-benchmark-register "performance-driver" (id &rest properties))

(defun etaf-algo-lab-benchmark--setup (mode keyboard)
  "Prepare one retained laboratory for MODE; KEYBOARD selects real RET input."
  (let* ((buffer (generate-new-buffer " *algo-lab benchmark*"))
         (runtime nil) (before 0))
    (etaf-algo-lab-open 'pathfinding (buffer-name buffer))
    (setq runtime (etaf-runtime-for-buffer buffer))
    (list
     :buffer buffer
     :ready (lambda ()
              (when (eq mode 'gui) (etaf-refit runtime (selected-window)))
              t)
     :prepare (lambda ()
                (when (string-match-p "已完成"
                                      (with-current-buffer buffer (buffer-string)))
                  (etaf-dispatch-event runtime 'al-reset 'press))
                (when keyboard (etaf-focus runtime 'al-step))
                (setq before (etaf-runtime-generation runtime)))
     :invoke (lambda (_sample)
               (if keyboard
                   (execute-kbd-macro (kbd "RET"))
                 (etaf-dispatch-event runtime 'al-step 'press)))
     :verify (lambda ()
               (and (> (etaf-runtime-generation runtime) before)
                    (not (null (etaf-host-ref-bounds runtime 'al-counters)))
                    t))
     :outcome (lambda ()
                (list :generation (etaf-runtime-generation runtime)
                      :counters (string-trim
                                 (let ((bounds (etaf-host-ref-bounds runtime 'al-counters)))
                                   (with-current-buffer buffer
                                     (buffer-substring-no-properties (car bounds) (cdr bounds)))))))
     :observe
     (lambda (sink)
       (etaf-performance-start runtime)
       (let ((before-ids (mapcar (lambda (record)
                                   (cons (plist-get record :runtime-id)
                                         (plist-get record :id)))
                                 (plist-get (etaf-performance-report-data) :operations))))
         (lambda ()
           (etaf-performance-stop runtime)
           (dolist (operation (plist-get (etaf-performance-report-data) :operations))
             (when (and (equal (plist-get operation :buffer-name) (buffer-name buffer))
                        (not (member (cons (plist-get operation :runtime-id)
                                           (plist-get operation :id)) before-ids)))
               (dolist (stage (plist-get operation :stages))
                 (funcall sink
                          (append (list :provider (plist-get stage :provider)
                                        :stage (plist-get stage :stage)
                                        :duration-ms (plist-get stage :duration-ms))
                                  (plist-get stage :metadata)))))))))
     :cleanup (lambda ()
                (when-let* ((live (etaf-runtime-for-buffer buffer))) (etaf-unmount live))
                (when (buffer-live-p buffer) (kill-buffer buffer))))))

(taf-benchmark-register
 "algolab.pathfinding.step.callback" :version 1 :modes '(batch gui) :isolation 'series
 :required-providers '(ebox)
 :budget-ms 100 :impact 'local
 :description "One real search/route step on the retained 24x14 board"
 :setup (lambda (mode) (etaf-algo-lab-benchmark--setup mode nil)))

(taf-benchmark-register
 "algolab.pathfinding.step.keyboard" :version 1 :modes '(gui) :isolation 'series
 :required-providers '(ebox)
 :budget-ms 100 :impact 'local
 :description "RET on the focused Single Step button through the command loop"
 :setup (lambda (mode) (etaf-algo-lab-benchmark--setup mode t)))

(provide 'performance-scenarios)
;;; performance-scenarios.el ends here
