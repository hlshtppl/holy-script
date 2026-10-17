# AGENTS.md

Panduan ini untuk AI agent / developer yang akan maintain atau ngembangin script **RouteTools - XCUNG**.

---

## 📌 Ringkasan Project

**RouteTools** adalah script executor Roblox (Delta Executor) untuk game **XCUNG** (Mount XCUNG). Fitur utama: auto-teleport ke checkpoint (CP), walk muter buat trigger Touched CP, loop otomatis, resume pending, anti-AFK, dan auto-fish (dengan remote discovery).

**Target runner**: Delta Executor (Android/iOS)
**Bahasa**: Lua 5.1 (Roblox Luau)
**Host**: GitHub raw (`raw.githubusercontent.com/...`)
**Load method**: `loadstring(game:HttpGet(URL))()`

---

## 🎯 Tujuan Script

1. **Otomatisasi naik CP** dari CP 1 sampai CP 21 tanpa main manual
2. **Trigger checkpoint server** dengan gerakan muter (CFrame) — karena `Humanoid:Move` di-block game mount
3. **Loop terus-menerus** biar bisa ditinggal AFK
4. **Resume CP yang gagal** (pending system)
5. **Anti-AFK** biar tidak di-kick Roblox
6. **Auto-fish tanpa animasi** (opsional, dengan remote discovery)

---

## 🏗️ Struktur Script

```
RouteTools.lua
├── CONFIG               — semua setting di atas (mudah di-tuning)
├── WALK                 — walk muter (CFrame-based)
├── LOOP                 — loop setting
├── PENDING              — pending CP system
├── AUTO START & RESET   — auto-start dari server CP + reset mode
├── ANTI-AFK             — anti-kick system
├── AUTO FISH            — no-animation fishing + remote discovery
├── CP_LIST              — koordinat CP (hardcoded)
├── RESET_POS            — koordinat tombol BC
├── STATE                — variable runtime
├── UTIL                 — getRoot, teleport
├── BACA STAT            — getServerCheckpoint (leaderstats/attribute/Stats)
├── WALK MUTER           — fungsi utama pergerakan
├── PLAY CP              — loop utama
├── UI (SIDEBAR 5 TAB)   — panel + sidebar + tab content
└── LOGIC TOMBOL         — handler tiap tombol
```

---

## 🔑 Komponen Kritis

### 1. `teleport(pos)` — Teleport ke posisi

```lua
local function teleport(pos)
    local root = getRoot()
    if not root then return false end
    pcall(function()
        root.CFrame = CFrame.new(pos + TELEPORT_OFFSET)
        root.Velocity = Vector3.zero
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
    task.wait(0.1)
    return true
end
```

**Catatan penting:**
- **WAJIB** zero-kan `Velocity`, `AssemblyLinearVelocity`, `AssemblyAngularVelocity` biar tidak rubberband
- `TELEPORT_OFFSET = Vector3.new(0, 3, 0)` biar tidak nyangkut di lantai
- Bungkus `pcall` karena game bisa lock `root.CFrame`

### 2. `walkMuter()` — Gerakan muter

**KENAPA CFrame, bukan `Humanoid:Move`?**
- Game XCUNG pakai **mount / VehicleSeat**
- `Humanoid:Move` **TIDAK BEKERJA** saat naik mount
- CFrame langsung menggerakkan `HumanoidRootPart` → otomatis bawa mount

**Cara kerja:**
1. Ambil posisi tengah (`center = root.Position`)
2. Loop 8 titik di lingkaran (radius `WALK_RADIUS`)
3. Setiap titik: geser CFrame dari posisi sekarang ke titik itu
4. Kembali ke tengah + naik-turun sedikit

**JANGAN** ganti ke `Humanoid:Move` atau `MoveTo` — sudah di-test dan gagal.

### 3. `playCP()` — Loop utama

- Pakai **`while` loop eksplisit**, bukan recursive
- `stopFlag` untuk stop dari tombol
- `RESET_MODE` menentukan kapan reset ke BC:
  - `"Never"` — tidak pernah reset (default)
  - `"Once"` — reset cuma di loop pertama
  - `"Always"` — reset tiap loop

