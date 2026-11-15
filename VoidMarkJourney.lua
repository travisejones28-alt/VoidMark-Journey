-- VoidMark Journey: leveling companion for WoW Forever.
-- Complements Questie / RestedXP guides: it never tracks quests or routes, only
-- your pace, rested XP, the Cozy Sleeping Bag, alts and level history.
local addonName = ...
VoidMarkJourney = VoidMarkJourney or {}
local J = VoidMarkJourney
J.VERSION = "0.1.3"

local BAG_ITEM = 211527          -- Cozy Sleeping Bag
local WELL_RESTED = 429959       -- Well-Rested (+1% XP per stack)
local WELL_RESTED_MAX = 3
local STACK_SECONDS = 60         -- one stack per minute lying on the bag
local RATE_WINDOW = 600          -- XP/hour uses the last 10 minutes
local REST_PER_SEC = 0.05 / 28800 -- 5% of a level per 8 hours in a rest area

local DB, char, key
local frame, list, ticker
local lastXP, lastMax
local session = { start = 0, gained = 0, samples = {} }
local bag = { stacks = 0, stackAt = nil, alerted = false }

-- Forever marks some values "secret"; never do math on those.
local function Readable(v)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return v
end
local function pack(...) return { n = select("#", ...), ... } end
local function Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = pack(pcall(fn, ...))
    if not r[1] then return nil end
    for i = 2, r.n do r[i] = Readable(r[i]) end
    return unpack(r, 2, r.n)
end
local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffb86cff[Journey]|r " .. tostring(msg)) end

-- Forever names are "First Surname": UnitName returns the surname second.
local function CharacterName()
    local first, second = Safe(UnitName, "player")
    local realm = Safe(GetRealmName) or "Unknown"
    local name = first or "Unknown"
    if type(second) == "string" and second ~= "" and second:gsub("%s", ""):lower() ~= realm:gsub("%s", ""):lower() then
        name = name .. " " .. second
    end
    return name, realm
end

local function Short(n)
    n = tonumber(n) or 0
    if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
    if n >= 10000 then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n + 0.5))
