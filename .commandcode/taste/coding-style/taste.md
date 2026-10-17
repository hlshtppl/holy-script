# Coding Style Preferences

- Uses task.wait() instead of wait() in Roblox Lua scripts. Confidence: 0.95
- Wraps network calls (FireServer) and VirtualUser calls in pcall. Confidence: 0.85
- Uses section banner comments like `-- ====== SECTION NAME ======` to organize code. Confidence: 0.8
- Avoids loadstring() inside scripts. Confidence: 0.7
- Prefers bounded-depth recursive traversal (with a depth cap) over full GetDescendants() scans to avoid lag on large containers. Confidence: 0.85
- Spaces out sequential method/remote attempts with a short delay (e.g., 0.3s) so the server has time to process before results are checked. Confidence: 0.6
- Uses a prioritized fallback chain, trying the least invasive method first (tool:Activate() → UI button click → VirtualUser) before escalating. Confidence: 0.6
- Uses AbsolutePosition/AbsoluteSize (screen-space) rather than Position/Size (which may be in scale units) when computing button coordinates for hit-testing or layout. Confidence: 0.8
- For in-game UI clicks, fires multiple click methods in sequence (MouseButton1Click:Fire, MouseButton1Down/Up:Fire, Activated:Fire, Activate, VirtualUser, UserInputService touch) instead of a single method to maximize the chance the game registers the click. Confidence: 0.7
- Logs detailed diagnostic info on fallback/unknown paths to an on-panel UI log (not console) so failures can be debugged without console access. Confidence: 0.6
- When invoking a Roblox remote, auto-detects its type via IsA("RemoteFunction") and calls InvokeServer(...) for RemoteFunction vs FireServer(...) for RemoteEvent through a shared fireRemote helper. Confidence: 0.8
- Prefers automating in-game actions by calling official remotes directly (discovered through the game's net package / named lookup) over simulating UI clicks, when such remotes are available. Confidence: 0.7
