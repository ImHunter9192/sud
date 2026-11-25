local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Players, RS, RepS = game:GetService("Players"), game:GetService("RunService"), game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer
local scriptStart = os.clock()

-- ===== always on (no switch) =====
-- 1) anti-kick: blocks kicks that are requested by scripts on MY client (LocalPlayer:Kick).
--    It cannot stop a kick or ban the server itself decides on.
pcall(function()
    if hookmetamethod and getnamecallmethod then
        local old
        old = hookmetamethod(game, "__namecall", newcclosure and newcclosure(function(self, ...)
            if self == lp and getnamecallmethod():lower() == "kick" then return end
            return old(self, ...)
        end) or function(self, ...)
            if self == lp and getnamecallmethod():lower() == "kick" then return end
            return old(self, ...)
        end)
    end
end)
-- 2) anti "gameplay paused": the pause appears when the world streams in slower than I move (fast flying).
--    Turn the pause-on-streaming behaviour off and keep it off.
task.spawn(function()
    while true do
        pcall(function()
            workspace.StreamingIntegrityMode = Enum.StreamingIntegrityMode.Disabled
        end)
        task.wait(3)
    end
end)

local CFG = {
    Bases = "Bases", Treadmill = "TreadmillLocation", Admin = "Admin Treadmill",
    BoxTool = "Box",   -- backpack tools whose name contains this get placed
    PlaceY = 0,        -- ground height used for PlaceBox
}
local on, placeDelay = {}, 0.5
local placeTarget -- defined below
local VirtualUser = game:GetService("VirtualUser")

local function root() local c = lp.Character return c and c:FindFirstChild("HumanoidRootPart") end
local function posOf(o) return o:IsA("Model") and o:GetPivot().Position or o.Position end
-- the game shows the owner's name on Base.Origin.OwnerNameplate.PlayerName
local function mine(base)
    local l = base:FindFirstChild("PlayerName", true)
    if not (l and l:IsA("TextLabel")) then return false end
    local t = (l.Text:gsub("^@", "")):lower()
    return t == lp.DisplayName:lower() or t == lp.Name:lower()
end

local function myBase()
    local bases = workspace:FindFirstChild(CFG.Bases)
    if not bases then return end
    for _, b in ipairs(bases:GetChildren()) do
        if mine(b) then return b end
    end
end

local function myTreadmill()
    local bases = workspace:FindFirstChild(CFG.Bases)
    if not bases then return end
    for _, b in ipairs(bases:GetChildren()) do
        if mine(b) then return b:FindFirstChild(CFG.Treadmill, true) end
    end
end

local function admin()
    local o = workspace:FindFirstChild(CFG.Admin)
    return (o and (o:IsA("BasePart") or o:IsA("Model"))) and o or nil
end

local function goTo(t, up)
    local r = root()
    if r and t then r.CFrame = CFrame.new(posOf(t) + Vector3.new(0, up, 0)) return true end
    Rayfield:Notify({Title = "Teleport", Content = "Target not found", Duration = 3})
end
local function adminUp(a) return (a:IsA("BasePart") and a.Size.Y / 2 or 0) + 4 end

workspace.ChildAdded:Connect(function(c)
    if c.Name == CFG.Admin then
        Rayfield:Notify({Title = "Admin Treadmill", Content = "Spawned!", Duration = 4})
        if on.admin then task.wait(0.2) goTo(c, adminUp(c)) end
    end
end)

task.spawn(function()
    while task.wait(0.5) do
        pcall(function()
            local r, a = root(), admin()
            if not r then return end
            if on.admin and a then
                if (posOf(a) - r.Position).Magnitude > 15 then goTo(a, adminUp(a)) end
            elseif on.tread then
                local t = myTreadmill()
                if t and (posOf(t) - r.Position).Magnitude > 15 then goTo(t, 4) end
            end
        end)
    end
end)

local function remote(name) return RepS:FindFirstChild(name, true) end

-- where boxes go: inside MY base, no matter where I'm standing.
-- "boxSpot" is a point saved relative to my base's Origin part (set it with the button in the Main tab).
local placeSpread = 6
local boxSpot
pcall(function()
    if readfile and isfile and isfile("stela_boxspot.txt") then
        local x, y, z = readfile("stela_boxspot.txt"):match("([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)")
        if x then boxSpot = Vector3.new(tonumber(x), tonumber(y), tonumber(z)) end
    end
end)

local function baseRef()
    local b = myBase()
    return b and (b:FindFirstChild("Origin") or b:FindFirstChild("PetBounds")), b
end

function placeTarget()
    local ref = baseRef()
    if not ref then return end
    local p = boxSpot and ref.CFrame:PointToWorldSpace(boxSpot) or ref.Position
    local off = Vector3.new(math.random(-placeSpread, placeSpread), 0, math.random(-placeSpread, placeSpread))
    return Vector3.new(p.X, CFG.PlaceY, p.Z) + off
end

local function saveBoxSpot()
    local r, ref = root(), baseRef()
    if not (r and ref) then
        Rayfield:Notify({Title = "Box spot", Content = "Couldn't find your base", Duration = 4})
        return
    end
    boxSpot = ref.CFrame:PointToObjectSpace(r.Position)
    pcall(function()
        if writefile then writefile("stela_boxspot.txt", boxSpot.X .. "," .. boxSpot.Y .. "," .. boxSpot.Z) end
    end)
    Rayfield:Notify({Title = "Box spot saved", Content = "Boxes now go here, from anywhere", Duration = 4})
end

-- auto place boxes: EquipTool(tool) then PlaceBox(Vector3) near where you stand
task.spawn(function()
    while task.wait(placeDelay) do
        if on.boxes then pcall(function()
            local r, place, equip = root(), remote("PlaceBox"), remote("EquipTool")
            if not (r and place and equip) then return end
            local tool
            for _, c in ipairs({lp.Character, lp.Backpack}) do
                for _, t in ipairs(c:GetChildren()) do
                    if t:IsA("Tool") and t.Name:find(CFG.BoxTool, 1, true) then tool = t break end
                end
                if tool then break end
            end
            if not tool then return end
            if tool.Parent ~= lp.Character then equip:FireServer(tool) task.wait(0.15) end
            local target = placeTarget()
            if not target then return end
            local back
            if on.tpPlace and (r.Position - target).Magnitude > 30 then
                back = r.CFrame -- remember where I was
                r.CFrame = CFrame.new(target + Vector3.new(0, 4, 0))
                task.wait(0.25)
            end
            pcall(function() place:FireServer(target) end)
            if back then
                task.wait(0.25)
                local r2 = root()
                if r2 then
                    r2.CFrame = back
                    r2.AssemblyLinearVelocity = Vector3.zero
                end
            end
        end) end
    end
end)

-- webhook notifier: reads the game's own night-reset announcements (PlayerGui.NightWarning)
-- e.g. "ALL BOXES RESET!" then "Winged Verity Box" + " spawned in " + "Glass House!"
local HttpService = game:GetService("HttpService")
local wh = {url = "", bosses = ""}
on.night = true
local sent = {}
local httpReq = (syn and syn.request) or (http and http.request) or http_request or request

local function validUrl(u)
    return u:find("^https://[%w%.]*discord%.com/api/webhooks/") or u:find("^https://[%w%.]*discordapp%.com/api/webhooks/")
end

local function sendWebhook(title, desc)
    if not (httpReq and validUrl(wh.url)) then return false end
    pcall(httpReq, {
        Url = wh.url, Method = "POST", Headers = {["Content-Type"] = "application/json"},
        Body = HttpService:JSONEncode({embeds = {{title = title, description = desc, color = 5814783, footer = {text = lp.DisplayName}}}}),
    })
    return true
end

local function trim(s) return s:match("^%s*(.-)%s*$") end