### 4. `getServerCheckpoint()` — Baca stat CP dari server

Urutan prioritas:
1. `leaderstats.Checkpoint`
2. `player:GetAttribute("Checkpoint")`
3. `Stats.Checkpoint`
4. (kalau perlu) scan TextLabel di PlayerGui

**Fallback**: kalau tidak ketemu, pakai manual (currentIndex).

### 5. Pending System

- `pendingCPs` = array index CP yang belum berhasil
- `addPending(idx)` dipanggil manual via tombol "Tandai Pending"
- `Resume Pending` = coba ulang semua pending
- Kalau `AUTO_PENDING_RETRY = true`, pending diproses dulu tiap loop

### 6. Auto Fish + Remote Discovery

- `getNetCandidates()` baca net dari beberapa path:
  - `ReplicatedStorage.Packages._Index[*].net`
  - `ReplicatedStorage.Packages.net`
  - `ReplicatedStorage.net`
  - `ReplicatedStorage.Net`
- `scanFishingRemotes()` scan `ReplicatedStorage` (bounded depth 8) untuk RemoteEvent & RemoteFunction yang cocok keyword.
- `autoFish()` coba skenario:
  - Fast: Equip → Complete (atau Complete langsung)
  - Safe: Equip → Cast/Charge → wait 1s → Complete
- Setelah tiap percobaan, cek perubahan `leaderstats` / attribute (max 3x), kalau tidak ada perubahan → `warn()`.

---

## 🎨 UI Architecture v9

Panel pakai **sidebar 5 tab** di kiri + content area di kanan.

```
ScreenGui (RoutePanel, DisplayOrder = max)
└── Panel (Frame, 340×380, ClipsDescendants)
    ├── Header (32px)  — Title "XCUNG Route" + MinBtn (−) + CloseBtn (X)
    ├── Sidebar (kiri, 44px, #2D2D38)
    │   ├── Tab 1 🎮 Route
    │   ├── Tab 2 ⚙️ CP
    │   ├── Tab 3 🎣 Fishing
    │   ├── Tab 4 💾 Tools
    │   └── Tab 5 ⚙️ Settings
    ├── Content (kanan, sisa area) — 5 Frame tab, Visible sesuai tab aktif
    │   └── tiap tab punya ScrollingFrame sendiri (ScrollBarThickness 6)
    └── 4× ResizeHandle (TL, TR, BL, BR)
```

**Isi tiap tab:**
- **Route** 🎮 — posLabel, cpLabel, loopLabel, Play CP, Auto-Start, Reset Mode, Teleport Reset, Loop
- **CP** ⚙️ — Grid pilih CP 1-21 + Next/Prev
- **Fishing** 🎣 — Auto Fish toggle, Fishing Mode (Fast/Safe), Scan Fishing Remotes, Test Fishing, fishDebugLabel
- **Tools** 💾 — pendingLabel, Resume Pending, Tandai Pending, Clear Pending, Scan CP Server, debugLabel (CP server)
- **Settings** ⚙️ — Anti-AFK, TP Delay, Walk Radius, Walk Move
- **Cosmetics** `C` — Start/Stop Spy, Replay Last, Get Skin List, Clear Log, label log (`Cos.log`). Lihat bagian "Tab Cosmetics" di bawah.
- Tab **Fishing** juga memuat (ditambah belakangan): Remote Sell Fish (No NPC), Debug AmbilSemua, TextBox Filter Mutasi/Rarity, Favorite by Filter. Tombolnya dibuat di bagian kode Cosmetics (tabel `Cos`), tapi parent-nya `fishScroll`.

**Sidebar scrollable:** `sidebar` adalah `ScrollingFrame` (`AutomaticCanvasSize = Y`, scrollbar 4px). Padding list 6, tinggi item tab 56. Urutan `tabFrames` harus sama dengan urutan `tabDefs` (Cosmetics = tab ke-6, dibuat setelah Settings). Di HP, geser sidebar dari celah antar-tab; tombol tab menangkap sentuhan lebih dulu.

