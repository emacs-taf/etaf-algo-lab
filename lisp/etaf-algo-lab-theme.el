;;; etaf-algo-lab-theme.el --- Shared palette for the algorithm laboratory -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; One dark palette for the workspace, its catalog and its laboratories.
;; The :ui-* tokens are the catalog's own names, so unselected chips, ghost
;; buttons, panels and disabled states stay legible on this dark surface
;; instead of inheriting the light defaults.

;;; Code:

(defconst etaf-algo-lab-palette
  '(:fg "#E5EDF7" :muted "#9CADC1" :bg "#101925" :surface "#182332"
    :accent "#356BB2" :accent-soft "#25374F" :line "#2B3A4E"
    :ui-fg "#E5EDF7" :ui-bg "#101925" :ui-border "#2B3A4E"
    :ui-muted-fg "#9CADC1" :ui-success-fg "#4ADE80" :ui-danger-fg "#F87171"
    :ui-panel-fg "#E5EDF7" :ui-panel-bg "#182332" :ui-panel-border "#2B3A4E"
    :ui-button-primary-fg "#FFFFFF" :ui-button-primary-bg "#356BB2"
    :ui-button-primary-border "#356BB2"
    :ui-button-secondary-fg "#DCE6F5" :ui-button-secondary-bg "#25374F"
    :ui-button-secondary-border "#25374F"
    :ui-button-ghost-fg "#C3D0E0" :ui-button-ghost-bg "#182332"
    :ui-button-ghost-border "#2B3A4E"
    :ui-disabled-fg "#7C8CA1" :ui-disabled-bg "#1B2534"
    :ui-disabled-border "#26344A"
    :ui-table-border "#2B3A4E" :ui-table-selected-fg "#E4ECFF"
    :ui-table-selected-bg "#25374F" :ui-pagination-muted-fg "#9CADC1")
  "Semantic colors shared by the workspace chrome and every laboratory.")

(defun etaf-algo-lab-token (key)
  "Return the shared palette value for KEY."
  (plist-get etaf-algo-lab-palette key))

(provide 'etaf-algo-lab-theme)
;;; etaf-algo-lab-theme.el ends here
