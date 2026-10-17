--[[
    XCUNG RouteTools v9
    - Walk muter + Play CP + Loop + Pending
    - Anti-AFK + Auto Fish
    - Sidebar 5 tab + drag fix + minimize jadi icon
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ====== ERROR TAMPIL DI LAYAR (Delta tidak punya console) ======
local fatalLabel = nil
local fatalLines = {}
local function showFatal(msg)
    pcall(function()
        table.insert(fatalLines, tostring(msg))
        if #fatalLines > 3 then table.remove(fatalLines, 1) end
        if not fatalLabel or not fatalLabel.Parent then
            local sg = Instance.new("ScreenGui")
            sg.Name = "RouteError"
            sg.ResetOnSpawn = false
            sg.DisplayOrder = 2147483647
            local okParent = pcall(function() sg.Parent = playerGui end)
            if not okParent or not sg.Parent then
                pcall(function() sg.Parent = game:GetService("CoreGui") end)
            end
            local tb = Instance.new("TextLabel")
            tb.Size = UDim2.new(1, 0, 0, 100)
            tb.Position = UDim2.new(0, 0, 1, -100)
            tb.BackgroundColor3 = Color3.fromRGB(80, 20, 20)
            tb.TextColor3 = Color3.new(1, 1, 1)
            tb.Font = Enum.Font.Code
            tb.TextSize = 10
            tb.TextWrapped = true
            tb.TextYAlignment = Enum.TextYAlignment.Top
            tb.Parent = sg
            fatalLabel = tb
        end
        fatalLabel.Text = "RouteTools ERROR:\n" .. table.concat(fatalLines, "\n")
    end)
end

-- bungkus handler tombol: error tidak mematikan script, tampil di layar
local function safe(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            warn("[RouteTools] handler error: " .. tostring(err))
            showFatal("handler: " .. tostring(err))
        end
    end
end

-- semua kode di dalam main(); urutan: KONFIG -> STATE -> UI -> UTIL -> fishing/spy -> PlayCP -> handler -> loop
-- (isi main sengaja tidak di-indent ulang supaya diff tetap kecil)
local function main()

-- ====== KONFIG ======
local MIN_W, MIN_H = 220, 260
local TP_DELAY = 0.5
local RESET_DELAY = 0.8
local TELEPORT_OFFSET = Vector3.new(0, 3, 0)

-- ====== ANTI-AFK ======
local USE_ANTI_AFK = true
local ANTI_AFK_INTERVAL = 60   -- detik

-- ====== AUTO FISH ======
local USE_AUTO_FISH = false
local FISH_DELAY = 0.15

-- ====== WALK ======
local USE_WIGGLE = true
local WIGGLE_DELAY = 0.15
local WALK_MOVE_TIME = 0.08
local WALK_RADIUS = 6
local WALK_STEPS = 8

-- ====== LOOP ======
local USE_LOOP = false
local LOOP_DELAY = 2
local loopCount = 0

-- ====== PENDING ======
local pendingCPs = {}
local AUTO_PENDING_RETRY = true

-- ====== AUTO START & RESET ======
local AUTO_START = false
local RESET_MODE = "Never"   -- "Always" | "Once" | "Never"

-- ====== NAMA STAT ======
local CHECKPOINT_STAT_NAMES = {
    "Checkpoint", "CP", "Stage", "Level", "Progress",
    "CheckPoint", "checkpoint", "cp",
}

-- ====== KOORDINAT ======
local CP_LIST = {
    Vector3.new(464,   444,  -8942),
    Vector3.new(449,   489,  -9567),
    Vector3.new(392,   629,  -10120),
    Vector3.new(488,   637,  -10687),
    Vector3.new(1083,  725,  -11160),
    Vector3.new(976,   733,  -11817),
    Vector3.new(392,   885,  -11839),
    Vector3.new(-326,  849,  -11735),
    Vector3.new(-872,  853,  -11733),
    Vector3.new(-1281, 857,  -12098),
    Vector3.new(-1313, 889,  -12829),
    Vector3.new(-2314, 913,  -12667),
    Vector3.new(-2306, 917,  -11851),
    Vector3.new(-2449, 961,  -11051),
    Vector3.new(-3478, 981,  -11049),
    Vector3.new(-4227, 1001, -11012),
    Vector3.new(-4654, 1081, -11662),
    Vector3.new(-5541, 1101, -11649),
    Vector3.new(-6761, 1097, -11506),
    Vector3.new(-6787, 1102, -10808),
    Vector3.new(-6766, 1313, -10083),
}

-- ====== CP CUSTOM (save/load) ======
-- Satu tabel supaya hemat slot local (batas Luau 200). Semua akses file executor di-guard + pcall
-- (Delta di beberapa device tidak punya writefile/readfile -> fungsi return false, script tetap jalan).
local CPStore = {
    file = "RouteTools/custom_cps.json",
    dir = "RouteTools",
    defaults = {},
}
for i, cp in ipairs(CP_LIST) do CPStore.defaults[i] = cp end

function CPStore.save()
    if not writefile then return false end
    local ok = pcall(function()
        if isfolder and makefolder and not isfolder(CPStore.dir) then makefolder(CPStore.dir) end
        local data = {}
        for i, cp in ipairs(CP_LIST) do
            data[i] = { x = cp.X, y = cp.Y, z = cp.Z }
        end
        writefile(CPStore.file, game:GetService("HttpService"):JSONEncode(data))
    end)
    return ok
end

function CPStore.load()
    if not (readfile and isfile) then return false end
    local loaded = false
    pcall(function()
        if not isfile(CPStore.file) then return end
        local data = game:GetService("HttpService"):JSONDecode(readfile(CPStore.file))
        if type(data) ~= "table" then return end
        for i, pos in ipairs(data) do
            if CP_LIST[i] and type(pos) == "table"
                and type(pos.x) == "number" and type(pos.y) == "number" and type(pos.z) == "number" then
                CP_LIST[i] = Vector3.new(pos.x, pos.y, pos.z)
                loaded = true
            end
        end
    end)
    return loaded
end

function CPStore.reset()
    for i, cp in ipairs(CPStore.defaults) do CP_LIST[i] = cp end
end

CPStore.load()

local RESET_POS = Vector3.new(-6828, 1314, -9902)

-- ====== STATE ======
local cpPlaying = false
local stopFlag = false
local currentIndex = 1
local cpButtons = {}
local cpLabel, loopLabel, pendingLabel, debugLabel
local cachedServerCP = nil
local fishDebugLabel

-- ====== UI ======
local gui = Instance.new("ScreenGui")
gui.Name = "RoutePanel"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2147483647
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.new(0, 340, 0, 380)
panel.Position = UDim2.new(0, 20, 0, 20)
panel.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 0
panel.Active = true
panel.ClipsDescendants = true
panel.Parent = gui
Instance.new("UICorner", panel)

local stroke = Instance.new("UIStroke", panel)
stroke.Color = Color3.fromRGB(120, 120, 140)
stroke.Thickness = 2

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 32)
header.Position = UDim2.new(0, 0, 0, 0)
header.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
header.BorderSizePixel = 0
header.Active = true
header.ZIndex = 100
header.Parent = panel
Instance.new("UICorner", header)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -90, 1, 0)
title.Position = UDim2.new(0, 8, 0, 0)
title.BackgroundTransparency = 1
title.Text = "XCUNG Route"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 101
title.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 26, 0, 26)
minBtn.Position = UDim2.new(1, -60, 0, 3)
minBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 120)
minBtn.Text = "-"
minBtn.TextColor3 = Color3.new(1, 1, 1)
minBtn.TextSize = 18
minBtn.Font = Enum.Font.GothamBold
minBtn.ZIndex = 101
minBtn.Parent = header
Instance.new("UICorner", minBtn)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 26, 0, 26)
closeBtn.Position = UDim2.new(1, -30, 0, 3)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.TextSize = 14
closeBtn.Font = Enum.Font.GothamBold
closeBtn.ZIndex = 101
closeBtn.Parent = header
Instance.new("UICorner", closeBtn)

-- ====== SIDEBAR ======
local sidebar = Instance.new("ScrollingFrame")
sidebar.Name = "Sidebar"
sidebar.Size = UDim2.new(0, 44, 1, -32)
sidebar.Position = UDim2.new(0, 0, 0, 32)
sidebar.BackgroundColor3 = Color3.fromRGB(45, 45, 56)   -- #2D2D38
sidebar.BackgroundTransparency = 0
sidebar.BorderSizePixel = 0
sidebar.ScrollBarThickness = 4
sidebar.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 120)
sidebar.CanvasSize = UDim2.new(0, 0, 0, 0)
sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
sidebar.ScrollingDirection = Enum.ScrollingDirection.Y
sidebar.ZIndex = 1
sidebar.Parent = panel

local sidebarList = Instance.new("UIListLayout")
sidebarList.Padding = UDim.new(0, 6)
sidebarList.HorizontalAlignment = Enum.HorizontalAlignment.Center
sidebarList.SortOrder = Enum.SortOrder.LayoutOrder
sidebarList.Parent = sidebar

local sidebarPad = Instance.new("UIPadding")
sidebarPad.PaddingTop = UDim.new(0, 8)
sidebarPad.PaddingLeft = UDim.new(0, 2)
sidebarPad.PaddingRight = UDim.new(0, 2)
sidebarPad.Parent = sidebar

-- ====== CONTENT AREA ======
local contentHolder = Instance.new("Frame")
contentHolder.Name = "Content"
contentHolder.Size = UDim2.new(1, -44, 1, -32)
contentHolder.Position = UDim2.new(0, 44, 0, 32)
contentHolder.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
contentHolder.BorderSizePixel = 0
contentHolder.ZIndex = 1
contentHolder.Parent = panel

local tabButtons = {}
local tabFrames = {}

local function setActiveTab(idx)
    for i, f in ipairs(tabFrames) do
        f.Visible = (i == idx)
    end
    for i, b in ipairs(tabButtons) do
        if i == idx then
            b.BackgroundColor3 = Color3.fromRGB(50, 160, 70)
            b.ZIndex = 102
        else
            b.BackgroundColor3 = Color3.fromRGB(70, 70, 84)
            b.ZIndex = 1
        end
    end
end

-- ====== UI HELPER ======
local function makeButton(parent, text, color, order, height)
    local b = Instance.new("TextButton")
    b.LayoutOrder = order
    b.Size = UDim2.new(1, -8, 0, height or 32)
    b.BackgroundColor3 = color
    b.Text = text
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.Parent = parent
    Instance.new("UICorner", b)
    return b
end

local function makeLabel(parent, text, color, order, height)
    local l = Instance.new("TextLabel")
    l.LayoutOrder = order
    l.Size = UDim2.new(1, -8, 0, height or 22)
    l.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    l.Text = text
    l.TextColor3 = color
    l.Font = Enum.Font.Code
    l.TextSize = 11
    l.Parent = parent
    Instance.new("UICorner", l)
    return l
end

local function makeContentTab()
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.Position = UDim2.new(0, 0, 0, 0)
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.Visible = false
    frame.Parent = contentHolder

    local sc = Instance.new("ScrollingFrame")
    sc.Size = UDim2.new(1, -6, 1, -6)
    sc.Position = UDim2.new(0, 3, 0, 3)
    sc.BackgroundTransparency = 1
    sc.BorderSizePixel = 0
    sc.ScrollBarThickness = 6
    sc.ScrollBarImageColor3 = Color3.fromRGB(180, 180, 200)
    sc.CanvasSize = UDim2.new(0, 0, 0, 0)
    sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sc.ScrollingDirection = Enum.ScrollingDirection.Y
    sc.Parent = frame

    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0, 5)
    lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = sc

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 8)
    pad.PaddingLeft = UDim.new(0, 4)
    pad.PaddingRight = UDim.new(0, 4)
    pad.Parent = sc

    return frame, sc
end

-- ====== TAB 1: ROUTE ======
local routeTab, routeScroll = makeContentTab()
table.insert(tabFrames, routeTab)

local posLabel = makeLabel(routeScroll, "X: --  Y: --  Z: --", Color3.fromRGB(120, 220, 120), 0, 22)
cpLabel = makeLabel(routeScroll, "CP: - / " .. #CP_LIST, Color3.fromRGB(255, 200, 100), 1, 22)
loopLabel = makeLabel(routeScroll, "Loop: OFF", Color3.fromRGB(150, 200, 255), 2, 22)

local playCpBtn    = makeButton(routeScroll, "Play CP",         Color3.fromRGB(50, 160, 70),  3)
local autoStartBtn = makeButton(routeScroll, "Auto-Start: OFF", Color3.fromRGB(120, 120, 120), 4)
local resetModeBtn = makeButton(routeScroll, "Reset: Never",    Color3.fromRGB(120, 120, 120), 5)
local tpResetBtn   = makeButton(routeScroll, "Teleport Reset",  Color3.fromRGB(200, 130, 30), 6)
local loopBtn      = makeButton(routeScroll, "Loop: OFF",       Color3.fromRGB(120, 120, 120), 7)

-- ====== TAB 2: CP ======
local cpTab, cpScroll = makeContentTab()
table.insert(tabFrames, cpTab)

local cpGridLabel = makeLabel(cpScroll, "Pilih CP:", Color3.new(1, 1, 1), 0, 22)
cpGridLabel.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
cpGridLabel.Font = Enum.Font.GothamBold
cpGridLabel.TextSize = 12

local cpGrid = Instance.new("Frame")
cpGrid.LayoutOrder = 1
cpGrid.Size = UDim2.new(1, -8, 0, 240)
cpGrid.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
cpGrid.BorderSizePixel = 0
cpGrid.Parent = cpScroll
Instance.new("UICorner", cpGrid)

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 46, 0, 30)
gridLayout.CellPadding = UDim2.new(0, 3, 0, 3)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gridLayout.Parent = cpGrid

local gridPad = Instance.new("UIPadding")
gridPad.PaddingTop = UDim.new(0, 4)
gridPad.PaddingBottom = UDim.new(0, 4)
gridPad.PaddingLeft = UDim.new(0, 4)
gridPad.PaddingRight = UDim.new(0, 4)
gridPad.Parent = cpGrid