**Minimize jadi icon:**
- Klik `−` → panel `Visible = false`, muncul icon bulat 40×40 hijau (`#32A046`, teks "RT")
- Icon bisa di-drag, `UICorner` radius penuh, `UIStroke` putih 2px
- Klik icon → panel `Visible = true` kembali ke `lastPanelPosition`
- Icon `ZIndex = 1000` biar selalu di atas

**Drag (fix):**
- Pakai `UserInputService.InputBegan/InputChanged/InputEnded` global
- Deteksi area pakai `AbsolutePosition`/`AbsoluteSize` (bukan `input.Target`)
- Header boleh di-drag, tapi tombol `−`/`X` dikecualikan
- Simpan `lastPanelPosition` untuk restore

**Z-Index penting:**
- Header: `100`
- Tombol di header: `101`
- Tab aktif: `102`
- Icon minimized: `1000`
- Resize handle: `50`

---

## 🎬 Anti-Cutscene & Anti-Shake (Secret)

`Fish.cutsceneTick()` (skip cutscene: animasi, kamera, GUI, beam) ditambah pembersihan di `Fish.cleanTick()`. Loop gabungan 0.1s di akhir script jalan hanya saat `USE_AUTO_FISH and Fish.stopAnimOn`:

- `Fish.forceCameraStable()` — `CameraType` balik ke Custom + `CameraSubject` = Humanoid. CFrame kamera hanya dipaksa saat `cutsceneActive` (kalau dipaksa terus, kamera pemain terkunci).
- `Fish.resetPlayerVelocity()` — nol-kan `AssemblyLinearVelocity` / `AssemblyAngularVelocity` root.
- `Fish.destroyCutsceneEffects()` (tiap 0.2s, hanya saat `cutsceneActive`) — hapus `ParticleEmitter`/`Beam`/`Attachment` ber-nama beam/particle/flash/shake/burst/cutscene/secret/effect. Karakter sendiri dan karakter pemain lain dikecualikan; `BasePart` TIDAK dihapus (bisa merusak map).
- `Fish.destroySecretGui()` (tiap 0.2s) — hapus ScreenGui game ber-nama cutscene/secret/cinematic/reveal/intro. "catch"/"notification" SENGAJA tidak disentuh: deteksi hasil tangkapan membaca label di sana. GUI kita (`RoutePanel`, `RouteIcon`, `RouteError`) dikecualikan.
- Batasan: kalau getaran dari modul kamera di RenderStep, interval 0.1s mungkin kurang; opsi lanjutan `RunService:BindToRenderStep` prioritas kamera.

---

## 🧴 Tab Cosmetics (Spy & Observasi Network)

Spy (hook `__namecall`, fallback `hookfunction`) sekarang menulis ke `Cos.log` (tab Cosmetics), bukan `fishDebugLabel`.

- **Start Spy / Stop Spy / Clear Log** — Stop menampilkan ringkasan remote unik + jumlah panggilan.
- **Filter `[NET-OBSERVE]`** — di `spyRecord`, remote yang namanya mengandung `skin`, `title`, `equip`, `inventory`, `wear` diberi prefix itu (nama + format argumen). Hanya mencatat, tanpa aksi.
- **Replay Last** — `Spy.last` menyimpan remote + argumen asli panggilan terakhir; tombol mengulangnya sekali lewat `pcall`, jeda 0.5s, tidak bisa ditumpuk. TIDAK ada input payload bebas.
- **Get Skin List** — `DaftarSkin:InvokeServer()` sekali tanpa argumen, hasil lewat `Cos.tableToString` (kedalaman 3, maks 60 item).
- **Helper di tabel `Cos`** (slot local script hampir penuh, batas 200): `Cos.setText`, `Cos.tableToString`, `Cos.findNamed(name)` (cache per nama), `Cos.fetchInventory`, `Cos.makeBox`.

