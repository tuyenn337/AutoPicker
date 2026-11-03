-- Anime Adventures Auto Picker (Delta Executor)
-- Features:
--   1) Picks buff cards by name priority (LAST item in each list = HIGHEST priority)
--   2) Votes for the best weather card (green text = good, red text = bad)
--   3) Built-in diagnostics: executor support check, remote logger, text dump
--
-- Set these globals BEFORE loading this file to override the defaults.

local env = getgenv()

env.FocusWave = env.FocusWave or 50
env.PriorityCards = env.PriorityCards or {
    "- Cooldown I", "+ Gain 2 Random Effects Tier 1", "- Cooldown II", "- Cooldown III",
    "+ Range I", "+ Attack I", "+ Attack II", "+ Gain 2 Random Effects Tier 2",
    "+ Range II", "+ Range III", "+ Attack III", "+ Gain 2 Random Effects Tier 3",
}
env.Cards = env.Cards or {
    "+ Yen I", "+ Yen II", "+ Yen III",
    "+ Boss Damage I", "+ Boss Damage II", "+ Boss Damage III",
    "- Cooldown I", "- Gain 2 Random Effects Tier 1", "- Cooldown II", "- Cooldown III",
    "+ Range I", "- Gain 2 Random Effects Tier 2", "+ Attack I", "+ Attack II",
    "+ Range II", "+ Range III", "+ Attack III", "- Gain 2 Random Effects Tier 3",
    "+ Enemy Health III", "+ Enemy Health II", "+ Enemy Health I",
    "+ Gain 2 Random Curses Tier 1", "+ Gain 2 Random Curses Tier 2", "+ Gain 2 Random Curses Tier 3",
    "+ Enemy Speed I", "+ Explosive Deaths I", "+ Enemy Regen I", "+ Enemy Shield I",
    "+ Enemy Speed II", "+ Explosive Deaths II", "+ Enemy Shield II", "+ Enemy Regen II",
    "+ Enemy Speed III", "+ Explosive Deaths III", "+ Enemy Shield III", "+ Enemy Regen III",
    "+ New Path",
}

local CONFIG = {
    ScanInterval = 0.5,
    ActionCooldown = 5,                  -- seconds to wait after any pick or vote
    Debug = env.AutoPickerDebug ~= false, -- set getgenv().AutoPickerDebug = false to silence logs
    LogRemotes = env.AutoPickerLogRemotes ~= false, -- logs FireServer/InvokeServer calls
    DumpIntervalSeconds = 10,            -- how often to dump visible texts when nothing matches
    VoteScreenText = "vote ends in",
    CardSuffix = " card",                -- weather cards end with this (e.g. "Windy Card")
}

-- Stop any previous copy of this script
env.AutoPickerToken = (env.AutoPickerToken or 0) + 1
local myToken = env.AutoPickerToken

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local VIM
pcall(function() VIM = game:GetService("VirtualInputManager") end)

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function log(...)
    if CONFIG.Debug then print("[AutoPicker]", ...) end
end

local function norm(text)
    text = tostring(text)
    text = text:gsub("<[^>]+>", "")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return string.lower(text)
end

local function visible(gui)
    while gui and gui ~= PlayerGui do
        if gui:IsA("GuiObject") and not gui.Visible then return false end
        if gui:IsA("ScreenGui") and not gui.Enabled then return false end
        gui = gui.Parent
    end
    return true
end

