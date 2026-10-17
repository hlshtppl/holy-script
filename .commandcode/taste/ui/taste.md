# UI Preferences

- Uses UserInputService.InputBegan/InputChanged/InputEnded with manual AbsolutePosition/AbsoluteSize bounds checks for drag interactions, instead of relying on input.Target (which can conflict with buttons or be overridden on mobile executors). Confidence: 0.7
- Organizes dense feature sets into a sidebar/tabbed navigation layout (left sidebar tabs switch content frames) to keep the panel compact and avoid overlapping the game UI. Confidence: 0.7
- Prefers minimize-to-floating-icon behavior for overlay panels: minimize hides the panel and shows a small draggable icon that restores the panel at its last position. Confidence: 0.6
- Uses consistent color semantics for toggles and active states: green (#32A046 / RGB 50,160,70) for ON/active and gray (#787878 / RGB 120,120,120) for OFF/inactive. Confidence: 0.7
- Prefers UI-only logging over console print(): all debug/status/error output goes to an on-panel TextLabel because Delta Executor auto-minimizes the console when clicking elsewhere. Confidence: 0.85
- Uses a bounded rolling log buffer (e.g., max ~10 lines) rendered into a panel TextLabel so verbose output stays compact and oldest entries scroll out. Confidence: 0.7
- When scanning/discovering in-game UI, excludes its own overlay GUI (e.g., by name filter) to avoid matching its own buttons. Confidence: 0.6
- Identifies unlabeled in-game buttons via positional heuristics and structural cues: filter by screen Y (bottom of screen), sort by X left-to-right to infer role (leftmost = primary action), and fall back to child TextLabels or image assets as identifiers. Confidence: 0.7