**Sengaja TIDAK dibuat:** tombol equip skin/rod dengan nama bebas, "try all skins" (loop ID), payload TextBox ke remote skin/title. Itu brute-force otorisasi server untuk item yang belum dimiliki — ditolak. Jangan tambahkan kembali.

---

## 💰 Remote Sell Fish (No NPC)

Tombol di tab Fishing. Hasil spy jual manual di NPC: `InfoJual("semua")`, `JualSemua()`, `AmbilSemua()` (semua InvokeServer).

- `Cos.findSellRemote()` — scan ReplicatedStorage sekali (cache), prioritas: `JualSemua`, `SellFish`, `SellAllFish`, `SellAll`, `JualIkan`, `Jual`. Sekaligus cache `AmbilSemua` ke `Cos.ambilSemuaRemote`.
- `Cos.remoteSell()` — tolak kalau Auto Fish ON; 1x `JualSemua`, tunggu 0.2s, 1x `AmbilSemua` (refresh inventory), semua `pcall`. Tombol: "Selling..." → "Sold!"/"Error"/"Not Found" 1.5s. Tombol "Sell All Fish" lama (`SellFish`) tetap ada.

---

## ⭐ Favorite by Filter (Mutasi / Rarity)

- **Debug AmbilSemua** — invoke sekali, tampilkan 3 entri pertama ke log Cosmetics. Jalankan dulu untuk tahu struktur data.
- **Favorite by Filter** — filter koma-terpisah, case-insensitive, "mengandung". Mutasi + rarity keduanya diisi = AND. Kedua kosong = ditolak. Field dicari dari kandidat nama (`uuid/UUID/id`, `mutation/mutasi/variant`, `rarity/kelangkaan/tier`, UUID cadangan `item[1]` atau key dict). Kalau field yang difilter tidak ada di 5 item pertama → batal dengan pesan "Struktur data tidak dikenali". Per item cocok: `TandaiFavorit:FireServer(uuid, true)` lewat `pcall`, `task.wait(0.1)`. Log total.

---

## 🕵️ Remote Discovery Pattern

Cara scan remote fishing resmi game XCUNG.

### Net package

```lua
local net = findNetPackage()  -- sleitnick_net@0.2.0 → net, atau Packages.net / ReplicatedStorage.net
```

### Remote fishing (case-insensitive)

| Slot | Candidate nama |
|---|---|
| equip | `RE/EquipToolFromHotbar`, `EquipToolFromHotbar`, `EquipRod`, `Equip` |
| charge | `RF/ChargeFishingRod`, `ChargeFishingRod`, `ChargeRod`, `Charge` |
| start | `RF/RequestFishingMinigameStarted`, `RequestFishingMinigameStarted`, `StartFishing`, `Start` |
| complete | `RE/FishingCompleted`, `FishingCompleted`, `CompleteFishing`, `Complete` |
| sell | `RF/SellAllItems`, `SellAllItems`, `SellAll`, `Sell` |

`findRemoteInNet()` cek langsung di root `net` (nama literal dengan `/`) dan di folder `RE`/`RF`.

Kalau tidak ketemu, fallback scan `ReplicatedStorage` (depth 8) untuk RemoteEvent/RemoteFunction match keyword.

---

## 🎣 Blatant Fishing (Remote-based)

Instant fishing tanpa animasi — panggil remote resmi game langsung (seperti Chloe-X / Fish It):

```lua
humanoid:ChangeState(Enum.HumanoidStateType.Physics)
humanoid:Move(Vector3.new(0, 0, 0))
equip:FireServer()
charge:InvokeServer(1)      -- KUNCI: Charge dulu
start:InvokeServer(1, 1)
complete:FireServer()
task.wait(0.001)
```

`blatantFish()` panggil urutan: `equip` → `charge(1)` → `start(1,1)` → `complete`, tiap step delay 0.05s. `FISH_DELAY = 0.05` (super cepat).

Kalau remote tidak lengkap → `fallbackFish()` (Tool Activate → VirtualUser click → UI click).

---

## 🔥 Fire vs Invoke Remote