-- Text can live in a TextLabel OR a TextButton
local function isText(obj)
    return (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.Text ~= ""
end

local function visibleTexts()
    local out = {}
    for _, o in ipairs(PlayerGui:GetDescendants()) do
        if isText(o) and visible(o) then table.insert(out, o) end
    end
    return out
end

-- Climb up from a label to the nearest button
local function buttonAbove(from)
    for _ = 1, 8 do
        if not from or from == PlayerGui then return nil end
        if from:IsA("GuiButton") then return from end
        from = from.Parent
    end
    return nil
end

-- Find a button inside a card container (or just above it)
local function buttonIn(root)
    if root:IsA("GuiButton") then return root end
    for _, o in ipairs(root:GetDescendants()) do
        if o:IsA("GuiButton") and visible(o) then return o end
    end
    return buttonAbove(root.Parent)
end

local function click(target)
    local btn = target:IsA("GuiButton") and target or buttonAbove(target)
    if btn then
        for _, signalName in ipairs({ "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up" }) do
            if firesignal then pcall(firesignal, btn[signalName]) end
            if getconnections then
                local ok, cons = pcall(getconnections, btn[signalName])
                if ok then
                    for _, c in ipairs(cons) do pcall(function() c:Fire() end) end
                end
            end
        end
    end
    -- Simulated click as a fallback
    if VIM then
        local g = btn or target
        local pos, size, inset = g.AbsolutePosition, g.AbsoluteSize, GuiService:GetGuiInset()
        local x, y = pos.X + size.X / 2, pos.Y + size.Y / 2 + inset.Y
        pcall(function()
            VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(0.05)
            VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
        pcall(function()
            VIM:SendTouchEvent(1, 0, x, y)
            task.wait(0.05)
            VIM:SendTouchEvent(1, 2, x, y)
        end)
    end
end

---------------------------------------------------------------------
-- Diagnostics
---------------------------------------------------------------------
if CONFIG.Debug then
    print("=== AutoPicker: FUNCTION SUPPORT ===")
    for _, name in ipairs({ "firesignal", "getconnections", "hookmetamethod", "getnamecallmethod", "fireclickdetector" }) do
        print("  " .. name, env[name] ~= nil)
    end
    print("  VirtualInputManager", VIM ~= nil)
end

if CONFIG.LogRemotes and hookmetamethod and getnamecallmethod and not env.AutoPickerRemoteHooked then
    env.AutoPickerRemoteHooked = true
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if (method == "FireServer" or method == "InvokeServer") and env.AutoPickerToken == myToken then
            local parts = {}
            for i, v in ipairs({ ... }) do parts[i] = tostring(v) end
            print("[AutoPicker][REMOTE]", self:GetFullName(), method, table.concat(parts, ", "))
        end
        return oldNamecall(self, ...)
    end)
    log("Remote logger active. Click a card manually once to see its remote.")
end

local lastDump = 0
local function dumpTexts(all)
    if os.clock() - lastDump < CONFIG.DumpIntervalSeconds then return end
    lastDump = os.clock()
    log("No card matched. Visible texts:")
    for _, o in ipairs(all) do
        print("   ", o.ClassName, o:GetFullName(), "=>", o.Text)
    end
end

---------------------------------------------------------------------
-- Weather vote (green = +1, red = -1)
---------------------------------------------------------------------
local function sign(label)
    local c = label.TextColor3
    local rich = label.Text:match('color%s*=%s*"#(%x%x%x%x%x%x)"')
    if rich then
        c = Color3.fromRGB(
            tonumber(rich:sub(1, 2), 16),
            tonumber(rich:sub(3, 4), 16),
            tonumber(rich:sub(5, 6), 16)
        )
    end
    if c.G >= 0.6 and c.R <= 0.55 and c.B <= 0.55 and c.G - c.R >= 0.2 then return 1 end
    if c.R >= 0.6 and c.G <= 0.5 and c.B <= 0.5 and c.R - c.G >= 0.25 then return -1 end
    return 0
end

local function isTitle(o)
    local t = norm(o.Text)
    return #t > #CONFIG.CardSuffix and t:sub(-#CONFIG.CardSuffix) == CONFIG.CardSuffix
end

local function cardRoot(title)
    local r = title
    while r.Parent and r.Parent ~= PlayerGui do
        local n = 0
        for _, o in ipairs(r.Parent:GetDescendants()) do
            if isText(o) and visible(o) and isTitle(o) then n += 1 end
        end
        if n > 1 then break end
        r = r.Parent
    end
    return r
end

local lastAction = 0

local function weatherVote(all)
    local best, bestScore, seen = nil, nil, {}
    for _, l in ipairs(all) do
        if isTitle(l) then
            local root = cardRoot(l)
            if not seen[root] then
                seen[root] = true
                local score = 0
                for _, o in ipairs(root:GetDescendants()) do
                    if isText(o) and o ~= l and visible(o) then score += sign(o) end
                end
                log("Weather card:", l.Text, "| score:", score)
                if not bestScore or score > bestScore then best, bestScore = root, score end
            end
        end
    end
    if best then
        local btn = buttonIn(best)
        log("Voting | score:", bestScore, "| button:", btn and btn:GetFullName() or "none (coordinate click)")
        lastAction = os.clock()
        click(btn or best)
    end
end

---------------------------------------------------------------------
-- Buff cards by name
---------------------------------------------------------------------
local function buffPick(all)
    local wave
    for _, l in ipairs(all) do
        local n = norm(l.Text):match("wave%s*:?%s*(%d+)")
        if n then wave = tonumber(n) end
    end

    local usePriority = wave ~= nil and wave <= env.FocusWave
    local list = usePriority and env.PriorityCards or env.Cards
    local rank = {}
    for i, name in ipairs(list) do rank[norm(name)] = i end -- last item = highest priority

    local best, bestRank = nil, 0
    for _, l in ipairs(all) do
        local r = rank[norm(l.Text)]
        if r and r > bestRank then best, bestRank = l, r end
    end

    if best then
        log("Wave:", wave, "| mode:", usePriority and "Priority" or "Normal", "| picking:", best.Text)
        lastAction = os.clock()
        click(best)
    else
        dumpTexts(all)
    end
end

---------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------
task.spawn(function()
    log("Started. Waiting for buff cards and weather votes...")
    while task.wait(CONFIG.ScanInterval) do
        if env.AutoPickerToken ~= myToken then break end -- a newer copy took over
        local ok, err = pcall(function()
            if os.clock() - lastAction < CONFIG.ActionCooldown then return end
            local all, voting = visibleTexts(), false
            for _, l in ipairs(all) do
                if norm(l.Text):find(CONFIG.VoteScreenText, 1, true) then voting = true break end
            end
            if voting then weatherVote(all) else buffPick(all) end
        end)
        if not ok then warn("[AutoPicker] Error:", err) end
    end
end)