end
local function Clock(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    if sec < 3600 then return string.format("%d:%02d", math.floor(sec / 60), sec % 60) end
    return string.format("%dh %02dm", math.floor(sec / 3600), math.floor(sec / 60) % 60)
end
local function Duration(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    if sec < 60 then return sec .. "s" end
    if sec < 3600 then return math.floor(sec / 60) .. "m" end
    if sec < 86400 then return string.format("%dh %dm", math.floor(sec / 3600), math.floor(sec / 60) % 60) end
    return string.format("%dd %dh", math.floor(sec / 86400), math.floor(sec / 3600) % 24)
end

local function MaxLevel()
    return Safe(GetMaxPlayerLevel) or 60
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
local function InitDB()
    VoidMarkJourneyDB = type(VoidMarkJourneyDB) == "table" and VoidMarkJourneyDB or {}
    DB = VoidMarkJourneyDB
    DB.characters = type(DB.characters) == "table" and DB.characters or {}
    DB.settings = type(DB.settings) == "table" and DB.settings or {}
    if DB.settings.shown == nil then DB.settings.shown = true end
    if DB.settings.bagAlert == nil then DB.settings.bagAlert = true end
    local name, realm = CharacterName()
    key = name .. " - " .. realm
    DB.characters[key] = type(DB.characters[key]) == "table" and DB.characters[key] or {}
    char = DB.characters[key]
    char.name, char.realm = name, realm
    char.dings = type(char.dings) == "table" and char.dings or {}
    char.levelPlayed = tonumber(char.levelPlayed) or 0
    char.levelDeaths = tonumber(char.levelDeaths) or 0
    local _, class = Safe(UnitClass, "player")
    char.class = class or char.class
end

local function Snapshot()
    if not char then return end
    char.level = Safe(UnitLevel, "player") or char.level
    char.xp = Safe(UnitXP, "player") or char.xp
    char.maxXP = Safe(UnitXPMax, "player") or char.maxXP
    char.rested = Safe(GetXPExhaustion) or 0
    char.resting = Safe(IsResting) and true or false
    char.savedAt = time()
end

-- Rested XP an alt has now, including what built up while logged out.
function J.EstimateRested(c, now)
    if not c or not c.maxXP or (c.level or 0) >= MaxLevel() then return 0, true end
    local elapsed = math.max(0, (now or time()) - (c.savedAt or now or time()))
    local rate = c.maxXP * REST_PER_SEC * (c.resting and 1 or 0.25)
    return math.min((c.rested or 0) + elapsed * rate, c.maxXP * 1.5), false
end

---------------------------------------------------------------------------
-- XP pace
---------------------------------------------------------------------------
local function OnXP()
    local xp, max = Safe(UnitXP, "player"), Safe(UnitXPMax, "player")
    if not xp or not max then return end
    if lastXP and lastMax then
        local delta = xp - lastXP
        if delta < 0 then delta = (lastMax - lastXP) + xp end   -- crossed a level
        if delta > 0 then
            session.gained = session.gained + delta
            local now = GetTime()
            table.insert(session.samples, { t = now, g = session.gained })
            while #session.samples > 1 and now - session.samples[1].t > RATE_WINDOW * 1.5 do
                table.remove(session.samples, 1)
            end
        end
    end
    lastXP, lastMax = xp, max
end

-- XP per hour over the last 10 minutes (or the whole session if shorter).
function J.XPPerHour()
    local now = GetTime()
    local span = math.min(RATE_WINDOW, now - session.start)
    if span < 30 then return 0 end
    local before = 0
    for i = #session.samples, 1, -1 do
        if now - session.samples[i].t > RATE_WINDOW then before = session.samples[i].g; break end
    end
    return (session.gained - before) / span * 3600
end

---------------------------------------------------------------------------
-- Cozy Sleeping Bag / Well-Rested
---------------------------------------------------------------------------
-- Returns stacks, expiration, known. known=false means the client hid the
-- answer (secret/blocked, e.g. in combat) - that is NOT the same as "no buff".
local function WellRested()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, WELL_RESTED)
        if not ok or (aura ~= nil and Readable(aura) == nil) then return bag.stacks or 0, nil, false end
        if type(aura) == "table" then
            local stacks = tonumber(Readable(aura.applications)) or 1
            return math.max(stacks, 1), tonumber(Readable(aura.expirationTime)), true
        end
        return 0, nil, true
    end
    for i = 1, 40 do
        local ok, name, _, count, _, _, expires, _, _, _, spellId = pcall(UnitBuff, "player", i)
        if not ok or (name ~= nil and Readable(name) == nil) then return bag.stacks or 0, nil, false end
        if not name then break end
        if tonumber(Readable(spellId)) == WELL_RESTED then return math.max(tonumber(Readable(count)) or 1, 1), tonumber(Readable(expires)), true end
    end
    return 0, nil, true
end

local function BagCooldown()
    local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    local start, duration = Safe(fn, BAG_ITEM)
    start, duration = tonumber(start), tonumber(duration)
    if not start or not duration or start <= 0 or duration <= 2 then return 0, nil end
    return math.max(0, start + duration - GetTime()), start
end

local function HasBag()
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    return (tonumber(Safe(fn, BAG_ITEM)) or 0) > 0
end

local function BagAlert()
    if not DB.settings.bagAlert then return end
    local msg = "Well-Rested 3/3 - you can get up!"
    Print("|cff7cff7c" .. msg .. "|r")
    if RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 1, b = 1 })
    end
    if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960, "Master") end
end

local ALERT_GAP = 1800   -- at most one 3/3 alert per 30 minutes (bag cooldown is 1 hour)
local function OnAura()
    local stacks, _, known = WellRested()
    if not known then return end          -- hidden read: keep what we had
    local now = GetTime()
    if stacks > 0 and stacks < WELL_RESTED_MAX then bag.buildingAt = now end
    if stacks > bag.stacks then
        bag.stackAt = now
        -- Only alert if we watched the stacks build (1/3 or 2/3 in the last 3 min).
        -- Forever sometimes reports the buff missing for a moment; a buff that just
        -- "reappears" at 3/3 must never trigger the alert.
        local built = bag.buildingAt and now - bag.buildingAt <= 180
        if stacks >= WELL_RESTED_MAX and built and not bag.alerted
            and (not bag.alertAt or now - bag.alertAt > ALERT_GAP) then
            bag.alerted = true; bag.alertAt = GetTime(); BagAlert()
        end
    elseif stacks == 0 then
        bag.alerted = false; bag.stackAt = nil
    end
    bag.stacks = stacks