`fireRemote(remote, ...)` auto-detect jenis remote:

```lua
local function fireRemote(remote, ...)
    if not remote then return false end
    return pcall(function()
        if remote:IsA("RemoteFunction") then
            remote:InvokeServer(...)   -- RemoteFunction
        else
            remote:FireServer(...)     -- RemoteEvent
        end
    end)
end
```

- **RemoteEvent** → `FireServer(...)`
- **RemoteFunction** → `InvokeServer(...)` (yields, butuh `pcall`)

---

## 🎣 Fishing Methods

`detectFishingMethod()` cek 4 kemungkinan metode mancing di game, berurutan:

| Priority | Method | Deteksi |
|---|---|---|
| 1 | `tool` | Tool "rod"/"pancing"/"fish" di Backpack / Character |
| 2 | `prompt` | ProximityPrompt dekat player (radius 50 studs) |
| 3 | `remotefunction` | RemoteFunction fishing di ReplicatedStorage |
| 4 | `bindable` | BindableEvent fishing di ReplicatedStorage / player |

**Cara trigger per method:**
- `tool`: `tool:Activate()` (+ `tool.Handle:Activate()` fallback)
- `prompt`: `prompt:InputHoldBegin()` → wait `HoldDuration` → `prompt:InputHoldEnd()` → `fireproximityprompt(prompt)`
- `remotefunction`: `rf:InvokeServer()`
- `bindable`: `bindable:Fire()`
- `unknown` (fallback): stop animasi + fire `FishCatchBroadcast` + `EquipTitle`

Hasil method di-cache biar tidak scan berulang; tombol "Detect Fishing Method" reset cache lalu detect ulang.

---

## 🐛 Auto-Fish Debug

Tab Fishing punya tombol + debug label 5 baris:

- `Auto Fish: ON/OFF` — toggle utama (loop background)
- `Fishing Mode: Fast/Safe` — Fast: delay 0.1s, Safe: delay 2s + tunggu 1.5s antar cast
- `Scan Fishing Remotes` — print semua remote fishing ke console
- `Detect Fishing Method` — reset cache + deteksi ulang
- `Test Fishing Once` — panggil `autoFish()` 1x manual
- `Stop Animation` — hentikan semua `AnimationTrack` aktif
- `Sell All Fish` — fire remote `SellFish`
- `Reset Counter` — reset `fishCaught`
- `Detect Game UI` — scan tombol Cast/Reel di CoreGui & PlayerGui
- `Show UI Elements` — print semua TextButton/ImageButton
- `Auto Click Cast: ON/OFF` — toggle klik tombol Cast otomatis
- `Auto Click Reel: ON/OFF` — toggle klik tombol Reel otomatis

**fishDebugLabel (5 baris):**
```
Method: tool/prompt/remotefunction/bindable/unknown
UI: TextButton 'Cast' found
Status: idle/casting/reeling/success/error
Fish caught: N
Last catch: <nama ikan>
```

**Fish counter:** baca `leaderstats` / attribute ikan kalau ada, else pakai counter manual `fishCaught` (increment saat stat berubah). Reset via tombol.

---

## 🎯 Fishing UI Detection

`detectGameFishingUI()` scan CoreGui & PlayerGui (bounded depth 8) untuk tombol fishing:

- **TextButton** yang text-nya mengandung: `Cast`, `Lempar`, `Mancing`, `Fish`, `Reel`, `Tarik` (case-insensitive)
- **ImageButton** yang parent-nya mengandung `Fish` / `Fishing` / `Rod`
- **ProximityPrompt** jarak < 10 studs dari player (fallback)

Klasifikasi action: `cast` (cast/lempar/mancing/fish) vs `reel` (reel/tarik). Hasil di-cache di `cachedCastButton` / `cachedReelButton`.

---

## 🎣 Cast -> Reel Flow

`autoFish()` sekarang 2 step:

1. **CAST** — klik tombol Cast (atau `tool:Activate()` kalau tidak ada tombol UI)
2. **REEL** — klik tombol Reel (atau `tool:Activate()` lagi)

