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

**Measured state: one step commits through the native frame, p95 ≈ 90 ms
against the 100 ms budget (GUI, 3 sets × 30 samples + 5 warmups).**

| scenario | p50 | p95 |
| --- | --- | --- |
| `algolab.pathfinding.step.callback` | 71.4 ms | 89.2 ms |
| `algolab.pathfinding.step.keyboard` | 76.0 ms | 89.6 ms |

The publication stays tiny (3 ms, `full-root=nil`, 42 touched characters) and
the Ebox commit now answers with `native-frame` (`reconciled=0`, layout
≈ 11 ms).  The rest of the wall time is the driver's settlement/redisplay
boundary (~45 ms), not application work.

The slow path had two causes, both fixed:

- **This workspace** put page padding on the scroll owner and nested a second
  full-height scroll region inside the first.  A padded scroll container can
  neither produce a native scroll plan nor stay on the fast path, and the
  nested region duplicated the whole interactive page inside one scroll
  producer.  The application now has exactly one undecorated page scroll
owner, page padding inside it, and panels that hug their charts.
- **Ebox** forced a column flex item in an auto-height container to its
  intrinsic measured main size, so a wrapped card overflowed its own padding
  box; the padded box then became a scroll owner without a plan and the whole
  frame fell back to the Elisp layout.  Fixed in ebox `c248077` (auto-height
  column items keep their natural main size; tape validation accepts the
  derived sticky properties; scroll-producer literals from the matched
  encoder skip their repeated rescan).

A 90-sample run can still show one or two samples above the budget (GC or a
slow redisplay inside the measured boundary); the aggregate p95 above is the
accepted figure.  Evidence is written under `~/.cache/emacs-taf/performance/`
with `valid=true` and `acceptance_eligible=true`.  A minimal reproduction is
kept in `~/.pi/reports/etaf-algo-lab-perf/` in case the fast path regresses.

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

Two environment traps worth knowing before rerunning the GUI checks: a
full-screen frame ignores `set-frame-size` (the scenario clears that state
first), and the performance driver refuses packages edited or rebuilt after
the verification instance started, so compile before starting the instance.