end

-- One line describing the bag: stacking countdown, done, or cooldown.
function J.BagLine()
    local stacks, expires = WellRested()
    local remaining, start = BagCooldown()
    local now = GetTime()
    if stacks >= WELL_RESTED_MAX then
        local left = expires and expires > now and (" · " .. Duration(expires - now) .. " left") or ""
        return "|cff7cff7cWell-Rested 3/3 (+3% XP)" .. left .. "|r"
    end
    -- Stacking: bag used recently, or a stack is already building.
    local recent = start and (now - start) < (WELL_RESTED_MAX + 1) * STACK_SECONDS
    if recent or stacks > 0 then
        local base = bag.stackAt or (start and start + stacks * STACK_SECONDS) or now
        local nextIn = base + STACK_SECONDS - now
        if stacks > 0 and not bag.stackAt and not start then nextIn = STACK_SECONDS end
        if nextIn > -15 then
            return string.format("Well-Rested %d/3 · next in %s", stacks, Clock(math.max(0, nextIn)))
        end
        return string.format("Well-Rested %d/3 · stay on the bag", stacks)
    end
    if remaining > 0 then return "Sleeping bag ready in " .. Clock(remaining) end
    if HasBag() then return "|cff7cff7cSleeping bag ready|r" end
    return nil
end

---------------------------------------------------------------------------
-- Level history
---------------------------------------------------------------------------
local function OnLevelUp(level)
    level = tonumber(Readable(level)) or ((Safe(UnitLevel, "player") or 0) + 1)
    table.insert(char.dings, 1, {
        level = level,
        at = time(),
        zone = Safe(GetZoneText) or "Unknown",
        played = char.levelPlayed,
        deaths = char.levelDeaths,
    })
    while #char.dings > 60 do table.remove(char.dings) end
    char.levelPlayed, char.levelDeaths = 0, 0
    Print(string.format("Level %d! That level took %s played, %d death%s.", level,
        Duration(char.dings[1].played), char.dings[1].deaths, char.dings[1].deaths == 1 and "" or "s"))
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local function Backdrop(f)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        if f.SetBackdropColor then f:SetBackdropColor(0.035, 0.02, 0.055, 0.94) end
        if f.SetBackdropBorderColor then f:SetBackdropBorderColor(0.48, 0.20, 0.68, 1) end
    end
