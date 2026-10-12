;;; etaf-algo-lab.el --- Learn algorithms by watching and steering them -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Author: ETAF contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (etaf "0.2.1") (etaf-ui "0.1.0") (ebox "3.0.0"))
;; Keywords: education, tools, convenience
;; URL: https://github.com/emacs-taf/etaf-algo-lab

;;; Commentary:

;; Public API
;;
;; Load this package with (require 'etaf-algo-lab) after adding this
;; repository root and the ETAF, ETAF UI, Ebox and ECSS roots to `load-path'.
;;
;; The workspace serves three levels of use with one shared player:
;;   1. Learn:    every laboratory opens with plain-language narration and a
;;                one-step-at-a-time animation, so the algorithm explains
;;                itself without prerequisites.
;;   2. Feel:     start, pause, single-step, change speed, edit the data and
;;                switch algorithms while the animation keeps publishing.
;;   3. Explore:  "批量对比" runs every algorithm headlessly on the current
;;                input and reports their real work counts side by side.
;;
;; Only the interfaces listed below are supported for use by other packages.
;; All unlisted symbols and implementation features are internal, including
;; names without a double hyphen.  This Commentary is the authoritative export
;; list; implementations and precise docstrings remain beside their
;; definitions.
;;
;; Function: etaf-algo-lab-open (&optional lab buffer-name)
;;;###autoload (autoload 'etaf-algo-lab-open "etaf-algo-lab" nil t)
;; Mount the workspace in BUFFER-NAME, selecting LAB, and return that buffer.
;;
;; LAB accepts a registered identifier (see `etaf-algo-lab-labs') or its
;; displayed title.  BUFFER-NAME defaults to `etaf-algo-lab-buffer-name'.
;; With a prefix argument, prompt for the laboratory by title.
;;
;; Function: etaf-algo-lab-close (&optional buffer-name)
;;;###autoload (autoload 'etaf-algo-lab-close "etaf-algo-lab" nil t)
;; Unmount the workspace in BUFFER-NAME and kill its buffer.
;;
;; Function: etaf-algo-lab-labs ()
;;;###autoload (autoload 'etaf-algo-lab-labs "etaf-algo-lab" nil nil)
;; Return the registered laboratory identifiers in display order.

;;; Code:

;;;###autoload
(eval-and-compile
  (add-to-list 'load-path
               (expand-file-name "lisp"
                                 (file-name-directory
                                  (or load-file-name
                                      (bound-and-true-p byte-compile-current-file)
                                      buffer-file-name)))))

(require 'etaf-algo-lab-app)

(provide 'etaf-algo-lab)
;;; etaf-algo-lab.el ends here