-- selectable lists for the notification filters (edit or add names here)
local LISTS = {
    areas = {"Forest", "Ruins", "Desert", "Backrooms", "Dungeon", "Ocean", "Abyss", "Elysium", "Fracture",
        "Inferno", "Genesis", "Eternity", "Candyland", "Moonfall", "Glass House", "Observatory",
        "Haunted Graveyard", "Heaven's Gate", "Event Horizon", "Frostfire", "Checkmate", "Dread Keep"},
    boxes = {"Happy", "Smiling", "Annoyed", "Moggity", "Creepy", "Enraged", "True", "Lord",
        "King", "Divine", "Winged"},
}
-- the game stores each area's name on Workspace.Areas.AreaN (attribute DisplayName): use it if present
pcall(function()
    local af = workspace:FindFirstChild("Areas")
    if not af then return end
    local list = {}
    for _, a in ipairs(af:GetChildren()) do
        local n = a:GetAttribute("DisplayName")
        if n then list[#list + 1] = {tonumber(a.Name:match("%d+")) or 0, n} end
    end
    table.sort(list, function(x, y) return x[1] < y[1] end)
    if #list > 0 then
        LISTS.areas = {}
        for _, e in ipairs(list) do table.insert(LISTS.areas, e[2]) end
    end
end)
-- boss tiers (Normal, Winged, ...) come from the game's own BossConfig
LISTS.tiers = {"Normal", "Winged"}
pcall(function()
    local cfg = require(RepS.Shared.BossConfig)
    local t = {}
    for _, tier in ipairs(cfg.BOSS_TIERS) do table.insert(t, tier.Name == "" and "Normal" or tier.Name) end
    if #t > 0 then LISTS.tiers = t end
end)
local function copy(t) local c = {} for i, v in ipairs(t) do c[i] = v end return c end

-- a "selection" = which names of LISTS[key] are ticked in one picker
local function makeSel(key)
    local picked, all = {}, true
    local o = {}
    function o.set(list)
        picked = {}
        local n = 0
        for _, name in ipairs(list) do picked[name:lower()] = true n = n + 1 end
        all = n >= #LISTS[key]
    end
    -- exact name read from the map. Names the script doesn't know only pass while everything is ticked.
    function o.allowed(t)
        for _, opt in ipairs(LISTS[key]) do
            if t:lower() == opt:lower() then return picked[opt:lower()] == true end
        end
        return all
    end
    -- free text like "Winged Verity Box": passes if a ticked name is inside it; unknown text always passes
    function o.allowedText(text)
        local t, known = text:lower(), false
        for _, opt in ipairs(LISTS[key]) do
            if t:find(opt:lower(), 1, true) then
                known = true
                if picked[opt:lower()] then return true end
            end
        end
        return not known
    end
    function o.isEmpty() return next(picked) == nil end
    o.set(LISTS[key])
    return o
end
-- three independent sets: in-game popups, Discord, ESP
local SEL = {
    notifAreas = makeSel("areas"), notifBoxes = makeSel("boxes"),
    hookAreas = makeSel("areas"), hookBoxes = makeSel("boxes"),
    espAreas = makeSel("areas"), espBoxes = makeSel("boxes"),
    bossAreas = makeSel("areas"), bossTiers = makeSel("tiers"),
    stealBoxes = makeSel("boxes"), stealAreas = makeSel("areas"),
    customBoxes = makeSel("boxes"), customAreas = makeSel("areas"),
}

local function findOpt(key, word)
    for _, opt in ipairs(LISTS[key]) do
        if opt:lower() == word:lower() then return opt:lower() end
    end
end


-- comma separated filter; empty = match everything
local function passes(filter, text)
    local any = false
    for item in filter:lower():gmatch("[^,]+") do
        item = trim(item)
        if item ~= "" then
            any = true
            if text:lower():find(item, 1, true) then return true end
        end
    end
    return not any
end

local function readAnnouncements(gui)
    local list = {}
    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text:lower():find("spawned in", 1, true) then
            local sibs = {}
            for _, c in ipairs(d.Parent:GetChildren()) do
                if c:IsA("TextLabel") and c.Text:match("%S") then sibs[#sibs + 1] = c end
            end
            table.sort(sibs, function(a, b)
                if a.LayoutOrder ~= b.LayoutOrder then return a.LayoutOrder < b.LayoutOrder end
                return a.AbsolutePosition.X < b.AbsolutePosition.X
            end)
            for i, c in ipairs(sibs) do
                if c == d and sibs[i - 1] and sibs[i + 1] then
                    local area = trim(sibs[i + 1].Text):gsub("!+$", "")
                    list[#list + 1] = {box = trim(sibs[i - 1].Text), area = area}
                end
            end
        end
    end
    return list
end

local function processAnnouncements(force)
    local gui = lp.PlayerGui:FindFirstChild("NightWarning")
    if not gui then return false end
    local toastLines, hookLines, now = {}, {}, os.clock()
    for _, a in ipairs(readAnnouncements(gui)) do
        local sig = a.box .. "@" .. a.area
        local line = "• **" .. a.box .. "** in **" .. a.area .. "**"
        local function fresh(dest) return force or not sent[dest .. sig] or now - sent[dest .. sig] > 200 end
        if fresh("t") and SEL.notifBoxes.allowedText(a.box) and SEL.notifAreas.allowedText(a.area) then
            sent["t" .. sig] = now
            toastLines[#toastLines + 1] = line
        end
        if fresh("h") and SEL.hookBoxes.allowedText(a.box) and SEL.hookAreas.allowedText(a.area) then
            sent["h" .. sig] = now
            hookLines[#hookLines + 1] = line
        end
    end
    if #hookLines > 0 then sendWebhook("Boxes reset: new spawns", table.concat(hookLines, "\n")) end
    if #toastLines > 0 then
        Rayfield:Notify({Title = "New boxes", Content = (table.concat(toastLines, "\n"):gsub("%*", "")), Duration = 8})
    end
    return #hookLines > 0 or #toastLines > 0
end

-- wait until the announcements stop changing for 3s, then send them as one message
local token = 0
local function schedule()
    if not on.night then return end
    token = token + 1
    local my = token
    task.delay(3, function() if my == token then pcall(processAnnouncements) end end)
end

local function hookGui(gui)
    local function watch(d)
        if d:IsA("TextLabel") then d:GetPropertyChangedSignal("Text"):Connect(schedule) end
    end
    for _, d in ipairs(gui:GetDescendants()) do watch(d) end
    gui.DescendantAdded:Connect(function(d) watch(d) if d:IsA("TextLabel") then schedule() end end)
end

local pg = lp:WaitForChild("PlayerGui")
local nw = pg:FindFirstChild("NightWarning")
if nw then hookGui(nw) end
pg.ChildAdded:Connect(function(c) if c.Name == "NightWarning" then hookGui(c) end end)

-- boss prediction: the game picks bosses with its own fixed formula (BossConfig), so we just ask it
local okC, BossConfig = pcall(function() return require(RepS.Shared.BossConfig) end)
local okP, BossPortal = pcall(function() return require(RepS.Shared.BossPortalConfig) end)
local canPredict = okC and okP and type(BossConfig) == "table" and type(BossPortal) == "table"
    and type(BossConfig.AreaForBand) == "function" and type(BossConfig.SlotIndex) == "function"
    and type(BossPortal.SignStateAt) == "function"

local BAND_NAMES = {"Normal", "High", "Top"}
local bandOfKey = {Normal = 1, High = 2, Top = 3}
local PRED_SLOTS = 4
local predLabels, infoCache, areaNames = {}, {}, nil

local function areaName(id)
    if not areaNames then
        areaNames = {}
        local af = workspace:FindFirstChild("Areas")
        for _, a in ipairs(af and af:GetChildren() or {}) do
            local aid, dn = a:GetAttribute("AreaId"), a:GetAttribute("DisplayName")
            if aid and dn then areaNames[aid] = dn end
        end
    end
    return areaNames[id] or tostring(id)
end

local function shortNum(n)
    local units = {{"Dc", 1e33}, {"No", 1e30}, {"Oc", 1e27}, {"Sp", 1e24}, {"Sx", 1e21}, {"Qi", 1e18},
        {"Qa", 1e15}, {"T", 1e12}, {"B", 1e9}, {"M", 1e6}, {"K", 1e3}}
    for _, u in ipairs(units) do
        if n >= u[2] then return string.format("%.2f", n / u[2]) .. u[1] end
    end
    return tostring(math.floor(n))
end

local function mmss(sec)
    sec = math.max(0, math.floor(sec))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- the boss for one portal ("band") in one time slot: its area, its tier and the speed needed to enter
local function bossInfo(slot, band)
    local key = slot .. ":" .. band
    if infoCache[key] then return infoCache[key] end
    local ok, info = pcall(function()
        local area = BossConfig.AreaForBand(slot, band)
        if not area then return nil end
        local tname = BossConfig.TierName(BossConfig.TierFor(slot, band))
        local tierLabel = (tname == nil or tname == "") and "Normal" or tname
        local an = areaName(area.Id)
        return {
            area = an, tierLabel = tierLabel, speed = BossConfig.EntrySpeedFor(area.Id),
            full = (tierLabel ~= "Normal" and (tierLabel .. " ") or "") .. an .. " boss",
        }
    end)
    if ok and info then infoCache[key] = info return info end
end

-- for the "boss soon" Discord alert: returns skip, text
local function bossLine(key)
    if not canPredict then return false, "" end
    local now = workspace:GetServerTimeNow()
    if (BossPortal.SignStateAt(now)) then return true, "" end -- the clock is counting to the portal CLOSING
    local info = bossInfo(BossConfig.SlotIndex(now) + 1, bandOfKey[key] or 1)
    if not info then return false, "" end
    if not (SEL.bossAreas.allowed(info.area) and SEL.bossTiers.allowed(info.tierLabel)) then return true, "" end
    return false, " - **" .. info.full .. "**"
end

-- keep the Boss tab labels up to date
task.spawn(function()
    while task.wait(1) do
        if canPredict and next(predLabels) then
            pcall(function()
                local now = workspace:GetServerTimeNow()
                local open, left = BossPortal.SignStateAt(now)
                local cur = BossConfig.SlotIndex(now)
                local first = open and cur or cur + 1
                for i = 1, PRED_SLOTS do
                    local pl, slot = predLabels[i], first + i - 1
                    local startT = BossConfig.SlotStart(slot)
                    local head
                    if i == 1 and open then
                        head = "OPEN NOW - closes in " .. mmss(left)
                    else
                        head = "Starts in " .. mmss(startT - now) .. "  (" .. os.date("%H:%M", math.floor(startT)) .. ")"
                    end
                    if pl.headText ~= head then pl.head:Set(head) pl.headText = head end
                    local bands = BossConfig.BandsForSlot(slot)
                    for b = 1, 3 do
                        local txt
                        if table.find(bands, b) then
                            local info = bossInfo(slot, b)
                            if info then
                                local need = (info.speed and info.speed > 0) and ("needs " .. shortNum(info.speed) .. " speed") or "no minimum"
                                txt = BAND_NAMES[b] .. ": " .. info.full .. " (" .. need .. ")"
                            else
                                txt = BAND_NAMES[b] .. ": ?"
                            end
                        else
                            txt = BAND_NAMES[b] .. ": -"
                        end
                        if pl.rowText[b] ~= txt then pl.rows[b]:Set(txt) pl.rowText[b] = txt end
                    end
                end
            end)
        end
    end
end)

-- boss timers + alerts (the three portal signs show the countdown and the speed needed)
local TIERS = {
    {key = "Normal", gui = "BossPortalSign"},
    {key = "High", gui = "BossPortalSignHigh"},
    {key = "Top", gui = "BossPortalSignTop"},
}
local bossLabels, lastSecs, lastText = {}, {}, {}
local bossTiers = {Normal = true, High = true, Top = true}
local bossWarn = 60
on.bossSoon, on.bossEvent = false, false

local function readTier(t)
    local g = lp.PlayerGui:FindFirstChild(t.gui)
    if not g then return end
    local clock = g:FindFirstChild("Clock", true)
    local req
    -- the speed needed is a label somewhere under an object called "Speed"
    for _, d in ipairs(g:GetDescendants()) do
        if d.Name == "Speed" then
            local labels = d:IsA("TextLabel") and {d} or {}
            for _, x in ipairs(d:GetDescendants()) do
                if x:IsA("TextLabel") then labels[#labels + 1] = x end
            end
            for _, l in ipairs(labels) do
                if l.Text ~= "" and l.Text:lower() ~= "speed" then req = l.Text break end
            end
            if req then break end
        end
    end
    if not req then -- fallback: a label that looks like a number such as 600M or 1T
        for _, d in ipairs(g:GetDescendants()) do
            if d:IsA("TextLabel") and d ~= clock and d.Text:match("^[%d%.,]+%s*%a*$") then req = d.Text break end
        end
    end
    return clock and clock.Text or "?", req or "?"
end

local function toSecs(txt)
    local a, b, c = txt:match("^(%d+):(%d+):(%d+)$")
    if a then return tonumber(a) * 3600 + tonumber(b) * 60 + tonumber(c) end
    a, b = txt:match("^(%d+):(%d+)$")
    if a then return tonumber(a) * 60 + tonumber(b) end
end

task.spawn(function()
    while task.wait(1) do
        pcall(function()
            local lines = {}
            for _, t in ipairs(TIERS) do
                local clock, req = readTier(t)
                if clock then
                    local need = (req == "0" or req == "") and "no minimum" or ("needs " .. req .. " speed")
                    local txt = t.key .. " (" .. need .. "): " .. clock
                    local lbl = bossLabels[t.key]
                    if lbl and lastText[t.key] ~= txt then lbl:Set(txt) lastText[t.key] = txt end
                    local secs, prev = toSecs(clock), lastSecs[t.key]
                    if secs then
                        if on.bossSoon and bossTiers[t.key] and prev and prev > bossWarn and secs <= bossWarn then
                            local skip, who = bossLine(t.key)
                            if not skip then
                                lines[#lines + 1] = "• **" .. t.key .. "** portal (" .. need .. ") in " .. clock .. who
                            end
                        end
                        lastSecs[t.key] = secs
                    end
                end
            end
            if #lines > 0 then
                local desc = table.concat(lines, "\n")
                sendWebhook("Boss fight soon", desc)
                local plain = desc:gsub("%*", "")
                Rayfield:Notify({Title = "Boss soon", Content = plain, Duration = 8})
            end
        end)
    end
end)

-- game-side boss announcements: we forward whatever the remote sends so you can see boss names
local function fmt(v, d)
    d = d or 0
    local t = typeof(v)
    if t == "table" and d < 2 then
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. fmt(x, d + 1) end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif t == "Instance" then
        return v.Name
    end
    return tostring(v)
end

for _, name in ipairs({"BossAnnounce", "BossPortalOffer"}) do
    task.spawn(function()
        local folder = RepS:WaitForChild("Remotes", 15)
        local r = folder and folder:WaitForChild(name, 15)
        if not r then return end
        r.OnClientEvent:Connect(function(...)
            if not on.bossEvent then return end
            local args, parts = table.pack(...), {}
            for i = 1, args.n do parts[#parts + 1] = fmt(args[i]) end
            local text = table.concat(parts, " | ")
            if not passes(wh.bosses, text) then return end
            local msg = name .. ": " .. (text ~= "" and text or "(no data)")
            sendWebhook("Boss event", msg)
            Rayfield:Notify({Title = "Boss event", Content = msg:sub(1, 200), Duration = 8})
        end)
    end)
end

-- stats: money / speed change since you executed the script
local SUFFIX = {{"Dc", 1e33}, {"No", 1e30}, {"Oc", 1e27}, {"Sp", 1e24}, {"Sx", 1e21}, {"Qi", 1e18},
    {"Qa", 1e15}, {"T", 1e12}, {"B", 1e9}, {"M", 1e6}, {"K", 1e3}}

local function parseNum(txt)
    if txt == nil then return end
    local num, suf = tostring(txt):match("^%+?%$?%s*([%d%.,]+)%s*(%a*)")
    if not num then return end
    local n = tonumber((num:gsub(",", "")))
    if not n then return end
    if suf == "" then return n end
    for _, x in ipairs(SUFFIX) do
        if x[1]:lower() == suf:lower() then return n * x[2] end
    end
end

local function abbr(n)
    local sign = n < 0 and "-" or ""
    n = math.abs(n)
    for _, x in ipairs(SUFFIX) do
        if n >= x[2] then return sign .. string.format("%.2f", n / x[2]) .. x[1] end
    end
    return sign .. string.format("%.2f", n)
end

local function pct(now, start)
    if not (now and start) or start == 0 then return "n/a" end
    return string.format("%+.2f%%", (now - start) / start * 100)
end

local function hms(sec)
    sec = math.floor(sec)
    return string.format("%02d:%02d:%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60)
end

local function readSpeed()
    local ls = lp:FindFirstChild("leaderstats")
    local v = ls and ls:FindFirstChild("Speed")
    return v and parseNum(v.Value)
end

local function readMoneyRate()
    local a = lp:GetAttribute("AdvancedCashRate")
    if type(a) == "number" then return a end
    local ls = lp:FindFirstChild("leaderstats")
    local v = ls and ls:FindFirstChild("Money/s")
    return v and parseNum(v.Value)
end

-- current money isn't in leaderstats, so read the HUD text that looks like "$52.1B"
local moneyLabel
local function isMoneyText(t) return t:match("^%$[%d%.,]+%s*%a*$") and not t:find("/") end
local function readMoney()
    if moneyLabel and moneyLabel:IsDescendantOf(game) and isMoneyText(moneyLabel.Text) then
        return parseNum(moneyLabel.Text)
    end
    moneyLabel = nil
    local best, bestSize = nil, -1
    for _, root in ipairs({lp.PlayerGui:FindFirstChild("StealAVerityHUD"), lp.PlayerGui}) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("TextLabel") and d.Visible and isMoneyText(d.Text) and d.TextSize > bestSize then
                    best, bestSize = d, d.TextSize
                end
            end
        end
        if best then break end
    end
    moneyLabel = best
    return best and parseNum(best.Text)
end

local statLabels, statText = {}, {}
local function setStat(key, txt)
    local l = statLabels[key]
    if l and statText[key] ~= txt then l:Set(txt) statText[key] = txt end
end

task.spawn(function()
    local samples, speed0, money0 = {}, nil, nil
    while task.wait(1) do
        pcall(function()
            setStat("timer", "Script running: " .. hms(os.clock() - scriptStart))
            local speed, money, mrate = readSpeed(), readMoney(), readMoneyRate()
            speed0 = speed0 or speed
            money0 = money0 or money
            setStat("money", "Money: " .. (money and ("$" .. abbr(money)) or "not found") .. "  (" .. pct(money, money0) .. ")")
            setStat("speed", "Speed: " .. (speed and abbr(speed) or "?") .. "  (" .. pct(speed, speed0) .. ")")
            if speed then -- speed/s averaged over the last 30 seconds
                samples[#samples + 1] = {os.clock(), speed}
                while #samples > 1 and os.clock() - samples[1][1] > 30 do table.remove(samples, 1) end
            end
            local sps = "..."
            if #samples >= 2 then
                local f, l = samples[1], samples[#samples]
                sps = abbr((l[2] - f[2]) / math.max(l[1] - f[1], 1))
            end
            setStat("sps", "Speed/s: " .. sps)
            setStat("mps", "Money/s: " .. (mrate and ("$" .. abbr(mrate)) or "?"))
        end)
    end
end)

-- REAL boxes are the models in Workspace.BoxRuntime (Areas.X.Boxes.Box are only 1x1 spawn markers).
-- An area box = a BoxRuntime model that sits on one of the area floors.
on.espArea, on.espMood, on.espLabel = false, false, false
local areaBounds, areaIdx = {}, {}
for i, n in ipairs(LISTS.areas) do areaIdx[n] = i end

local function refreshAreaBounds()
    table.clear(areaBounds)
    local af = workspace:FindFirstChild("Areas")
    if not af then return end
    for _, a in ipairs(af:GetChildren()) do
        local name = a:GetAttribute("DisplayName")
        if name then
            local f = a:FindFirstChild("Floor")
            if f and f:IsA("BasePart") then areaBounds[#areaBounds + 1] = {name = name, cf = f.CFrame, size = f.Size} end
            local split = a:FindFirstChild("FloorSplit")
            if split and split:IsA("Model") then
                local cf, size = split:GetBoundingBox()
                areaBounds[#areaBounds + 1] = {name = name, cf = cf, size = size}
            end
        end
    end
end

local function areaOf(pos)
    for _, b in ipairs(areaBounds) do
        local p = b.cf:PointToObjectSpace(pos)
        if math.abs(p.X) <= b.size.X / 2 + 2 and math.abs(p.Z) <= b.size.Z / 2 + 2 and math.abs(p.Y) <= 60 then
            return b.name
        end
    end
end

-- face image id -> box type, built from the game's own BoxConfig.ById (only ids that belong to one box type)
local boxTypeByImage = {}
local function prettyId(id)
    local x = id:gsub("_box$", "")
    return (x:gsub("^%l", string.upper))
end
pcall(function()
    local cfg = require(RepS.Shared.BoxConfig)
    local owners = {}
    local function walk(v, id, d)
        if type(v) == "string" then
            for digits in v:gmatch("%d%d%d%d%d+") do
                owners[digits] = owners[digits] or {}
                owners[digits][id] = true
            end
        elseif type(v) == "table" and d < 3 then
            for _, x in pairs(v) do walk(x, id, d + 1) end
        end
    end
    for id, entry in pairs(cfg.ById) do walk(entry, prettyId(id), 0) end
    for digits, ids in pairs(owners) do
        local only, n = nil, 0
        for id in pairs(ids) do only, n = id, n + 1 end
        if n == 1 then boxTypeByImage[digits] = only end
    end
end)

local function faceDigits(model)
    local face = model:FindFirstChild("Face", true)
    local img = face and face:IsA("ImageLabel") and face.Image or ""
    return img:match("%d+")
end

local function boxTypeOf(model)
    for _, o in ipairs({model, model:FindFirstChild("Core")}) do
        if o then
            for k, v in pairs(o:GetAttributes()) do
                if type(v) == "string" and v ~= "" and k ~= "BoxUid" then return v end
            end
        end
    end
    local d = faceDigits(model)
    if d and boxTypeByImage[d] then return boxTypeByImage[d] end
    -- rare boxes share one face image, so tell them apart by their ornament/wings parts
    if d == "108908582036844" then
        local has = {}
        for _, c in ipairs(model:GetDescendants()) do has[c.Name:lower()] = true end
        local function any(sub)
            for n in pairs(has) do if n:find(sub, 1, true) then return true end end
        end
        if any("lord") then return "Lord" end
        if any("king") then return "King" end
        if any("golem") then return "Golem" end
        if any("prism") then return "Prism" end
        if any("wing") then return "Winged" end
        return "True"
    end
    return d and ("Face " .. d) or "Unknown"
end

local function areaBoxes()
    refreshAreaBounds()
    local res = {}
    local br = workspace:FindFirstChild("BoxRuntime")
    if not br then return res end
    for _, m in ipairs(br:GetChildren()) do
        if m:IsA("Model") then
            local core = m:FindFirstChild("Core") or m.PrimaryPart
            if core then
                local area = areaOf(core.Position)
                if area then res[#res + 1] = {model = m, core = core, area = area, type = boxTypeOf(m)} end
            end
        end
    end
    return res
end

-- boxes that are NOT inside a map area and not near a base (for example the boxes a boss drops in its arena)
local function dropBoxes()
    local res = {}
    local br = workspace:FindFirstChild("BoxRuntime")
    if not br then return res end
    refreshAreaBounds()
    local origins = {}
    local bases = workspace:FindFirstChild(CFG.Bases)
    if bases then
        for _, b in ipairs(bases:GetChildren()) do
            local o = b:FindFirstChild("Origin") or b.PrimaryPart
            if o then origins[#origins + 1] = o.Position end
        end
    end
    for _, m in ipairs(br:GetChildren()) do
        if m:IsA("Model") then
            local core = m:FindFirstChild("Core") or m.PrimaryPart
            local pr = core and core:FindFirstChild("Steal")
            if pr and not areaOf(core.Position) then
                local nearBase = false
                for _, o in ipairs(origins) do
                    if (o - core.Position).Magnitude < 150 then nearBase = true break end
                end
                if not nearBase then res[#res + 1] = {model = m, core = core, area = "Boss drop", type = boxTypeOf(m)} end
            end
        end
    end
    return res
end
-- the boxes an auto steal may go for; includeDrops adds the boss drops
local function allBoxes(includeDrops)
    local list = areaBoxes()
    if includeDrops then for _, b in ipairs(dropBoxes()) do list[#list + 1] = b end end
    return list
end

local espSingle, espColor, espTransp, typeColors = false, Color3.fromRGB(255, 200, 0), 0.6, {}
local espTextSize, espRange, espShowArea = 13, 100, false
local function colorFor(t)
    if espSingle then return espColor end
    if typeColors[t] then return typeColors[t] end
    local h = 0
    for i = 1, #t do h = (h * 31 + t:byte(i)) % 360 end
    return Color3.fromHSV(h / 360, 0.8, 1)
end

-- ESP
local espObjs = {}
local function espClear()
    for _, o in pairs(espObjs) do o.folder:Destroy() end
    table.clear(espObjs)
end

local function styleOne(o)
    o.label.TextSize = espTextSize
    o.label.Text = espShowArea and (o.type .. " - " .. o.area) or o.type
    o.gui.MaxDistance = espRange
    o.gui.Size = UDim2.fromOffset(espTextSize * 12, espTextSize + 6)
    o.gui.Enabled = on.espLabel
end
local function espRestyle() for _, o in pairs(espObjs) do styleOne(o) end end

task.spawn(function()
    while task.wait(2) do
        if not (on.espArea or on.espMood) then
            if next(espObjs) then espClear() end
        else
            pcall(function()
                local parent = (gethui and gethui()) or game:GetService("CoreGui")
                local live = {}
                for _, b in ipairs(areaBoxes()) do
                    if (on.espArea and SEL.espAreas.allowed(b.area)) or (on.espMood and SEL.espBoxes.allowed(b.type)) then
                        live[b.model] = true
                        local o = espObjs[b.model]
                        if not o then
                            local f = Instance.new("Folder")
                            local adorn = Instance.new("BoxHandleAdornment")
                            adorn.Adornee, adorn.AlwaysOnTop, adorn.ZIndex = b.core, true, 1
                            adorn.Size, adorn.Transparency = b.model:GetExtentsSize(), 0.6
                            adorn.Parent = f
                            local gui = Instance.new("BillboardGui")
                            gui.Adornee, gui.AlwaysOnTop = b.core, true
                            gui.Size, gui.StudsOffset = UDim2.fromOffset(160, 22), Vector3.new(0, 3, 0)
                            local tl = Instance.new("TextLabel", gui)
                            tl.Size, tl.BackgroundTransparency = UDim2.fromScale(1, 1), 1
                            tl.TextScaled, tl.Font, tl.TextStrokeTransparency = false, Enum.Font.GothamBold, 0.5
                            gui.Parent = f
                            f.Parent = parent
                            o = {folder = f, adorn = adorn, gui = gui, label = tl}
                            espObjs[b.model] = o
                        end
                        local c = colorFor(b.type)
                        o.adorn.Color3, o.label.TextColor3 = c, c
                        o.adorn.Transparency = espTransp
                        o.type, o.area = b.type, b.area
                        styleOne(o)
                    end
                end
                for m, o in pairs(espObjs) do
                    if not live[m] then o.folder:Destroy() espObjs[m] = nil end
                end
            end)
        end
    end
end)

-- summary of every box on the map, grouped by area (sent after each night reset)
local function boxSummary(areaSel, typeSel)
    local byArea, order = {}, {}
    for _, b in ipairs(areaBoxes()) do
        if areaSel.allowed(b.area) and typeSel.allowed(b.type) then
            if not byArea[b.area] then byArea[b.area] = {} order[#order + 1] = b.area end
            byArea[b.area][b.type] = (byArea[b.area][b.type] or 0) + 1
        end
    end
    table.sort(order, function(x, y) return (areaIdx[x] or 99) < (areaIdx[y] or 99) end)
    local lines = {}
    for _, area in ipairs(order) do
        local parts = {}
        for ty, n in pairs(byArea[area]) do parts[#parts + 1] = ty .. (n > 1 and (" x" .. n) or "") end
        table.sort(parts)
        lines[#lines + 1] = "**" .. area .. "**: " .. table.concat(parts, ", ")
    end
    return table.concat(lines, "\n"), #order
end

local function sendBoxSummary()
    local hookDesc, hn = boxSummary(SEL.hookAreas, SEL.hookBoxes)
    local toastDesc, tn = boxSummary(SEL.notifAreas, SEL.notifBoxes)
    if hn > 0 then sendWebhook("Boxes on the map", hookDesc:sub(1, 4000)) end
    if tn > 0 then
        Rayfield:Notify({Title = "Boxes on the map", Content = (toastDesc:gsub("%*", "")):sub(1, 200), Duration = 8})
    end
    return hn > 0 or tn > 0
end

-- night reset = the NightReadout countdown jumps from ~0 back up to minutes
local lastNight
task.spawn(function()
    while task.wait(1) do
        pcall(function()
            local g = lp.PlayerGui:FindFirstChild("NightReadout")
            if not g then return end
            local txt
            for _, d in ipairs(g:GetDescendants()) do
                if d:IsA("TextLabel") and d.Text:find("%d+s") then txt = d.Text break end
            end
            if not txt then return end
            local m, sec = txt:match("(%d+)m%s*(%d+)s")
            local secs = m and (tonumber(m) * 60 + tonumber(sec)) or tonumber(txt:match("(%d+)s"))
            if not secs then return end
            if on.night and lastNight and lastNight <= 20 and secs > lastNight + 100 then
                task.delay(6, function() pcall(sendBoxSummary) end) -- give the new boxes time to spawn
            end
            lastNight = secs
        end)
    end
end)

-- debug: every box with its area, detected type and face image id
local function scanReport()
    local out = {}
    for _, b in ipairs(areaBoxes()) do
        out[#out + 1] = b.area .. " | " .. b.type .. " | face=" .. tostring(faceDigits(b.model))
    end
    table.sort(out)
    local text = table.concat(out, "\n")
    if setclipboard then setclipboard(text) end
    print(text)
    Rayfield:Notify({Title = "Box scan", Content = #out .. " boxes scanned (copied to clipboard)", Duration = 4})
end

-- boxes menu: one dropdown per area listing the boxes in it; picking one teleports you next to it
local menuDD, menuMap, menuSig, menuSuppress, lastPos = {}, {}, {}, false, nil

-- smooth movement (looks less suspicious than an instant teleport)
local tweenSpeed = 80
on.tween = false
local curTween
local function moveTo(cf)
    local r = root()
    if not r then return end
    if curTween then pcall(function() curTween:Cancel() end) curTween = nil end
    if not on.tween then
        r.CFrame = cf
        r.AssemblyLinearVelocity = Vector3.zero
        return
    end
    local dist = (r.Position - cf.Position).Magnitude
    local t = game:GetService("TweenService"):Create(r,
        TweenInfo.new(math.max(0.2, dist / math.max(tweenSpeed, 1)), Enum.EasingStyle.Linear), {CFrame = cf})
    curTween = t
    local hb = RS.Heartbeat:Connect(function() r.AssemblyLinearVelocity = Vector3.zero end)
    t.Completed:Connect(function()
        hb:Disconnect()
        if curTween == t then curTween = nil end
    end)
    t:Play()
end

-- auto steal: fly (slowly) to a box lying in a map area (Forest etc.), hold the Steal prompt, fly home to my base
-- where stolen boxes are brought: the spawn (default) or my base
local spawnCache
local function spawnPoint()
    if spawnCache and spawnCache.Parent then return spawnCache.Position end
    local rl = lp.RespawnLocation
    if rl and rl.Parent then spawnCache = rl return rl.Position end
    local best, bd
    local b = myBase()
    local o = b and (b:FindFirstChild("Origin") or b.PrimaryPart)
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("SpawnLocation") then
            local dd = o and (d.Position - o.Position).Magnitude or 0
            if not bd or dd < bd then best, bd = d, dd end
        end
    end
    if not best then
        for _, d in ipairs(workspace:GetChildren()) do
            if d.Name == "Spawn" and (d:IsA("BasePart") or d:IsA("Model")) then
                best = d:IsA("Model") and (d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart", true)) or d
                break
            end
        end
    end
    spawnCache = best
    return best and best.Position
end
-- returns something with .Position, or nil
local function deliverPos(useSpawn)
    if useSpawn then
        local p = spawnPoint()
        if p then return {Position = p} end
    end
    local b = myBase()
    return b and (b:FindFirstChild("Origin") or b.PrimaryPart)
end
on.steal, on.stealEdge, on.stealRare = false, true, true
on.stealSpawn, on.customSpawn, on.customAvoid = true, true, true
on.stealDrops, on.customDrops, on.dropsOnly = true, true, false
on.autoLeave = false
local stealSpeed, stealSkipNear = 400, true
local stealAreaSpeed = {} -- area name -> speed override
local function speedFor(area) return (on.stealPerArea and stealAreaSpeed[area]) or stealSpeed end
local stealTried = {}
-- higher number = rarer mood (guessed order from BoxConfig rarities; unknown moods rank 0)
local MOOD_RANK = {happy = 1, smiling = 2, annoyed = 3, moggity = 4, creepy = 5, enraged = 6,
    winged = 7, lord = 8, king = 9, golem = 10, ["true"] = 11, prism = 12}
on.stealNoclip, on.stealHigh = true, true
local stealAlt = 60
local function startNoclip()
    local saved, conn = {}, nil
    local function apply()
        local c = lp.Character
        if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then
                if saved[p] == nil then saved[p] = p.CanCollide end
                p.CanCollide = false
                pcall(function() p.CanTouch = false end) -- best effort: ignore touch traps (may not replicate to the server)
            end
        end
    end
    conn = RS.Stepped:Connect(apply)
    return function()
        conn:Disconnect()
        for p, v in pairs(saved) do pcall(function() p.CanCollide = v p.CanTouch = true end) end
    end
end
local function flyTo(cf, speed)
    local r = root()
    if not r then return false end
    local stopNoclip = on.stealNoclip and startNoclip()
    local dist = (r.Position - cf.Position).Magnitude
    local t = game:GetService("TweenService"):Create(r,
        TweenInfo.new(math.max(0.05, dist / math.max(speed, 1)), Enum.EasingStyle.Linear), {CFrame = cf})
    local done = false
    t.Completed:Connect(function() done = true end)
    t:Play()
    local started = os.clock()
    local alive = true
    while not done and os.clock() - started < 60 do
        if not on.steal then t:Cancel() alive = false break end
        r.AssemblyLinearVelocity = Vector3.zero
        task.wait()
    end
    if stopNoclip then stopNoclip() end
    return alive
end
-- go up, across, then down (ground traps like mines, spikes, lava and waves are mostly near the floor)
local function flyRoute(pos, speed)
    local r = root()
    if not r then return false end
    if not on.stealHigh then return flyTo(CFrame.new(pos), speed) end
    local y = math.max(r.Position.Y, pos.Y) + stealAlt
    return flyTo(CFrame.new(r.Position.X, y, r.Position.Z), speed)
        and flyTo(CFrame.new(pos.X, y, pos.Z), speed)
        and flyTo(CFrame.new(pos), speed)
end
-- boxes stolen since the script started
local stolenLog, stolenParas = {}, {}
local function updateStolen()
    pcall(function()
        local counts, order = {}, {}
        for _, e in ipairs(stolenLog) do
            if not counts[e.type] then counts[e.type] = 0 order[#order + 1] = e.type end
            counts[e.type] = counts[e.type] + 1
        end
        local parts = {}
        for _, t in ipairs(order) do parts[#parts + 1] = t .. " x" .. counts[t] end
        if stolenParas.sum then
            stolenParas.sum:Set({Title = "Total stolen: " .. #stolenLog,
                Content = #parts > 0 and table.concat(parts, ", ") or "nothing yet"})
        end
        local lines = {}
        for i = #stolenLog, math.max(1, #stolenLog - 29), -1 do
            local e = stolenLog[i]
            lines[#lines + 1] = e.time .. "  " .. e.type .. "  (" .. e.name .. ")  - " .. e.area
        end
        if stolenParas.log then
            stolenParas.log:Set({Title = "Latest steals (newest first)",
                Content = #lines > 0 and table.concat(lines, "\n") or "nothing yet"})
        end
    end)
end
local function boxNames()
    local set = {}
    for _, c in ipairs({lp:FindFirstChild("Backpack"), lp.Character}) do
        if c then
            for _, t in ipairs(c:GetChildren()) do
                if t:IsA("Tool") and t.Name:find(CFG.BoxTool, 1, true) then set[t.Name] = (set[t.Name] or 0) + 1 end
            end
        end
    end
    return set
end
local function playerNear(pos, radius)
    for _, p in ipairs(Players:GetPlayers()) do
        local h = p ~= lp and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
        if h and (h.Position - pos).Magnitude <= radius then return true end
    end
    return false
end
-- how many box tools I am holding (backpack + hand)
local function boxCount()
    local n = 0
    for _, c in ipairs({lp:FindFirstChild("Backpack"), lp.Character}) do
        if c then
            for _, t in ipairs(c:GetChildren()) do
                if t:IsA("Tool") and t.Name:find(CFG.BoxTool, 1, true) then n = n + 1 end
            end
        end
    end
    return n
end
-- a point just outside the walls of the box's area (the chasers should not leave the map)
local function edgePoint(pos)
    refreshAreaBounds()
    for _, b in ipairs(areaBounds) do
        local p = b.cf:PointToObjectSpace(pos)
        local hx, hz = b.size.X / 2, b.size.Z / 2
        if math.abs(p.X) <= hx + 2 and math.abs(p.Z) <= hz + 2 then
            local dx, dz = hx - math.abs(p.X), hz - math.abs(p.Z)
            local margin = 14
            local lx, lz = p.X, p.Z
            if dx < dz then lx = (p.X >= 0 and 1 or -1) * (hx + margin)
            else lz = (p.Z >= 0 and 1 or -1) * (hz + margin) end
            local w = b.cf:PointToWorldSpace(Vector3.new(lx, p.Y, lz))
            return Vector3.new(w.X, pos.Y + 3, w.Z)
        end
    end
end
local function stealPick()
    local r = root()
    if not r then return end
    local best, bestRank, bestD
    for _, b in ipairs(allBoxes(on.stealDrops or on.dropsOnly)) do
        local pr = b.core:FindFirstChild("Steal")
        if pr and pr:IsA("ProximityPrompt") and pr.Enabled and (stealTried[b.model] or 0) < os.clock() - 8
            and (not on.dropsOnly or b.area == "Boss drop")
            and (b.area == "Boss drop" or SEL.stealAreas.isEmpty() or SEL.stealAreas.allowed(b.area))
            and (SEL.stealBoxes.isEmpty() or SEL.stealBoxes.allowed(b.type))
            and not (stealSkipNear and playerNear(b.core.Position, 30)) then
            local d = (b.core.Position - r.Position).Magnitude
            local rank = on.stealRare and (MOOD_RANK[b.type:lower()] or 0) or 0
            if not best or rank > bestRank or (rank == bestRank and d < bestD) then
                best, bestRank, bestD = {model = b.model, core = b.core, prompt = pr, area = b.area, type = b.type}, rank, d
            end
        end
    end
    return best
end
local function holdPrompt(pr)
    pcall(function() pr:InputHoldBegin() end)
    task.wait(pr.HoldDuration + 0.2)
    pcall(function() pr:InputHoldEnd() end)
    if fireproximityprompt then pcall(fireproximityprompt, pr) end
    task.wait(0.4)
end
-- the boss arena is its own place: boxes dropped there are picked up, then I leave through BossExit
local function arenaExit()
    local m = workspace:FindFirstChild("BossExit")
    if not m then return end
    local part = m:FindFirstChild("Doorway") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
    local pr = (part and part:FindFirstChildWhichIsA("ProximityPrompt", true)) or m:FindFirstChildWhichIsA("ProximityPrompt", true)
    return part, pr
end
local dropPending = false
task.spawn(function()
    while task.wait(0.5) do
        if on.steal then
            pcall(function()
                local pick = stealPick()
                if not pick then
                    if dropPending then
                        dropPending = false
                        local part, pr = arenaExit()
                        if on.autoLeave and part and pr then
                            flyTo(CFrame.new(part.Position + Vector3.new(0, 3, 0)), stealSpeed)
                            holdPrompt(pr) -- "Leave": takes me out of the arena
                            task.wait(3)
                        end
                    end
                    return
                end
                stealTried[pick.model] = os.clock()
                local spd = speedFor(pick.area)
                local isDrop = pick.area == "Boss drop"
                local go = isDrop and function(p, sp) return flyTo(CFrame.new(p), sp) end or flyRoute
                local before, namesBefore = boxCount(), boxNames()
                local function got() return boxCount() > before or not pick.model.Parent end
                local ep = on.stealEdge and edgePoint(pick.core.Position)
                if ep then
                    -- wait outside the walls and try the prompt from there first
                    if not go(ep, spd) then return end
                    holdPrompt(pick.prompt)
                end
                if not got() then
                    if not go(pick.core.Position + Vector3.new(0, 3, 0), spd) then return end
                    holdPrompt(pick.prompt)
                end
                if ep then flyRoute(ep, spd) end -- leave the area first
                if not got() then
                    -- got hit / box not obtained: do NOT fly home empty-handed
                    Rayfield:Notify({Title = "Auto steal", Content = "Missed " .. pick.type .. " (hit or taken). Next box...", Duration = 3})
                    return
                end
                local nm
                for n, c in pairs(boxNames()) do if c > (namesBefore[n] or 0) then nm = n end end
                stolenLog[#stolenLog + 1] = {type = pick.type, area = pick.area, name = nm or (pick.type .. " Verity Box"),
                    time = os.date("%H:%M:%S")}
                updateStolen()
                if isDrop then dropPending = true task.wait(0.2) return end -- keep picking up, leave when none are left
                local o = deliverPos(on.stealSpawn)
                if o then flyRoute(o.Position + Vector3.new(0, 5, 0), spd) end
                task.wait(0.5)
            end)
        end
    end
end)

-- ===== CUSTOM: auto steal on foot (own WalkSpeed, no tween), dodges traps, noclip =====
on.custom, on.customDodge, on.customNoclip, on.customRare, on.customSkip = false, true, true, true, true
local hazardWords = {"landmine", "mine", "spike", "tsunami", "wave", "lava", "volcano", "magma", "fireball",
    "meteor", "trap", "hazard", "killbrick", "kill"}
local extraWords = {}
local hazards, hazardAt = {}, 0
local function hazardMatch(name)
    name = name:lower()
    for _, w in ipairs(hazardWords) do if name:find(w, 1, true) then return w end end
    for _, w in ipairs(extraWords) do if name:find(w, 1, true) then return w end end
end
local function refreshHazards(force)
    if not force and os.clock() - hazardAt < 3 then return end
    hazardAt = os.clock()
    table.clear(hazards)
    local char = lp.Character
    local br = workspace:FindFirstChild("BoxRuntime")
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BasePart") and hazardMatch(d.Name) and not (char and d:IsDescendantOf(char))
            and not (br and d:IsDescendantOf(br)) then
            hazards[#hazards + 1] = d
        end
    end
end
local function humanoid()
    local c = lp.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end
local customStatusPara
local function customStatus(msg)
    if customStatusPara then pcall(function() customStatusPara:Set({Title = "Status", Content = msg}) end) end
end
-- walk (with my own WalkSpeed) to a spot, stepping around trap parts. Returns true when I arrived.
local function walkTo(pos, stop, timeout)
    local hum = humanoid()
    if not (hum and root()) then return false end
    local stopNoclip = on.customNoclip and startNoclip()
    local t0, arrived = os.clock(), false
    local chk, chkDist, manualUntil, lastStep = os.clock(), nil, 0, nil
    while (on.custom or on.bossFight or on.bossEnter or on.joining) and os.clock() - t0 < timeout do
        local r = root()
        hum = humanoid()
        if not (r and hum) or hum.Health <= 0 then break end
        local to = Vector3.new(pos.X - r.Position.X, 0, pos.Z - r.Position.Z)
        local dist = to.Magnitude
        if dist <= stop then arrived = true break end
        local dir = to / dist
        chkDist = chkDist or dist
        -- walls / structures: look ahead and turn toward whichever side is free
        if on.customAvoid and dist > 12 then
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {lp.Character, workspace:FindFirstChild("BoxRuntime")}
            params.RespectCanCollide = true
            local origin = r.Position + Vector3.new(0, 1, 0)
            local len = math.clamp(hum.WalkSpeed * 0.08, 14, 60)
            local function blocked(d) return workspace:Raycast(origin, d * len, params) end
            if blocked(dir) then
                for _, ang in ipairs({35, -35, 70, -70, 110, -110, 160}) do
                    local d = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(ang)):VectorToWorldSpace(dir)
                    if not blocked(d) then dir = d break end
                end
            end
        end
        if on.customDodge then
            refreshHazards()
            local push = Vector3.zero
            for _, h in ipairs(hazards) do
                if h.Parent then
                    local away = Vector3.new(r.Position.X - h.Position.X, 0, r.Position.Z - h.Position.Z)
                    local rad = math.clamp(math.max(h.Size.X, h.Size.Z) / 2, 3, 60) + 12
                    local d = away.Magnitude
                    if d < rad and d > 0.01 then
                        push = push + away.Unit * ((rad - d) / rad) * (dist < 15 and 1.2 or 3)
                    end
                end
            end
            local v = dir + push
            if v.Magnitude > 0.01 then dir = v.Unit end
        end
        -- aim far ahead so a fast WalkSpeed never reaches the aim point between two checks (this made the walk
        -- slower than my real speed); aim exactly at the spot once it is close so I do not overshoot
        hum:MoveTo(r.Position + dir * math.min(dist, 150))
        local now = os.clock()
        if now - chk >= 1.5 then
            -- stuck (a wall, or MoveTo does nothing): jump and step along by hand at my own WalkSpeed for a moment
            if chkDist - dist < 3 and now >= manualUntil then
                manualUntil = now + 2
                hum.Jump = true
                customStatus("Stuck, pushing through at WalkSpeed " .. math.floor(hum.WalkSpeed))
            end
            chk, chkDist = now, dist
        end
        if now < manualUntil then
            local dt = math.clamp(now - (lastStep or now), 0, 0.2)
            lastStep = now
            r.CFrame = r.CFrame + dir * math.min(math.max(hum.WalkSpeed, 8) * dt, dist)
            task.wait()
        else
            task.wait(0.1)
        end
    end
    local h2 = humanoid()
    local r2 = root()
    if h2 and r2 then h2:MoveTo(r2.Position) end
    if stopNoclip then stopNoclip() end
    return arrived
end
local function customPick()
    local r = root()
    if not r then return end
    local best, bestRank, bestD
    for _, b in ipairs(allBoxes(on.customDrops or on.dropsOnly)) do
        local pr = b.core:FindFirstChild("Steal")
        if pr and pr:IsA("ProximityPrompt") and pr.Enabled and (stealTried[b.model] or 0) < os.clock() - 8
            and (not on.dropsOnly or b.area == "Boss drop")
            and (b.area == "Boss drop" or SEL.customAreas.isEmpty() or SEL.customAreas.allowed(b.area))
            and (SEL.customBoxes.isEmpty() or SEL.customBoxes.allowed(b.type))
            and not (on.customSkip and playerNear(b.core.Position, 30)) then
            local d = (b.core.Position - r.Position).Magnitude
            local rank = on.customRare and (MOOD_RANK[b.type:lower()] or 0) or 0
            if not best or rank > bestRank or (rank == bestRank and d < bestD) then
                best, bestRank, bestD = {model = b.model, core = b.core, prompt = pr, area = b.area, type = b.type}, rank, d
            end
        end
    end
    return best
end
-- the game tells my client when I pick up / drop a box (Remotes.CarryChanged); remember when and what
local lastCarry
task.spawn(function()
    pcall(function()
        local ev = RepS:WaitForChild("Remotes", 10):WaitForChild("CarryChanged", 10)
        ev.OnClientEvent:Connect(function(...)
            local parts = {}
            for _, v in ipairs({...}) do parts[#parts + 1] = typeof(v) == "Instance" and v.Name or tostring(v) end
            lastCarry = {t = os.clock(), text = table.concat(parts, ",")}
        end)
    end)
end)
-- hold the prompt, then check for the pickup every 0.05s (up to 0.3s) so the run home starts right away
local function quickSteal(pr, check)
    pcall(function() pr:InputHoldBegin() end)
    task.wait(pr.HoldDuration + 0.05)
    pcall(function() pr:InputHoldEnd() end)
    if fireproximityprompt then pcall(fireproximityprompt, pr) end
    local t = os.clock()
    while os.clock() - t < 0.3 do
        if check() then return true end
        task.wait(0.05)
    end
    return check()
end
-- attribute snapshot of me and my character (used to show what changes when a box is picked up)
local function attrSnap()
    local snap = {}
    for _, o in ipairs({lp, lp.Character}) do
        if o then
            for k, v in pairs(o:GetAttributes()) do
                if not tostring(k):find("Advanced") and k ~= "SanctionedTeleportUntil" then snap[o.Name .. "@" .. k] = tostring(v) end
            end
        end
    end
    return snap
end
local function attrDiff(a, b)
    local out = {}
    for k, v in pairs(b) do if a[k] ~= v then out[#out + 1] = k .. "=" .. tostring(a[k]) .. "->" .. v end end
    for k, v in pairs(a) do if b[k] == nil then out[#out + 1] = k .. " removed" end end
    return #out > 0 and table.concat(out, ", "):sub(1, 140) or "no attribute change"
end
local function customWhy()
    local total, prompt, area, var, near = 0, 0, 0, 0, 0
    for _, b in ipairs(allBoxes(on.customDrops or on.dropsOnly)) do
        total = total + 1
        local pr = b.core:FindFirstChild("Steal")
        if pr and pr:IsA("ProximityPrompt") and pr.Enabled then
            prompt = prompt + 1
            if b.area == "Boss drop" or SEL.customAreas.isEmpty() or SEL.customAreas.allowed(b.area) then
                area = area + 1
                if SEL.customBoxes.isEmpty() or SEL.customBoxes.allowed(b.type) then
                    var = var + 1
                    if on.customSkip and playerNear(b.core.Position, 30) then near = near + 1 end
                end
            end
        end
    end
    return "No box to steal. Boxes on map: " .. total .. ", stealable: " .. prompt .. ", in chosen areas: " .. area
        .. ", matching variant: " .. var .. ", skipped (player near): " .. near
end
local customDropPending = false
task.spawn(function()
    local lastMsg = ""
    while task.wait(0.5) do
        if on.custom then
            local ok, err = pcall(function()
                local pick = customPick()
                if not pick then
                    if customDropPending then
                        customDropPending = false
                        local part, pr = arenaExit()
                        if on.autoLeave and part and pr then
                            customStatus("No more boss drops, leaving the arena")
                            if walkTo(part.Position, 6, 90) then holdPrompt(pr) task.wait(3) end
                            return
                        end
                    end
                    customStatus(customWhy())
                    return
                end
                stealTried[pick.model] = os.clock()
                local before, namesBefore = boxCount(), boxNames()
                local origPos = pick.core.Position
                customStatus("Walking to " .. pick.type .. " in " .. pick.area)
                if not walkTo(pick.core.Position, 6, 90) then
                    customStatus("Could not reach the box (timeout), trying another")
                    return
                end
                customStatus("Stealing " .. pick.type)
                local tHold = os.clock()
                local snapBefore = attrSnap()
                local function check()
                    local carried = lastCarry and lastCarry.t >= tHold - 0.5
                    local moved = pick.model.Parent and pick.core.Parent and (pick.core.Position - origPos).Magnitude > 5
                    return boxCount() > before or not pick.model.Parent or moved or not pick.prompt.Enabled or carried
                end
                local got = quickSteal(pick.prompt, check)
                local info = "boxes " .. before .. "->" .. boxCount() .. ", carry event: "
                    .. (lastCarry and lastCarry.text or "none") .. ", " .. attrDiff(snapBefore, attrSnap())
                -- ALWAYS deliver first: even when pickup was not detected, go to base before any other box
                local hum0 = humanoid()
                if not (hum0 and hum0.Health > 0) then customStatus("I died, restarting") return end
                local o = deliverPos(on.customSpawn)
                if got then task.spawn(function() -- log it while I am already running
                    local nm
                    for n, c in pairs(boxNames()) do if c > (namesBefore[n] or 0) then nm = n end end
                    stolenLog[#stolenLog + 1] = {type = pick.type, area = pick.area,
                        name = nm or (pick.type .. " Verity Box"), time = os.date("%H:%M:%S")}
                    updateStolen()
                end) end
                if got and pick.area == "Boss drop" then
                    customDropPending = true
                    customStatus("Picked up a boss drop (" .. pick.type .. "), next one...")
                    return
                end
                customStatus((got and "Got " or "Not sure I got ") .. pick.type .. ", running to " .. (on.customSpawn and "spawn" or "my base") .. " (" .. info .. ")")
                if o then
                    if not walkTo(o.Position, 10, 120) then customStatus("Could not reach the drop-off (timeout)") end
                else
                    customStatus("Could not find the spawn or my base")
                end
            end)
            if not ok and tostring(err) ~= lastMsg then
                lastMsg = tostring(err)
                customStatus("Error: " .. lastMsg)
                Rayfield:Notify({Title = "Custom steal error", Content = lastMsg:sub(1, 120), Duration = 6})
            end
        end
    end
end)

-- ===== BOSS FIGHT: auto hit the boss + step away from incoming attacks (best guess, needs the debug dump) =====
on.bossFight, on.bossDodge, on.bossEquip = false, true, true
local bossRange = 8
local attackWords = {"attack", "warning", "telegraph", "hitbox", "projectile", "shockwave", "slam", "laser",
    "fireball", "meteor", "bullet", "missile", "aoe", "danger", "explosion", "beam", "spike", "wave",
    "ring", "circle", "zone", "marker", "indicator"}
local attackExtra = {}
-- the game announces every boss attack to my client: remember where it will land
local dangerZones, eventLog = {}, {}
local DANGER = {BossTnt = 32, BossBomb = 24, BossSlam = 30, BossDive = 32, BossNuke = 70, BossSpin = 26,
    BossCharge = 22, BossChargeWarn = 22, BossBlink = 26}
task.spawn(function()
    local remotes = RepS:WaitForChild("Remotes", 10)
    if not remotes then return end
    for name, radius in pairs(DANGER) do
        local ev = remotes:FindFirstChild(name)
        if ev and ev:IsA("RemoteEvent") then
            ev.OnClientEvent:Connect(function(...)
                local pos, parts = nil, {}
                for _, v in ipairs({...}) do
                    local t = typeof(v)
                    if t == "Vector3" then pos = pos or v
                    elseif t == "CFrame" then pos = pos or v.Position
                    elseif t == "Instance" and v:IsA("BasePart") then pos = pos or v.Position
                    elseif t == "table" then
                        for _, x in pairs(v) do if typeof(x) == "Vector3" then pos = pos or x end end
                    end
                    parts[#parts + 1] = t == "Instance" and v.Name or t == "table" and "{...}" or tostring(v)
                end
                eventLog[#eventLog + 1] = os.date("%H:%M:%S") .. " " .. name .. "(" .. table.concat(parts, ", "):sub(1, 120) .. ")"
                if #eventLog > 60 then table.remove(eventLog, 1) end
                dangerZones[#dangerZones + 1] = {pos = pos, radius = radius, untilT = os.clock() + 3}
            end)
        end
    end
end)
local bossStatusPara
local function bossStatus(msg)
    if bossStatusPara then pcall(function() bossStatusPara:Set({Title = "Status", Content = msg}) end) end
end
local function isPlayerChar(m)
    for _, p in ipairs(Players:GetPlayers()) do if p.Character == m then return true end end
end
local bossCache, bossAt = nil, 0
local function findBoss()
    if bossCache and bossCache.Parent and os.clock() - bossAt < 1.5 then return bossCache end
    bossAt, bossCache = os.clock(), nil
    local rt = workspace:FindFirstChild("BossRuntime")
    local live = rt and rt:FindFirstChild("Boss")
    if live then bossCache = live return live end
    local r = root()
    if not r then return end
    local best, bd
    for _, m in ipairs(workspace:GetDescendants()) do
        if m:IsA("Model") and not isPlayerChar(m) then
            local n = m.Name:lower()
            if n:find("boss", 1, true) and not (n:find("portal", 1, true) or n:find("sign", 1, true)
                or n:find("display", 1, true) or n:find("reward", 1, true) or n:find("arena", 1, true)
                or n:find("exit", 1, true)) then
                local hum = m:FindFirstChildOfClass("Humanoid")
                local part = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
                if part and not (hum and hum.Health <= 0) then
                    local d = (part.Position - r.Position).Magnitude
                    if not bd or d < bd then best, bd = m, d end
                end
            end
        end
    end
    bossCache = best
    return best
end
local function attackMatch(name)
    name = name:lower()
    for _, w in ipairs(attackWords) do if name:find(w, 1, true) then return true end end
    for _, w in ipairs(attackExtra) do if name:find(w, 1, true) then return true end end
end
local attacks, attacksAt = {}, 0
local function refreshAttacks(boss, force)
    if not force and os.clock() - attacksAt < 0.6 then return end
    attacksAt = os.clock()
    table.clear(attacks)
    local char = lp.Character
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BasePart") and attackMatch(d.Name) and d.Size.Magnitude < 250
            and not (char and d:IsDescendantOf(char)) and not (boss and d:IsDescendantOf(boss)) then
            attacks[#attacks + 1] = d
        end
    end
end
task.spawn(function()
    while task.wait(0.1) do
        if on.bossFight then
            pcall(function()
                local r, hum = root(), humanoid()
                if not (r and hum) or hum.Health <= 0 then return end
                local boss = findBoss()
                if not boss then bossStatus("No boss found. Enter a boss fight first.") return end
                local bp = boss:FindFirstChild("VerityBall_Master") or boss:FindFirstChild("HumanoidRootPart") or boss.PrimaryPart or boss:FindFirstChildWhichIsA("BasePart", true)
                -- make sure the bat is in my hand
                local char = lp.Character
                local tool = char:FindFirstChildOfClass("Tool")
                if on.bossEquip and not (tool and tool.Name:lower():find("bat", 1, true)) then
                    local bag = lp:FindFirstChild("Backpack")
                    local bat
                    if bag then
                        for _, t in ipairs(bag:GetChildren()) do
                            if t:IsA("Tool") and t.Name:lower():find("bat", 1, true) then bat = t break end
                        end
                    end
                    if bat then pcall(function() hum:EquipTool(bat) end) tool = bat end
                end
                local to = Vector3.new(bp.Position.X - r.Position.X, 0, bp.Position.Z - r.Position.Z)
                local dist = to.Magnitude
                -- step away from incoming attacks
                local push = Vector3.zero
                if on.bossDodge then
                    refreshAttacks(boss)
                    for _, a in ipairs(attacks) do
                        if a.Parent then
                            local away = Vector3.new(r.Position.X - a.Position.X, 0, r.Position.Z - a.Position.Z)
                            local rad = math.clamp(math.max(a.Size.X, a.Size.Z) / 2, 4, 50) + 6
                            local d = away.Magnitude
                            if d < rad and d > 0.01 then push = push + away.Unit * ((rad - d) / rad) end
                        end
                    end
                end
                if on.bossDodge then
                    for i = #dangerZones, 1, -1 do
                        local z = dangerZones[i]
                        if os.clock() > z.untilT then
                            table.remove(dangerZones, i)
                        else
                            local c = z.pos or bp.Position
                            local away = Vector3.new(r.Position.X - c.X, 0, r.Position.Z - c.Z)
                            local d = away.Magnitude
                            if d < z.radius + 4 then
                                push = push + (d > 0.01 and away.Unit or Vector3.new(1, 0, 0)) * (((z.radius + 4) - d) / (z.radius + 4) + 0.5)
                            end
                        end
                    end
                end
                if on.bossDodge then
                    -- the boss jumps up and slams down: while it is in the air, get out from under it
                    local rp = RaycastParams.new()
                    rp.FilterDescendantsInstances = {boss, lp.Character}
                    rp.FilterType = Enum.RaycastFilterType.Exclude
                    local hit = workspace:Raycast(bp.Position, Vector3.new(0, -300, 0), rp)
                    local height = hit and (bp.Position.Y - hit.Position.Y) or 0
                    if (height > 8 or math.abs(bp.AssemblyLinearVelocity.Y) > 25) and dist < 40 and dist > 0.01 then
                        push = push - to.Unit * ((40 - dist) / 40 + 0.6)
                    end
                end
                if push.Magnitude > 0.2 then
                    hum:MoveTo(r.Position + push.Unit * 30)
                    bossStatus("Dodging an attack")
                elseif dist > bossRange then
                    hum:MoveTo(bp.Position - to.Unit * bossRange * 0.8)
                    bossStatus("Going to the boss (" .. math.floor(dist) .. " studs)")
                else
                    hum:MoveTo(r.Position)
                    bossStatus("Hitting the boss" .. (boss:GetAttribute("HP") and (" - HP " .. math.floor(boss:GetAttribute("HP")) .. "/" .. tostring(boss:GetAttribute("MaxHP"))) or ""))
                end
                if dist <= bossRange + 6 and dist > 0.5 then
                    r.CFrame = CFrame.lookAt(r.Position, Vector3.new(bp.Position.X, r.Position.Y, bp.Position.Z))
                    if tool then pcall(function() tool:Activate() end) end
                end
            end)
        end
    end
end)

-- choose which boss portal to enter (shows the boss and the speed needed), and walk in when it is open
on.bossEnter = false
local chosenPortal
local PORTAL_NAMES = {Normal = "BossPortal", High = "BossPortalHigh", Top = "BossPortalTop"}
local portalDD
local portalLabels, portalShort, portalBtns = {}, {}, {}
local function portalPos(key)
    local p = workspace:FindFirstChild(PORTAL_NAMES[key])
    if not p then return end
    return p:IsA("Model") and p:GetPivot().Position or (p:IsA("BasePart") and p.Position) or nil
end
local function portalOpen()
    if not (BossPortal and type(BossPortal.SignStateAt) == "function") then return nil end
    local ok, open = pcall(BossPortal.SignStateAt, workspace:GetServerTimeNow())
    return ok and open or false
end
local function portalOptions()
    local opts = {}
    local ok, slot = pcall(function()
        local now = workspace:GetServerTimeNow()
        return BossConfig.SlotIndex(now) + (BossPortal.SignStateAt(now) and 0 or 1)
    end)
    for b, t in ipairs(TIERS) do
        local clock, req = readTier(t)
        local name = "?"
        if ok and canPredict then
            local good, info = pcall(bossInfo, slot, b)
            if good and info and info.full then name = info.full end
        end
        local label = t.key .. ": " .. name .. " (needs " .. tostring(req or "?") .. ")"
        opts[#opts + 1] = label
        portalLabels[t.key] = label
        portalShort[t.key] = t.key .. "  -  " .. name .. " (" .. tostring(req or "?") .. ")"
    end
    return opts
end
task.spawn(function()
    task.wait(3)
    while task.wait(5) do
        if portalDD or next(portalBtns) then
            pcall(function()
                local opts = portalOptions()
                for key, btn in pairs(portalBtns) do
                    if portalShort[key] then pcall(function() btn:Set(portalShort[key]) end) end
                end
                if portalDD then
                    portalDD:Refresh(opts)
                    if chosenPortal and portalLabels[chosenPortal] then portalDD:Set({portalLabels[chosenPortal]}) end
                end
            end)
        end
    end
end)
local enterTried = 0
task.spawn(function()
    while task.wait(1) do
        if on.bossEnter and chosenPortal and os.clock() - enterTried > 25 then
            pcall(function()
                if findBoss() then return end -- already at a boss
                if portalOpen() ~= true then return end
                local pos = portalPos(chosenPortal)
                if not pos then return end
                enterTried = os.clock()
                bossStatus("Walking into the " .. chosenPortal .. " portal")
                walkTo(pos, 2, 60)
            end)
        end
    end
end)

local function tpToBox(m)
    local r = root()
    local core = m and m.Parent and (m:FindFirstChild("Core") or m.PrimaryPart)
    if not (r and core) then
        Rayfield:Notify({Title = "Boxes", Content = "That box is gone (night reset?)", Duration = 3})
        return
    end
    lastPos = r.CFrame
    moveTo(CFrame.new(core.Position + Vector3.new(0, 5, 0)))
end

local function refreshBoxMenu()
    local byArea = {}
    for _, b in ipairs(areaBoxes()) do
        byArea[b.area] = byArea[b.area] or {}
        table.insert(byArea[b.area], b)
    end
    for _, area in ipairs(LISTS.areas) do
        local dd = menuDD[area]
        if dd then
            local list = byArea[area] or {}
            table.sort(list, function(x, y)
                if x.type ~= y.type then return x.type < y.type end
                return x.model.Name < y.model.Name
            end)
            local count = {}
            for _, b in ipairs(list) do count[b.type] = (count[b.type] or 0) + 1 end
            local seen, labels, map = {}, {}, {}
            for _, b in ipairs(list) do
                seen[b.type] = (seen[b.type] or 0) + 1
                local label = count[b.type] > 1 and (b.type .. " #" .. seen[b.type]) or b.type
                labels[#labels + 1] = label
                map[label] = b.model
            end
            menuMap[area] = map
            local sig = table.concat(labels, ",")
            if sig ~= menuSig[area] then
                menuSig[area] = sig
                if #labels == 0 then labels = {"(no boxes)"} end
                menuSuppress = true
                pcall(function() dd:Refresh(labels) end)
                menuSuppress = false
            end
        end
    end
end

task.spawn(function()
    while task.wait(3) do pcall(refreshBoxMenu) end
end)

-- anti-AFK
on.afk = false
lp.Idled:Connect(function()
    if on.afk then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end)

-- re-run this script after server hops / rejoins
local loaderUrl = "https://raw.githubusercontent.com/ImHunter9192/StealAVerity/refs/heads/main/stela.lua"
local function loaderSrc() return 'loadstring(game:HttpGet("' .. loaderUrl .. '"))()' end
local queueFn = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
on.reexec = false
lp.OnTeleport:Connect(function()
    if on.reexec and queueFn then pcall(queueFn, loaderSrc()) end
end)

local function rayfieldGui()
    local roots = {game:GetService("CoreGui"), lp.PlayerGui}
    if gethui then table.insert(roots, 1, gethui()) end
    for _, root in ipairs(roots) do
        for _, g in ipairs(root:GetChildren()) do
            if g:IsA("ScreenGui") and g.Name:find("Rayfield") and g:FindFirstChild("Main") then return g end
        end
    end
end
local function rayfieldMain()
    local g = rayfieldGui()
    return g and g.Main
end

local Window = Rayfield:CreateWindow({
    Name = "Steal A Verity", LoadingTitle = "Steal A Verity", LoadingSubtitle = "by StanHub",
    ConfigurationSaving = {Enabled = true, FolderName = "StelaAVerity", FileName = "Config"},
    KeySystem = false,
})
local Main = Window:CreateTab("Main")

-- header: Verity face after the title + chroma "StanHub"
task.spawn(function()
    for _ = 1, 20 do
        task.wait(0.5)
        local ok = pcall(function()
            local g = rayfieldGui()
            local top = g.Main.Topbar
            local title = top:FindFirstChild("Title")
            if not title then error("no title") end
            if top:FindFirstChild("StanHub") then return end
            local x = title.Position.X.Offset + title.TextBounds.X + 8
            local face = Instance.new("ImageLabel")
            face.Name, face.BackgroundTransparency = "VerityFace", 1
            face.Image = "rbxassetid://139657139910728"
            face.AnchorPoint, face.Size = Vector2.new(0, 0.5), UDim2.fromOffset(22, 22)
            face.Position = UDim2.new(0, x, 0.5, 0)
            face.Parent = top
            local tag = Instance.new("TextLabel")
            tag.Name, tag.BackgroundTransparency = "StanHub", 1
            tag.Text, tag.Font, tag.TextSize = "StanHub", Enum.Font.GothamBold, 16
            tag.TextXAlignment = Enum.TextXAlignment.Left
            tag.AnchorPoint, tag.Size = Vector2.new(0, 0.5), UDim2.fromOffset(90, 22)
            tag.Position = UDim2.new(0, x + 28, 0.5, 0)
            tag.Parent = top
            task.spawn(function()
                while tag.Parent do
                    tag.TextColor3 = Color3.fromHSV((os.clock() * 0.35) % 1, 0.9, 1)
                    task.wait(0.05)
                end
            end)
        end)
        if ok then return end
    end
end)

-- blank space + a titled section between groups of features
local function group(tab, title, first)
    if not first then
        if not pcall(function() tab:CreateDivider() end) then pcall(function() tab:CreateSection(" ") end) end
    end
    tab:CreateSection(title)
end

local function toggle(tab, name, key, cb)
    return tab:CreateToggle({Name = name, CurrentValue = false, Flag = key,
        Callback = function(v) on[key] = v if cb then cb(v) end end})
end

group(Main, "Teleport", true)
Main:CreateButton({Name = "Go To My Treadmill", Callback = function() goTo(myTreadmill(), 4) end})
Main:CreateButton({Name = "Go To Admin Treadmill", Callback = function()
    local a = admin()
    if a then goTo(a, adminUp(a)) else Rayfield:Notify({Title = "Admin Treadmill", Content = "Not spawned", Duration = 3}) end
end})
group(Main, "Auto treadmill")
toggle(Main, "Auto Go To Treadmill", "tread")
toggle(Main, "Auto Go To Admin Treadmill", "admin")
group(Main, "Auto place verity boxes")
toggle(Main, "Auto Place Verity Boxes", "boxes")
on.tpPlace = true
Main:CreateToggle({Name = "Teleport to base while placing, then back", CurrentValue = true, Flag = "TpPlace",
    Callback = function(v) on.tpPlace = v end})
group(Main, "Box spot")
Main:CreateButton({Name = "Set Box Spot To Where I'm Standing", Callback = saveBoxSpot})
Main:CreateButton({Name = "Reset Box Spot (use base center)", Callback = function()
    boxSpot = nil
    pcall(function() if writefile then writefile("stela_boxspot.txt", "") end end)
    Rayfield:Notify({Title = "Box spot", Content = "Reset to base center", Duration = 3})
end})
group(Main, "Placing speed")
Main:CreateSlider({Name = "Box Spread Around Spot", Range = {0, 20}, Increment = 1, Suffix = " studs",
    CurrentValue = 6, Flag = "PlaceSpread", Callback = function(v) placeSpread = v end})
Main:CreateSlider({Name = "Place Delay", Range = {0.1, 5}, Increment = 0.1, Suffix = "s",
    CurrentValue = 0.5, Flag = "PlaceDelay", Callback = function(v) placeDelay = v end})



-- scrollable multi-select dropdown. A search bar + Select all / Clear all are injected at the top of the
-- opened list (they only show while the dropdown is open, because they live inside it).
local function addHeader(title, getDD, getCurrent, setCurrent)
    task.spawn(function()
        for _ = 1, 20 do
            task.wait(0.5)
            local ok = pcall(function()
                local g = rayfieldGui()
                local el
                for _, d in ipairs(g:GetDescendants()) do
                    if d.Name == title and d:IsA("Frame") and d:FindFirstChild("List") then el = d break end
                end
                if not el then error("no element") end
                local list = el.List
                if list:FindFirstChild("!SearchHeader") then return end
                local lay = list:FindFirstChildOfClass("UIListLayout")
                if lay then lay.SortOrder = Enum.SortOrder.LayoutOrder end
                pcall(function()
                    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
                    list.CanvasSize = UDim2.new(0, 0, 0, 0)
                end)
                local h = Instance.new("CanvasGroup") -- not a "Frame", so Rayfield's open/close loops skip it
                h.Name, h.LayoutOrder, h.BackgroundTransparency = "!SearchHeader", -100, 1
                h.Size = UDim2.new(1, -10, 0, 70)
                local box = Instance.new("TextBox")
                box.Size, box.Position = UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 2)
                box.BackgroundColor3, box.TextColor3 = Color3.fromRGB(45, 45, 52), Color3.new(1, 1, 1)
                box.PlaceholderText, box.PlaceholderColor3 = "Search...", Color3.fromRGB(150, 150, 160)
                box.Text, box.ClearTextOnFocus, box.TextSize = "", false, 14
                box.Font, box.TextXAlignment = Enum.Font.Gotham, Enum.TextXAlignment.Left
                Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
                local pad = Instance.new("UIPadding", box)
                pad.PaddingLeft = UDim.new(0, 8)
                box.Parent = h
                local function visibleNames()
                    local out = {}
                    for _, f in ipairs(list:GetChildren()) do
                        if f:IsA("GuiObject") and f.Name ~= "!SearchHeader" and f.Name ~= "Template"
                            and f.Name ~= "Placeholder" and f.Visible then out[#out + 1] = f.Name end
                    end
                    return out
                end
                box:GetPropertyChangedSignal("Text"):Connect(function()
                    local q = box.Text:lower()
                    for _, f in ipairs(list:GetChildren()) do
                        if f:IsA("GuiObject") and f.Name ~= "!SearchHeader" and f.Name ~= "Template"
                            and f.Name ~= "Placeholder" and f.Name ~= "UIListLayout" then
                            f.Visible = q == "" or f.Name:lower():find(q, 1, true) ~= nil
                        end
                    end
                end)
                local function btn(text, x, fn)
                    local b = Instance.new("TextButton")
                    b.Size, b.Position = UDim2.new(0.5, -3, 0, 28), UDim2.new(x, x == 0 and 0 or 3, 0, 38)
                    b.BackgroundColor3, b.TextColor3 = Color3.fromRGB(60, 60, 70), Color3.new(1, 1, 1)
                    b.Text, b.TextSize, b.Font = text, 13, Enum.Font.GothamBold
                    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
                    b.MouseButton1Click:Connect(fn)
                    b.Parent = h
                end
                -- click the real option rows (this never closes the dropdown, unlike dd:Set)
                local function clickOpt(f)
                    local b = f:FindFirstChild("Interact")
                    if b and getconnections then
                        for _, c in ipairs(getconnections(b.MouseButton1Click)) do pcall(function() c:Fire() end) end
                        return true
                    end
                end
                local function bulk(wantOn)
                    local have = {}
                    for _, n in ipairs(getCurrent()) do have[n] = true end
                    local todo = {}
                    for _, f in ipairs(list:GetChildren()) do
                        if f:IsA("GuiObject") and f.Name ~= "!SearchHeader" and f.Name ~= "Template"
                            and f.Name ~= "Placeholder" and f.Visible and f:FindFirstChild("Interact")
                            and (have[f.Name] == true) ~= wantOn then todo[#todo + 1] = f end
                    end
                    local ok = true
                    for _, f in ipairs(todo) do
                        if not clickOpt(f) then ok = false break end
                        task.wait()
                    end
                    if not ok then
                        -- fallback: set the whole selection, then reopen the dropdown if it closed
                        local merged, gone = {}, {}
                        for _, f in ipairs(todo) do gone[f.Name] = true end
                        if wantOn then
                            merged = copy(getCurrent())
                            for n in pairs(gone) do merged[#merged + 1] = n end
                        else
                            for _, n in ipairs(getCurrent()) do if not gone[n] then merged[#merged + 1] = n end end
                        end
                        setCurrent(merged)
                        pcall(function() getDD():Set(copy(merged)) end)
                        task.wait(0.15)
                        if not list.Visible then
                            local ib = el:FindFirstChild("Interact")
                            if ib and getconnections then
                                for _, c in ipairs(getconnections(ib.MouseButton1Click)) do pcall(function() c:Fire() end) end
                            end
                        end
                    end
                end
                btn("Select all", 0, function() bulk(true) end)
                btn("Clear all", 0.5, function() bulk(false) end)
                h.Parent = list
                -- highlight: picked options = white, not picked = normal gray
                task.spawn(function()
                    while list.Parent do
                        if not list.Visible then task.wait(0.3) continue end
                        local on_ = {}
                        for _, n in ipairs(getCurrent()) do on_[n] = true end
                        for _, f in ipairs(list:GetChildren()) do
                            if f:IsA("GuiObject") and f.Name ~= "!SearchHeader" and f.Name ~= "Template"
                                and f.Name ~= "Placeholder" then
                                local picked = on_[f.Name] == true
                                pcall(function()
                                    f.BackgroundColor3 = picked and Color3.fromRGB(245, 245, 245) or Color3.fromRGB(38, 38, 44)
                                    f.BackgroundTransparency = 0
                                    local t = f:FindFirstChild("Title")
                                    if t then t.TextColor3 = picked and Color3.fromRGB(20, 20, 24) or Color3.fromRGB(235, 235, 240) end
                                end)
                            end
                        end
                        task.wait(0.15)
                    end
                end)
            end)
            if ok then return end
        end
    end)
end

local function selectPicker(tab, title, key, flag, sel, startEmpty)
    local current, dd = startEmpty and {} or copy(LISTS[key]), nil
    if startEmpty then sel.set({}) end
    dd = tab:CreateDropdown({Name = title, Options = copy(LISTS[key]),
        CurrentOption = startEmpty and {} or copy(LISTS[key]), MultipleOptions = true, Flag = flag,
        Callback = function(o)
            if type(o) == "string" then o = {o} end
            local clean = {}
            for _, n in ipairs(o) do if findOpt(key, n) then clean[#clean + 1] = n end end
            current = clean
            sel.set(clean)
        end})
    addHeader(title, function() return dd end, function() return current end,
        function(l) current = l sel.set(l) end)
end

local Stats = Window:CreateTab("Stats")
group(Stats, "Session", true)
statLabels.timer = Stats:CreateLabel("Script running: 00:00:00")
group(Stats, "Change since you executed the script")
statLabels.money = Stats:CreateLabel("Money: loading...")
statLabels.speed = Stats:CreateLabel("Speed: loading...")
group(Stats, "Rates")
statLabels.sps = Stats:CreateLabel("Speed/s: loading...")
statLabels.mps = Stats:CreateLabel("Money/s: loading...")


local Visuals = Window:CreateTab("Visuals")
group(Visuals, "ESP switches", true)
toggle(Visuals, "ESP by area (on/off)", "espArea")
toggle(Visuals, "ESP by mood (on/off)", "espMood")
group(Visuals, "Labels")
toggle(Visuals, "Show box labels", "espLabel", function() espRestyle() end)
Visuals:CreateToggle({Name = "Include area name in label", CurrentValue = false, Flag = "EspShowArea",
    Callback = function(v) espShowArea = v espRestyle() end})
Visuals:CreateSlider({Name = "Label text size", Range = {8, 24}, Increment = 1, CurrentValue = 13,
    Flag = "EspTextSize", Callback = function(v) espTextSize = v espRestyle() end})
Visuals:CreateSlider({Name = "Label range (studs)", Range = {20, 500}, Increment = 10, CurrentValue = 100,
    Flag = "EspRange", Callback = function(v) espRange = v espRestyle() end})
group(Visuals, "What to highlight")
selectPicker(Visuals, "ESP areas", "areas", "EspAreas", SEL.espAreas)
selectPicker(Visuals, "ESP moods", "boxes", "EspTypes", SEL.espBoxes)
group(Visuals, "ESP colors")
Visuals:CreateToggle({Name = "Use one color for all boxes", CurrentValue = false, Flag = "EspSingle",
    Callback = function(v) espSingle = v end})
Visuals:CreateColorPicker({Name = "One color", Color = espColor, Flag = "EspColor",
    Callback = function(c) espColor = c end})
Visuals:CreateSlider({Name = "ESP fill transparency", Range = {0, 0.95}, Increment = 0.05, CurrentValue = 0.6,
    Flag = "EspTransp", Callback = function(v) espTransp = v end})
local colorType, pickerReady = LISTS.boxes[1], false
task.delay(3, function() pickerReady = true end) -- ignore the color picker's startup callback
Visuals:CreateDropdown({Name = "Pick a box type to recolor", Options = copy(LISTS.boxes),
    CurrentOption = {LISTS.boxes[1]}, MultipleOptions = false,
    Callback = function(o) colorType = type(o) == "table" and o[1] or o end})
Visuals:CreateColorPicker({Name = "Color for that box type", Color = Color3.fromRGB(255, 255, 255),
    Callback = function(c) if pickerReady and colorType then typeColors[colorType] = c end end})
Visuals:CreateButton({Name = "Reset per-type colors", Callback = function() table.clear(typeColors) end})
group(Visuals, "Tools")
Visuals:CreateButton({Name = "Scan Boxes (copy report)", Callback = scanReport})

local BoxesTab = Window:CreateTab("Boxes")
local stealTog, customTog, fightTog
group(BoxesTab, "Auto steal  -  main", true)
stealTog = toggle(BoxesTab, "Auto steal boxes from the maps", "steal")
BoxesTab:CreateSlider({Name = "Fly speed", Range = {10, 2000}, Increment = 10, Suffix = " studs/s",
    CurrentValue = 400, Flag = "StealSpeed", Callback = function(v) stealSpeed = v end})
selectPicker(BoxesTab, "Steal areas (empty = all)", "areas", "StealAreas2", SEL.stealAreas, true)
selectPicker(BoxesTab, "Steal moods (empty = all)", "boxes", "StealTypes2", SEL.stealBoxes, true)
BoxesTab:CreateToggle({Name = "Bring stolen boxes to spawn (off = my base)", CurrentValue = true, Flag = "StealSpawn",
    Callback = function(v) on.stealSpawn = v end})
BoxesTab:CreateToggle({Name = "Also steal boss drops (boxes outside the areas)", CurrentValue = true, Flag = "StealDrops",
    Callback = function(v) on.stealDrops = v end})
BoxesTab:CreateToggle({Name = "Steal the rarest mood first", CurrentValue = true, Flag = "StealRare",
    Callback = function(v) on.stealRare = v end})

group(BoxesTab, "Auto steal  -  safety")
BoxesTab:CreateToggle({Name = "Noclip while flying", CurrentValue = true, Flag = "StealNoclip",
    Callback = function(v) on.stealNoclip = v end})
BoxesTab:CreateToggle({Name = "Fly high above the ground (avoids ground traps)", CurrentValue = true,
    Flag = "StealHigh", Callback = function(v) on.stealHigh = v end})
BoxesTab:CreateSlider({Name = "Flight height", Range = {10, 300}, Increment = 5, Suffix = " studs",
    CurrentValue = 60, Flag = "StealAlt", Callback = function(v) stealAlt = v end})
BoxesTab:CreateToggle({Name = "Wait outside the map walls before going in", CurrentValue = true,
    Flag = "StealEdge", Callback = function(v) on.stealEdge = v end})
BoxesTab:CreateToggle({Name = "Skip boxes with a player nearby", CurrentValue = true, Flag = "StealSkipNear",
    Callback = function(v) stealSkipNear = v end})

group(BoxesTab, "Auto steal  -  speed per area")
BoxesTab:CreateToggle({Name = "Use a different fly speed per area", CurrentValue = false, Flag = "StealPerArea",
    Callback = function(v) on.stealPerArea = v end})
local areaSpeedSlider
local speedArea = LISTS.areas[1]
BoxesTab:CreateDropdown({Name = "Pick area to set its speed", Options = copy(LISTS.areas),
    CurrentOption = {speedArea}, MultipleOptions = false,
    Callback = function(o)
        speedArea = type(o) == "table" and o[1] or o
        if areaSpeedSlider then pcall(function() areaSpeedSlider:Set(stealAreaSpeed[speedArea] or stealSpeed) end) end
    end})
areaSpeedSlider = BoxesTab:CreateSlider({Name = "Fly speed for that area", Range = {10, 2000}, Increment = 10,
    Suffix = " studs/s", CurrentValue = 400, Flag = "StealAreaSpeedValue",
    Callback = function(v) if speedArea then stealAreaSpeed[speedArea] = v end end})

group(BoxesTab, "Teleport to a box")
BoxesTab:CreateToggle({Name = "Smooth tween (instead of instant teleport)", CurrentValue = false,
    Flag = "BoxTween", Callback = function(v) on.tween = v end})
BoxesTab:CreateSlider({Name = "Tween speed", Range = {20, 400}, Increment = 10, Suffix = " studs/s",
    CurrentValue = 80, Flag = "BoxTweenSpeed", Callback = function(v) tweenSpeed = v end})
BoxesTab:CreateButton({Name = "Go back to where I was", Callback = function()
    local r = root()
    if r and lastPos then
        moveTo(lastPos)
    else
        Rayfield:Notify({Title = "Boxes", Content = "No saved position yet", Duration = 3})
    end
end})
BoxesTab:CreateButton({Name = "Refresh boxes now", Callback = function() pcall(refreshBoxMenu) end})

group(BoxesTab, "Boxes on the map  -  tap an area, then tap a box")
for _, area in ipairs(LISTS.areas) do
    menuDD[area] = BoxesTab:CreateDropdown({Name = area, Options = {"(loading)"}, CurrentOption = {},
        MultipleOptions = false,
        Callback = function(o)
            if menuSuppress then return end
            local label = type(o) == "table" and o[1] or o
            local m = menuMap[area] and menuMap[area][label]
            if m then
                tpToBox(m)
                task.defer(function()
                    menuSuppress = true
                    pcall(function() menuDD[area]:Set({}) end)
                    menuSuppress = false
                end)
            end
        end})
end

local CustomTab = Window:CreateTab("Custom")
group(CustomTab, "Auto steal on foot (uses your own walk speed)", true)
customTog = toggle(CustomTab, "Custom auto steal", "custom", function(v) if not v then customStatus("Off") end end)
customStatusPara = CustomTab:CreateParagraph({Title = "Status", Content = "Off"})
selectPicker(CustomTab, "Area (empty = all areas)", "areas", "CustomAreas", SEL.customAreas, true)
selectPicker(CustomTab, "Variant (empty = all variants)", "boxes", "CustomVariants", SEL.customBoxes, true)
CustomTab:CreateToggle({Name = "Bring stolen boxes to spawn (off = my base)", CurrentValue = true, Flag = "CustomSpawn",
    Callback = function(v) on.customSpawn = v end})
CustomTab:CreateToggle({Name = "Also steal boss drops (boxes outside the areas)", CurrentValue = true, Flag = "CustomDrops",
    Callback = function(v) on.customDrops = v end})
CustomTab:CreateToggle({Name = "Steal the rarest variant first", CurrentValue = true, Flag = "CustomRare",
    Callback = function(v) on.customRare = v end})
CustomTab:CreateToggle({Name = "Skip boxes with a player nearby", CurrentValue = true, Flag = "CustomSkip",
    Callback = function(v) on.customSkip = v end})

group(CustomTab, "Safety")
CustomTab:CreateToggle({Name = "Dodge traps (mines, spikes, lava, waves...)", CurrentValue = true, Flag = "CustomDodge",
    Callback = function(v) on.customDodge = v end})
CustomTab:CreateToggle({Name = "Avoid structures (walk around walls)", CurrentValue = true, Flag = "CustomAvoid",
    Callback = function(v) on.customAvoid = v end})
CustomTab:CreateToggle({Name = "Noclip (walk through builds and walls)", CurrentValue = true, Flag = "CustomNoclip",
    Callback = function(v) on.customNoclip = v end})
CustomTab:CreateInput({Name = "Extra trap names (comma separated)", PlaceholderText = "e.g. bomb, laser",
    RemoveTextAfterFocusLost = false, Flag = "CustomExtraTraps", Callback = function(t)
        extraWords = {}
        for w in (t or ""):gmatch("[^,]+") do
            w = trim(w):lower()
            if w ~= "" then extraWords[#extraWords + 1] = w end
        end
        hazardAt = 0
    end})
CustomTab:CreateButton({Name = "Scan trap parts (copy list)", Callback = function()
    refreshHazards(true)
    local counts, order = {}, {}
    for _, h in ipairs(hazards) do
        local key = h.Name .. " (" .. (h.Parent and h.Parent.Name or "?") .. ")"
        if not counts[key] then counts[key] = 0 order[#order + 1] = key end
        counts[key] = counts[key] + 1
    end
    local lines = {}
    for _, k in ipairs(order) do lines[#lines + 1] = k .. " x" .. counts[k] end
    local text = #lines > 0 and table.concat(lines, "\n"):sub(1, 6000) or "no trap parts found"
    if setclipboard then setclipboard(text) end
    Rayfield:Notify({Title = "Traps", Content = #hazards .. " trap parts found (list copied)", Duration = 4})
end})

local FightTab = Window:CreateTab("Boss Fight")
group(FightTab, "Full auto (one switch)", true)
local fullMode = "Flying (fast)"
FightTab:CreateDropdown({Name = "Pick up the drops by", Options = {"Flying (fast)", "Walking"},
    CurrentOption = {"Flying (fast)"}, MultipleOptions = false, Callback = function(o)
        fullMode = type(o) == "table" and o[1] or o
    end})
FightTab:CreateToggle({Name = "FULL AUTO: fight + dodge + pick up drops + leave", CurrentValue = false,
    Flag = "BossFullAuto", Callback = function(v)
        on.dropsOnly = v -- the pick-up part only takes the boss drops while this is on
        local walking = tostring(fullMode):find("Walk", 1, true) ~= nil
        pcall(function() fightTog:Set(v) end)
        if walking then
            pcall(function() customTog:Set(v) end)
            if v then pcall(function() stealTog:Set(false) end) end
        else
            pcall(function() stealTog:Set(v) end)
            if v then pcall(function() customTog:Set(false) end) end
        end
        if not v then
            pcall(function() stealTog:Set(false) end)
            pcall(function() customTog:Set(false) end)
        end
    end})
group(FightTab, "Join a boss portal (tap = go in now)")
local function joinPortal(key)
    local pos = portalPos(key)
    if not pos then Rayfield:Notify({Title = "Boss portal", Content = "Portal not found", Duration = 3}) return end
    if portalOpen() ~= true then
        Rayfield:Notify({Title = "Boss portal", Content = key .. " portal is closed right now", Duration = 3})
        return
    end
    task.spawn(function()
        on.joining = true
        walkTo(pos, 2, 60)
        on.joining = false
    end)
end
for _, t in ipairs(TIERS) do
    portalBtns[t.key] = FightTab:CreateButton({Name = t.key .. "  -  loading...", Callback = function() joinPortal(t.key) end})
end
FightTab:CreateToggle({Name = "Leave the arena after picking up the drops", CurrentValue = false, Flag = "BossAutoLeave",
    Callback = function(v) on.autoLeave = v end})
group(FightTab, "Auto boss fight (parts you can use alone)")
fightTog = toggle(FightTab, "Auto boss fight (hit the boss + dodge)", "bossFight", function(v) if not v then bossStatus("Off") end end)
bossStatusPara = FightTab:CreateParagraph({Title = "Status", Content = "Off"})
FightTab:CreateSlider({Name = "Stay this close to the boss", Range = {3, 30}, Increment = 1, Suffix = " studs",
    CurrentValue = 8, Flag = "BossFightRange", Callback = function(v) bossRange = v end})
FightTab:CreateToggle({Name = "Equip my bat automatically", CurrentValue = true, Flag = "BossFightEquip",
    Callback = function(v) on.bossEquip = v end})
group(FightTab, "Boss portal")
portalDD = FightTab:CreateDropdown({Name = "Portal to enter", Options = {"(loading...)"}, CurrentOption = {},
    MultipleOptions = false, Callback = function(o)
        local label = type(o) == "table" and o[1] or o
        local k = tostring(label):match("^(%a+):")
        if k and PORTAL_NAMES[k] then chosenPortal = k end
    end})
toggle(FightTab, "Auto walk into the chosen portal when it opens", "bossEnter")
group(FightTab, "Dodging")
FightTab:CreateToggle({Name = "Auto dodge incoming attacks", CurrentValue = true, Flag = "BossFightDodge",
    Callback = function(v) on.bossDodge = v end})
FightTab:CreateInput({Name = "Extra attack part names (comma separated)", PlaceholderText = "e.g. fist, orb",
    RemoveTextAfterFocusLost = false, Flag = "BossFightExtra", Callback = function(t)
        attackExtra = {}
        for w in (t or ""):gmatch("[^,]+") do
            w = trim(w):lower()
            if w ~= "" then attackExtra[#attackExtra + 1] = w end
        end
        attacksAt = 0
    end})
group(FightTab, "Debug (run while a boss fight is going on)")
FightTab:CreateButton({Name = "Copy boss fight info", Callback = function()
    local out = {}
    local boss = findBoss()
    out[#out + 1] = "BOSS: " .. (boss and boss:GetFullName() or "not found")
    if boss then
        for k, v in pairs(boss:GetAttributes()) do out[#out + 1] = "  @" .. k .. " = " .. tostring(v) end
        local hum = boss:FindFirstChildOfClass("Humanoid")
        if hum then out[#out + 1] = "  Humanoid health " .. hum.Health .. "/" .. hum.MaxHealth end
    end
    out[#out + 1] = "TOOLS:"
    for _, c in ipairs({lp:FindFirstChild("Backpack"), lp.Character}) do
        if c then for _, t in ipairs(c:GetChildren()) do if t:IsA("Tool") then out[#out + 1] = "  " .. t.Name end end end
    end
    out[#out + 1] = "REMOTES:"
    for _, d in ipairs(RepS:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then out[#out + 1] = "  " .. d:GetFullName() end
    end
    out[#out + 1] = "RECENT BOSS ATTACK EVENTS:"
    for _, l in ipairs(eventLog) do out[#out + 1] = "  " .. l end
    refreshAttacks(boss, true)
    out[#out + 1] = "ATTACK-LIKE PARTS (" .. #attacks .. "):"
    local seen = {}
    for _, a in ipairs(attacks) do
        local key = a:GetFullName()
        if not seen[key] and #seen < 60 then seen[key] = true out[#out + 1] = "  " .. key .. " size=" .. tostring(a.Size) end
    end
    local text = table.concat(out, "\n"):sub(1, 30000)
    if setclipboard then setclipboard(text) end
    Rayfield:Notify({Title = "Boss fight", Content = "Info copied to clipboard", Duration = 4})
end})

local StolenTab = Window:CreateTab("Stolen")
group(StolenTab, "Stolen since you executed the script", true)
stolenParas.sum = StolenTab:CreateParagraph({Title = "Total stolen: 0", Content = "nothing yet"})
stolenParas.log = StolenTab:CreateParagraph({Title = "Latest steals (newest first)", Content = "nothing yet"})
StolenTab:CreateButton({Name = "Clear the list", Callback = function() table.clear(stolenLog) updateStolen() end})

local Misc = Window:CreateTab("Misc")
group(Misc, "Utility", true)
toggle(Misc, "Anti-AFK", "afk")
group(Misc, "Interface")
Misc:CreateDropdown({Name = "UI color theme",
    Options = {"Default", "AmberGlow", "Amethyst", "Bloom", "DarkBlue", "Green", "Light", "Ocean", "Serenity"},
    CurrentOption = {"Default"}, MultipleOptions = false, Flag = "UiTheme",
    Callback = function(o)
        local name = type(o) == "table" and o[1] or o
        if not pcall(function() Window.ModifyTheme(name) end) then
            Rayfield:Notify({Title = "Theme", Content = "This Rayfield version can't change themes", Duration = 4})
        end
    end})
Misc:CreateSlider({Name = "UI size", Range = {50, 150}, Increment = 5, Suffix = "%", CurrentValue = 100,
    Flag = "UiScale", Callback = function(v)
        pcall(function()
            local m = rayfieldMain()
            if not m then return end
            local sc = m:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", m)
            sc.Scale = v / 100
        end)
    end})
group(Misc, "Auto execute")
Misc:CreateInput({Name = "Script link to auto execute", CurrentValue = loaderUrl, PlaceholderText = loaderUrl,
    RemoveTextAfterFocusLost = false, Flag = "LoaderUrl",
    Callback = function(t) t = trim(t or "") if t ~= "" then loaderUrl = t end end})
toggle(Misc, "Re-run script after server hop / rejoin", "reexec")
Misc:CreateButton({Name = "Save to executor autoexec folder", Callback = function()
    local ok = pcall(function()
        if makefolder and isfolder and not isfolder("autoexec") then makefolder("autoexec") end
        writefile("autoexec/StelaAVerity.lua", loaderSrc())
    end)
    Rayfield:Notify({Title = "Auto execute", Duration = 5,
        Content = ok and "Saved autoexec/StelaAVerity.lua (delete it to turn this off)" or "Your executor can't write files"})
end})


local Hook = Window:CreateTab("Webhook")
group(Hook, "Setup", true)
Hook:CreateInput({Name = "Webhook URL", PlaceholderText = "https://discord.com/api/webhooks/...",
    RemoveTextAfterFocusLost = false, Flag = "WebhookUrl", Callback = function(t) wh.url = t end})
Hook:CreateToggle({Name = "Notify after every night reset", CurrentValue = true, Flag = "WebhookNight",
    Callback = function(v) on.night = v end})
group(Hook, "Send now")
Hook:CreateButton({Name = "Send Test Message", Callback = function()
    local ok = sendWebhook("Test", "Webhook works!")
    Rayfield:Notify({Title = "Webhook", Duration = 3,
        Content = ok and "Test sent" or "Invalid URL or your executor has no request function"})
end})
Hook:CreateButton({Name = "Read Current Announcements Now", Callback = function()
    if not processAnnouncements(true) then
        Rayfield:Notify({Title = "Webhook", Content = "No matching announcements on screen right now", Duration = 4})
    end
end})

Hook:CreateButton({Name = "Send Box Summary Now", Callback = function()
    if not sendBoxSummary() then
        Rayfield:Notify({Title = "Webhook", Content = "No boxes matched your filters", Duration = 4})
    end
end})

group(Hook, "What to send")
selectPicker(Hook, "Discord areas", "areas", "HookAreas", SEL.hookAreas)
selectPicker(Hook, "Discord moods", "boxes", "HookTypes", SEL.hookBoxes)

local Filters = Window:CreateTab("Notif Filters")
group(Filters, "In-game popups: which boxes to show", true)
selectPicker(Filters, "Popup areas", "areas", "FilterAreas", SEL.notifAreas)
selectPicker(Filters, "Popup moods", "boxes", "FilterBoxes", SEL.notifBoxes)

local Boss = Window:CreateTab("Boss")
group(Boss, "Next boss timers", true)
for _, t in ipairs(TIERS) do bossLabels[t.key] = Boss:CreateLabel(t.key .. ": loading...") end
Boss:CreateButton({Name = "Copy boss sign info (debug)", Callback = function()
    local out = {}
    for _, t in ipairs(TIERS) do
        local g = lp.PlayerGui:FindFirstChild(t.gui)
        if g then
            for _, d in ipairs(g:GetDescendants()) do
                if d:IsA("TextLabel") or d:IsA("ValueBase") then
                    out[#out + 1] = d:GetFullName() .. " [" .. d.ClassName .. "] = " .. tostring(d:IsA("TextLabel") and d.Text or d.Value)
                end
            end
        end
    end
    local text = table.concat(out, "\n")
    if setclipboard then setclipboard(text) end
    print(text)
end})
group(Boss, "Predicted bosses")
if canPredict then
    for i = 1, PRED_SLOTS do
        local pl = {rowText = {}, rows = {}}
        pl.head = Boss:CreateLabel("Loading...")
        for b = 1, 3 do pl.rows[b] = Boss:CreateLabel(BAND_NAMES[b] .. ": ...") end
        predLabels[i] = pl
    end
    Boss:CreateButton({Name = "Check prediction vs portal displays", Callback = function()
        local now = workspace:GetServerTimeNow()
        local open = BossPortal.SignStateAt(now)
        local slot = BossConfig.SlotIndex(now) + (open and 0 or 1)
        local lines = {}
        for b, nm in ipairs({"BossPortal", "BossPortalHigh", "BossPortalTop"}) do
            local portal = workspace:FindFirstChild(nm)
            local d = portal and portal:FindFirstChild("DisplayBoss")
            local shown = d and (areaName(d:GetAttribute("AreaId")) .. " tier " .. tostring(d:GetAttribute("BossTier"))) or "no display"
            local info = bossInfo(slot, b)
            lines[#lines + 1] = BAND_NAMES[b] .. ": portal shows " .. shown .. " | predicted " .. (info and info.full or "?")
        end
        local text = table.concat(lines, "\n")
        print(text)
        if setclipboard then setclipboard(text) end
        Rayfield:Notify({Title = "Prediction check", Content = text:sub(1, 220), Duration = 10})
    end})
else
    Boss:CreateLabel("Prediction unavailable: couldn't read the game's boss code")
end
group(Boss, "Discord alerts (uses the Webhook tab URL)")
Boss:CreateToggle({Name = "Alert shortly before the boss starts", CurrentValue = false, Flag = "BossSoon",
    Callback = function(v) on.bossSoon = v end})
Boss:CreateSlider({Name = "Alert when this many seconds away", Range = {10, 300}, Increment = 5, Suffix = "s",
    CurrentValue = 60, Flag = "BossWarn", Callback = function(v) bossWarn = v end})
Boss:CreateDropdown({Name = "Which portals to alert for", Options = {"Normal", "High", "Top"},
    CurrentOption = {"Normal", "High", "Top"}, MultipleOptions = true, Flag = "BossTiers",
    Callback = function(o)
        if type(o) == "string" then o = {o} end
        bossTiers = {}
        for _, k in ipairs(o) do bossTiers[k] = true end
    end})
Boss:CreateToggle({Name = "Alert when the game announces a boss", CurrentValue = false, Flag = "BossEvent",
    Callback = function(v) on.bossEvent = v end})
Boss:CreateInput({Name = "Boss names (comma separated, empty = all)", PlaceholderText = "name1, name2",
    RemoveTextAfterFocusLost = false, Flag = "BossNames", Callback = function(t) wh.bosses = t end})

group(Boss, "Which bosses to alert for")
selectPicker(Boss, "Boss areas to alert for", "areas", "BossAreas", SEL.bossAreas)
selectPicker(Boss, "Boss tiers to alert for", "tiers", "BossTiers", SEL.bossTiers)

Rayfield:LoadConfiguration()
