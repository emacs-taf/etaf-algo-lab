;;; etaf-algo-lab-sorting.el --- Comparison-sorting laboratory -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Four comparison sorts over one bar chart: bubble, insertion, selection and
;; bottom-up merge.  Each visible step is one comparison, one write or one
;; range transition, so the animation shows where the work really goes.
;; Columns own one value ref and one role ref, so a step rewrites only the
;; columns it touched instead of repainting the whole chart.

;;; Code:

(require 'cl-lib)
(require 'etaf)
(require 'etaf-ui)
(require 'etaf-algo-lab-player)

(defconst etaf-algo-lab--sort-colors
  '((bar . "#3B6EA5") (sorted . "#2F7D5B") (compare . "#C9A227")
    (write . "#7C4DBE"))
  "Bar colors of the sorting laboratory.")

(defconst etaf-algo-lab--sort-input
  [8 3 12 1 14 6 10 2 13 5 11 7 9 4]
  "Fixed input so every run and every comparison is reproducible.")

(defconst etaf-algo-lab--sort-names
  '((bubble . "冒泡") (insert . "插入") (select . "选择") (merge . "归并"))
  "Display names of the sorting algorithms.")

(cl-defstruct (etaf-algo-lab--sort-model (:constructor etaf-algo-lab--sort-model-create))
  "State of one sorting run."
  n levels algorithm values roles marks comparisons writes record
  sorted-upto phase i j k width left mid right out temp)

(defun etaf-algo-lab--sort-name (algorithm)
  "Return the display name of ALGORITHM."
  (or (cdr (assq algorithm etaf-algo-lab--sort-names)) "?"))

(defun etaf-algo-lab--sort-model-make (n levels)
  "Create a sorting model with N columns and LEVELS bar rows."
  (etaf-algo-lab--sort-model-create
   :n n :levels levels :algorithm (etaf-ref 'bubble)
   :comparisons 0 :writes 0 :sorted-upto 0
   :values (vconcat (cl-loop for index below n
                             collect (etaf-ref (aref etaf-algo-lab--sort-input index))))
   :roles (vconcat (cl-loop repeat n collect (etaf-ref 'bar)))))

(defun etaf-algo-lab--sort-value (model index)
  "Return MODEL's value at INDEX."
  (etaf-value (aref (etaf-algo-lab--sort-model-values model) index)))

(defun etaf-algo-lab--sort-set (model index value)
  "Store VALUE at INDEX in MODEL."
  (setf (etaf-value (aref (etaf-algo-lab--sort-model-values model) index)) value))

(defun etaf-algo-lab--sort-mark (model index role)
  "Highlight INDEX in MODEL with ROLE until its next step."
  (let ((ref (aref (etaf-algo-lab--sort-model-roles model) index)))
    (push (cons index (etaf-value ref)) (etaf-algo-lab--sort-model-marks model))
    (setf (etaf-value ref) role)))

(defun etaf-algo-lab--sort-restore (model)
  "Restore the roles MODEL highlighted during its previous step."
  (dolist (mark (etaf-algo-lab--sort-model-marks model))
    (setf (etaf-value (aref (etaf-algo-lab--sort-model-roles model) (car mark)))
          (cdr mark)))
  (setf (etaf-algo-lab--sort-model-marks model) nil))

(defun etaf-algo-lab--sort-settle (model from to)
  "Mark the settled columns FROM up to TO of MODEL as sorted."
  (cl-loop for index from (max 0 from) below (min to (etaf-algo-lab--sort-model-n model))
           unless (eq (etaf-value (aref (etaf-algo-lab--sort-model-roles model) index))
                      'sorted)
           do (setf (etaf-value (aref (etaf-algo-lab--sort-model-roles model) index))
                    'sorted)))

(defun etaf-algo-lab--sort-finish (model)
  "Mark MODEL complete and remember its comparison count."
  (etaf-algo-lab--sort-settle model 0 (etaf-algo-lab--sort-model-n model))
  (setf (etaf-algo-lab--sort-model-phase model) 'done
        (etaf-algo-lab--sort-model-record model)
        (cons (cons (etaf-value (etaf-algo-lab--sort-model-algorithm model))
                    (etaf-algo-lab--sort-model-comparisons model))
              (assq-delete-all (etaf-value (etaf-algo-lab--sort-model-algorithm model))
                               (etaf-algo-lab--sort-model-record model)))))

(defun etaf-algo-lab--sort-swap (model left right)
  "Swap MODEL's LEFT and RIGHT values and count two writes."
  (let ((a (etaf-algo-lab--sort-value model left))
        (b (etaf-algo-lab--sort-value model right)))
    (etaf-algo-lab--sort-set model left b)
    (etaf-algo-lab--sort-set model right a)
    (cl-incf (etaf-algo-lab--sort-model-writes model) 2)))

(defun etaf-algo-lab--sort-bubble-step (model)
  "Advance MODEL's bubble sort by one comparison or one settled column."
  (let ((n (etaf-algo-lab--sort-model-n model))
        (i (etaf-algo-lab--sort-model-i model))
        (j (etaf-algo-lab--sort-model-j model)))
    (cond
     ((>= i (1- n)) (etaf-algo-lab--sort-finish model))
     ((>= j (- n 1 i))
      (etaf-algo-lab--sort-settle model (- n i 1) (- n i))
      (setf (etaf-algo-lab--sort-model-i model) (1+ i)
            (etaf-algo-lab--sort-model-j model) 0))
     (t
      (cl-incf (etaf-algo-lab--sort-model-comparisons model))
      (etaf-algo-lab--sort-mark model j 'compare)
      (etaf-algo-lab--sort-mark model (1+ j) 'compare)
      (when (> (etaf-algo-lab--sort-value model j)
               (etaf-algo-lab--sort-value model (1+ j)))
        (etaf-algo-lab--sort-swap model j (1+ j))
        (etaf-algo-lab--sort-mark model j 'write)
        (etaf-algo-lab--sort-mark model (1+ j) 'write))
      (setf (etaf-algo-lab--sort-model-j model) (1+ j))))))

(defun etaf-algo-lab--sort-land (model next)
  "Mark MODEL's prefix up to NEXT as sorted and continue from NEXT."
  (etaf-algo-lab--sort-settle model (etaf-algo-lab--sort-model-sorted-upto model) next)
  (setf (etaf-algo-lab--sort-model-sorted-upto model) next
        (etaf-algo-lab--sort-model-i model) next
        (etaf-algo-lab--sort-model-j model) next))

(defun etaf-algo-lab--sort-insert-step (model)
  "Advance MODEL's insertion sort by one comparison or one landing."
  (let ((n (etaf-algo-lab--sort-model-n model))
        (i (etaf-algo-lab--sort-model-i model))
        (j (etaf-algo-lab--sort-model-j model)))
    (cond
     ((>= i n) (etaf-algo-lab--sort-finish model))
     ((<= j 0) (etaf-algo-lab--sort-land model (1+ i)))
     (t
      (cl-incf (etaf-algo-lab--sort-model-comparisons model))
      (etaf-algo-lab--sort-mark model (1- j) 'compare)
      (etaf-algo-lab--sort-mark model j 'compare)
      (if (> (etaf-algo-lab--sort-value model (1- j))
             (etaf-algo-lab--sort-value model j))
          (progn
            (etaf-algo-lab--sort-swap model (1- j) j)
            (etaf-algo-lab--sort-mark model (1- j) 'write)
            (etaf-algo-lab--sort-mark model j 'write)
            (setf (etaf-algo-lab--sort-model-j model) (1- j)))
        (etaf-algo-lab--sort-land model (1+ i)))))))

(defun etaf-algo-lab--sort-select-step (model)
  "Advance MODEL's selection sort by one comparison or one settled column."
  (let ((n (etaf-algo-lab--sort-model-n model))
        (i (etaf-algo-lab--sort-model-i model))
        (j (etaf-algo-lab--sort-model-j model))
        (k (etaf-algo-lab--sort-model-k model)))
    (cond
     ((>= i (1- n)) (etaf-algo-lab--sort-finish model))
     ((>= j n)
      (when (/= i k)
        (etaf-algo-lab--sort-mark model i 'write)
        (etaf-algo-lab--sort-mark model k 'write)
        (etaf-algo-lab--sort-swap model i k))
      (let ((next (1+ i)))
        (etaf-algo-lab--sort-settle model (etaf-algo-lab--sort-model-sorted-upto model) next)
        (setf (etaf-algo-lab--sort-model-sorted-upto model) next
              (etaf-algo-lab--sort-model-i model) next
              (etaf-algo-lab--sort-model-j model) (1+ next)
              (etaf-algo-lab--sort-model-k model) next)))
     (t
      (cl-incf (etaf-algo-lab--sort-model-comparisons model))
      (etaf-algo-lab--sort-mark model j 'compare)
      (etaf-algo-lab--sort-mark model k 'compare)
      (when (< (etaf-algo-lab--sort-value model j)
               (etaf-algo-lab--sort-value model k))
        (setf (etaf-algo-lab--sort-model-k model) j))
      (setf (etaf-algo-lab--sort-model-j model) (1+ j))))))

(defun etaf-algo-lab--sort-merge-step (model)
  "Advance MODEL's bottom-up merge sort by one comparison or one write."
  (let ((n (etaf-algo-lab--sort-model-n model)))
    (pcase (etaf-algo-lab--sort-model-phase model)
      ('advance
       (let ((width (etaf-algo-lab--sort-model-width model))
             (left (etaf-algo-lab--sort-model-left model)))
         (cond
          ((>= width n) (etaf-algo-lab--sort-finish model))
          ((>= left n)
           (setf (etaf-algo-lab--sort-model-width model) (* 2 width)
                 (etaf-algo-lab--sort-model-left model) 0)
           (when (>= (* 2 width) n) (etaf-algo-lab--sort-finish model)))
          (t
           (let ((mid (min (+ left width) n))
                 (right (min (+ left (* 2 width)) n)))
             (if (>= mid right)
                 (setf (etaf-algo-lab--sort-model-left model) (+ left (* 2 width)))
               (setf (etaf-algo-lab--sort-model-mid model) mid
                     (etaf-algo-lab--sort-model-right model) right
                     (etaf-algo-lab--sort-model-i model) left
                     (etaf-algo-lab--sort-model-j model) mid
                     (etaf-algo-lab--sort-model-out model) left
                     (etaf-algo-lab--sort-model-temp model)
                     (or (etaf-algo-lab--sort-model-temp model) (make-vector n nil))
                     (etaf-algo-lab--sort-model-phase model) 'merge)))))))
      ('merge
       (let* ((i (etaf-algo-lab--sort-model-i model))
              (j (etaf-algo-lab--sort-model-j model))
              (mid (etaf-algo-lab--sort-model-mid model))
              (right (etaf-algo-lab--sort-model-right model))
              (out (etaf-algo-lab--sort-model-out model))
              (temp (etaf-algo-lab--sort-model-temp model))
              (take-left (cond ((>= i mid) nil)
                               ((>= j right) t)
                               (t (cl-incf (etaf-algo-lab--sort-model-comparisons model))
                                  (<= (etaf-algo-lab--sort-value model i)
                                      (etaf-algo-lab--sort-value model j))))))
         (if take-left
             (progn (aset temp out (etaf-algo-lab--sort-value model i))
                    (etaf-algo-lab--sort-mark model i 'compare)
                    (setf (etaf-algo-lab--sort-model-i model) (1+ i)))
           (progn (aset temp out (etaf-algo-lab--sort-value model j))
                  (etaf-algo-lab--sort-mark model j 'compare)
                  (setf (etaf-algo-lab--sort-model-j model) (1+ j))))
         (etaf-algo-lab--sort-mark model out 'write)
         (setf (etaf-algo-lab--sort-model-out model) (1+ out))
         (when (>= (1+ out) right)
           (setf (etaf-algo-lab--sort-model-phase model) 'copy
                 (etaf-algo-lab--sort-model-out model) (etaf-algo-lab--sort-model-left model)))))
      ('copy
       (let ((out (etaf-algo-lab--sort-model-out model))
             (right (etaf-algo-lab--sort-model-right model)))
         (etaf-algo-lab--sort-set model out
                                 (aref (etaf-algo-lab--sort-model-temp model) out))
         (etaf-algo-lab--sort-mark model out 'write)
         (cl-incf (etaf-algo-lab--sort-model-writes model))
         (setf (etaf-algo-lab--sort-model-out model) (1+ out))
         (when (>= (1+ out) right)
           (setf (etaf-algo-lab--sort-model-left model)
                 (+ (etaf-algo-lab--sort-model-left model)
                    (* 2 (etaf-algo-lab--sort-model-width model)))
                 (etaf-algo-lab--sort-model-phase model) 'advance)))))
    model))

(defun etaf-algo-lab--sort-step (model)
  "Advance MODEL by exactly one visible step."
  (etaf-algo-lab--sort-restore model)
  (pcase (etaf-value (etaf-algo-lab--sort-model-algorithm model))
    ('bubble (etaf-algo-lab--sort-bubble-step model))
    ('insert (etaf-algo-lab--sort-insert-step model))
    ('select (etaf-algo-lab--sort-select-step model))
    ('merge (etaf-algo-lab--sort-merge-step model)))
  model)

(defun etaf-algo-lab--sort-terminal (model)
  "Return non-nil when MODEL has finished sorting."
  (eq (etaf-algo-lab--sort-model-phase model) 'done))

(defun etaf-algo-lab--sort-reset (model)
  "Return MODEL to its initial data and settings."
  (let ((n (etaf-algo-lab--sort-model-n model))
        (algorithm (etaf-value (etaf-algo-lab--sort-model-algorithm model))))
    (dotimes (index n)
      (etaf-algo-lab--sort-set model index (aref etaf-algo-lab--sort-input index))
      (setf (etaf-value (aref (etaf-algo-lab--sort-model-roles model) index)) 'bar))
    (setf (etaf-algo-lab--sort-model-marks model) nil
          (etaf-algo-lab--sort-model-comparisons model) 0
          (etaf-algo-lab--sort-model-writes model) 0
          (etaf-algo-lab--sort-model-temp model) nil
          (etaf-algo-lab--sort-model-sorted-upto model) 0
          (etaf-algo-lab--sort-model-width model) 1
          (etaf-algo-lab--sort-model-left model) 0
          (etaf-algo-lab--sort-model-j model) 0
          (etaf-algo-lab--sort-model-k model) 0)
    (pcase algorithm
      ('bubble (setf (etaf-algo-lab--sort-model-phase model) 'bubble
                     (etaf-algo-lab--sort-model-i model) 0))
      ('insert (setf (etaf-algo-lab--sort-model-phase model) 'insert
                     (etaf-algo-lab--sort-model-i model) 1
                     (etaf-algo-lab--sort-model-j model) 1
                     (etaf-algo-lab--sort-model-sorted-upto model) 1))
      ('select (setf (etaf-algo-lab--sort-model-phase model) 'select
                     (etaf-algo-lab--sort-model-i model) 0
                     (etaf-algo-lab--sort-model-j model) 1))
      ('merge (setf (etaf-algo-lab--sort-model-phase model) 'advance
                    (etaf-algo-lab--sort-model-temp model) (make-vector n nil)))))
  model)

(defun etaf-algo-lab--sort-run (algorithm n levels)
  "Run ALGORITHM headlessly on N columns of LEVELS; return counts."
  (let* ((model (etaf-algo-lab--sort-model-make n levels))
         (_ (progn (etaf-algo-lab--sort-reset model)
                   (setf (etaf-value (etaf-algo-lab--sort-model-algorithm model))
                         algorithm)
                   (etaf-algo-lab--sort-reset model))))
    (while (not (etaf-algo-lab--sort-terminal model))
      (etaf-algo-lab--sort-step model))
    (cons (etaf-algo-lab--sort-model-comparisons model)
          (etaf-algo-lab--sort-model-writes model))))

;;; Laboratory adapter.

(defun etaf-algo-lab--sort-session-model (session)
  "Return SESSION's sorting model."
  (etaf-algo-lab--session-model session))

(defun etaf-algo-lab--sort-counters (model)
  "Return MODEL's counter line."
  (format "比较 %d 次 · 写入 %d 次"
          (etaf-algo-lab--sort-model-comparisons model)
          (etaf-algo-lab--sort-model-writes model)))

(defun etaf-algo-lab--sort-narration (model)
  "Return MODEL's plain-language narration line."
  (if (etaf-algo-lab--sort-terminal model)
      "完成。点「批量对比」看四种算法各比较了多少次。"
    (pcase (etaf-value (etaf-algo-lab--sort-model-algorithm model))
      ('bubble "冒泡：相邻两列大的换到右边；一趟下来最大的沉到末尾。")
      ('insert "插入：右边的新数字往左挪，直到找到它该待的位置。")
      ('select "选择：每轮挑出剩下最小的，放到已排好的后面。")
      ('merge "归并：先两两合并成有序小段，再合成整段。"))))

(defun etaf-algo-lab--sort-memory (model)
  "Return MODEL's cross-run memory line."
  (let ((record (etaf-algo-lab--sort-model-record model)))
    (if record
        (concat "跑完记录（比较次数）："
                (mapconcat (lambda (algorithm)
                             (let ((count (alist-get algorithm record)))
                               (format "%s %s" (etaf-algo-lab--sort-name algorithm)
                                       (if count (number-to-string count) "未跑"))))
                           '(bubble insert select merge) " · "))
      "跑完后这里记住每种算法比较了多少次。")))

(defun etaf-algo-lab--sort-legend (_session)
  "Return the sorting legend."
  (etaf-view
   (flex :flex-wrap 'wrap :gap '((lh 0) (ch 1))
     (text :background-color (cdr (assq 'bar etaf-algo-lab--sort-colors)) " 柱＝数值 ")
     (text :background-color (cdr (assq 'compare etaf-algo-lab--sort-colors)) " 正在比较 ")
     (text :background-color (cdr (assq 'write etaf-algo-lab--sort-colors)) " 正在写回 ")
     (text :background-color (cdr (assq 'sorted etaf-algo-lab--sort-colors)) " 已排好 "))))

(defconst etaf-algo-lab--sort-cell-width 2
  "Column width of the sorting chart in characters.")

(defun etaf-algo-lab--sort-gap-column-p (column)
  "Return non-nil when grid COLUMN is the separator between two bars.
Every bar owns one two-character column and every pair of bars is separated
by one dark gap column, so neighbouring bars never read as one block."
  (= 1 (mod column 2)))

(defun etaf-algo-lab--sort-bar-index (column)
  "Return the model index shown in grid COLUMN."
  (/ column 2))

(defun etaf-algo-lab--sort-values-text (model)
  "Return MODEL's values as one line aligned under the chart columns.
Every bar owns a two-character column and every gap owns two characters, so
each value is printed in two characters followed by two filler spaces."
  (let ((bars (etaf-algo-lab--sort-model-n model)))
    (mapconcat (lambda (index)
                 (format "%2d" (etaf-value
                                (aref (etaf-algo-lab--sort-model-values model) index))))
               (number-sequence 0 (1- bars)) "  ")))

(etaf-define-component etaf-algo-lab--sort-board (&key session)
  "Render the bar chart of SESSION with its values under the columns.
The chart is one fixed-width block so the surrounding panel can hug it
instead of stretching into an empty strip.  Bars never touch: every bar is
separated from its neighbour by one dark gap column.  The `sort-values' host
is the values line, so its bounds locate the chart row and its text carries
every value exactly once."
  :render
  (let* ((model (etaf-algo-lab--sort-session-model session))
         (bars (etaf-algo-lab--sort-model-n model))
         (levels (etaf-algo-lab--sort-model-levels model))
         (grid-columns (1- (* bars 2))))
    (etaf-view
     (column :item-gap '(lh 0)
       (expr
        (etaf-node
         'etaf-tile-grid
         (list :rows levels :columns grid-columns
               :cell-width etaf-algo-lab--sort-cell-width
               :cell-background
               (lambda (row column)
                 (if (etaf-algo-lab--sort-gap-column-p column)
                     "#101925"
                   (let* ((index (etaf-algo-lab--sort-bar-index column))
                          (value (etaf-value
                                  (aref (etaf-algo-lab--sort-model-values model) index)))
                          (role (etaf-value
                                 (aref (etaf-algo-lab--sort-model-roles model) index))))
                     (if (< row (- levels value))
                         "#101925"
                       (cdr (assq role etaf-algo-lab--sort-colors))))))
               :cell-text (lambda (_row _column) " "))
         nil))
       (box :width (list 'ch (* grid-columns etaf-algo-lab--sort-cell-width))
            :height '(lh 1) :wrap-mode 'none :overflow 'hidden
         (text :ref 'sort-values :color "#9CADC1"
               (expr (etaf-algo-lab--sort-values-text model))))))))

(etaf-define-component etaf-algo-lab--sort-controls (&key session)
  "Render SESSION's algorithm selector."
  :render
  (let ((model (etaf-algo-lab--sort-session-model session)))
    (etaf-view
     (etaf-select :label "算法" :ref 'sort-algorithm
                  :value (etaf-value (etaf-algo-lab--sort-model-algorithm model))
                  :options '((bubble . "冒泡") (insert . "插入")
                             (select . "选择") (merge . "归并"))
                  :presentation 'chips
                  :on-change
                  (lambda (next)
                    (setf (etaf-value (etaf-algo-lab--sort-model-algorithm model)) next)
                    (etaf-algo-lab--restart
                     session (format "算法已切换为%s，数据从头开始。"
                                     (etaf-algo-lab--sort-name next))))))))

(defun etaf-algo-lab--sort-compare (model)
  "Return headless comparison rows on MODEL's current input."
  (let ((n (etaf-algo-lab--sort-model-n model))
        (levels (etaf-algo-lab--sort-model-levels model)))
    (mapcar (lambda (algorithm)
              (let ((result (etaf-algo-lab--sort-run algorithm n levels)))
                (cons (etaf-algo-lab--sort-name algorithm)
                      (format "%s：比较 %d 次 · 写入 %d 次"
                              (etaf-algo-lab--sort-name algorithm)
                              (car result) (cdr result)))))
            '(bubble insert select merge))))

(defconst etaf-algo-lab--sort-lab
  (etaf-algo-lab--make-lab
   :id 'sorting :title "排序实验台"
   :summary "四种比较排序在同一组数据上的比较与写回次数"
   :intro '("每一列的高度就是一个数字，最下面一行是它的值。"
            "黄色 = 正在比较，紫色 = 正在写回，绿色 = 已经排好。")
   :create (lambda () (etaf-algo-lab--sort-reset (etaf-algo-lab--sort-model-make 14 14)))
   :step #'etaf-algo-lab--sort-step
   :terminal #'etaf-algo-lab--sort-terminal
   :reset #'etaf-algo-lab--sort-reset
   :narration #'etaf-algo-lab--sort-narration
   :counters #'etaf-algo-lab--sort-counters
   :memory #'etaf-algo-lab--sort-memory
   :board 'etaf-algo-lab--sort-board
   :controls 'etaf-algo-lab--sort-controls
   :legend #'etaf-algo-lab--sort-legend
   :keys nil
   :keys-hint ""
   :reset-notice "已回到初始数据，算法保持不变。"
   :compare #'etaf-algo-lab--sort-compare)
  "The sorting laboratory.")

(etaf-algo-lab--register-lab etaf-algo-lab--sort-lab)

(provide 'etaf-algo-lab-sorting)
;;; etaf-algo-lab-sorting.el ends here
