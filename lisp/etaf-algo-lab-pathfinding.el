;;; etaf-algo-lab-pathfinding.el --- Grid pathfinding laboratory -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Three search variants over one editable grid: A* (Manhattan heuristic),
;; Dijkstra (the same expansion without a heuristic) and BFS (uniform cost).
;; The engine is pure and testable headless; the laboratory adapter below it
;; only projects model state into refs, callbacks and plain-language copy.

;;; Code:

(require 'cl-lib)
(require 'etaf)
(require 'etaf-ui)
(require 'etaf-algo-lab-player)

(defconst etaf-algo-lab--pf-colors
  '((empty . "#182332") (wall . "#46546C") (frontier . "#167B9A")
    (visited . "#25445D") (current . "#9752BA") (path . "#8D6C1C")
    (start . "#176D50") (goal . "#98435C"))
  "Cell colors of the pathfinding laboratory.")

;;; Engine: deterministic four-way search with unit cost.

(cl-defstruct (etaf-algo-lab--pf-search (:constructor etaf-algo-lab--pf-search-create))
  rows columns walls start goal algorithm costs parents closed queue
  (head 0) (tail 0) heap (heap-size 0) (serial 0) (frontier 1)
  (expanded 0) (phase 'search) path distance)

(defun etaf-algo-lab--pf-heuristic (search index)
  "Return SEARCH's estimated remaining cost from INDEX."
  (if (eq (etaf-algo-lab--pf-search-algorithm search) 'bfs)
      0
    (if (eq (etaf-algo-lab--pf-search-algorithm search) 'dijkstra)
        0
      (let ((columns (etaf-algo-lab--pf-search-columns search))
            (goal (etaf-algo-lab--pf-search-goal search)))
        (+ (abs (- (% index columns) (% goal columns)))
           (abs (- (/ index columns) (/ goal columns))))))))

(defun etaf-algo-lab--pf-before-p (left right)
  "Order heap entries LEFT and RIGHT by f, then larger g, then arrival."
  (or (< (aref left 0) (aref right 0))
      (and (= (aref left 0) (aref right 0))
           (or (< (aref left 1) (aref right 1))
               (and (= (aref left 1) (aref right 1))
                    (< (aref left 2) (aref right 2)))))))

(defun etaf-algo-lab--pf-heap-push (search index cost)
  "Insert INDEX with COST into SEARCH's binary min-heap."
  (let* ((size (etaf-algo-lab--pf-search-heap-size search))
         (heap (etaf-algo-lab--pf-search-heap search))
         (entry (vector (+ cost (etaf-algo-lab--pf-heuristic search index))
                        (- cost) (cl-incf (etaf-algo-lab--pf-search-serial search))
                        index)))
    (when (= size (length heap))
      (setq heap (vconcat heap (make-vector (max 1 size) nil)))
      (setf (etaf-algo-lab--pf-search-heap search) heap))
    (let ((position size))
      (while (and (> position 0)
                  (etaf-algo-lab--pf-before-p
                   entry (aref heap (/ (1- position) 2))))
        (aset heap position (aref heap (/ (1- position) 2)))
        (setq position (/ (1- position) 2)))
      (aset heap position entry))
    (cl-incf (etaf-algo-lab--pf-search-heap-size search))))

(defun etaf-algo-lab--pf-heap-pop (search)
  "Remove the minimum entry from SEARCH, returning its cell index or nil."
  (when (> (etaf-algo-lab--pf-search-heap-size search) 0)
    (let* ((heap (etaf-algo-lab--pf-search-heap search))
           (top (aref heap 0))
           (size (cl-decf (etaf-algo-lab--pf-search-heap-size search)))
           (last (aref heap size)) (position 0))
      (aset heap size nil)
      (when (> size 0)
        (let (finished)
          (while (not finished)
            (let ((child (1+ (* 2 position))))
              (if (>= child size) (setq finished t)
                (when (and (< (1+ child) size)
                           (etaf-algo-lab--pf-before-p
                            (aref heap (1+ child)) (aref heap child)))
                  (cl-incf child))
                (if (etaf-algo-lab--pf-before-p (aref heap child) last)
                    (progn (aset heap position (aref heap child))
                           (setq position child))
                  (setq finished t)))))
          (aset heap position last)))
      (aref top 3))))

(defun etaf-algo-lab--pf-search-make (rows columns walls start goal algorithm)
  "Create an isolated search over ROWS, COLUMNS, WALLS and endpoints."
  (let* ((count (* rows columns))
         (search (etaf-algo-lab--pf-search-create
                  :rows rows :columns columns :walls (copy-sequence walls)
                  :start start :goal goal :algorithm algorithm
                  :costs (make-vector count -1) :parents (make-vector count nil)
                  :closed (make-vector count nil) :queue (make-vector count nil)
                  :heap (make-vector count nil))))
    (aset (etaf-algo-lab--pf-search-costs search) start 0)
    (if (eq algorithm 'bfs)
        (progn (aset (etaf-algo-lab--pf-search-queue search) 0 start)
               (setf (etaf-algo-lab--pf-search-tail search) 1))
      (etaf-algo-lab--pf-heap-push search start 0))
    search))

(defun etaf-algo-lab--pf-neighbors (search index)
  "Return SEARCH's in-bounds neighbors of INDEX in right/down/left/up order."
  (let ((columns (etaf-algo-lab--pf-search-columns search))
        (rows (etaf-algo-lab--pf-search-rows search)) result)
    (when (> (/ index columns) 0) (push (- index columns) result))
    (when (> (% index columns) 0) (push (1- index) result))
    (when (< (/ index columns) (1- rows)) (push (+ index columns) result))
    (when (< (% index columns) (1- columns)) (push (1+ index) result))
    result))

(defun etaf-algo-lab--pf-search-step (search)
  "Advance SEARCH once; return the changed cells as (INDEX . STATE) pairs."
  (pcase (etaf-algo-lab--pf-search-phase search)
    ('trace
     (let ((index (pop (etaf-algo-lab--pf-search-path search))))
       (unless (etaf-algo-lab--pf-search-path search)
         (setf (etaf-algo-lab--pf-search-phase search) 'found))
       (when index (list (cons index 'path)))))
    ('search
     (let (index changes)
       (if (eq (etaf-algo-lab--pf-search-algorithm search) 'bfs)
           (when (< (etaf-algo-lab--pf-search-head search)
                    (etaf-algo-lab--pf-search-tail search))
             (setq index (aref (etaf-algo-lab--pf-search-queue search)
                               (etaf-algo-lab--pf-search-head search)))
             (cl-incf (etaf-algo-lab--pf-search-head search)))
         (while (and (> (etaf-algo-lab--pf-search-heap-size search) 0)
                     (null index))
           (let ((next (etaf-algo-lab--pf-heap-pop search)))
             (unless (aref (etaf-algo-lab--pf-search-closed search) next)
               (setq index next)))))
       (if (null index)
           (setf (etaf-algo-lab--pf-search-phase search) 'unreachable)
         (aset (etaf-algo-lab--pf-search-closed search) index t)
         (cl-incf (etaf-algo-lab--pf-search-expanded search))
         (cl-decf (etaf-algo-lab--pf-search-frontier search))
         (push (cons index 'current) changes)
         (if (= index (etaf-algo-lab--pf-search-goal search))
             (let ((cursor index) route)
               (while cursor
                 (push cursor route)
                 (setq cursor (aref (etaf-algo-lab--pf-search-parents search) cursor)))
               (let ((interior (butlast (cdr route))))
                 (setf (etaf-algo-lab--pf-search-path search) interior
                       (etaf-algo-lab--pf-search-distance search) (1- (length route))
                       (etaf-algo-lab--pf-search-phase search)
                       (if interior 'trace 'found))))
           (dolist (next (etaf-algo-lab--pf-neighbors search index))
             (let ((cost (1+ (aref (etaf-algo-lab--pf-search-costs search) index)))
                   (old (aref (etaf-algo-lab--pf-search-costs search) next)))
               (when (and (not (aref (etaf-algo-lab--pf-search-walls search) next))
                          (not (aref (etaf-algo-lab--pf-search-closed search) next))
                          (or (< old 0) (< cost old)))
                 (when (< old 0) (cl-incf (etaf-algo-lab--pf-search-frontier search)))
                 (aset (etaf-algo-lab--pf-search-costs search) next cost)
                 (aset (etaf-algo-lab--pf-search-parents search) next index)
                 (if (eq (etaf-algo-lab--pf-search-algorithm search) 'bfs)
                     (progn
                       (aset (etaf-algo-lab--pf-search-queue search)
                             (etaf-algo-lab--pf-search-tail search) next)
                       (cl-incf (etaf-algo-lab--pf-search-tail search)))
                   (etaf-algo-lab--pf-heap-push search next cost))
                 (push (cons next 'frontier) changes))))))
       changes))))

;;; Model: board truth plus per-cell identities.

(cl-defstruct (etaf-algo-lab--pf-model (:constructor etaf-algo-lab--pf-model-create))
  rows columns walls cells start goal search current algorithm tool record)

(defun etaf-algo-lab--pf-model-make (rows columns)
  "Create a bounded board of ROWS by COLUMNS."
  (let* ((count (* rows columns))
         (model (etaf-algo-lab--pf-model-create
                 :rows rows :columns columns :walls (make-vector count nil)
                 :cells (vconcat (cl-loop repeat count collect (etaf-ref 'empty)))
                 :start (+ (* columns 2) 2)
                 :goal (+ (* columns (- rows 3)) (- columns 3))
                 :algorithm (etaf-ref 'astar) :tool (etaf-ref 'wall))))
    (etaf-algo-lab--pf-preset model)
    (etaf-algo-lab--pf-reset model)
    model))

(defun etaf-algo-lab--pf-preset (model)
  "Replace MODEL's walls with alternating corridor barriers."
  (fillarray (etaf-algo-lab--pf-model-walls model) nil)
  (let ((rows (etaf-algo-lab--pf-model-rows model))
        (columns (etaf-algo-lab--pf-model-columns model)))
    (cl-loop for column from 6 below (- columns 3) by 6
             for barrier from 0 do
             (dotimes (row rows)
               (unless (= row (if (zerop (% barrier 2)) (- rows 4) 3))
                 (aset (etaf-algo-lab--pf-model-walls model)
                       (+ (* row columns) column) t)))))
  (aset (etaf-algo-lab--pf-model-walls model) (etaf-algo-lab--pf-model-start model) nil)
  (aset (etaf-algo-lab--pf-model-walls model) (etaf-algo-lab--pf-model-goal model) nil))

(defun etaf-algo-lab--pf-paint (model index state)
  "Project STATE into MODEL's cell INDEX, keeping walls and endpoints."
  (setf (etaf-value (aref (etaf-algo-lab--pf-model-cells model) index))
        (cond ((= index (etaf-algo-lab--pf-model-start model)) 'start)
              ((= index (etaf-algo-lab--pf-model-goal model)) 'goal)
              ((aref (etaf-algo-lab--pf-model-walls model) index) 'wall)
              (t state))))

(defun etaf-algo-lab--pf-index (model row column)
  "Return MODEL's cell index for ROW and COLUMN."
  (+ (* row (etaf-algo-lab--pf-model-columns model)) column))

(defun etaf-algo-lab--pf-reset (model)
  "Rebuild MODEL's search, keeping terrain, endpoints and settings."
  (setf (etaf-algo-lab--pf-model-search model)
        (etaf-algo-lab--pf-search-make
         (etaf-algo-lab--pf-model-rows model) (etaf-algo-lab--pf-model-columns model)
         (etaf-algo-lab--pf-model-walls model) (etaf-algo-lab--pf-model-start model)
         (etaf-algo-lab--pf-model-goal model)
         (etaf-value (etaf-algo-lab--pf-model-algorithm model)))
        (etaf-algo-lab--pf-model-current model) nil)
  (dotimes (index (length (etaf-algo-lab--pf-model-cells model)))
    (etaf-algo-lab--pf-paint model index 'empty))
  (etaf-algo-lab--pf-paint model (etaf-algo-lab--pf-model-start model) 'frontier)
  model)

(defun etaf-algo-lab--pf-step (model)
  "Advance MODEL's search or route illumination by one visible step."
  (let* ((search (etaf-algo-lab--pf-model-search model))
         (phase (etaf-algo-lab--pf-search-phase search)))
    (unless (memq phase '(found unreachable))
      (when (and (eq phase 'search) (etaf-algo-lab--pf-model-current model))
        (etaf-algo-lab--pf-paint model (etaf-algo-lab--pf-model-current model) 'visited))
      (dolist (change (etaf-algo-lab--pf-search-step search))
        (when (eq (cdr change) 'current)
          (setf (etaf-algo-lab--pf-model-current model) (car change)))
        (etaf-algo-lab--pf-paint model (car change) (cdr change)))
      (when (memq (etaf-algo-lab--pf-search-phase search) '(found unreachable))
        (let* ((algorithm (etaf-algo-lab--pf-search-algorithm search))
               (record (etaf-algo-lab--pf-model-record model)))
          (setf (etaf-algo-lab--pf-model-record model)
                (cons (cons algorithm (etaf-algo-lab--pf-search-expanded search))
                      (assq-delete-all algorithm record)))))))
  model)

(defun etaf-algo-lab--pf-terminal (model)
  "Return MODEL's terminal phase, or nil while its search can continue."
  (memq (etaf-algo-lab--pf-search-phase (etaf-algo-lab--pf-model-search model))
        '(found unreachable)))

(defun etaf-algo-lab--pf-edit (model row column)
  "Apply MODEL's editing tool at ROW and COLUMN; return non-nil when changed."
  (let* ((index (etaf-algo-lab--pf-index model row column))
         (walls (etaf-algo-lab--pf-model-walls model))
         (start (etaf-algo-lab--pf-model-start model))
         (goal (etaf-algo-lab--pf-model-goal model))
         (tool (etaf-value (etaf-algo-lab--pf-model-tool model)))
         changed)
    (pcase tool
      ('start
       (unless (or (= index goal) (= index start))
         (setf (etaf-algo-lab--pf-model-start model) index)
         (aset walls index nil) (setq changed t)))
      ('goal
       (unless (or (= index start) (= index goal))
         (setf (etaf-algo-lab--pf-model-goal model) index)
         (aset walls index nil) (setq changed t)))
      ((or 'wall 'erase)
       (unless (or (= index start) (= index goal))
         (let ((next (and (eq tool 'wall) (not (aref walls index)))))
           (unless (eq next (aref walls index))
             (aset walls index next) (setq changed t))))))
    changed))

;;; Headless comparison: run one algorithm on the current board, no animation.

(defun etaf-algo-lab--pf-run (model algorithm)
  "Run ALGORITHM on MODEL's current terrain and return (EXPANDED . DISTANCE)."
  (let ((search (etaf-algo-lab--pf-search-make
                 (etaf-algo-lab--pf-model-rows model)
                 (etaf-algo-lab--pf-model-columns model)
                 (etaf-algo-lab--pf-model-walls model)
                 (etaf-algo-lab--pf-model-start model)
                 (etaf-algo-lab--pf-model-goal model) algorithm)))
    (while (not (memq (etaf-algo-lab--pf-search-phase search) '(found unreachable)))
      (etaf-algo-lab--pf-search-step search))
    (cons (etaf-algo-lab--pf-search-expanded search)
          (etaf-algo-lab--pf-search-distance search))))

(defun etaf-algo-lab--pf-name (algorithm)
  "Return the user-visible name of ALGORITHM."
  (pcase algorithm
    ('astar "A*") ('dijkstra "Dijkstra") ('bfs "BFS") (_ "?")))

;;; Laboratory adapter.

(defun etaf-algo-lab--pf-counters (model)
  "Return MODEL's counter line: explored, frontier and route length."
  (let ((search (etaf-algo-lab--pf-model-search model)))
    (format "探索 %d 格 · 前沿 %d 格 · 路径 %s 步"
            (etaf-algo-lab--pf-search-expanded search)
            (etaf-algo-lab--pf-search-frontier search)
            (or (etaf-algo-lab--pf-search-distance search) "--"))))

(defun etaf-algo-lab--pf-narration (model)
  "Return MODEL's plain-language narration line."
  (let* ((search (etaf-algo-lab--pf-model-search model))
         (phase (etaf-algo-lab--pf-search-phase search))
         (expanded (etaf-algo-lab--pf-search-expanded search)))
    (cond
     ((eq phase 'unreachable) "起点被墙围住了，终点摸不到。擦掉几堵墙再试。")
     ((eq phase 'found) "完成：黄色就是最短路线。点「批量对比」比三种算法。")
     ((eq phase 'trace) "碰到终点了，正沿记录倒推回来，把路线一格格点亮。")
     ((> expanded 0) "正在从起点向外扩散：蓝色是候选，深色是走过的。")
     (t "按「开始/继续」自动跑；想细看就按「单步」。"))))

(defun etaf-algo-lab--pf-memory (model)
  "Return MODEL's cross-run memory line."
  (let* ((record (etaf-algo-lab--pf-model-record model))
         (astar (alist-get 'astar record))
         (dijkstra (alist-get 'dijkstra record))
         (bfs (alist-get 'bfs record)))
    (if (or astar dijkstra bfs)
        (format "跑完的结果：A* %s · Dijkstra %s · BFS %s"
                (if astar (format "%d 格" astar) "未跑")
                (if dijkstra (format "%d 格" dijkstra) "未跑")
                (if bfs (format "%d 格" bfs) "未跑"))
      "跑完后这里记住每种算法摸了多少格。")))

(defun etaf-algo-lab--pf-legend (_session)
  "Return the pathfinding legend."
  (etaf-view
   (flex :flex-wrap 'wrap :gap '((lh 0) (ch 1))
     (text :background-color (cdr (assq 'start etaf-algo-lab--pf-colors)) " S 起点 ")
     (text :background-color (cdr (assq 'goal etaf-algo-lab--pf-colors)) " G 终点 ")
     (text :background-color (cdr (assq 'wall etaf-algo-lab--pf-colors)) " # 障碍 ")
     (text :background-color (cdr (assq 'frontier etaf-algo-lab--pf-colors)) " 前沿 ")
     (text :background-color (cdr (assq 'visited etaf-algo-lab--pf-colors)) " 已探索 ")
     (text :background-color (cdr (assq 'path etaf-algo-lab--pf-colors)) " 路径 "))))

(defun etaf-algo-lab--pf-cell-ref (row column)
  "Return the public address of the cell at ROW and COLUMN."
  (intern (format "pf-cell-%d-%d" row column)))

(defun etaf-algo-lab--pf-session-model (session)
  "Return SESSION's pathfinding model."
  (etaf-algo-lab--session-model session))

(defun etaf-algo-lab--pf-choose-algorithm (session next)
  "Switch SESSION to algorithm NEXT and restart its search."
  (let ((model (etaf-algo-lab--pf-session-model session)))
    (setf (etaf-value (etaf-algo-lab--pf-model-algorithm model)) next)
    (etaf-algo-lab--restart
     session (format "算法已切换为 %s，地图保持不变。" (etaf-algo-lab--pf-name next)))))

(defun etaf-algo-lab--pf-move-focus (session dr dc)
  "Move the board's logical focus by DR and DC cells inside SESSION."
  (let* ((runtime (etaf-algo-lab--session-runtime session))
         (model (etaf-algo-lab--pf-session-model session))
         (ref (etaf-focused-host-ref runtime))
         (name (and (symbolp ref) (symbol-name ref)))
         (row 0) (column 0))
    (when (and name (string-match "\\`pf-cell-\\([0-9]+\\)-\\([0-9]+\\)\\'" name))
      (setq row (string-to-number (match-string 1 name))
            column (string-to-number (match-string 2 name))))
    (etaf-focus runtime
                (etaf-algo-lab--pf-cell-ref
                 (max 0 (min (1- (etaf-algo-lab--pf-model-rows model)) (+ row dr)))
                 (max 0 (min (1- (etaf-algo-lab--pf-model-columns model)) (+ column dc)))))))

(etaf-define-component etaf-algo-lab--pf-board (&key session)
  "Render the search board of SESSION."
  :render
  (let* ((model (etaf-algo-lab--pf-session-model session)))
    (etaf-node
     'etaf-tile-grid
     (list :rows (etaf-algo-lab--pf-model-rows model)
           :columns (etaf-algo-lab--pf-model-columns model)
           :cell-width 2 :cell-ref #'etaf-algo-lab--pf-cell-ref
           :cell-background
           (lambda (row column)
             (cdr (assq (etaf-value
                         (aref (etaf-algo-lab--pf-model-cells model)
                               (etaf-algo-lab--pf-index model row column)))
                        etaf-algo-lab--pf-colors)))
           :cell-text
           (lambda (row column)
             (pcase (etaf-value (aref (etaf-algo-lab--pf-model-cells model)
                                      (etaf-algo-lab--pf-index model row column)))
               ('start "S") ('goal "G") ('wall "#") ('path "+")
               ('current "@") (_ "·")))
           :on-cell-press
           (lambda (row column)
             (when (etaf-algo-lab--pf-edit model row column)
               (etaf-algo-lab--restart session "地图改变，已从当前起点重新寻路。"))))
     nil)))

(etaf-define-component etaf-algo-lab--pf-controls (&key session)
  "Render SESSION's algorithm, tool and map controls."
  :render
  (let ((model (etaf-algo-lab--pf-session-model session)))
    (etaf-view
     (column :item-gap '(lh 1)
       (etaf-select :label "算法" :ref 'pf-algorithm
                    :value (etaf-value (etaf-algo-lab--pf-model-algorithm model))
                    :options '((astar . "A*") (dijkstra . "Dijkstra") (bfs . "BFS"))
                    :presentation 'chips
                    :on-change (lambda (next)
                                 (etaf-algo-lab--pf-choose-algorithm session next)))
       (etaf-select :label "工具" :ref 'pf-tool
                    :value (etaf-value (etaf-algo-lab--pf-model-tool model))
                    :options '((wall . "障碍") (erase . "擦除")
                               (start . "起点") (goal . "终点"))
                    :presentation 'chips
                    :on-change (lambda (next)
                                 (setf (etaf-value (etaf-algo-lab--pf-model-tool model))
                                       next)))
       (flex :flex-wrap 'wrap :gap '((lh 0) (ch 1))
         (etaf-button :label "示例地图" :ref 'pf-preset :variant 'ghost
                      :on-press (lambda ()
                                  (etaf-algo-lab--pf-preset model)
                                  (etaf-algo-lab--restart session "示例地图已载入。")))
         (etaf-button :label "清空障碍" :ref 'pf-clear :variant 'ghost
                      :on-press (lambda ()
                                  (fillarray (etaf-algo-lab--pf-model-walls model) nil)
                                  (etaf-algo-lab--restart session "障碍已清空，已重新准备搜索。"))))))))

(defun etaf-algo-lab--pf-compare (model)
  "Return headless comparison rows for MODEL's current terrain."
  (delq nil
        (mapcar
         (lambda (algorithm)
           (let ((result (etaf-algo-lab--pf-run model algorithm)))
             (cons (etaf-algo-lab--pf-name algorithm)
                   (format "%s：探索 %d 格 · 路径 %s 步"
                           (etaf-algo-lab--pf-name algorithm)
                           (car result)
                           (if (cdr result) (number-to-string (cdr result)) "不通")))))
         '(astar dijkstra bfs))))

(defconst etaf-algo-lab--pf-lab
  (etaf-algo-lab--make-lab
   :id 'pathfinding :title "寻路实验台"
   :summary "BFS、Dijkstra 与 A* 在同一张地图上的扩散范围对比"
   :intro '("蓝色 = 待检查的候选，深色 = 走过的，黄色 = 答案；随时可以改地图。"
            "A* 用「离终点大概多远」优先试更近的格子，Dijkstra 没有引导，BFS 只管步数。")
   :create (lambda () (etaf-algo-lab--pf-model-make 14 24))
   :step #'etaf-algo-lab--pf-step
   :terminal #'etaf-algo-lab--pf-terminal
   :reset #'etaf-algo-lab--pf-reset
   :narration #'etaf-algo-lab--pf-narration
   :counters #'etaf-algo-lab--pf-counters
   :memory #'etaf-algo-lab--pf-memory
   :board 'etaf-algo-lab--pf-board
   :controls 'etaf-algo-lab--pf-controls
   :legend #'etaf-algo-lab--pf-legend
   :direction (lambda (direction)
                (pcase direction
                  ('right (etaf-algo-lab--pf-move-focus etaf-algo-lab--session 0 1) 'handled)
                  ('left (etaf-algo-lab--pf-move-focus etaf-algo-lab--session 0 -1) 'handled)
                  ('down (etaf-algo-lab--pf-move-focus etaf-algo-lab--session 1 0) 'handled)
                  ('up (etaf-algo-lab--pf-move-focus etaf-algo-lab--session -1 0) 'handled)
                  (_ 'release)))
   :keys-hint "方向键 移动格子焦点 · RET 使用工具 · TAB 选控件"
   :reset-notice "已重置搜索，地图和起终点保留。"
   :compare #'etaf-algo-lab--pf-compare)
  "The pathfinding laboratory.")

(etaf-algo-lab--register-lab etaf-algo-lab--pf-lab)

(provide 'etaf-algo-lab-pathfinding)
;;; etaf-algo-lab-pathfinding.el ends here