Prioritas trigger: `tool:Activate()` → UI button (`MouseButton1Click:Fire()` + `Activate()`) → `VirtualUser` click.

Timing:
- Fast: cast → 0.2s → stop animasi → 0.1s → reel → 0.3s
- Safe: cast → `waitForCastAnimation(3)` → reel → 1.5s

---

## ⏭️ Animation Skip Strategy

Biar server kenal "sudah cast" tapi animasi visual tetap singkat:

1. Klik Cast → animasi cast mulai
2. Tunggu 0.2s (minimal terlihat lempar tali)
3. `stopAllAnimations()` — `track:Stop(0)` semua animasi aktif
4. Tunggu 0.1s
5. Klik Reel

Efek: server sudah terima event Cast, tapi animasi visual cuma ~0.2s, jadi loop tetap cepat.

---

## 🎯 Game Button Detection

`scanGameButtons()` scan PlayerGui & CoreGui (bounded depth 8, skip GUI sendiri "RoutePanel"/"RouteIcon") untuk TextButton & ImageButton yang text/name-nya mengandung keyword:

```
automatic, auto, cast, lempar, mancing, fish, reel, tarik, stop, click, quick, sell, jual
```

Hasil disimpan di `cachedGameButtons`, lalu `refreshGameButtons()` menentukan:
- `autoBtn` — "Automatic" / "Auto" / "Cast" / "Lempar"
- `quickBtn` — "Quick Click" / "Click" / "Reel" / "Tarik"
- `stopBtn` — "STOP" / "Stop"

Tombol "Show Found Buttons" nampilin list ke `fishLogLabel` (bukan console).

---

## 🎣 Automatic Fishing via Game UI

`autoFish()` via tombol game, 3 mode:

| Mode | Perilaku |
|---|---|
| Automatic | Klik `autoBtn` sekali → game auto mancing (yang FishIt pakai) |
| Tool | `tool:Activate()` untuk cast + spam `quickBtn` |
| Manual | `tool:Activate()` saja |

`FISH_MODE` cycle: Automatic → Tool → Manual (tombol "Fishing Mode").

---

## ⏭️ Spam Click Reel Skip

`spamClick(button, count, delay)` loop `count` kali (default 10x, delay 0.05s), tiap iterasi `clickButton()` (Activate + MouseButton1Click:Fire + VirtualUser click).

Dipanggil saat broadcast `FishCatchBroadcast` ter-fire oleh server → skip animasi reel panjang → instant catch.

---

## 📟 UI-Only Logging (no console)

Karena Delta tidak bisa buka console:

- `log(msg)` append ke `logBuffer` (max 30 baris, auto-scroll ke bawah), tampil di `fishLogLabel`.
- `updateFishDebug()` render status 6 baris di `fishDebugLabel`.
- **TIDAK ADA `print()`** di seluruh script — semua output via UI.

---

## 🖼️ ImageButton Detection

Tombol fishing di XCUNG pakai `ImageButton` (bukan TextButton), sering tanpa nama/text. `scanGameButtons()` sekarang capture info lengkap tiap tombol:

```
N. [ClassName] Text='...' Pos=(X,Y) Size=(W,H)
```

Deteksi ImageButton via:
- **Child TextLabel** — kalau ImageButton punya TextLabel di dalamnya, pakai text itu sebagai identifier.
- **Image asset** — cek `Image` property.
- **Position** — tombol fishing biasanya di bawah layar (Y > 60% screen height).

---

## 🎯 Position-based Button Assign

Karena tombol fishing di BAWAH layar:

1. Filter ImageButton dengan `AbsolutePosition.Y > screenHeight * 0.6`
2. Sort by `AbsolutePosition.X` (kiri → kanan)
3. `autoBtn` = ImageButton paling kiri (Btn1)
4. `quickBtn` = ImageButton kedua (Btn2)
5. `stopBtn` = TextButton "STOP" (bukan "STOP SPECTATE")

`assignButtonsByPosition()` dipanggil otomatis di `refreshGameButtons()`, dan bisa dipaksa lewat tombol "Assign Auto=Btn1, Quick=Btn2".