end
local function Text(parent, template, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    return fs
end
local function SmallButton(parent, label, width)
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetSize(width, 18)
    Backdrop(b)
    b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.Text:SetAllPoints(); b.Text:SetText(label)
    return b
end

local function ListLines(mode)
    local lines = {}
    if mode == "alts" then
        local rows = {}
        for k, c in pairs(DB.characters) do
            if type(c) == "table" and c.level then rows[#rows + 1] = c end
        end
        table.sort(rows, function(a, b) return (a.level or 0) > (b.level or 0) end)
        for _, c in ipairs(rows) do
            local rested, maxed = J.EstimateRested(c, time())
            local pct = (c.maxXP and c.maxXP > 0) and math.floor(rested / c.maxXP * 100 + 0.5) or 0
            local tag = maxed and "max level" or (pct >= 150 and "|cff7cff7cfull rested|r" or (pct .. "% rested"))
            lines[#lines + 1] = string.format("%s  |cffb88cffLv %d|r  %s", c.name or "?", c.level or 0, tag)
        end
        if #lines == 0 then lines[1] = "Log in on your other characters once to list them here." end
    else
        for i, d in ipairs(char.dings) do
            if i > 12 then break end
            lines[#lines + 1] = string.format("|cffb88cffLv %d|r  %s  ·  %s  ·  %s played  ·  %d death%s",
                d.level or 0, date("%b %d", d.at or 0), d.zone or "?", Duration(d.played),
                d.deaths or 0, (d.deaths or 0) == 1 and "" or "s")
        end
        if #lines == 0 then lines[1] = "Your level-ups will be listed here." end
    end
    return lines
end

local function ShowList(mode)
    if list and list:IsShown() and list.mode == mode then list:Hide(); return end
    if not list then
        list = CreateFrame("Frame", "VoidMarkJourneyList", frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        list:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
        list:SetWidth(330)
        Backdrop(list)
        list.Title = Text(list, "GameFontNormal", 10, -8)
        list.Body = Text(list, "GameFontHighlightSmall", 10, -26)
        list.Body:SetWidth(310)
        if list.Body.SetSpacing then list.Body:SetSpacing(3) end
    end
    list.mode = mode
    local lines = ListLines(mode)
    list.Title:SetText(mode == "alts" and "CHARACTERS" or "LEVEL HISTORY")
    list.Body:SetText(table.concat(lines, "\n"))
    list:SetHeight(36 + #lines * 15)
    list:Show()
end

function J.Refresh()
    if not frame or not frame:IsShown() then return end
    local level = Safe(UnitLevel, "player") or 0
    local xp, max = Safe(UnitXP, "player"), Safe(UnitXPMax, "player")
    if level >= MaxLevel() or not xp or not max or max <= 0 then
        frame.Level:SetText(string.format("Level %d", level))
        frame.Bar:SetValue(1); frame.RestBar:SetValue(0)
        frame.Pace:SetText("Max level - nothing left to track here.")
        frame.Rested:SetText("")
    else
        local pct = xp / max
        frame.Level:SetText(string.format("Level %d  ·  %.1f%%  ·  %s to go", level, pct * 100, Short(max - xp)))
        frame.Bar:SetValue(pct)
        local rested = Safe(GetXPExhaustion) or 0
        frame.RestBar:SetValue(math.min(1, (xp + rested) / max))
        local rate = J.XPPerHour()
        if rate > 0 then
            frame.Pace:SetText(string.format("XP/hr |cffffffff%s|r  ·  level in |cffffffff%s|r", Short(rate), Duration((max - xp) / rate * 3600)))
        else
            frame.Pace:SetText("XP/hr |cff8f8f8fearn some XP to start the clock|r")
        end
        if rested > 0 then
            frame.Rested:SetText(string.format("Rested |cff6cb8ff%s|r  (%.1f bubbles)", Short(rested), rested / max * 20))
        else
            frame.Rested:SetText("Rested |cff8f8f8fnone|r")
        end
    end
    local bagLine = J.BagLine()
    frame.Bag:SetText(bagLine or "")
    frame:SetHeight(bagLine and 118 or 100)
end

local function BuildUI()
    if frame then return end
    frame = CreateFrame("Frame", "VoidMarkJourneyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(330, 118)
    local p = DB.settings.point
    if type(p) == "table" and p[1] then frame:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else frame:SetPoint("TOP", UIParent, "TOP", 0, -140) end
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if not DB.settings.locked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, r, x, y = self:GetPoint()
        DB.settings.point = { a, r, x, y }
    end)
    Backdrop(frame)

    local title = Text(frame, "GameFontNormal", 10, -8)
    title:SetText("|cffb86cffVOIDMARK|r JOURNEY")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(22, 22); close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() J.Toggle(false) end)

    local dings = SmallButton(frame, "Dings", 50); dings:SetPoint("TOPRIGHT", -26, -6)
    dings:SetScript("OnClick", function() ShowList("dings") end)
    local alts = SmallButton(frame, "Alts", 44); alts:SetPoint("RIGHT", dings, "LEFT", -4, 0)
    alts:SetScript("OnClick", function() ShowList("alts") end)

    frame.Level = Text(frame, "GameFontHighlight", 10, -28)
    -- XP bar with a rested overlay behind it.
    frame.RestBar = CreateFrame("StatusBar", nil, frame)
    frame.RestBar:SetPoint("TOPLEFT", 10, -46); frame.RestBar:SetSize(310, 8)
    frame.RestBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    frame.RestBar:SetStatusBarColor(0.25, 0.45, 0.85, 0.55)
    frame.RestBar:SetMinMaxValues(0, 1)
    local bg = frame.RestBar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    if bg.SetVertexColor then bg:SetVertexColor(0.1, 0.05, 0.15, 1) end
    frame.Bar = CreateFrame("StatusBar", nil, frame)
    frame.Bar:SetAllPoints(frame.RestBar)
    frame.Bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    frame.Bar:SetStatusBarColor(0.66, 0.28, 0.90, 1)
    frame.Bar:SetMinMaxValues(0, 1)

    frame.Pace = Text(frame, "GameFontHighlightSmall", 10, -60)
    frame.Rested = Text(frame, "GameFontHighlightSmall", 10, -76)
    frame.Bag = Text(frame, "GameFontHighlightSmall", 10, -92)
    frame:SetScript("OnShow", J.Refresh)
end

function J.Toggle(show)
    BuildUI()
    if show == nil then show = not frame:IsShown() end
    DB.settings.shown = show and true or false
    if show then frame:Show(); J.Refresh() else frame:Hide(); if list then list:Hide() end end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
    "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING", "PLAYER_DEAD", "UNIT_AURA", "BAG_UPDATE_COOLDOWN" }) do
    pcall(events.RegisterEvent, events, ev)
end
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then InitDB() end
        return
    end
    if not char then return end
    if event == "PLAYER_LOGIN" then
        session.start = GetTime(); session.gained = 0; session.samples = {}
        lastXP, lastMax = Safe(UnitXP, "player"), Safe(UnitXPMax, "player")
        bag.stacks = WellRested(); bag.alerted = bag.stacks >= WELL_RESTED_MAX
        if bag.alerted then bag.alertAt = GetTime() end
        Snapshot()
        BuildUI()
        if DB.settings.shown then frame:Show() else frame:Hide() end
        if C_Timer and C_Timer.NewTicker then
            local last = GetTime()
            ticker = C_Timer.NewTicker(1, function()
                local now = GetTime()
                char.levelPlayed = (char.levelPlayed or 0) + (now - last); last = now
                J.Refresh()
            end)
        end
    elseif event == "PLAYER_XP_UPDATE" then
        OnXP(); Snapshot(); J.Refresh()
    elseif event == "PLAYER_LEVEL_UP" then
        OnLevelUp(arg1); Snapshot()
    elseif event == "PLAYER_DEAD" then
        char.levelDeaths = (char.levelDeaths or 0) + 1
    elseif event == "UNIT_AURA" then
        if arg1 == "player" then OnAura(); J.Refresh() end
    elseif event == "BAG_UPDATE_COOLDOWN" then
        J.Refresh()
    else -- logout, rested changes
        Snapshot()
    end
end)

SLASH_VOIDMARKJOURNEY1 = "/journey"
SLASH_VOIDMARKJOURNEY2 = "/vmj"
SlashCmdList.VOIDMARKJOURNEY = function(msg)
    msg = tostring(msg or ""):lower():match("^%s*(.-)%s*$")
    if not DB then return end
    if msg == "alts" then J.Toggle(true); ShowList("alts")
    elseif msg == "dings" then J.Toggle(true); ShowList("dings")
    elseif msg == "lock" then DB.settings.locked = not DB.settings.locked; Print(DB.settings.locked and "Window locked." or "Window unlocked.")
    elseif msg == "reset" then session.start = GetTime(); session.gained = 0; session.samples = {}; Print("XP/hour reset."); J.Refresh()
    elseif msg == "bagalert" then DB.settings.bagAlert = not DB.settings.bagAlert; Print("Sleeping bag alert " .. (DB.settings.bagAlert and "on." or "off."))
    elseif msg == "help" then
        Print("/journey - show/hide  ·  alts  ·  dings  ·  lock  ·  reset (XP/hr)  ·  bagalert")
    else J.Toggle() end
end