for i, cp in ipairs(CP_LIST) do
    local btn = Instance.new("TextButton")
    btn.Name = "CP" .. i
    btn.LayoutOrder = i
    btn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    btn.Text = tostring(i)
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.Parent = cpGrid
    Instance.new("UICorner", btn)
    table.insert(cpButtons, btn)
end

local tpNextBtn = makeButton(cpScroll, "Next CP", Color3.fromRGB(50, 120, 190), 2)
local tpPrevBtn = makeButton(cpScroll, "Prev CP", Color3.fromRGB(50, 120, 190), 3)
CPStore.updateBtn = makeButton(cpScroll, "Update CP (Current Pos)", Color3.fromRGB(200, 130, 30), 4)
CPStore.saveBtn = makeButton(cpScroll, "Save CPs to File", Color3.fromRGB(50, 160, 70), 5)
CPStore.resetBtn = makeButton(cpScroll, "Reset CPs to Default", Color3.fromRGB(200, 50, 50), 6)
CPStore.infoLabel = makeLabel(cpScroll, "CP List:", Color3.fromRGB(200, 200, 200), 7, 270)
CPStore.infoLabel.TextWrapped = true
CPStore.infoLabel.TextSize = 9
CPStore.infoLabel.TextXAlignment = Enum.TextXAlignment.Left
CPStore.infoLabel.TextYAlignment = Enum.TextYAlignment.Top
CPStore.deleteBtn = makeButton(cpScroll, "Delete Saved CPs", Color3.fromRGB(120, 60, 60), 8)

-- daftar CP + koordinat; CP aktif ditandai >>>
function CPStore.updateInfo()
    pcall(function()
        local lines = {}
        for i, cp in ipairs(CP_LIST) do
            lines[i] = ((i == currentIndex) and ">>> " or "    ") .. "CP " .. i .. ": "
                .. math.floor(cp.X) .. ", " .. math.floor(cp.Y) .. ", " .. math.floor(cp.Z)
        end
        CPStore.infoLabel.Text = table.concat(lines, "\n")
    end)
end

-- ====== TAB 3: FISHING ======
local fishTab, fishScroll = makeContentTab()
table.insert(tabFrames, fishTab)

local autoFishBtn = makeButton(fishScroll, "Auto Fish: OFF", Color3.fromRGB(120, 120, 120), 0)
local fishStatusLabel = makeLabel(fishScroll, "Status: Idle", Color3.fromRGB(150, 255, 150), 1, 40)
fishStatusLabel.TextSize = 10
fishStatusLabel.TextWrapped = true

-- label debug tetap dibuat (Fish.render / log tetap jalan di belakang layar) tapi TIDAK ditampilkan di UI
fishDebugLabel = Instance.new("TextLabel")
fishDebugLabel.Name = "FishDebugHidden"

-- ====== TAB 4: TOOLS ======
local toolsTab, toolsScroll = makeContentTab()
table.insert(tabFrames, toolsTab)

pendingLabel = makeLabel(toolsScroll, "Pending: -", Color3.fromRGB(255, 150, 150), 0, 22)
pendingLabel.BackgroundColor3 = Color3.fromRGB(60, 40, 40)

local resumeBtn    = makeButton(toolsScroll, "Resume Pending",  Color3.fromRGB(200, 100, 200), 1)
local addPendingBtn = makeButton(toolsScroll, "Tandai Pending", Color3.fromRGB(180, 80, 80), 2)
local clearPendingBtn = makeButton(toolsScroll, "Clear Pending", Color3.fromRGB(80, 80, 80), 3)
local scanBtn = makeButton(toolsScroll, "Scan CP Server",       Color3.fromRGB(100, 180, 100), 4)

debugLabel = makeLabel(toolsScroll, "CP Server: --", Color3.fromRGB(150, 255, 150), 5, 40)
debugLabel.BackgroundColor3 = Color3.fromRGB(20, 40, 20)
debugLabel.TextSize = 10
debugLabel.TextWrapped = true

-- ====== TAB 5: SETTINGS ======
local settingsTab, settingsScroll = makeContentTab()
table.insert(tabFrames, settingsTab)

local antiAfkBtn = makeButton(settingsScroll, "Anti-AFK: ON", Color3.fromRGB(50, 160, 70), 0)
local tpDelayBtn = makeButton(settingsScroll, "TP Delay: 0.5s", Color3.fromRGB(120, 120, 120), 1)
local walkRadiusBtn = makeButton(settingsScroll, "Walk Radius: 6", Color3.fromRGB(120, 120, 120), 2)
local walkSpeedBtn = makeButton(settingsScroll, "Walk Move: 0.08s", Color3.fromRGB(120, 120, 120), 3)

-- ====== REMOTE SPY UI (di bawah Settings) ======
-- Remote spy: WAJIB dipakai dulu (Start -> mancing manual 1x -> Stop)
local SpyUI = {}
SpyUI.start = makeButton(settingsScroll, "Start Spy", Color3.fromRGB(50, 160, 70), 20)
SpyUI.stop = makeButton(settingsScroll, "Stop Spy", Color3.fromRGB(200, 50, 50), 21)
SpyUI.clear = makeButton(settingsScroll, "Clear Spy Log", Color3.fromRGB(120, 120, 120), 22)
SpyUI.log = makeLabel(settingsScroll, "[spy] log kosong", Color3.fromRGB(150, 255, 150), 23, 300)
SpyUI.log.BackgroundColor3 = Color3.fromRGB(20, 40, 20)
SpyUI.log.TextSize = 9
SpyUI.log.TextWrapped = true
SpyUI.log.TextXAlignment = Enum.TextXAlignment.Left
SpyUI.log.TextYAlignment = Enum.TextYAlignment.Top

function SpyUI.setText(text)
    if SpyUI.log and SpyUI.log.Parent then
        pcall(function() SpyUI.log.Text = text end)
    end
end


-- ====== TAB BUTTONS (SIDEBAR) ======
local tabDefs = {
    { emoji = "R", name = "Route" },
    { emoji = "C", name = "CP" },
    { emoji = "F", name = "Fishing" },
    { emoji = "T", name = "Tools" },
    { emoji = "S", name = "Settings" },
}

for i, def in ipairs(tabDefs) do
    local idx = i

    local item = Instance.new("Frame")
    item.LayoutOrder = i
    item.Size = UDim2.new(0, 40, 0, 56)
    item.BackgroundTransparency = 1
    item.BorderSizePixel = 0
    item.Parent = sidebar

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 40)
    btn.Position = UDim2.new(0, 0, 0, 0)
    btn.BackgroundColor3 = Color3.fromRGB(70, 70, 84)
    btn.Text = def.emoji
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.TextSize = 20
    btn.Font = Enum.Font.GothamBold
    btn.ZIndex = 1
    btn.Parent = item
    Instance.new("UICorner", btn)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 14)
    lbl.Position = UDim2.new(0, 0, 0, 40)
    lbl.BackgroundTransparency = 1
    lbl.Text = def.name
    lbl.TextColor3 = Color3.fromRGB(200, 200, 210)
    lbl.TextSize = 7
    lbl.Font = Enum.Font.GothamBold
    lbl.Parent = item

    btn.MouseButton1Click:Connect(safe(function()
        setActiveTab(idx)
    end))

    table.insert(tabButtons, btn)
end

-- ====== RESIZE HANDLE ======
local function makeHandle(name, pos, anchorPoint)
    local h = Instance.new("TextButton")
    h.Name = name
    h.Size = UDim2.new(0, 22, 0, 22)
    h.Position = pos
    h.AnchorPoint = anchorPoint
    h.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
    h.Text = ""
    h.ZIndex = 50
    h.Parent = panel
    Instance.new("UICorner", h)
    local s = Instance.new("UIStroke", h)
    s.Color = Color3.new(1, 1, 1)
    s.Thickness = 2
    return h
end

local hTL = makeHandle("ResizeTL", UDim2.new(0, 0, 0, 0), Vector2.new(0, 0))
local hTR = makeHandle("ResizeTR", UDim2.new(1, 0, 0, 0), Vector2.new(1, 0))
local hBL = makeHandle("ResizeBL", UDim2.new(0, 0, 1, 0), Vector2.new(0, 1))
local hBR = makeHandle("ResizeBR", UDim2.new(1, 0, 1, 0), Vector2.new(1, 1))

local function setupResize(handle, mode)
    local resizing, resizeStart, startSize, startPos
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            resizing = true
            resizeStart = input.Position
            startSize = panel.Size
            startPos = panel.Position
        end
    end)
    handle.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            resizing = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not resizing then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - resizeStart
        local newW = startSize.X.Offset
        local newH = startSize.Y.Offset
        local newX = startPos.X.Offset
        local newY = startPos.Y.Offset
        if mode == "bottomRight" then
            newW = math.max(MIN_W, startSize.X.Offset + delta.X)
            newH = math.max(MIN_H, startSize.Y.Offset + delta.Y)
        elseif mode == "bottomLeft" then
            local w = math.max(MIN_W, startSize.X.Offset - delta.X)
            local h = math.max(MIN_H, startSize.Y.Offset + delta.Y)
            newX = startPos.X.Offset + (startSize.X.Offset - w)
            newW = w
            newH = h
        elseif mode == "topRight" then
            local w = math.max(MIN_W, startSize.X.Offset + delta.X)
            local h = math.max(MIN_H, startSize.Y.Offset - delta.Y)
            newY = startPos.Y.Offset + (startSize.Y.Offset - h)
            newW = w
            newH = h
        elseif mode == "topLeft" then
            local w = math.max(MIN_W, startSize.X.Offset - delta.X)
            local h = math.max(MIN_H, startSize.Y.Offset - delta.Y)
            newX = startPos.X.Offset + (startSize.X.Offset - w)
            newY = startPos.Y.Offset + (startSize.Y.Offset - h)
            newW = w
            newH = h
        end
        panel.Size = UDim2.new(0, newW, 0, newH)
        panel.Position = UDim2.new(startPos.X.Scale, newX, startPos.Y.Scale, newY)
    end)
end

setupResize(hTL, "topLeft")
setupResize(hTR, "topRight")
setupResize(hBL, "bottomLeft")
setupResize(hBR, "bottomRight")

-- ====== UTIL ======
local function getRoot()
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

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

local function getServerCheckpoint()
    local ls = player:FindFirstChild("leaderstats")
    if ls then
        for _, n in ipairs(CHECKPOINT_STAT_NAMES) do
            local stat = ls:FindFirstChild(n)
            if stat and stat:IsA("ValueBase") then
                local num = tonumber(stat.Value)
                if num then return num, n, "leaderstats" end
            end
        end
    end
    for _, n in ipairs(CHECKPOINT_STAT_NAMES) do
        local val = player:GetAttribute(n)
        if val then
            local num = tonumber(val)
            if num then return num, n, "attribute" end
        end
    end
    local sf = player:FindFirstChild("Stats")
    if sf then
        for _, n in ipairs(CHECKPOINT_STAT_NAMES) do
            local stat = sf:FindFirstChild(n)
            if stat and stat:IsA("ValueBase") then
                local num = tonumber(stat.Value)
                if num then return num, n, "Stats" end
            end
        end
    end
    return nil, nil, nil
end

local function walkMuter()
    if not USE_WIGGLE then return end
    local root = getRoot()
    if not root then return end
    local center = root.Position

    for i = 0, WALK_STEPS - 1 do
        if stopFlag then return end
        local angle = i * (math.pi * 2 / WALK_STEPS)
        local offset = Vector3.new(math.cos(angle) * WALK_RADIUS, 0, math.sin(angle) * WALK_RADIUS)
        local currentPos = root.Position
        local targetPos = center + offset
        local delta = targetPos - currentPos
        delta = Vector3.new(delta.X, 0, delta.Z)
        local dist = delta.Magnitude

        if dist > 0.5 then
            local t0 = tick()
            local conn
            conn = RunService.Heartbeat:Connect(function()
                local elapsed = tick() - t0
                if elapsed >= WALK_MOVE_TIME then
                    if conn then conn:Disconnect() end
                    return
                end
                local alpha = elapsed / WALK_MOVE_TIME
                local newPos = currentPos:Lerp(targetPos, alpha)
                pcall(function()
                    root.CFrame = CFrame.new(newPos) * (root.CFrame - root.Position)
                    root.Velocity = Vector3.zero
                    root.AssemblyLinearVelocity = Vector3.zero
                end)
            end)
            task.wait(WALK_MOVE_TIME)
            if conn then conn:Disconnect() end
        end
        task.wait(0.02)
    end

    pcall(function()
        root.CFrame = CFrame.new(center + Vector3.new(0, 1, 0)) * (root.CFrame - root.Position)
    end)
    task.wait(0.03)
    pcall(function()
        root.CFrame = CFrame.new(center) * (root.CFrame - root.Position)
    end)
    task.wait(WIGGLE_DELAY)
end

local function isPending(idx)
    for _, v in ipairs(pendingCPs) do
        if v == idx then return true end
    end
    return false
end

local function highlightCP(idx)
    if cpLabel then
        cpLabel.Text = "CP: " .. idx .. " / " .. #CP_LIST
    end
    CPStore.updateInfo()
    for i, b in ipairs(cpButtons) do
        if i == idx then
            b.BackgroundColor3 = Color3.fromRGB(50, 160, 70)
        elseif isPending(i) then
            b.BackgroundColor3 = Color3.fromRGB(180, 80, 80)
        else
            b.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
        end
    end
end

local function updatePendingLabel()
    if not pendingLabel then return end
    if #pendingCPs == 0 then
        pendingLabel.Text = "Pending: -"
    else
        local s = ""
        for i, v in ipairs(pendingCPs) do
            if i > 1 then s = s .. "," end
            s = s .. v
        end
        pendingLabel.Text = "Pending: " .. s
    end
end

local function addPending(idx)
    for _, v in ipairs(pendingCPs) do
        if v == idx then return end
    end
    table.insert(pendingCPs, idx)
    updatePendingLabel()
end

