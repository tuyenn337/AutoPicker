-- Anime Adventures Auto Picker (Delta) - compact version
getgenv().FocusWave = getgenv().FocusWave or 50
getgenv().PriorityCards = getgenv().PriorityCards or {
    "+ Range I", "+ Attack I", "+ Attack II", "+ Attack III",
}
getgenv().Cards = getgenv().Cards or {
    "+ Yen I", "+ Yen II", "+ Yen III",
}

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local VIM = game:GetService("VirtualInputManager")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local lastAction = 0

local function norm(t)
    return string.lower((tostring(t):gsub("<[^>]+>", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")))
end

local function visible(g)
    while g and g ~= PlayerGui do
        if (g:IsA("GuiObject") and not g.Visible) or (g:IsA("ScreenGui") and not g.Enabled) then return false end
        g = g.Parent
    end
    return true
end

local function labels()
    local out = {}
    for _, o in ipairs(PlayerGui:GetDescendants()) do
        if o:IsA("TextLabel") and o.Text ~= "" and visible(o) then table.insert(out, o) end
    end
    return out
end

local function button(from)
    for _ = 1, 8 do
        if not from or from == PlayerGui then return nil end
        if from:IsA("GuiButton") then return from end
        from = from.Parent
    end
end

local function click(target)
    local btn = target:IsA("GuiButton") and target or button(target)
    if btn then
        for _, s in ipairs({ "Activated", "MouseButton1Click" }) do
            if firesignal then pcall(firesignal, btn[s]) end
            if getconnections then
                local ok, cons = pcall(getconnections, btn[s])
                if ok then for _, c in ipairs(cons) do pcall(function() c:Fire() end) end end
            end
        end
    end
    local g = btn or target
    local p, s, i = g.AbsolutePosition, g.AbsoluteSize, GuiService:GetGuiInset()
    local x, y = p.X + s.X / 2, p.Y + s.Y / 2 + i.Y
    VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
    task.wait(0.05)
    VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
end

-- Weather: green text = +, red text = -
local function sign(l)
    local c = l.TextColor3
    if c.G >= 0.6 and c.R <= 0.55 and c.B <= 0.55 then return 1 end
    if c.R >= 0.6 and c.G <= 0.5 and c.B <= 0.5 then return -1 end
    return 0
end

local function cardRoot(title)
    local r = title
    while r.Parent and r.Parent ~= PlayerGui do
        local n = 0
        for _, o in ipairs(r.Parent:GetDescendants()) do
            if o:IsA("TextLabel") and visible(o) and norm(o.Text):sub(-5) == " card" then n += 1 end
        end
        if n > 1 then break end
        r = r.Parent
    end
    return r
end

local function weatherVote(all)
    local best, bestScore
    for _, l in ipairs(all) do
        if norm(l.Text):sub(-5) == " card" then
            local root, score = cardRoot(l), 0
            for _, o in ipairs(root:GetDescendants()) do
                if o:IsA("TextLabel") and o ~= l and visible(o) then score += sign(o) end
            end
            print("[AutoPicker] Weather:", l.Text, "score", score)
            if not bestScore or score > bestScore then best, bestScore = root, score end
        end
    end
    if best then lastAction = os.clock() click(best) end
end

local function buffPick(all)
    local wave
    for _, l in ipairs(all) do
        wave = tonumber(norm(l.Text):match("wave%s*:?%s*(%d+)")) or wave
    end
    local list = (wave and wave <= getgenv().FocusWave) and getgenv().PriorityCards or getgenv().Cards
    local rank = {}
    for i, n in ipairs(list) do rank[norm(n)] = i end -- last item = highest priority
    local best, bestRank = nil, 0
    for _, l in ipairs(all) do
        local r = rank[norm(l.Text)]
        if r and r > bestRank then best, bestRank = l, r end
    end
    if best then
        print("[AutoPicker] Picking:", best.Text)
        lastAction = os.clock()
        click(best)
    end
end

task.spawn(function()
    print("[AutoPicker] Started")
    while task.wait(0.5) do
        pcall(function()
            if os.clock() - lastAction < 5 then return end
            local all, voting = labels(), false
            for _, l in ipairs(all) do
                if norm(l.Text):find("vote ends in", 1, true) then voting = true end
            end
            if voting then weatherVote(all) else buffPick(all) end
        end)
    end
end)
