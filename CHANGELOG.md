# Changelog

## Unreleased

### Fixed

- Player shortcuts now respect shared help and text editing. Pressing `q`,
  `n` or another player key while reading help no longer closes or operates
  the laboratory; help lists labelled bindings in the application's palette.

### Added

- The workspace opens two laboratories through one shared player: 寻路实验台
  (A*, Dijkstra, BFS on an editable grid) and 排序实验台 (bubble, insertion,
  selection and bottom-up merge on one fixed input). Both teach in plain
  language, animate one step at a time, remember earlier runs, and offer
  **批量对比**, a headless run of every algorithm on the current input.
- The player owns play, pause, single step, jump-to-finish, speed, the bounded
  timer, the comparison run, the scoped key declarations and cleanup. A laboratory
  only describes its model, one step, a terminal predicate and presentation
  callbacks, so a new laboratory is one file.
- Boards compose `etaf-ui`'s `etaf-tile-grid`: per-cell refs for the search
  grid and per-column value/role refs for the bar chart keep one step's
  publication to the cells that actually changed.