local function removePending(idx)
    for i, v in ipairs(pendingCPs) do
        if v == idx then
            table.remove(pendingCPs, i)
            break
        end
    end
    updatePendingLabel()
end

-- ====== ANTI-AFK FUNCTION ======
local function antiAFK()
    local ok = pcall(function()
        local vUser = game:GetService("VirtualUser")
        vUser:CaptureController()
        vUser:ClickButton2(Vector2.new())
    end)
    if not ok then
        local root = getRoot()
        if not root then return end
        pcall(function()
            local original = root.CFrame
            root.CFrame = original + Vector3.new(0.1, 0, 0)
            task.wait(0.1)
            root.CFrame = original
        end)
    end
end

-- ====== AUTO FISH FUNCTION ======
local function getNet()
    local pkgs = ReplicatedStorage:FindFirstChild("Packages")
    if not pkgs then return nil end
    local index = pkgs:FindFirstChild("_Index")
    if not index then return nil end
    for _, child in ipairs(index:GetChildren()) do
        if string.find(child.Name:lower(), "sleitnick") then
            local net = child:FindFirstChild("net")
            if net then return net end
        end
    end
    return nil
end

local function autoFish()
    local net = getNet()
    if not net then
        warn("[RouteTools] AutoFish: net tidak ditemukan")
        return
    end
    local equip = net:FindFirstChild("RE/EquipToolFromHotbar")
    local complete = net:FindFirstChild("RE/FishingCompleted")
    if not equip or not complete then
        warn("[RouteTools] AutoFish: remote tidak ditemukan")
        return
    end
    pcall(function()
        equip:FireServer()
        task.wait(0.1)
        complete:FireServer()
    end)
end

-- ====== SELL ALL FISH + SCAN REMOTES ======
local function setFishText(text)
    if fishDebugLabel and fishDebugLabel.Parent then
        pcall(function() fishDebugLabel.Text = text end)
    end
end

local function scanFishingRemotes()
    local keywords = { "fish", "cast", "charge", "complete", "reel", "rod", "sell", "minigame" }
    local lines = {}
    local total = 0
    pcall(function()
        for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
            if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
                local n = d.Name:lower()
                for _, kw in ipairs(keywords) do
                    if string.find(n, kw, 1, true) then
                        total = total + 1
                        if #lines < 25 then
                            table.insert(lines, (d:IsA("RemoteFunction") and "RF " or "RE ") .. d.Name)
                        end
                        break
                    end
                end
            end
        end
    end)
    if total == 0 then
        setFishText("Scan: tidak ada remote cocok")
    else
        local extra = total > #lines and ("\n... +" .. (total - #lines) .. " lagi") or ""
        setFishText("Scan: " .. total .. " remote\n" .. table.concat(lines, "\n") .. extra)
    end
end