---

## 🖱️ Spam Click Multi-Method

`clickButton()` coba SEMUA metode (semua di-`pcall`):

1. `button.MouseButton1Click:Fire()`
2. `button.MouseButton1Down:Fire()` + `button.MouseButton1Up:Fire()`
3. `button.Activated:Fire()`
4. `VirtualUser:ClickButton1(center)`
5. `UserInputService` simulate tap

`spamClick()` loop dengan delay default 0.05s; listener `FishCatchBroadcast` spam `quickBtn` 20x untuk skip reel.

---

## ⚠️ Known Issues & Constraints

| Issue | Solusi |
|---|---|
| Game block `Humanoid:Move` | Pakai CFrame geser |
| Rubberband saat teleport | Zero-kan velocity + tunggu 0.1s |
| CP beda tipis dari koordinat | Walk muter radius lebar + spiral |
| Reset BC tidak trigger | Walk muter di RESET_POS biar Touched kena |
| Delta tidak support `writefile` | Jangan pakai; simpan di memory saja |
| Delta tidak support `VirtualUser` | Fallback: geser CFrame 0.1 studs |
| Leaderboard tidak kebaca | Cek `leaderstats` → attribute → Stats folder |

---

## 🚧 Known Limitations

- **Auto-fish belum tentu langsung works** di XCUNG — remote mancing bukan RemoteEvent biasa, kemungkinan pakai Tool `Activate` / ProximityPrompt / RemoteFunction / BindableEvent.
- **Hasil scan cuma 4 remote** (`EquipTitle`, `SellFish`, `FishCatchBroadcast`, `CutsceneBroadcast`) — tidak ada cast/reel, jadi fallback pakai `FishCatchBroadcast`.
- **Perlu update nama remote / method** sesuai hasil "Detect Fishing Method" + "Scan Fishing Remotes".
- **Kalau server pakai obfuscated remote name**, pantau perubahan `leaderstats` / attribute lewat `updateFishDebug()`.
- Stat ikan bisa disimpan di nama yang tidak terdeteksi — kalau begitu perlu tambah nama stat di `snapshotStats()`.

---

## 🚫 Larangan (JANGAN Dilakukan)

1. **JANGAN** ganti `walkMuter` ke `Humanoid:Move` — sudah di-test, tidak works di mount
2. **JANGAN** pakai `writefile`/`readfile` — Delta tidak support di beberapa device
3. **JANGAN** hapus `pcall` di sekitar CFrame — game bisa lock
4. **JANGAN** panggil `teleport()` tanpa tunggu `task.wait()` — bisa rubberband
5. **JANGAN** pakai `wait()` — pakai `task.wait()` (Luau modern)
6. **JANGAN** pakai `Frame.Draggable` — sudah deprecated, pakai drag manual
7. **JANGAN** hapus zero-velocity di `teleport()` — akan rubberband parah

---

## 🎯 Coding Conventions

- **Indentasi**: 4 spasi
- **Naming**: `camelCase` untuk variabel, `PascalCase` untuk UI element name
- **Comment**: pakai `--[[ ]]` untuk header, `-- ==== ====` untuk section
- **Task**: pakai `task.spawn` / `task.wait`, **JANGAN** `spawn` / `wait`
- **PCall**: selalu bungkus operasi CFrame, FireServer, dan Instance creation di `pcall`
- **State**: semua state di top-level, bukan nested function

---

## 🔧 Cara Modifikasi Umum

### Menambah CP baru
```lua
-- Tambahkan di CP_LIST, urutannya sesuai urutan game
local CP_LIST = {
    ...
    Vector3.new(X, Y, Z),   -- CP 22
}
-- Otomatis muncul di grid (loop for i, cp in ipairs(CP_LIST))
```

### Mengubah radius walk muter
```lua
local WALK_RADIUS = 6     -- naikkan jadi 8-10 kalau CP-nya lebar
local WALK_STEPS = 8      -- naikkan jadi 12 kalau mau lebih halus
local WALK_MOVE_TIME = 0.08  -- turunkan jadi 0.05 buat lebih cepat
```

