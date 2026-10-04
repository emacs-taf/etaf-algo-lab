# etaf-algo-lab

Learn algorithms by watching them, steering them and comparing them — inside Emacs.

`etaf-algo-lab` is a normal ETAF application above `etaf` and `etaf-ui`. It is not
a single demo: one shared player runs any number of laboratories, and every
laboratory describes only its own algorithm and cells.

## What it is for

| Level | Who | What the workspace gives |
| --- | --- | --- |
| Learn | No prior knowledge | Plain-language introduction, live narration of the current phase, and a one-step-at-a-time animation that explains itself |
| Feel | You know the algorithm | Play, pause, single step, change speed and data, switch algorithms, watch the counters move |
| Explore | You want to compare or question | **批量对比** runs every algorithm headlessly on the current input and reports their real work counts side by side |

Nothing here assumes a textbook. Colors, vocabulary and the difference between
the algorithms are stated on screen, and every counter is paired with a sentence.

## Laboratories

| Laboratory | Algorithms | Board |
| --- | --- | --- |
| 寻路实验台 | A* (Manhattan heuristic), Dijkstra, BFS | editable grid with walls, start and goal |
| 排序实验台 | bubble, insertion, selection, bottom-up merge | 14-bar chart of one fixed input |

## Usage

Add this repository root and the ETAF, ETAF UI, Ebox and ECSS roots to
`load-path`, then load the package and open the workspace:

```elisp
(require 'etaf-algo-lab)
(etaf-algo-lab-open)          ; default laboratory
(etaf-algo-lab-open 'sorting) ; a specific laboratory
(etaf-algo-lab-labs)          ; ('pathfinding 'sorting)
```

`M-x etaf-algo-lab-open` selects the default laboratory; with a prefix argument
it asks by title. `M-x etaf-algo-lab-close` releases the workspace.

| Key | Action |
| --- | --- |
| `p` | start or pause |
| `n` | one step |
| `f` | jump to the end without animation |
| `r` | reset the current laboratory |
| `c` | batch comparison |
| `q` | close |
| arrows, `RET`, `TAB` | move cell focus, use the cell tool, reach the controls |

Every laboratory's own hint line is appended to that list, so the keyboard
surface is always visible.

## Layout

```
etaf-algo-lab.el              entry: public API and autoloads
lisp/etaf-algo-lab-app.el     application layer: catalog, buffer, lifecycle
lisp/etaf-algo-lab-player.el  laboratory contract, playback and control surface
lisp/etaf-algo-lab-pathfinding.el  laboratory: search engine + adapter
lisp/etaf-algo-lab-sorting.el      laboratory: sort machines + adapter
lisp/etaf-algo-lab-theme.el   shared palette
```

The player owns play/pause/step/finish/reset/speed, the bounded timer, the live
lines, the comparison run, the keymap and cleanup. A laboratory supplies a
model, one `step`, a terminal predicate, and presentation callbacks. The board
itself comes from the catalog: `etaf-ui`'s `etaf-tile-grid`.

Dependencies point one way: `app` → laboratories → `player` → `etaf`/`etaf-ui`.
Adding a laboratory means adding one file that registers a laboratory record;
the player, keys, comparison button and layout come for free.

## Performance

**Measured state: a single step costs ~340 ms and the 100 ms budget fails.**
The publication is *not* the problem (3.3 ms, `full-root=nil`, 42 touched
characters); the commit is. Ebox answers every reactive write with
`ordinary-fallback`/`mixed-owner-reflow`: only 4 objects reconcile, but the
whole tree is laid out again (layout 240 ms, projection 42 ms) because the
patch proof cannot stay local — the step dirties several owners in two
different subtrees (counters/narration/memory on the left, board cells on the
right).

Eliminated by minimal reproduction (each still `native-frame`, ~12 ms): the
wrapping flex skeleton, the padded card box, a theme provided at the root, an
`:if` label that reads a ref during render, and a component boundary around
the board. The remaining difference between those reproductions and this
workspace is the number of owners a step dirties and the size of the tree
(~780 objects).

The documented way out for hot paths is to stop writing reactive refs per
step and publish retained Host content updates instead (the route
`etaf-runtime-update-host-content` and the catalog's retained-icon pattern
use); that bypasses the render pipeline entirely. Until that lands, treat the
animation as functionally complete but not performance-accepted.

A hidden window, a finished laboratory and a closed or replaced buffer all
stop the animation, and one timer per mount is the only scheduled work. `make gui` and the shared driver measure the real
step; `benchmarks/performance-scenarios.el` registers the workloads:

```sh
python3 ../scripts/performance.py run --mode gui --server <owned-server> \
  --scenario-file benchmarks/performance-scenarios.el \
  --scenario 'algolab.*' --sets 3 --samples 30 --warmups 5
```

## Checks

```sh
make check   # structure, compilation, public acceptance, API boundary
make gui     # 20 real GUI actions in an existing owned server; prints evidence
```

`make gui` writes window-only screenshots plus `result.json`. A passing run
proves the functional assertions only; review the images, and treat background
timing as a screen rather than a foreground latency certificate.