-- ====== FISHING MODULE ======
-- Instant fishing remote-based (hasil spy): AmbilSemua -> CastEvent(true) -> CastEvent(false, ...args) -> MiniGame.
-- Reference remote diambil dari SPY (objeknya langsung), scan by name hanya fallback.
-- Dibungkus do...end + tabel Fish: slot local di script ini hampir penuh (batas Luau 200).
local Fish = {
    live = true,
    mode = "Safe",          -- Safe | Aggressive | Random
    stopAnimOn = true,
    useSpyArgs = true,
    autoTrigger = true,     -- true: MiniGame otomatis setelah cast (tanpa spam click)
    postSpam = true,        -- true: setelah MiniGame, cari tombol minigame lalu spam klik
    markerDelay = 0.5,      -- jeda marker terdeteksi -> MiniGame (server perlu waktu 'menerima' marker)
    spamDuration = 3,       -- lama spam klik minigame (detik)
    spamTarget = "Auto",    -- Auto | Quick | Berhenti | Screen
    skipCutscene = true,    -- skip animasi cutscene ikan langka (animasi + kamera + GUI)
    aggSkip = true,         -- Aggressive Cutscene Skip: tick cepat, grace pendek, matikan ScreenGui cutscene
    destroyBeam = true,     -- hancurkan BeamParticles/BeamLine (hanya saat cutscene aktif)
    beamDestroyed = 0,
    fastSkips = 0,          -- cutscene yang selesai < 0.5s
    csStart = 0,
    disabledGui = {},       -- [ScreenGui] = true : yang kita matikan (dinyalakan lagi setelah cutscene)
    spyActive = false,      -- diisi spy
    spyRefs = {},           -- diisi spy: [nama] = objek remote asli (CastEvent, MiniGame, AmbilSemua, TandaSeruBersama, GetKatalog)
    capturedCast = nil,     -- diisi spy: table.pack(false, 20, ...) dari CastEvent asli
    capturedTanda = nil,    -- diisi spy: argumen TandaSeruBersama asli
}
do
    local fishStatus = "idle"       -- idle / casting / reeling / success
    local fishCaught = 0
    local lastAction = "-"
    local lastCastArgs = "-"
    local logMsg = "-"
    local scanned = nil
    local lastScanT = 0
    local fishBusy = false
    local katalogDone = false
    local lastMarkerTime = nil      -- terakhir marker TandaSeruBersama (kita kirim / server kirim balik)
    local markerWaitStart = nil     -- mulai menunggu marker (dipakai watchdog)
    local miniFired = false         -- MiniGame sudah ditembak watchdog di siklus ini
    local markerListenerOn = false
    -- deteksi marker real-time (3 lapis: OnClientEvent, workspace/char/GUI watcher, timeout)
    local MARKER_TIMEOUT = 8        -- detik; lewat ini MiniGame dipaksa (tali ~2-3s sampai air + tanda seru 1-2s+)
    local markerDetected = false
    local markerSource = "-"
    local awaitMarker = false       -- true hanya saat siklus kita menunggu marker (abaikan marker lain)
    local lastCycleTime = 0
    local watchersOn = false
    local cycleT0 = tick()          -- awal siklus (untuk timeline)
    local timeline = {}
    local preSnapshot = nil         -- snapshot GUI sebelum MiniGame ditembak
    local probeCount = 0
    local baseSnapshot = nil        -- GUI yang sudah ada sebelum siklus (hotbar, HUD) -> bukan kandidat tombol minigame
    local inCycle = false           -- sedang di dalam runInstant
    local cycleCredited = false     -- ikan sudah dihitung di siklus ini (maks 1x per siklus)
    local cutsceneActive = false    -- cutscene ikan langka sedang tampil
    local lastCutsceneSeen = 0
    local cutsceneSkipped = 0
    local hiddenGui = {}            -- [obj] = true : frame yang kita sembunyikan (dikembalikan setelah cutscene selesai)
    local broadcastSeen = false     -- FishCatchBroadcast pernah fired (kalau belum, jangan percaya untuk cek hasil)

    local function tl(msg)
        table.insert(timeline, string.format("[+%.1f] ", tick() - cycleT0) .. tostring(msg))
        if #timeline > 24 then table.remove(timeline, 1) end
    end
    local listenerOn = false
    local REMOTE_NAMES = { "AmbilSemua", "CastEvent", "MiniGame", "TandaSeruBersama", "GetKatalog", "FishingCompleted" }
    -- nama alternatif untuk fallback scan (index kecil = prioritas tinggi)
    local ALT = {
        CastEvent = { "CastEvent", "Cast", "CastRod", "CastFishing" },
        MiniGame = { "MiniGame", "Minigame", "StartMinigame", "MiniGameStart" },
        AmbilSemua = { "AmbilSemua", "GetAll", "GetAllRod" },
        TandaSeruBersama = { "TandaSeruBersama" },
        GetKatalog = { "GetKatalog" },
        FishingCompleted = { "FishingCompleted" },
    }
    local CANON = {}
    for canon, list in pairs(ALT) do
        for rank, n in ipairs(list) do CANON[n] = { canon = canon, rank = rank } end
    end

    local NOT_READY = {
        "[!] Aktifkan Spy dulu:",
        "1. Klik Start Spy",
        "2. Mancing manual 1x di game (klik Automatic)",
        "3. Klik Stop Spy",
        "4. Baru Auto Fish / Test Instant bisa dipakai",
    }

    -- pola dari spy log (args sesudah `false` pertama)
    local DEFAULT_CAST = table.pack(false, 20, 0.9995213747024536, 0, 0.033333333333333,
        0.635294, 1, 0.0784314, 0.0784314, 0, 0.333333, 0.635294, 1, 0, 1.5)

    -- argumen TandaSeruBersama dari spy log (dipakai kalau belum ada hasil tangkapan sendiri)
    local TANDA_DEFAULT = table.pack(0.698039, 0.447059, 0.968627, 0.0784314, 0.0784314, 0,
        0.698039, 0.447059, 0.968627, 0, 1.5)

    local function fmtArgs(args)
        local parts = {}
        for i = 1, math.min(args.n, 9) do parts[i] = tostring(args[i]) end
        if args.n > 9 then table.insert(parts, "...") end
        return table.concat(parts, ", ")
    end

    -- argumen cast yang akan dipakai: hasil spy kalau ada & diizinkan, kalau tidak pola default
    local function baseCastArgs()
        if Fish.useSpyArgs and Fish.capturedCast and Fish.capturedCast.n > 0 then
            return Fish.capturedCast, true
        end
        return DEFAULT_CAST, false
    end

    -- Random: nilai pecahan digoyang +-0.5% (angka bulat tetap); yang aslinya <= 1 tidak boleh > 1
    local function generateCastArgs()
        local base = baseCastArgs()
        if Fish.mode ~= "Random" or (Fish.capturedCast and Fish.useSpyArgs) then return base end   -- args spy tidak pernah diacak
        local out = { n = base.n }
        for i = 1, base.n do
            local v = base[i]
            if type(v) == "number" and v ~= math.floor(v) then
                local j = v * (1 + (math.random() - 0.5) * 0.01)
                if v <= 1 then j = math.min(j, 1) end
                v = j
            end
            out[i] = v
        end
        return out
    end

    -- ---- FITUR 2: fallback scan (ReplicatedStorage + workspace + player, tanpa batas kedalaman) ----
    local function scanRemotes(force)
        if scanned and not force then
            local stale = false
            for _, n in ipairs(REMOTE_NAMES) do
                local r = scanned[n]
                if r and not r.Parent then stale = true end
            end
            if not stale then return scanned end
        end
        local found, rank = {}, {}
        local function visit(root)
            pcall(function()
                for _, d in ipairs(root:GetDescendants()) do
                    if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
                        local c = CANON[d.Name]
                        if c and (not found[c.canon] or c.rank < rank[c.canon]) then
                            found[c.canon] = d
                            rank[c.canon] = c.rank
                        end
                    end
                end
            end)
        end
        visit(ReplicatedStorage)
        visit(workspace)
        visit(player)
        scanned = found
        lastScanT = tick()
        return found
    end

    -- reference: spy (cached) dulu, lalu scan. Return remotes, sumber
    local function resolve()
        local out, src = {}, {}
        local needScan = false
        for _, n in ipairs(REMOTE_NAMES) do
            local r = Fish.spyRefs[n]
            if r and r.Parent then
                out[n], src[n] = r, "cached"
            else
                needScan = true
            end
        end
        if needScan then
            local sc = scanned
            if not sc or tick() - lastScanT > 5 then sc = scanRemotes() end
            for _, n in ipairs(REMOTE_NAMES) do
                if not out[n] then
                    local r = sc[n]
                    if r and r.Parent then
                        out[n], src[n] = r, "scan"
                    else
                        src[n] = "none"
                    end
                end
            end
        end
        return out, src
    end

    local function render()
        local _, src = resolve()
        local base = baseCastArgs()
        local lines = {
            "Auto: " .. (USE_AUTO_FISH and "ON" or "OFF") .. " | Mode: " .. Fish.mode,
            "Spy: " .. (Fish.spyActive and "active" or "inactive"),
            "CastEvent: " .. src.CastEvent .. " (" .. base.n .. " args)",
            "MiniGame: " .. src.MiniGame,
            "AmbilSemua: " .. src.AmbilSemua,
            "GetKatalog: " .. src.GetKatalog,
            "TandaSeru: " .. src.TandaSeruBersama,
            "Args: " .. base.n .. (Fish.capturedCast and Fish.useSpyArgs and " (spy)" or " (default)"),
            "Status: " .. fishStatus,
            "AutoTrig: " .. (Fish.autoTrigger and "ON" or "OFF") .. " | Last marker: "
                .. (lastMarkerTime and (math.floor(tick() - lastMarkerTime) .. "s lalu") or "-"),
            "Cutscene: " .. (cutsceneActive and "active" or "none") .. " | Skipped: " .. cutsceneSkipped
                .. " | Fast: " .. Fish.fastSkips .. " | Beam destroyed: " .. Fish.beamDestroyed,
            "Marker: " .. (markerDetected and "detected" or "not detected") .. " | Source: " .. markerSource,
            "Cycle: " .. string.format("%.1f", lastCycleTime) .. "s | Fish: " .. fishCaught,
            "Last log: " .. logMsg,
        }
        if src.CastEvent == "none" then
            for _, l in ipairs(NOT_READY) do table.insert(lines, l) end
        end
        if #timeline > 0 then
            table.insert(lines, "--- timeline ---")
            for _, l in ipairs(timeline) do table.insert(lines, l) end
        end
        setFishText(table.concat(lines, "\n"))
    end

    local function log(msg)
        logMsg = tostring(msg)
        render()
    end

    -- hitung ikan maks 1x per siklus, dari sumber yang pertama mendeteksi (Broadcast / Object / Manual)
    local function creditFish(source)
        if cycleCredited then return false end
        cycleCredited = true
        fishCaught = fishCaught + 1
        tl("Fish caught: +1 (via " .. source .. ")")
        return true
    end

    -- Auto Fish / Test Instant hanya boleh jalan kalau CastEvent sudah ada (hasil spy atau scan)
    local function ready()
        local r = resolve()
        return r.CastEvent ~= nil
    end

    -- RemoteFunction -> InvokeServer (max tunggu 1.5s, tidak menggantung), RemoteEvent -> FireServer
    local function callRemote(remote, name, ...)
        if not remote then return false end
        local args = table.pack(...)
        lastAction = name .. "(" .. fmtArgs(args) .. ")"
        if remote:IsA("RemoteFunction") then
            local done = false
            task.spawn(function()
                pcall(function() remote:InvokeServer(table.unpack(args, 1, args.n)) end)
                done = true
            end)
            local t0 = tick()
            while not done and tick() - t0 < 1.5 do task.wait(0.02) end
            return done
        end
        return (pcall(function() remote:FireServer(table.unpack(args, 1, args.n)) end))
    end

    local function stopAllAnimations()
        pcall(function()
            local char = player.Character
            if not char then return end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum then return end
            for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
                pcall(function() track:Stop(0) end)
            end
        end)
    end

    -- kirim CastEvent(true) lalu CastEvent(false, ...) dengan args yang diberikan (args[1] harus false)
    local function sendCast(remote, args, gap)
        callRemote(remote, "CastEvent", true)
        task.wait(0.1 + gap)
        lastCastArgs = fmtArgs(args)
        callRemote(remote, "CastEvent", table.unpack(args, 1, args.n))
    end

    local function tandaArgs()
        if Fish.useSpyArgs and Fish.capturedTanda and Fish.capturedTanda.n > 0 then
            return Fish.capturedTanda
        end
        return TANDA_DEFAULT
    end

    -- ---- deteksi marker: yang mana pun duluan -> MiniGame ----
    -- ---- GUI helper: snapshot tombol/label yang tampil di PlayerGui (tanpa GUI kita) ----
    local function isShown(obj)
        local cur = obj
        while cur and cur ~= playerGui do
            if cur:IsA("GuiObject") and not cur.Visible then return false end
            if cur:IsA("ScreenGui") and not cur.Enabled then return false end
            cur = cur.Parent
        end
        return true
    end

    local function guiText(obj)
        local txt = ""
        pcall(function()
            if obj:IsA("TextButton") or obj:IsA("TextLabel") then txt = obj.Text end
            if txt == "" then
                for _, c in ipairs(obj:GetChildren()) do
                    if c:IsA("TextLabel") and c.Text ~= "" then
                        txt = c.Text
                        break
                    end
                end
            end
        end)
        return txt
    end

    local function guiSnapshot()
        local snap = {}
        pcall(function()
            for _, obj in ipairs(playerGui:GetDescendants()) do
                if (obj:IsA("TextButton") or obj:IsA("ImageButton") or obj:IsA("TextLabel"))
                    and not obj:FindFirstAncestor("RoutePanel")
                    and not obj:FindFirstAncestor("RouteIcon")
                    and not obj:FindFirstAncestor("RouteError")
                    and isShown(obj) then
                    snap[obj] = true
                end
            end
        end)
        return snap
    end

    local function clickObj(obj)
        if not obj then return end
        pcall(function()
            if firesignal and obj:IsA("GuiButton") then
                firesignal(obj.MouseButton1Click)
                firesignal(obj.Activated)
            end
        end)
        pcall(function()
            if getconnections and obj:IsA("GuiButton") then
                for _, c in ipairs(getconnections(obj.MouseButton1Click)) do
                    pcall(function() c:Fire() end)
                end
            end
        end)
        pcall(function()
            local vu = game:GetService("VirtualUser")
            vu:CaptureController()
            local inset = 0
            local sg = obj:FindFirstAncestorOfClass("ScreenGui")
            if sg and not sg.IgnoreGuiInset then
                inset = game:GetService("GuiService"):GetGuiInset().Y
            end
            vu:ClickButton1(Vector2.new(
                obj.AbsolutePosition.X + obj.AbsoluteSize.X / 2,
                obj.AbsolutePosition.Y + obj.AbsoluteSize.Y / 2 + inset
            ))
        end)
    end

    -- ---- SKIP CUTSCENE ikan langka (animasi + kamera + GUI) ----
    -- Deteksi ketat: label peluang "1 in 1M" atau bobot "(461.6K kg)". Kata seperti Legendary/Large/Mythic
    -- sengaja TIDAK dipakai sendirian: terlalu umum, bisa mengenai inventory/toko.
    local function isCutsceneText(s)
        if type(s) ~= "string" or s == "" then return false end
        if s:match("^%s*1%s+in%s+[%d%.,]+%s*%a?%s*$") then return true end
        if s:match("%(%s*[%d%.,]+%s*[KkMmBbTt]%s*kg%s*%)") then return true end   -- bobot besar saja (K/M/B/T kg)
        return false
    end

    -- tampil, tidak menghitung frame yang kita sembunyikan sendiri
    local function shownIgnoringHidden(obj)
        local cur = obj
        while cur and cur ~= playerGui do
            if cur:IsA("GuiObject") and not cur.Visible and not hiddenGui[cur] then return false end
            if cur:IsA("ScreenGui") and not cur.Enabled then return false end
            cur = cur.Parent
        end
        return true
    end

    local function findCutsceneLabels()
        local found = {}
        pcall(function()
            for _, obj in ipairs(playerGui:GetDescendants()) do
                if obj:IsA("TextLabel") and isCutsceneText(obj.Text)
                    and not obj:FindFirstAncestor("RoutePanel")
                    and not obj:FindFirstAncestor("RouteIcon")
                    and not obj:FindFirstAncestor("RouteError")
                    and shownIgnoringHidden(obj) then
                    table.insert(found, obj)
                    if #found >= 3 then break end
                end
            end
        end)
        return found
    end

    local function stopTracks(obj)
        pcall(function()
            for _, tr in ipairs(obj:GetPlayingAnimationTracks()) do
                pcall(function() tr:Stop(0) end)
            end
        end)
    end

    -- karakter sendiri (Humanoid / Animator / AnimationController) + NPC di workspace (bukan karakter pemain lain)
    local function stopAllAnimsEverywhere()
        pcall(function()
            local char = player.Character
            if char then
                for _, obj in ipairs(char:GetDescendants()) do
                    if obj:IsA("AnimationController") or obj:IsA("Animator") or obj:IsA("Humanoid") then
                        stopTracks(obj)
                    end
                end
            end
        end)
        pcall(function()
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj:IsA("AnimationController") or obj:IsA("Humanoid") then
                    local model = obj.Parent
                    if not (model and Players:GetPlayerFromCharacter(model)) then stopTracks(obj) end
                end
            end
        end)
    end

    local function resetCamera()
        pcall(function()
            local cam = workspace.CurrentCamera
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if cam and hum then
                if cam.CameraType ~= Enum.CameraType.Custom then cam.CameraType = Enum.CameraType.Custom end
                if cam.CameraSubject ~= hum then cam.CameraSubject = hum end
            end
        end)
    end

    -- sembunyikan frame root (anak langsung ScreenGui) yang memuat label cutscene; tidak menyentuh ScreenGui.Enabled
    local function hideCutsceneGui(labels)
        pcall(function()
            for _, label in ipairs(labels) do
                local root = label
                while root.Parent and root.Parent ~= playerGui and not root.Parent:IsA("ScreenGui") do
                    root = root.Parent
                end
                if root:IsA("GuiObject") and root.Visible and not hiddenGui[root] then
                    hiddenGui[root] = true
                    root.Visible = false
                end
            end
        end)
    end

    local function restoreHiddenGui()
        for obj in pairs(hiddenGui) do
            pcall(function()
                if obj.Parent then obj.Visible = true end
            end)
        end
        hiddenGui = {}
    end

    -- nama persis saja (bukan find("Beam")) supaya objek game lain tidak ikut hancur
    function Fish.isBeam(obj)
        local n = obj.Name
        return n == "BeamParticles" or n == "BeamLine"
    end

    function Fish.destroyBeamObj(obj)
        pcall(function()
            if obj and obj.Parent and Fish.isBeam(obj)
                and not (player.Character and obj:IsDescendantOf(player.Character)) then
                obj:Destroy()
                Fish.beamDestroyed = Fish.beamDestroyed + 1
            end
        end)
    end

    -- hanya dipanggil saat cutscene aktif
    function Fish.destroyBeams()
        pcall(function()
            for _, obj in ipairs(workspace:GetDescendants()) do
                if Fish.isBeam(obj) then Fish.destroyBeamObj(obj) end
            end
        end)
    end

    -- objek baru yang muncul saat cutscene aktif langsung dihancurkan (tanpa nunggu tick)
    function Fish.setupBeamHook()
        if Fish.beamConn then return end
        pcall(function()
            Fish.beamConn = workspace.DescendantAdded:Connect(function(obj)
                if cutsceneActive and Fish.destroyBeam and USE_AUTO_FISH then
                    Fish.destroyBeamObj(obj)
                end
            end)
        end)
    end

    -- matikan ScreenGui cutscene (nama cutscene/cinematic/reveal/intro); dinyalakan lagi saat cutscene selesai
    function Fish.disableCsGuis()
        pcall(function()
            for _, gui in ipairs(playerGui:GetChildren()) do
                if gui:IsA("ScreenGui") and gui.Enabled and not Fish.disabledGui[gui]
                    and gui.Name ~= "RoutePanel" and gui.Name ~= "RouteIcon" and gui.Name ~= "RouteError" then
                    local n = gui.Name:lower()
                    if n:find("cutscene") or n:find("cinematic") or n:find("reveal") or n:find("intro") then
                        Fish.disabledGui[gui] = true
                        gui.Enabled = false
                    end
                end
            end
        end)
    end

    function Fish.restoreCsGuis()
        for gui in pairs(Fish.disabledGui) do
            pcall(function()
                if gui.Parent then gui.Enabled = true end
            end)
        end
        Fish.disabledGui = {}
    end

    -- dipanggil tiap ~0.2s (aggressive: 0.05s) saat Auto Fish ON + Skip Cutscene ON
    function Fish.cutsceneTick()
        local labels = findCutsceneLabels()
        local now = tick()
        if #labels > 0 then
            if not cutsceneActive then
                cutsceneActive = true
                cutsceneSkipped = cutsceneSkipped + 1
                Fish.csStart = now
                tl("Cutscene detected: '" .. tostring(labels[1].Text) .. "'")
                log("Cutscene aktif -> skip")
            end
            lastCutsceneSeen = now
        elseif cutsceneActive and now - lastCutsceneSeen > (Fish.aggSkip and 0.3 or 1) then
            cutsceneActive = false
            if lastCutsceneSeen - Fish.csStart < 0.5 then Fish.fastSkips = Fish.fastSkips + 1 end
            restoreHiddenGui()
            Fish.restoreCsGuis()
            tl("Cutscene selesai")
            render()
        end
        if cutsceneActive then
            stopAllAnimsEverywhere()
            resetCamera()
            hideCutsceneGui(labels)
            if Fish.aggSkip then Fish.disableCsGuis() end
            if Fish.destroyBeam then Fish.destroyBeams() end
        elseif fishStatus == "success" then
            resetCamera()
        end
    end

    -- ====== ANTI SHAKE + BERSIH-BERSIH EFEK SECRET ======
    -- (slot local penuh -> semua di tabel Fish; semua pcall + null check)
    Fish.lastCleanT = 0

    local function isOtherCharacter(obj)
        local m = obj:FindFirstAncestorOfClass("Model")
        while m do
            if Players:GetPlayerFromCharacter(m) then return true end
            m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
        end
        return false
    end

    -- kamera: selalu balik ke Custom + subject Humanoid; CFrame dipaksa hanya saat cutscene aktif
    -- (kalau dipaksa terus, kamera pemain ikut terkunci)
    function Fish.forceCameraStable()
        local cam = workspace.CurrentCamera
        local char = player.Character
        if not cam or not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not root or not hum then return end
        pcall(function()
            if cam.CameraType ~= Enum.CameraType.Custom then cam.CameraType = Enum.CameraType.Custom end
            if cam.CameraSubject ~= hum then cam.CameraSubject = hum end
        end)
        if cutsceneActive then
            pcall(function()
                cam.CFrame = CFrame.lookAt(root.Position + Vector3.new(0, 5, 15), root.Position)
            end)
        end
    end

    function Fish.resetPlayerVelocity()
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    -- hanya saat cutscene aktif; ParticleEmitter/Beam/Attachment ber-nama efek, bukan karakter siapa pun
    function Fish.destroyCutsceneEffects()
        if not cutsceneActive then return end
        local char = player.Character
        for _, obj in ipairs(workspace:GetDescendants()) do
            pcall(function()
                if not obj.Parent then return end
                if not (obj:IsA("ParticleEmitter") or obj:IsA("Beam") or obj:IsA("Attachment")) then return end
                if char and obj:IsDescendantOf(char) then return end
                if isOtherCharacter(obj) then return end
                local n = obj.Name:lower()
                if n:find("beam") or n:find("particle") or n:find("flash") or n:find("shake")
                    or n:find("burst") or n:find("cutscene") or n:find("secret") or n:find("effect") then
                    obj:Destroy()
                end
            end)
        end
    end

    -- GUI cutscene/secret milik game (bukan GUI kita); "catch"/"notification" sengaja tidak disentuh
    -- karena deteksi hasil tangkapan membaca label di sana
    function Fish.destroySecretGui()
        for _, gui in ipairs(playerGui:GetChildren()) do
            pcall(function()
                if gui.Name == "RoutePanel" or gui.Name == "RouteIcon" or gui.Name == "RouteError" then return end
                local n = gui.Name:lower()
                if n:find("cutscene") or n:find("secret") or n:find("cinematic") or n:find("reveal") or n:find("intro") then
                    gui:Destroy()
                end
            end)
        end
    end

    -- dipanggil tiap 0.1s dari loop gabungan di akhir script
    function Fish.cleanTick()
        pcall(Fish.forceCameraStable)
        pcall(Fish.resetPlayerVelocity)
        local now = tick()
        if now - Fish.lastCleanT > 0.2 then
            Fish.lastCleanT = now
            pcall(Fish.destroyCutsceneEffects)
            pcall(Fish.destroySecretGui)
        end
    end

    -- tes manual: jalankan skip selama 5 detik (munculkan cutscene saat tes berjalan, mis. mancing ikan langka)
    function Fish.testSkipCutscene()
        cycleT0 = tick()
        timeline = {}
        tl("Test Skip Cutscene 5s...")
        log("Test Skip Cutscene: menunggu cutscene 5s")
        local t0 = tick()
        local seen = false
        while tick() - t0 < 5 do
            Fish.cutsceneTick()
            if cutsceneActive then seen = true end
            task.wait(0.2)
        end
        restoreHiddenGui()
        Fish.restoreCsGuis()
        cutsceneActive = false
        log(seen and "Test selesai: cutscene terdeteksi + di-skip" or "Test selesai: tidak ada cutscene terdeteksi")
    end

    -- ---- tombol minigame: filter KETAT (bukan hotbar, bukan tombol STOP/BERHENTI, bukan HUD lama) ----
    local function isHotbar(obj)
        local cur = obj
        while cur and cur ~= playerGui do
            local n = cur.Name:lower()
            if n:find("hotbar") or n:find("backpack") or n:find("toolbar") or n:find("tool") then return true end
            cur = cur.Parent
        end
        return false
    end

    local function stopLike(obj)
        local s = (guiText(obj) .. " " .. obj.Name):lower()
        return s:find("berhenti") or s:find("stop") or s:find("batal") or s:find("cancel")
    end

    local function textMatch(obj)
        local s = guiText(obj):lower()
        return s:find("quick") or s:find("click") or s:find("tap") or s:find("tarik") or s:find("reel")
    end

    local function viewSize()
        local x, y = 1920, 1080
        pcall(function()
            local vp = workspace.CurrentCamera.ViewportSize
            x, y = vp.X, vp.Y
        end)
        return x, y
    end

    -- daftar kandidat berurutan: {obj=..., kind=...}; kind "screen" = klik tengah layar (minigame "tap di mana saja")
    local function collectCandidates(after, mode)
        local list = {}
        local seen = {}
        local _, vpY = viewSize()
        if mode == "Screen" then return { { kind = "screen" } } end
        if mode == "Berhenti" then
            for obj in pairs(after) do
                if obj:IsA("GuiButton") and stopLike(obj) then table.insert(list, { obj = obj, kind = "berhenti" }) end
            end
            return list
        end
        for obj in pairs(after) do
            if textMatch(obj) and not stopLike(obj) and not isHotbar(obj) then
                local target = obj
                if not obj:IsA("GuiButton") and obj.Parent and obj.Parent:IsA("GuiButton") then target = obj.Parent end
                if not seen[target] then
                    seen[target] = true
                    table.insert(list, { obj = target, kind = "text" })
                end
            end
        end
        -- Y > 50% layar dulu
        table.sort(list, function(x, y)
            local xa = x.obj.AbsolutePosition.Y > vpY * 0.5 and 0 or 1
            local ya = y.obj.AbsolutePosition.Y > vpY * 0.5 and 0 or 1
            return xa < ya
        end)
        if mode == "Quick" then return list end
        -- fallback tombol besar (bukan ikon item): lebar > 200, Y > 70%
        for obj in pairs(after) do
            if obj:IsA("GuiButton") and not seen[obj] and not stopLike(obj) and not isHotbar(obj)
                and not (baseSnapshot and baseSnapshot[obj])
                and obj.AbsoluteSize.X > 200 and obj.AbsolutePosition.Y > vpY * 0.7 then
                seen[obj] = true
                table.insert(list, { obj = obj, kind = "big" })
            end
        end
        table.insert(list, { kind = "screen" })   -- terakhir: klik tengah layar
        return list
    end

    local function clickScreenCenter()
        pcall(function()
            local x, y = viewSize()
            local vu = game:GetService("VirtualUser")
            vu:CaptureController()
            vu:ClickButton1(Vector2.new(x / 2, y / 2))
        end)
    end

    local function candName(c)
        if c.kind == "screen" then return "tengah layar" end
        return c.kind .. " '" .. guiText(c.obj) .. "' (" .. c.obj.Name .. ")"
    end

    -- spam loop: ~33 klik/detik selama `duration`. Kalau ada label counter angka (mis. '000') dan tidak berubah
    -- setelah 10 klik -> pindah ke kandidat berikutnya. Berhenti kalau tombolnya hilang.
    local function spamLoop(duration, mode)
        duration = duration or 3
        mode = mode or "Auto"
        local after = guiSnapshot()
        local cands = collectCandidates(after, mode)
        if #cands == 0 then
            tl("Spam: target '" .. mode .. "' tidak ketemu")
            log("WARNING: tombol minigame (" .. mode .. ") tidak ketemu")
            return false
        end
        local counter = nil
        for obj in pairs(after) do
            if obj:IsA("TextLabel") and guiText(obj):match("^%d+$") and not (baseSnapshot and baseSnapshot[obj]) then
                counter = obj
                break
            end
        end
        local function counterText() return counter and counter.Parent and counter.Text or "-" end
        local ci = 1
        local c0 = counterText()
        tl("Spam start (" .. duration .. "s) target: " .. candName(cands[ci]) .. " | counter " .. c0)
        local t0 = tick()
        local count = 0
        local winCount, winText = 0, c0
        while tick() - t0 < duration do
            if Fish.skipCutscene and cutsceneActive then
                tl("Cutscene -> spam dihentikan")
                break
            end
            local c = cands[ci]
            if c.kind ~= "screen" and (not c.obj.Parent or not isShown(c.obj)) then
                if ci < #cands and mode == "Auto" then
                    ci = ci + 1
                    winCount, winText = 0, counterText()
                else
                    tl("Tombol hilang -> minigame selesai")
                    break
                end
            else
                if c.kind == "screen" then clickScreenCenter() else clickObj(c.obj) end
                count = count + 1
                winCount = winCount + 1
                if count % 30 == 0 then
                    tl("Spam #" .. count .. " | counter " .. counterText())
                    render()
                end
                if counter and winCount == 10 then
                    if counterText() == winText and ci < #cands and mode == "Auto" then
                        ci = ci + 1
                        tl("Counter diam -> target berikutnya: " .. candName(cands[ci]))
                        winCount, winText = 0, counterText()
                    end
                end
            end
            task.wait(0.03)   -- 33 klik/detik
        end
        tl("Spam done: " .. count .. " clicks | counter " .. c0 .. " -> " .. counterText())
        log("Spam done: " .. count .. " clicks")
        return true
    end

    local function spamMiniGameClick(duration)
        return spamLoop(duration, Fish.spamTarget)
    end

    local function onMarkerDetected(source)
        if markerDetected or not awaitMarker then return end
        markerDetected = true
        markerSource = source
        lastMarkerTime = tick()
        tl(source == "timeout" and ("Timeout " .. MARKER_TIMEOUT .. "s") or ("Marker detected via " .. source))
        log("Marker detected via: " .. source)
        if Fish.autoTrigger then
            local remotes = resolve()
            if remotes.MiniGame then
                task.spawn(function()
                    task.wait(Fish.markerDelay)   -- beri server waktu "menerima" marker
                    if Fish.postSpam then preSnapshot = guiSnapshot() end
                    miniFired = true
                    callRemote(remotes.MiniGame, "MiniGame", true)
                    tl("MiniGame fired (delay " .. Fish.markerDelay .. "s)")
                    log("Auto MiniGame fired (" .. source .. ")")
                end)
            end
        end
    end
    Fish.onMarker = onMarkerDetected

    local function nearChar(obj, maxDist)
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return false end
        local cur = obj
        while cur do
            if cur:IsA("BasePart") then return (cur.Position - root.Position).Magnitude < maxDist end
            if cur:IsA("Attachment") then return (cur.WorldPosition - root.Position).Magnitude < maxDist end
            cur = cur.Parent
        end
        return false
    end

    local function nameLooksLikeMarker(n)
        n = n:lower()
        return n:find("tanda") or n:find("marker") or n:find("seru") or n:find("exclaim") or n:find("notice")
    end

    -- lapis 1: server fire TandaSeruBersama balik ke client
    function Fish.setupMarkerListener()
        if markerListenerOn then return true end
        local r = resolve().TandaSeruBersama
        if not (r and r:IsA("RemoteEvent")) then return false end
        markerListenerOn = true
        r.OnClientEvent:Connect(function(...)
            lastMarkerTime = tick()
            onMarkerDetected("OnClientEvent")
        end)
        return true
    end

    -- lapis 2/3/4: workspace baru, karakter, teks "!" di GUI (loop hanya bekerja saat menunggu marker)
    function Fish.startWatchers()
        pcall(Fish.setupMarkerListener)
        if watchersOn then return end
        watchersOn = true

        pcall(function()
            workspace.DescendantAdded:Connect(function(obj)
                if not awaitMarker or markerDetected then return end
                pcall(function()
                    -- marker resmi: BillboardGui "TandaSeruOrang" - hanya yang milik karakter kita / sangat dekat
                    if obj.Name == "TandaSeruOrang" or obj.Name:find("TandaSeru") then
                        local ref = obj:IsA("BasePart") and obj or (obj.Adornee or obj.Parent)
                        local char = player.Character
                        local mine = char and (obj:IsDescendantOf(char) or (ref and ref:IsDescendantOf(char)))
                        if mine or (ref and nearChar(ref, 12)) then
                            onMarkerDetected("TandaSeruOrang BillboardGui")
                        else
                            tl("TandaSeruOrang bukan milikmu (diabaikan)")
                        end
                        return
                    end
                    if probeCount < 8 and (obj:IsA("BasePart") or obj:IsA("BillboardGui") or obj:IsA("SurfaceGui")) then
                        local ref = obj:IsA("BasePart") and obj or (obj.Adornee or obj.Parent)
                        if ref and nearChar(ref, 25) then
                            probeCount = probeCount + 1
                            tl("WS+ " .. obj.ClassName .. " '" .. obj.Name .. "'")
                        end
                    end
                    if not nameLooksLikeMarker(obj.Name) then return end
                    if obj:IsA("BasePart") then
                        if nearChar(obj, 20) then onMarkerDetected("Workspace scan: " .. obj.Name) end
                    elseif obj:IsA("BillboardGui") then
                        if nearChar(obj.Adornee or obj.Parent, 30) then
                            onMarkerDetected("Workspace GUI: " .. obj.Name)
                        end
                    end
                end)
            end)
        end)

        pcall(function()
            workspace.DescendantAdded:Connect(function(obj)
                if not inCycle or fishStatus ~= "reel" then return end
                pcall(function()
                    local n = (obj.Name .. (obj.Parent and obj.Parent.Name or "")):lower()
                    if (n:find("fish") or n:find("ikan")) and obj:IsA("BasePart") and nearChar(obj, 40) then
                        creditFish("Object: " .. obj.Name)
                    end
                end)
            end)
        end)

        task.spawn(function()
            task.wait(3)
            while true do
                task.wait(0.1)
                if awaitMarker and not markerDetected then
                    pcall(function()
                        local char = player.Character
                        if char then
                            for _, obj in ipairs(char:GetDescendants()) do
                                local visible = false
                                if obj:IsA("BillboardGui") then visible = obj.Enabled
                                elseif obj:IsA("ImageLabel") then visible = obj.Visible end
                                if visible and nameLooksLikeMarker(obj.Name) then
                                    onMarkerDetected("Char scan: " .. obj.Name)
                                    break
                                end
                            end
                        end
                    end)
                    pcall(function()
                        if markerDetected then return end
                        for _, obj in ipairs(playerGui:GetDescendants()) do
                            if obj:IsA("TextLabel") and obj.Visible and obj.Text == "!"
                                and not obj:FindFirstAncestor("RoutePanel")
                                and not obj:FindFirstAncestor("RouteIcon")
                                and not obj:FindFirstAncestor("RouteError") then
                                onMarkerDetected("GUI text '!'")
                                break
                            end
                        end
                    end)
                end
            end
        end)
    end

    -- tunggu marker (max MARKER_TIMEOUT); kalau timeout -> kirim TandaSeruBersama sendiri (cara lama) lalu paksa MiniGame
    local function waitForMarker(remotes)
        local t0 = tick()
        local baseGui = guiSnapshot()
        local nextProbe = tick() + 0.25
        while not markerDetected and tick() - t0 < MARKER_TIMEOUT do
            task.wait(0.05)
            if tick() >= nextProbe then
                nextProbe = tick() + 0.25
                -- diagnosa: catat GUI baru yang muncul selagi menunggu (bisa jadi marker aslinya)
                local cur = guiSnapshot()
                for obj in pairs(cur) do
                    if not baseGui[obj] then
                        baseGui[obj] = true
                        if probeCount < 8 then
                            probeCount = probeCount + 1
                            tl("GUI+ " .. obj.ClassName .. " '" .. guiText(obj) .. "'")
                        end
                    end
                end
            end
        end
        if not markerDetected then
            log("Marker timeout, force MiniGame")
            if remotes.TandaSeruBersama then
                local ta = (Fish.useSpyArgs and Fish.capturedTanda and Fish.capturedTanda.n > 0)
                    and Fish.capturedTanda or TANDA_DEFAULT
                Fish.selfFiring = true
                callRemote(remotes.TandaSeruBersama, "TandaSeruBersama", table.unpack(ta, 1, ta.n))
                Fish.selfFiring = false
            end
            onMarkerDetected("timeout")
        end
    end

    local function runInstant()
        local remotes = resolve()
        if not remotes.CastEvent then
            fishStatus = "idle"
            log("CastEvent belum ke-capture. Spy dulu + mancing manual 1x.")
            return false
        end
        local k = (Fish.mode == "Aggressive") and 0.5 or 1
        local cycleStart = tick()
        cycleT0 = cycleStart
        timeline = {}
        probeCount = 0
        preSnapshot = nil
        cycleCredited = false
        baseSnapshot = Fish.postSpam and guiSnapshot() or nil   -- HUD/hotbar yang sudah ada sebelum siklus
        tl("Start cycle")
        if not (Fish.useSpyArgs and Fish.capturedCast and Fish.capturedCast.n > 0) then
            tl("WARNING: spy args belum ke-capture (pakai default). Spy dulu.")
        end
        markerDetected = false     -- reset marker tiap siklus
        markerSource = "-"
        awaitMarker = false

        -- 0. GetKatalog (sekali saja per sesi)
        if remotes.GetKatalog and not katalogDone then
            katalogDone = true
            callRemote(remotes.GetKatalog, "GetKatalog")
            task.wait(0.1 * k)
        end

        -- 1. AmbilSemua
        callRemote(remotes.AmbilSemua, "AmbilSemua")
        task.wait(0.1 * k)

        -- 2. CastEvent(true)
        fishStatus = "cast1"
        callRemote(remotes.CastEvent, "CastEvent", true)
        tl("Cast(true) fired")
        render()
        task.wait(0.2 * k)

        -- 3. CastEvent(false, args...) lengkap
        fishStatus = "cast2"
        local args = generateCastArgs()
        lastCastArgs = fmtArgs(args)
        awaitMarker = Fish.autoTrigger   -- marker bisa datang cepat setelah cast
        callRemote(remotes.CastEvent, "CastEvent", table.unpack(args, 1, args.n))
        tl("Cast(false, " .. (args.n - 1) .. " args) fired" .. ((Fish.useSpyArgs and Fish.capturedCast) and " [spy]" or " [default]"))
        render()

        if Fish.autoTrigger then
            -- 4. AUTO-TRIGGER: tunggu marker real-time (OnClientEvent / watcher), timeout 8s
            fishStatus = "waiting_marker"
            markerWaitStart = tick()
            miniFired = false
            local fishBefore = fishCaught   -- baseline untuk cek hasil
            tl("Waiting marker (max " .. MARKER_TIMEOUT .. "s)")
            render()
            waitForMarker(remotes)

            -- 5. MiniGame ditembak onMarkerDetected (setelah markerDelay); tunggu sampai benar-benar terkirim
            local tw = tick()
            while not miniFired and tick() - tw < (Fish.markerDelay + 1) do task.wait(0.02) end
            fishStatus = "reel"
            markerWaitStart = nil
            awaitMarker = false
            if Fish.stopAnimOn then stopAllAnimations() end
            render()
            if Fish.postSpam then
                spamMiniGameClick(Fish.spamDuration)
            else
                -- tunggu minigame selesai; kalau cutscene aktif (dan skip ON) langsung lanjut
                local tc = tick()
                while tick() - tc < 1.2 * k do
                    if Fish.skipCutscene and cutsceneActive then break end
                    task.wait(Fish.aggSkip and 0.03 or 0.1)
                end
            end

            -- cek hasil (hanya bisa kalau FishCatchBroadcast terpasang); kalau tidak ada perubahan -> retry max 2x
            if broadcastSeen then
                local retries = 0
                while true do
                    local t1 = tick()
                    while fishCaught <= fishBefore and tick() - t1 < 1 do task.wait(0.05) end
                    if fishCaught > fishBefore then
                        tl("Check result: Fish +" .. (fishCaught - fishBefore))
                        break
                    end
                    tl("Check result: no change")
                    if retries >= 2 or not remotes.MiniGame then break end
                    retries = retries + 1
                    tl("Retry " .. retries .. "/2: MiniGame(true) lagi")
                    callRemote(remotes.MiniGame, "MiniGame", true)
                    if Fish.postSpam then spamMiniGameClick(1) end
                end
            else
                tl("Check result: tidak bisa (FishCatchBroadcast belum pernah fired) -> counter manual")
            end
        else
            -- mode lama (Auto Trigger OFF)
            task.wait(0.5 * k)   -- tunggu server proses

            -- 4. TandaSeruBersama
            if remotes.TandaSeruBersama then
                local ta = tandaArgs()
                Fish.selfFiring = true
                callRemote(remotes.TandaSeruBersama, "TandaSeruBersama", table.unpack(ta, 1, ta.n))
                Fish.selfFiring = false
                lastMarkerTime = tick()
                task.wait(0.2 * k)
            end

            -- 5. MiniGame(true)
            fishStatus = "reel"
            if remotes.MiniGame then
                callRemote(remotes.MiniGame, "MiniGame", true)
            end
            if Fish.stopAnimOn then stopAllAnimations() end
            render()
            task.wait(1.0 * k)   -- tunggu minigame selesai
        end

        -- 6. AmbilSemua lagi
        callRemote(remotes.AmbilSemua, "AmbilSemua")

        -- counter: sumber pertama yang mendeteksi (Broadcast / Object) menang; kalau tidak ada -> manual (+1 per siklus)
        creditFish("Manual")
        fishStatus = "done"
        lastCycleTime = tick() - cycleStart
        tl("Instant done (Fish: " .. fishCaught .. ")")
        log("Instant done")
        return true
    end

    -- ---- tes per step: cari tahu step mana yang bikin tali terlempar ----
    function Fish.step1()
        local r = resolve()
        if not r.CastEvent then render() return false end
        fishStatus = "cast1"
        local ok = callRemote(r.CastEvent, "CastEvent", true)
        log("Step 1 Cast(true) -> " .. (ok and "terkirim" or "gagal"))
        return ok
    end

    function Fish.step2()
        local r = resolve()
        if not r.CastEvent then render() return false end
        fishStatus = "cast2"
        local args = generateCastArgs()
        lastCastArgs = fmtArgs(args)
        local ok = callRemote(r.CastEvent, "CastEvent", table.unpack(args, 1, args.n))
        log("Step 2 Cast(" .. args.n .. " args) -> " .. (ok and "terkirim" or "gagal") .. ": " .. lastCastArgs)
        return ok
    end

    function Fish.step3()
        local r = resolve()
        if not r.CastEvent then render() return false end
        if not r.MiniGame then
            log("Step 3: MiniGame belum ke-capture")
            return false
        end
        fishStatus = "reel"
        local ok = callRemote(r.MiniGame, "MiniGame", true)
        if Fish.stopAnimOn then stopAllAnimations() end
        log("Step 3 MiniGame(true) -> " .. (ok and "terkirim" or "gagal"))
        return ok
    end

    function Fish.instant()
        if fishBusy then return false end
        if not ready() then
            fishStatus = "idle"
            render()
            return false
        end
        fishBusy = true
        inCycle = true
        local ok, res = pcall(runInstant)
        inCycle = false
        fishBusy = false
        if not ok then
            fishStatus = "idle"
            log("err: " .. tostring(res))
            return false
        end
        return res
    end

    -- coba beberapa variasi argumen CastEvent; perhatikan sendiri mana yang bikin tali terlempar
    function Fish.testCastArgs()
        if fishBusy then return false end
        fishBusy = true
        local ok, err = pcall(function()
            local remotes = resolve()
            if not remotes.CastEvent then
                render()
                return
            end
            local variants = {}
            if Fish.capturedCast then
                table.insert(variants, { "spy captured", Fish.capturedCast })
            end
            table.insert(variants, { "spy log", DEFAULT_CAST })
            local r15 = table.pack(false)
            for i = 2, 15 do r15[i] = math.random() end
            r15.n = 15
            table.insert(variants, { "random 15", r15 })
            local r5 = table.pack(false, math.random(), math.random(), math.random(), math.random())
            table.insert(variants, { "random 5", r5 })
            table.insert(variants, { "(false)", table.pack(false) })
            table.insert(variants, { "(false, 20)", table.pack(false, 20) })
            for i, v in ipairs(variants) do
                fishStatus = "casting"
                sendCast(remotes.CastEvent, v[2], 0)
                log("Variant " .. i .. "/" .. #variants .. " [" .. v[1] .. "] " .. v[2].n .. " args - tali terlempar?")
                task.wait(3)
            end
            fishStatus = "idle"
            log("Test cast selesai")
        end)
        fishBusy = false
        if not ok then log("err: " .. tostring(err)) end
        return ok
    end

    function Fish.setupListener()
        if listenerOn then return true end
        local broadcast = ReplicatedStorage:FindFirstChild("FishCatchBroadcast")
        if not broadcast then
            pcall(function()
                for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
                    if d.Name == "FishCatchBroadcast" and d:IsA("RemoteEvent") then
                        broadcast = d
                        return
                    end
                end
            end)
        end
        if not broadcast then return false end
        listenerOn = true
        broadcast.OnClientEvent:Connect(function(...)
            broadcastSeen = true
            if inCycle then
                creditFish("Broadcast")
            else
                fishCaught = fishCaught + 1   -- mancing manual di luar siklus auto
            end
            fishStatus = "success"
            if Fish.stopAnimOn then stopAllAnimations() end
            render()
        end)
        return true
    end

    -- watchdog: kalau status nyangkut di waiting_marker > 4 detik (di atas timeout marker 3s), tembak MiniGame (tidak dobel dengan runInstant)
    function Fish.watchdogTick()
        if Fish.autoTrigger and fishStatus == "waiting_marker" and markerWaitStart
            and tick() - markerWaitStart > 4 and not miniFired then
            local remotes = resolve()
            if remotes.MiniGame then
                miniFired = true
                callRemote(remotes.MiniGame, "MiniGame", true)
                lastMarkerTime = tick()
                log("Auto-trigger MiniGame (watchdog)")
            end
        end
    end

    -- 1 siklus: CastEvent(true) + CastEvent(false, args) + tunggu 0.3s + MiniGame(true), log tiap step
    function Fish.testAutoTrigger()
        if fishBusy then return false end
        if not ready() then
            fishStatus = "idle"
            render()
            return false
        end
        fishBusy = true
        local ok, err = pcall(function()
            local r = resolve()
            fishStatus = "cast1"
            callRemote(r.CastEvent, "CastEvent", true)
            log("Test AT 1/4: CastEvent(true)")
            task.wait(0.2)

            fishStatus = "cast2"
            local args = generateCastArgs()
            lastCastArgs = fmtArgs(args)
            markerDetected = false
            markerSource = "-"
            awaitMarker = true
            callRemote(r.CastEvent, "CastEvent", table.unpack(args, 1, args.n))
            log("Test AT 2/4: CastEvent(false, " .. (args.n - 1) .. " args)")

            fishStatus = "waiting_marker"
            miniFired = false
            log("Test AT 3/4: tunggu marker (max 3s)")
            waitForMarker(r)
            fishStatus = "reel"
            awaitMarker = false
            if Fish.stopAnimOn then stopAllAnimations() end
            log("Test AT 4/4: marker via " .. markerSource .. " -> MiniGame ditembak")
            task.wait(1.2)
            fishStatus = "done"
            log("Test Auto Trigger selesai")
        end)
        fishBusy = false
        if not ok then
            fishStatus = "idle"
            log("err: " .. tostring(err))
        end
        return ok
    end

    -- spam manual 3 detik: dipakai saat MiniGame sedang aktif, memakai target terpilih (Auto/Quick/Berhenti/Screen)
    function Fish.testSpam3()
        if fishBusy then return false end
        fishBusy = true
        local ok, err = pcall(function()
            cycleT0 = tick()
            timeline = {}
            baseSnapshot = nil
            tl("Test Spam 3s, target: " .. Fish.spamTarget)
            log("Test Spam 3s mulai (" .. Fish.spamTarget .. ")")
            spamLoop(3, Fish.spamTarget)
        end)
        fishBusy = false
        if not ok then log("err: " .. tostring(err)) end
        return ok
    end

    function Fish.scan()
        scanRemotes(true)
        local on = Fish.setupListener()
        Fish.startWatchers()
        log("Scan selesai | broadcast: " .. (on and "aktif" or "tidak ada (counter manual)"))
    end

    function Fish.resetCounter()
        fishCaught = 0
        log("counter reset")
    end

    Fish.ready = ready
    Fish.find = scanRemotes
    Fish.render = render
    Fish.log = log
    Fish.stopAnims = stopAllAnimations
end

-- ====== REMOTE SPY ======
-- Log semua FireServer/InvokeServer yang dikirim client (pakai 1 hook __namecall, fallback hookfunction).
-- Cara pakai: Start Spy -> mancing manual 1x -> Stop Spy -> lihat/screenshot hasilnya.
-- (dibungkus do...end + tabel Spy: batas 200 local per fungsi di script ini hampir penuh)
local Spy = {}
do
    local SPY_PAUSE_AUTOFISH = true   -- auto-fish di-pause sampai remote yang benar diketahui
    local spyLog = {}
    local spyCounts = {}
    local spyActive = false
    local spyBusy = false
    local spyRenderQueued = false
    local spyHook = nil               -- closure __namecall kita
    local spyOldNamecall = nil
    local spyFnHooks = nil            -- fallback hookfunction

    local function spyRender()
        local lines = {}
        local from = math.max(1, #spyLog - 11)
        for i = from, #spyLog do table.insert(lines, spyLog[i]) end
        if #lines == 0 then lines = { "[spy] log kosong" } end
        SpyUI.setText(table.concat(lines, "\n"))
    end

    local function logSpy(msg)
        local last = spyLog[#spyLog]
        -- gabungkan baris identik berurutan -> "(xN)"
        local base = last and last:gsub(" %(x%d+%)$", "")
        if base == msg then
            local n = tonumber(last:match("%(x(%d+)%)$")) or 1
            spyLog[#spyLog] = msg .. " (x" .. (n + 1) .. ")"
        else
            table.insert(spyLog, msg)
            if #spyLog > 50 then table.remove(spyLog, 1) end
        end
        if not spyRenderQueued then
            spyRenderQueued = true
            task.defer(function()
                spyRenderQueued = false
                pcall(spyRender)
            end)
        end
    end

    local function spyFmt(v, depth)
        local t = typeof(v)
        if t == "string" then
            if #v > 40 then v = string.sub(v, 1, 40) .. "..." end
            return '"' .. v .. '"'
        elseif t == "Instance" then
            return "<" .. v.ClassName .. ":" .. v.Name .. ">"
        elseif t == "table" then
            if depth >= 1 then return "{...}" end
            local parts, n = {}, 0
            for k, x in pairs(v) do
                n = n + 1
                if n > 4 then
                    table.insert(parts, "...")
                    break
                end
                table.insert(parts, tostring(k) .. "=" .. spyFmt(x, depth + 1))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
        return tostring(v)
    end

    local lastSpyT = nil

    local function spyRecord(method, remote, ...)
        local n = select("#", ...)
        local parts = {}
        for i = 1, math.min(n, 20) do
            parts[i] = spyFmt((select(i, ...)), 0)
        end
        if n > 20 then table.insert(parts, "...") end
        local argStr = table.concat(parts, ", ")
        local now = tick()
        local dt = lastSpyT and (now - lastSpyT) or 0
        lastSpyT = now
        -- observasi saja: tandai remote terkait kostum (nama + format argumen), tanpa aksi
        local lname = string.lower(remote.Name)
        local tag = ""
        for _, kw in ipairs({ "skin", "title", "equip", "inventory", "wear" }) do
            if string.find(lname, kw, 1, true) then
                tag = "[NET-OBSERVE] "
                break
            end
        end
        logSpy(tag .. string.format("+%.2fs ", dt) .. "[" .. method .. "] " .. remote.Name .. "(" .. argStr .. ")")
        local key = method .. " " .. remote.Name
        local c = spyCounts[key]
        if not c then
            c = { count = 0, args = argStr }
            spyCounts[key] = c
        end
        c.count = c.count + 1
        c.args = argStr
        c.variants = c.variants or {}
        if #c.variants < 3 then
            local seen = false
            for _, v in ipairs(c.variants) do
                if v == argStr then seen = true end
            end
            if not seen then table.insert(c.variants, argStr) end
        end

        -- simpan objek remote asli (bukan scan by name) untuk instant fish
        local rname = remote.Name
        if (rname == "CastEvent" or rname == "MiniGame" or rname == "AmbilSemua" or rname == "TandaSeruBersama"
            or rname == "GetKatalog")
            and Fish.spyRefs[rname] ~= remote then
            Fish.spyRefs[rname] = remote
            logSpy("[spy] cached remote: " .. rname .. " (" .. remote.ClassName .. ")")
        end

        -- marker: game sendiri menembak TandaSeruBersama (bukan kita) -> deteksi real-time
        if method == "FireServer" and rname == "TandaSeruBersama" and not Fish.selfFiring and Fish.onMarker then
            Fish.onMarker("spy hook (game FireServer)")
        end

        -- simpan argumen asli untuk instant fish (dipakai Fish.instant)
        if method == "FireServer" and remote.Name == "CastEvent" then
            local packed = table.pack(...)
            if packed[1] == false and packed.n > 2 then
                Fish.capturedCast = packed
                logSpy("[spy] captured CastEvent args: " .. packed.n .. " values")
            end
        elseif method == "FireServer" and remote.Name == "TandaSeruBersama" then
            Fish.capturedTanda = table.pack(...)
            logSpy("[spy] captured TandaSeruBersama args: " .. Fish.capturedTanda.n .. " values")
        end
    end

    local function spyInstallNamecall()
        local mt = getrawmetatable(game)
        local old = mt.__namecall
        local function setRO(v)
            if setreadonly then setreadonly(mt, v)
            elseif make_writeable and not v then make_writeable(mt)
            elseif make_readonly and v then make_readonly(mt) end
        end
        setRO(false)
        spyOldNamecall = old
        spyHook = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if spyActive and not spyBusy and method then
                local m = string.lower(method)
                if m == "fireserver" or m == "invokeserver" then
                    spyBusy = true
                    pcall(function(...)
                        if typeof(self) == "Instance" and string.find(self.ClassName, "Remote", 1, true) then
                            spyRecord(m == "fireserver" and "FireServer" or "InvokeServer", self, ...)
                        end
                    end, ...)
                    spyBusy = false
                    if setnamecallmethod then setnamecallmethod(method) end
                end
            end
            return old(self, ...)
        end)
        mt.__namecall = spyHook
        setRO(true)
    end

    local function spyInstallHookFunction()
        local re = Instance.new("RemoteEvent")
        local rf = Instance.new("RemoteFunction")
        local oldFS, oldIS
        local fs, isf = re.FireServer, rf.InvokeServer
        oldFS = hookfunction(fs, newcclosure(function(self, ...)
            if spyActive and not spyBusy then
                spyBusy = true
                pcall(spyRecord, "FireServer", self, ...)
                spyBusy = false
            end
            return oldFS(self, ...)
        end))
        oldIS = hookfunction(isf, newcclosure(function(self, ...)
            if spyActive and not spyBusy then
                spyBusy = true
                pcall(spyRecord, "InvokeServer", self, ...)
                spyBusy = false
            end
            return oldIS(self, ...)
        end))
        spyFnHooks = { fs = fs, isf = isf }
        re:Destroy()
        rf:Destroy()
    end

    local function startSpy()
        if spyActive then return end
        local how = nil
        if getrawmetatable and getnamecallmethod and newcclosure then
            if pcall(spyInstallNamecall) then how = "namecall" end
        end
        if not how and hookfunction and newcclosure then
            if pcall(spyInstallHookFunction) then how = "hookfunction" end
        end
        if not how then
            logSpy("[spy] executor tidak support hook")
            pcall(spyRender)
            return
        end
        spyActive = true
        Fish.spyActive = true
        logSpy("[spy] Start (" .. how .. ") - mancing manual 1x")
    end

    local function stopSpy()
        if not spyActive then
            logSpy("[spy] belum aktif")
            return
        end
        spyActive = false
        Fish.spyActive = false
        -- restore hook
        if spyHook then
            pcall(function()
                local mt = getrawmetatable(game)
                if mt.__namecall == spyHook then   -- kalau script lain sudah hook di atas kita, biarkan (pass-through)
                    if setreadonly then setreadonly(mt, false)
                    elseif make_writeable then make_writeable(mt) end
                    mt.__namecall = spyOldNamecall
                    if setreadonly then setreadonly(mt, true)
                    elseif make_readonly then make_readonly(mt) end
                    spyHook = nil
                end
            end)
        end
        if spyFnHooks and restorefunction then
            pcall(restorefunction, spyFnHooks.fs)
            pcall(restorefunction, spyFnHooks.isf)
            spyFnHooks = nil
        end
        -- ringkasan: remote unik + jumlah panggilan
        local list = {}
        local total = 0
        for key, c in pairs(spyCounts) do
            table.insert(list, { key = key, c = c })
            total = total + c.count
        end
        table.sort(list, function(a, b) return a.c.count > b.c.count end)
        local lines = { "[spy] Stop - " .. total .. " panggilan, " .. #list .. " remote unik" }
        for i, e in ipairs(list) do
            if i > 10 then
                table.insert(lines, "... +" .. (#list - 10) .. " lagi")
                break
            end
            local vs = e.c.variants and table.concat(e.c.variants, " | ") or e.c.args
            if #vs > 110 then vs = string.sub(vs, 1, 110) .. "..." end
            table.insert(lines, e.key .. " x" .. e.c.count .. " (" .. vs .. ")")
        end
        for _, l in ipairs(lines) do table.insert(spyLog, l) end
        while #spyLog > 50 do table.remove(spyLog, 1) end
        SpyUI.setText(table.concat(lines, "\n"))
    end

    local function clearSpyLog()
        spyLog = {}
        spyCounts = {}
        SpyUI.setText("[spy] log dibersihkan")
    end

    Spy.pause = SPY_PAUSE_AUTOFISH
    Spy.start = startSpy
    Spy.stop = stopSpy
    Spy.clear = clearSpyLog
end

-- ====== BACKGROUND LOOPS ======
task.spawn(function()
    while true do
        task.wait(ANTI_AFK_INTERVAL)
        if USE_ANTI_AFK then antiAFK() end
    end
end)

task.spawn(function()
    while true do
        task.wait(FISH_DELAY)
        if USE_AUTO_FISH then autoFish() end
    end
end)

-- ====== PLAY CP ======
local function playCP(startFromPending, startFromIndex)
    stopFlag = false
    loopCount = 0

    print("[RouteTools] === PLAY CP START ===")
    print("[RouteTools] Reset mode: " .. RESET_MODE)

    if startFromPending and #pendingCPs > 0 then
        local list = {}
        for _, v in ipairs(pendingCPs) do table.insert(list, v) end
        for _, idx in ipairs(list) do
            if stopFlag then break end
            local cp = CP_LIST[idx]
            if cp then
                currentIndex = idx
                highlightCP(idx)
                teleport(cp)
                task.wait(0.2)
                walkMuter()
                task.wait(TP_DELAY)
                removePending(idx)
            end
        end
        cpPlaying = false
        return
    end

    local startIdx = startFromIndex or 1
    local firstLoop = true

    while not stopFlag do
        loopCount = loopCount + 1
        if loopLabel then
            loopLabel.Text = "Loop: #" .. loopCount
        end

        -- Tentukan reset
        local shouldReset = false
        if RESET_MODE == "Always" then
            shouldReset = true
        elseif RESET_MODE == "Once" then
            shouldReset = firstLoop
        elseif RESET_MODE == "Never" then
            shouldReset = false
        end

        if shouldReset then
            teleport(RESET_POS)
            task.wait(0.3)
            walkMuter()
            task.wait(RESET_DELAY)
        end

        firstLoop = false

        -- Susun list
        local processList = {}
        if AUTO_PENDING_RETRY and #pendingCPs > 0 then
            for _, v in ipairs(pendingCPs) do
                table.insert(processList, v)
            end
        end
        for i = math.max(1, startIdx), #CP_LIST do
            local already = false
            for _, v in ipairs(processList) do
                if v == i then already = true break end
            end
            if not already then
                table.insert(processList, i)
            end
        end

        for _, idx in ipairs(processList) do
            if stopFlag then break end
            local cp = CP_LIST[idx]
            currentIndex = idx
            highlightCP(idx)

            teleport(cp)
            task.wait(0.2)
            walkMuter()
            task.wait(TP_DELAY)
        end

        startIdx = 1

        if not USE_LOOP then break end

        if not stopFlag and USE_LOOP then
            local t0 = tick()
            while tick() - t0 < LOOP_DELAY and not stopFlag do
                task.wait(0.1)
            end
        end
    end

    cpPlaying = false
end

-- ====== MINIMIZE ICON ======
local guiIcon = Instance.new("ScreenGui")
guiIcon.Name = "RouteIcon"
guiIcon.ResetOnSpawn = false
guiIcon.IgnoreGuiInset = true
guiIcon.DisplayOrder = 2147483647
guiIcon.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
guiIcon.Parent = playerGui

local icon = Instance.new("TextButton")
icon.Name = "Icon"
icon.Size = UDim2.new(0, 40, 0, 40)
icon.Position = UDim2.new(1, -60, 0, 20)
icon.BackgroundColor3 = Color3.fromRGB(50, 160, 70)
icon.Text = "RT"
icon.TextColor3 = Color3.new(1, 1, 1)
icon.Font = Enum.Font.GothamBold
icon.TextSize = 16
icon.ZIndex = 1000
icon.Visible = false
icon.Parent = guiIcon

local iconCorner = Instance.new("UICorner")
iconCorner.CornerRadius = UDim.new(1, 0)
iconCorner.Parent = icon

local iconStroke = Instance.new("UIStroke", icon)
iconStroke.Color = Color3.new(1, 1, 1)
iconStroke.Thickness = 2

-- ====== DRAG SYSTEM (header + icon) ======
local function pointInRect(pos, absPos, absSize)
    return pos.X >= absPos.X
       and pos.X <= absPos.X + absSize.X
       and pos.Y >= absPos.Y
       and pos.Y <= absPos.Y + absSize.Y
end

local dragTarget = nil
local dragStart = Vector2.new()
local dragStartPos = nil
local iconDragMoved = false

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    local pos = input.Position

    if panel.Visible and pointInRect(pos, header.AbsolutePosition, header.AbsoluteSize) then
        local inMin = pointInRect(pos, minBtn.AbsolutePosition, minBtn.AbsoluteSize)
        local inClose = pointInRect(pos, closeBtn.AbsolutePosition, closeBtn.AbsoluteSize)
        if not inMin and not inClose then
            dragTarget = "panel"
            dragStart = pos
            dragStartPos = panel.Position
            return
        end
    end

    if icon.Visible and pointInRect(pos, icon.AbsolutePosition, icon.AbsoluteSize) then
        dragTarget = "icon"
        dragStart = pos
        dragStartPos = icon.Position
        iconDragMoved = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not dragTarget then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    local delta = input.Position - dragStart

    if dragTarget == "panel" then
        panel.Position = UDim2.new(
            dragStartPos.X.Scale, dragStartPos.X.Offset + delta.X,
            dragStartPos.Y.Scale, dragStartPos.Y.Offset + delta.Y
        )
    elseif dragTarget == "icon" then
        icon.Position = UDim2.new(
            dragStartPos.X.Scale, dragStartPos.X.Offset + delta.X,
            dragStartPos.Y.Scale, dragStartPos.Y.Offset + delta.Y
        )
        if delta.Magnitude > 3 then
            iconDragMoved = true
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    dragTarget = nil
end)

-- ====== BACKGROUND UPDATE LOOPS ======
task.spawn(function()
    while gui.Parent do
        local root = getRoot()
        if root then
            local p = root.Position
            posLabel.Text = string.format("X:%.0f Y:%.0f Z:%.0f", p.X, p.Y, p.Z)
        else
            posLabel.Text = "X:-- Y:-- Z:--"
        end
        task.wait(0.3)
    end
end)

task.spawn(function()
    while gui.Parent do
        local ok, cpServer, statName, source = pcall(getServerCheckpoint)
        if ok and cpServer then
            cachedServerCP = cpServer
            debugLabel.Text = "CP Server: " .. cpServer .. "\nStat: " .. tostring(statName)
        else
            cachedServerCP = nil
            debugLabel.Text = "CP Server: --"
        end
        task.wait(2)
    end
end)

-- ====== MINIMIZE / RESTORE ======
local isMinimized = false
local lastPanelPosition = panel.Position

minBtn.MouseButton1Click:Connect(safe(function()
    isMinimized = true
    lastPanelPosition = panel.Position
    panel.Visible = false
    icon.Visible = true
end))

icon.MouseButton1Click:Connect(safe(function()
    if iconDragMoved then
        iconDragMoved = false
        return
    end
    isMinimized = false
    panel.Position = lastPanelPosition
    panel.Visible = true
    icon.Visible = false
end))

-- ====== LOGIC TOMBOL: EDIT CP LIVE ======
-- teks tombol berubah sebentar lalu kembali (tanpa blok handler)
function CPStore.flash(btn, text, normal, color, normalColor)
    btn.Text = text
    if color then btn.BackgroundColor3 = color end
    task.delay(1.5, function()
        pcall(function()
            btn.Text = normal
            if normalColor then btn.BackgroundColor3 = normalColor end
        end)
    end)
end

-- CP terdekat dari posisi sekarang
function CPStore.findNearest()
    local root = getRoot()
    if not root then return nil end
    local nearest, nearestDist = nil, math.huge
    for i, cp in ipairs(CP_LIST) do
        local d = (cp - root.Position).Magnitude
        if d < nearestDist then nearest, nearestDist = i, d end
    end
    return nearest, nearestDist
end

CPStore.updateBtn.MouseButton1Click:Connect(safe(function()
    local root = getRoot()
    if not root then
        CPStore.flash(CPStore.updateBtn, "No Character!", "Update CP (Current Pos)")
        return
    end
    -- < 20 studs dari sebuah CP -> CP terdekat itu; selain itu pakai currentIndex
    local nearest, dist = CPStore.findNearest()
    local idx = (nearest and dist < 20) and nearest or currentIndex
    if not CP_LIST[idx] then return end
    -- teleport() menambah TELEPORT_OFFSET, jadi simpan posisi dikurangi offset supaya mendarat di titik yang sama
    local ok = pcall(function() CP_LIST[idx] = root.Position - TELEPORT_OFFSET end)
    if not ok then return end
    CPStore.updateInfo()
    CPStore.flash(CPStore.updateBtn, "CP " .. idx .. " Updated (dist " .. math.floor(dist or 0) .. ")",
        "Update CP (Current Pos)", Color3.fromRGB(50, 160, 70), Color3.fromRGB(200, 130, 30))
end))

CPStore.saveBtn.MouseButton1Click:Connect(safe(function()
    local ok = CPStore.save()
    CPStore.flash(CPStore.saveBtn, ok and "Saved!" or "Save Failed", "Save CPs to File")
end))

-- reset ke koordinat bawaan script (in-memory); file tersimpan tidak disentuh
CPStore.resetBtn.MouseButton1Click:Connect(safe(function()
    CPStore.reset()
    CPStore.updateInfo()
    CPStore.flash(CPStore.resetBtn, "Reset Done", "Reset CPs to Default")
end))

CPStore.deleteBtn.MouseButton1Click:Connect(safe(function()
    local deleted = false
    pcall(function()
        if delfile and isfile and isfile(CPStore.file) then
            delfile(CPStore.file)
            deleted = true
        end
    end)
    CPStore.flash(CPStore.deleteBtn, deleted and "Deleted!" or "No File", "Delete Saved CPs")
end))

CPStore.updateInfo()

-- ====== LOGIC TOMBOL ======
for i, b in ipairs(cpButtons) do
    b.MouseButton1Click:Connect(safe(function()
        currentIndex = i
        teleport(CP_LIST[i])
        highlightCP(i)
    end))
end

closeBtn.MouseButton1Click:Connect(safe(function()
    stopFlag = true
    gui:Destroy()
    guiIcon:Destroy()
end))

playCpBtn.MouseButton1Click:Connect(safe(function()
    if cpPlaying then
        stopFlag = true
        cpPlaying = false
        playCpBtn.Text = "Play CP"
        return
    end

    local startFrom = 1
    if AUTO_START and cachedServerCP then
        startFrom = cachedServerCP + 1
        if startFrom > #CP_LIST then startFrom = 1 end
    else
        startFrom = currentIndex or 1
    end

    cpPlaying = true
    playCpBtn.Text = "Stop CP"
    task.spawn(function()
        playCP(false, startFrom)
        if not stopFlag then
            playCpBtn.Text = "Play CP"
        end
        cpPlaying = false
    end)
end))

autoStartBtn.MouseButton1Click:Connect(safe(function()
    AUTO_START = not AUTO_START
    if AUTO_START then
        autoStartBtn.Text = "Auto-Start: ON"
        autoStartBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 70)
    else
        autoStartBtn.Text = "Auto-Start: OFF"
        autoStartBtn.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
    end
end))

resetModeBtn.MouseButton1Click:Connect(safe(function()
    if RESET_MODE == "Never" then
        RESET_MODE = "Once"
        resetModeBtn.Text = "Reset: Once"
        resetModeBtn.BackgroundColor3 = Color3.fromRGB(200, 130, 30)
    elseif RESET_MODE == "Once" then
        RESET_MODE = "Always"
        resetModeBtn.Text = "Reset: Always"
        resetModeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    else
        RESET_MODE = "Never"
        resetModeBtn.Text = "Reset: Never"
        resetModeBtn.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
    end
end))

tpResetBtn.MouseButton1Click:Connect(safe(function()
    teleport(RESET_POS)
    tpResetBtn.Text = "Teleported!"
    task.wait(1)
    tpResetBtn.Text = "Teleport Reset"
end))

loopBtn.MouseButton1Click:Connect(safe(function()
    USE_LOOP = not USE_LOOP
    if USE_LOOP then
        loopBtn.Text = "Loop: ON"
        loopBtn.BackgroundColor3 = Color3.fromRGB(150, 100, 200)
        loopLabel.Text = "Loop: ON"
    else
        loopBtn.Text = "Loop: OFF"
        loopBtn.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
        loopLabel.Text = "Loop: OFF"
    end
end))

resumeBtn.MouseButton1Click:Connect(safe(function()
    if cpPlaying then
        stopFlag = true
        task.wait(0.3)
    end
    if #pendingCPs == 0 then
        resumeBtn.Text = "Tidak ada pending"
        task.wait(1)
        resumeBtn.Text = "Resume Pending"
        return
    end
    cpPlaying = true
    resumeBtn.Text = "Resume..."
    task.spawn(function()
        playCP(true)
        resumeBtn.Text = "Resume Pending"
        cpPlaying = false
    end)
end))

addPendingBtn.MouseButton1Click:Connect(safe(function()
    addPending(currentIndex)
    addPendingBtn.Text = "Pending +CP" .. currentIndex
    task.wait(1.2)
    addPendingBtn.Text = "Tandai Pending"
end))

clearPendingBtn.MouseButton1Click:Connect(safe(function()
    pendingCPs = {}
    updatePendingLabel()
    clearPendingBtn.Text = "Cleared!"
    task.wait(1)
    clearPendingBtn.Text = "Clear Pending"
end))

scanBtn.MouseButton1Click:Connect(safe(function()
    local cpServer, statName, source = getServerCheckpoint()
    if cpServer then
        scanBtn.Text = "CP " .. cpServer .. " (" .. tostring(statName) .. ")"
    else
        scanBtn.Text = "Tidak ketemu"
    end
    task.wait(2)
    scanBtn.Text = "Scan CP Server"
end))

antiAfkBtn.MouseButton1Click:Connect(safe(function()
    USE_ANTI_AFK = not USE_ANTI_AFK
    if USE_ANTI_AFK then
        antiAfkBtn.Text = "Anti-AFK: ON"
        antiAfkBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 70)
    else
        antiAfkBtn.Text = "Anti-AFK: OFF"
        antiAfkBtn.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
    end
end))

autoFishBtn.MouseButton1Click:Connect(safe(function()
    USE_AUTO_FISH = not USE_AUTO_FISH
    if USE_AUTO_FISH then
        autoFishBtn.Text = "Auto Fish: ON"
        autoFishBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 70)
    else
        autoFishBtn.Text = "Auto Fish: OFF"
        autoFishBtn.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
    end
end))

local tpDelayOptions = {0.2, 0.5, 1.0, 2.0}
local tpDelayIdx = 2
tpDelayBtn.MouseButton1Click:Connect(safe(function()
    tpDelayIdx = tpDelayIdx % #tpDelayOptions + 1
    TP_DELAY = tpDelayOptions[tpDelayIdx]
    tpDelayBtn.Text = "TP Delay: " .. TP_DELAY .. "s"
end))

local walkRadiusOptions = {4, 6, 8, 10}
local walkRadiusIdx = 2
walkRadiusBtn.MouseButton1Click:Connect(safe(function()
    walkRadiusIdx = walkRadiusIdx % #walkRadiusOptions + 1
    WALK_RADIUS = walkRadiusOptions[walkRadiusIdx]
    walkRadiusBtn.Text = "Walk Radius: " .. WALK_RADIUS
end))

local walkMoveOptions = {0.05, 0.08, 0.12}
local walkMoveIdx = 2
walkSpeedBtn.MouseButton1Click:Connect(safe(function()
    walkMoveIdx = walkMoveIdx % #walkMoveOptions + 1
    WALK_MOVE_TIME = walkMoveOptions[walkMoveIdx]
    walkSpeedBtn.Text = "Walk Move: " .. WALK_MOVE_TIME .. "s"
end))

tpNextBtn.MouseButton1Click:Connect(safe(function()
    currentIndex = math.min(currentIndex + 1, #CP_LIST)
    teleport(CP_LIST[currentIndex])
    highlightCP(currentIndex)
end))

tpPrevBtn.MouseButton1Click:Connect(safe(function()
    currentIndex = math.max(currentIndex - 1, 1)
    teleport(CP_LIST[currentIndex])
    highlightCP(currentIndex)
end))

-- Aktifkan tab pertama (Route) saat script pertama jalan
setActiveTab(1)

-- ====== LOGIC TOMBOL: REMOTE SPY ======
SpyUI.start.MouseButton1Click:Connect(safe(function()
    local ok, err = pcall(Spy.start)
    if not ok then SpyUI.setText("[spy] err: " .. tostring(err)) end
end))

SpyUI.stop.MouseButton1Click:Connect(safe(function()
    local ok, err = pcall(Spy.stop)
    if not ok then SpyUI.setText("[spy] err: " .. tostring(err)) end
end))

SpyUI.clear.MouseButton1Click:Connect(safe(function()
    pcall(Spy.clear)
end))

-- Auto Fish hanya boleh ON kalau CastEvent sudah ada (defer = jalan setelah handler toggle lama)
autoFishBtn.MouseButton1Click:Connect(safe(function()
    task.defer(function()
        if USE_AUTO_FISH and not Fish.ready() then
            USE_AUTO_FISH = false
            Fish.refuseT = tick()
            autoFishBtn.Text = "Auto Fish: OFF"
            autoFishBtn.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
            Fish.live = true
            pcall(Fish.render)
        end
    end)
end))

-- ====== BACKGROUND LOOP: INSTANT FISH (setelah panel jadi) ======
task.spawn(function()
    task.wait(3)
    pcall(Fish.setupListener)
    pcall(Fish.find)
    pcall(Fish.startWatchers)
    pcall(Fish.render)
    while true do
        task.wait(FISH_DELAY)
        if USE_AUTO_FISH and not Fish.ready() then
            USE_AUTO_FISH = false
            Fish.refuseT = tick()
            autoFishBtn.Text = "Auto Fish: OFF"
            autoFishBtn.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
            Fish.live = true
            pcall(Fish.render)
        elseif USE_AUTO_FISH then
            Fish.live = true
            local ok, err = pcall(Fish.instant)
            if not ok then
                pcall(Fish.log, "err: " .. tostring(err))
                task.wait(1)
            end
        end
    end
end)

-- stop animasi (skip cutscene secret/forgotten) + refresh label saat auto fish jalan
task.spawn(function()
    task.wait(3)
    while true do
        task.wait(0.5)
        pcall(function()
            if USE_AUTO_FISH then
                fishStatusLabel.Text = "Status: Running"
            elseif Fish.refuseT and tick() - Fish.refuseT < 6 then
                fishStatusLabel.Text = "Idle: remote belum siap (Start Spy di Settings, mancing manual 1x)"
            else
                fishStatusLabel.Text = "Status: Idle"
            end
        end)
        if USE_AUTO_FISH and Fish.stopAnimOn then pcall(Fish.stopAnims) end
        if USE_AUTO_FISH and Fish.live then pcall(Fish.render) end
    end
end)
-- skip cutscene: cek tiap 0.2s saat Auto Fish ON + Skip Cutscene ON (semua pcall)
task.spawn(function()
    task.wait(3)
    pcall(Fish.setupBeamHook)
    -- hook CutsceneBroadcast: block FireServer dari client (opsional, semua pcall; remote harus ada)
    pcall(function()
        local cs = game:GetService("ReplicatedStorage"):FindFirstChild("CutsceneBroadcast", true)
        if cs and cs:IsA("RemoteEvent") and getrawmetatable and getnamecallmethod and newcclosure and setreadonly then
            local mt = getrawmetatable(game)
            local old = mt.__namecall
            setreadonly(mt, false)
            mt.__namecall = newcclosure(function(self, ...)
                if self == cs and Fish.aggSkip and getnamecallmethod() == "FireServer" then
                    return
                end
                return old(self, ...)
            end)
            setreadonly(mt, true)
        end
    end)
    while true do
        task.wait(Fish.aggSkip and 0.05 or 0.2)
        if USE_AUTO_FISH and Fish.skipCutscene then
            pcall(Fish.cutsceneTick)
        end
    end
end)

-- anti shake + bersihkan efek/GUI secret: gabungan, tiap 0.1s saat Auto Fish ON + Stop Anim ON
task.spawn(function()
    task.wait(3)
    while true do
        task.wait(0.1)
        if USE_AUTO_FISH and Fish.stopAnimOn then
            pcall(Fish.cleanTick)
        end
    end
end)

-- watchdog auto-trigger: cek tiap 0.1s, MiniGame ditembak kalau nyangkut di waiting_marker > 1s
task.spawn(function()
    task.wait(3)
    while true do
        task.wait(0.1)
        pcall(Fish.watchdogTick)
    end
end)

end

local okMain, errMain = xpcall(main, function(e)
    warn("[RouteTools FATAL] " .. tostring(e))
    warn(debug.traceback())
    showFatal(e)
    return e
end)