### Menambah remote fishing baru
```lua
-- Hasil scan dari debugAutoFish() dipakai untuk update nama remote
local complete = findRemote(nets, "RE/NamaRemoteBaru")
```

---

## 🧪 Testing Checklist v9

Sebelum push ke GitHub, cek:

- [ ] Panel muncul tanpa error di Delta
- [ ] Drag panel works dari header
- [ ] Minimize → icon bulat muncul, bisa di-drag
- [ ] Klik icon → panel restore ke posisi terakhir
- [ ] Sidebar 5 tab bisa diklik
- [ ] Konten tiap tab muncul sesuai
- [ ] Tombol `Play CP` mulai loop
- [ ] Walk muter kelihatan gerakan
- [ ] CP terdeteksi (cek `cpLabel` update)
- [ ] Loop mode tetap jalan
- [ ] `Stop CP` menghentikan loop di tengah
- [ ] `Resume Pending` coba CP yang pending
- [ ] Anti-AFK tidak crash
- [ ] Auto Fish: scan remotes dulu, lalu test
- [ ] Semua fitur lama masih works

---

## 📚 Resources

- Roblox Luau: https://luau-lang.org/
- Delta Executor: dokumentasi internal (tidak publik)
- Luraph Obfuscator: https://lura.ph/
- Reference script (Chloe-X): https://github.com/MajestySkie/Chloe-X

---

## 🎯 Prioritas Development

**High priority:**
1. Baca stat server checkpoint (auto-detect CP yang sudah lewat)
2. Auto-retry lebih pintar (pakai stat untuk cek berhasil/gagal)
3. UI resize lebih mulus

**Medium priority:**
1. Save/load CP ke memory (bukan file)
2. Speed toggle (ubah TP_DELAY dan WALK_MOVE_TIME dari UI)
3. Tambah stat ikan di `snapshotStats()` kalau leaderboard pakai nama lain

**Low priority:**
1. Multi-game support (loader seperti Chloe-X)
2. Auto-detect folder Checkpoints (scan workspace)
3. GUI setting export/import

---

## 🤝 Kontribusi

- **Testing**: selalu di game XCUNG asli, bukan Studio
- **Push**: update URL raw di Delta Executor
- **Backward compatibility**: jangan hapus fitur lama tanpa alasan

---

## 📝 Log Perubahan

| Versi | Perubahan |
|---|---|
| v1 | Script awal dengan walk maju-mundur |
| v2 | Walk muter 8 arah |
| v3 | Walk muter + spiral 3 lapis |
| v4 | Panel resize + scroll + drag |
| v5 | Pending system + Loop |
| v6 | Auto-start dari leaderboard |
| v7 | Fix reset mode (Never/Once/Always) |
| v8 | Anti-AFK + Auto-fish |
| v9 | Sidebar UI 5 tab + fix drag + minimize jadi icon |
| v10 | Auto-fish multi-method (tool/prompt/remotefunction/bindable) + fish counter + scan/detect/sell |
| v11 | Auto-fish via game "Automatic" button + spam click reel skip + UI-only logging |
| v12 | ImageButton position detection + aggressive spam click multi-method |
| v13 | Blatant fishing (remote-based instant) + remote discovery + fire/invoke |
| v14 | Anti-shake + bersihkan efek/GUI secret (`Fish.cleanTick`) |
| v15 | Tab Cosmetics: spy log dipindah, filter `[NET-OBSERVE]`, Replay Last, Get Skin List, Clear Log |
| v16 | Remote Sell Fish via `JualSemua` + `AmbilSemua` |
| v17 | Favorite by Filter (mutasi/rarity) + Debug AmbilSemua |
| v18 | Sidebar jadi ScrollingFrame (6 tab) |

---

**Maintainer**: hlshtppl
**Terakhir diupdate**: 2026-10-17
**File**: `src/StarterPlayerScripts/RouteTools.client.lua`
