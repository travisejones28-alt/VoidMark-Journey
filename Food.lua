-- VoidMark Journey: XP food reminder icon.
-- Drag your XP food onto the icon to set it. Left-click the icon to eat it.
-- The icon counts down the food buff, and you get a chat line + raid warning +
-- sound at 60 seconds left and again when it runs out.
-- The countdown runs off the clock, so Forever briefly hiding a buff can never
-- fire a false "expired" alert.
local J = VoidMarkJourney
local Food = {}
J.Food = Food

local WARN_AT = 60          -- seconds left for the "runs out soon" alert
local MIN_BUFF = 300        -- a food buff lasts at least 5 minutes
local LEARN_WINDOW = 90     -- after eating, watch this long for the new buff
local GONE_AFTER = 15       -- buff must read as missing this long before we believe it
local SKIP = { [429959] = true } -- Well-Rested (sleeping bag) is never the food buff

local btn, ticker
local learn            -- { at = GetTime(), before = {spellId=true} }
local missingSince
local pending          -- attribute change waiting for combat to end
local dropping         -- food dropped on the icon by a click
local syncLater        -- show/hide waiting for combat to end

local function settings() return J.DB.settings end
local function state()
    local c = J.char
    c.food = type(c.food) == "table" and c.food or {}
    return c.food
end
local function InCombat() return InCombatLockdown and InCombatLockdown() end

local function ItemIcon(id)
    local icon = (C_Item and C_Item.GetItemIconByID and J.Safe(C_Item.GetItemIconByID, id)) or J.Safe(GetItemIcon, id)
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function ItemName(id)
    local name = (C_Item and C_Item.GetItemNameByID and J.Safe(C_Item.GetItemNameByID, id)) or J.Safe(GetItemInfo, id)
    return name or "your XP food"
end
local function ItemCount(id)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    return tonumber(J.Safe(fn, id)) or 0
end
local function ItemSpell(id)
    local fn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    local _, spell = J.Safe(fn, id)
    return tonumber(spell)
end

-- Every readable buff on the player: { [spellId] = { exp=, dur= } }.
-- ok=false when the client hid any of them (secret / combat).
local function Buffs()
    local out, ok = {}, true
    for i = 1, 40 do
        local id, exp, dur
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local good, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not good or (a ~= nil and J.Readable(a) == nil) then ok = false; break end
            if type(a) ~= "table" then break end
            id, exp, dur = J.Readable(a.spellId), J.Readable(a.expirationTime), J.Readable(a.duration)
        elseif UnitBuff then
            local good, name, _, _, _, d, e, _, _, _, sid = pcall(UnitBuff, "player", i)
            if not good or (name ~= nil and J.Readable(name) == nil) then ok = false; break end
            if not name then break end
            id, exp, dur = J.Readable(sid), J.Readable(e), J.Readable(d)
        else
            ok = false; break
        end
        id = tonumber(id)
        if id then out[id] = { exp = tonumber(exp) or 0, dur = tonumber(dur) or 0 } end
    end
    return out, ok
end

-- The food's buff: expiration (GetTime clock) or nil, and known (false = hidden read).
local function BuffExpiry()
    local item = settings().foodItem
    if not item then return nil, true end
    local spells = {}
    local learned = settings().foodBuffs and settings().foodBuffs[item]
    if learned then spells[#spells + 1] = learned end
    local own = ItemSpell(item)
    if own and own ~= learned then spells[#spells + 1] = own end
    if #spells == 0 then return nil, true end
    local buffs, ok = Buffs()
    for _, id in ipairs(spells) do
        local b = buffs[id]
        if b and b.exp > 0 and (id == learned or b.dur >= MIN_BUFF) then return b.exp, true end
    end
    return nil, ok
end

-- After eating: the new long buff that wasn't there before is the food buff.
local function TryLearn()
    if not learn then return end
    if GetTime() - learn.at > LEARN_WINDOW then learn = nil; return end
    local buffs, ok = Buffs()
    if not ok then return end
    local best, bestDur
    for id, b in pairs(buffs) do
        if not learn.before[id] and not SKIP[id] and b.dur >= MIN_BUFF and (not bestDur or b.dur > bestDur) then
            best, bestDur = id, b.dur
        end
    end
    if best then
        settings().foodBuffs = settings().foodBuffs or {}
        settings().foodBuffs[settings().foodItem] = best
        learn = nil
    end
end

local function StartLearning()
    if not settings().foodItem then return end
    local before = Buffs()
    local set = {}
    for id in pairs(before) do set[id] = true end
    learn = { at = GetTime(), before = set }
end

---------------------------------------------------------------------------
-- Countdown + alerts
---------------------------------------------------------------------------
-- Seconds of food left (nil = none). Updates saved state from the buff.
function Food.Remaining()
    if not J.char or not settings().foodItem then return nil end
    TryLearn()
    local s = state()
    local exp, known = BuffExpiry()
    local now = time()
    if exp then
        missingSince = nil
        local wall = now + math.floor(exp - GetTime() + 0.5)
        if not s.expiresAt or wall > s.expiresAt + 5 then s.warned, s.ended = false, false end
        s.expiresAt = wall
    elseif known and s.expiresAt and s.expiresAt > now then
        -- Really gone early (died, cancelled)? Only after it stays gone a while.
        missingSince = missingSince or GetTime()
        if GetTime() - missingSince >= GONE_AFTER then s.expiresAt = now; missingSince = nil end
    end
    if not s.expiresAt then return nil end
    return s.expiresAt - now
end

local function Check()
    local left = Food.Remaining()
    if not left then return end
    local s = state()
    local name = ItemName(settings().foodItem)
    if left > 0 and left <= WARN_AT and not s.warned then
        s.warned = true
        if settings().foodAlert then J.Alert("XP food runs out in " .. math.ceil(left) .. " sec - click the food icon") end
    elseif left <= 0 and not s.ended then
        s.ended, s.warned = true, true
        if settings().foodAlert then J.Alert(name .. " expired - click the food icon to eat") end
    end
end
Food.Check = Check

---------------------------------------------------------------------------
-- Icon
---------------------------------------------------------------------------
local function ApplyItem()
    if not btn then return end
    if InCombat() then pending = true; return end
    local item = settings().foodItem
    btn:SetAttribute("type1", item and "item" or nil)
    btn:SetAttribute("item", item and ("item:" .. item) or nil)
    pending = nil
end

function Food.Set(itemId)
    itemId = tonumber(itemId)
    if not itemId then return end
    settings().foodItem = itemId
    local s = state(); s.expiresAt, s.warned, s.ended = nil, false, false
    ApplyItem()
    J.Print("XP food set: " .. ItemName(itemId) .. ". Click the icon to eat it.")
    Food.Update(); Food.Sync()
end

function Food.Clear()
    settings().foodItem = nil
    if J.char then J.char.food = nil end
    ApplyItem()
    J.Print("XP food cleared. Drag a food onto the icon to set it.")
    Food.Update(); Food.Sync()
end

function Food.Update()
    if not btn then return end
    local item = settings().foodItem
    local left = item and Food.Remaining()
    btn.Icon:SetTexture(item and ItemIcon(item) or "Interface\\Icons\\INV_Misc_QuestionMark")
    local count = item and ItemCount(item) or 0
    btn.Count:SetText(item and count > 0 and tostring(count) or "")
    if btn.Icon.SetDesaturated then btn.Icon:SetDesaturated(item ~= nil and count == 0) end
    local r, g, b = 0.48, 0.20, 0.68
    local flash = math.floor(GetTime() * 2) % 2 == 0
    if not item then
        btn.Time:SetText("|cff9a8fb0drag food|r")
    elseif left and left > WARN_AT then
        btn.Time:SetText(J.Duration(left))
    elseif left and left > 0 then
        btn.Time:SetText("|cffffb040" .. J.Clock(left) .. "|r")
        if flash then r, g, b = 1, 0.7, 0.1 end
    elseif count == 0 then
        btn.Time:SetText("|cffff6060none left|r"); r, g, b = 0.8, 0.2, 0.2
    else
        btn.Time:SetText("|cffff6060EAT|r"); r, g, b = 0.9, 0.15, 0.15
        -- Flash for the first 30 seconds after it runs out.
        local s = state()
        if s.expiresAt and time() - s.expiresAt < 30 and not flash then r, g, b = 0.48, 0.20, 0.68 end
    end
    if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(r, g, b, 1) end
end

-- Only show the icon when you need it: no food set yet, last minute of the
-- buff, or the buff is gone. Hidden at max level.
local function Needed()
    if not settings().foodItem then return true end
    local c = J.char
    local max = J.Safe(GetMaxPlayerLevel) or 60
    if c and (c.level or 0) >= max then return false end
    local left = Food.Remaining()
    return not left or left <= WARN_AT
end
Food.Needed = Needed

function Food.Sync()
    if not btn then return end
    local want = settings().foodShown and Needed() or false
    if want == (btn:IsShown() and true or false) then syncLater = nil; return end
    -- Don't yank it away while you're dropping food on it or moving it.
    if not want and btn.IsMouseOver and btn:IsMouseOver() then return end
    if InCombat() then syncLater = true; return end -- secure button: can't show/hide in combat
    syncLater = nil
    if want then btn:Show(); Food.Update()
    else
        btn:StopMovingOrSizing()
        if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == btn then GameTooltip:Hide() end
        btn:Hide()
    end
end

local function Tooltip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local item = settings().foodItem
    if item and GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, item)
    else GameTooltip:SetText("XP food reminder") end
    GameTooltip:AddLine(" ")
    if item then GameTooltip:AddLine("Left-click: eat", 1, 1, 1) end
    GameTooltip:AddLine("Drag a food here to set it", 1, 1, 1)
    GameTooltip:AddLine("Shift+drag: move  ·  Shift+right-click: clear", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function RealClick(down)
    local useDown = GetCVarBool and J.Safe(GetCVarBool, "ActionButtonUseKeyDown")
    if useDown == nil then return not down end
    return (down and true or false) == (useDown and true or false)
end

local function CursorItem()
    local kind, id = J.Safe(GetCursorInfo)
    if kind == "item" then return tonumber(id) end
end

local function Build()
    if btn then return end
    btn = CreateFrame("Button", "VoidMarkJourneyFood", UIParent,
        "SecureActionButtonTemplate" .. (BackdropTemplateMixin and ",BackdropTemplate" or ""))
    btn:SetSize(40, 40)
    local p = settings().foodPoint
    if type(p) == "table" and p[1] then btn:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else btn:SetPoint("TOP", UIParent, "TOP", 200, -140) end
    btn:SetFrameStrata("MEDIUM")
    btn:SetClampedToScreen(true)
    btn:SetMovable(true)
    -- Newer clients only run a secure click on key-down or key-up (ActionButtonUseKeyDown),
    -- so register both and only react to the half that actually uses the item.
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:RegisterForDrag("LeftButton")
    if btn.SetBackdrop then
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        btn:SetBackdropColor(0.035, 0.02, 0.055, 0.94)
    end
    btn.Icon = btn:CreateTexture(nil, "ARTWORK")
    btn.Icon:SetPoint("TOPLEFT", 2, -2); btn.Icon:SetPoint("BOTTOMRIGHT", -2, 2)
    if btn.Icon.SetTexCoord then btn.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    btn.Count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    btn.Count:SetPoint("BOTTOMRIGHT", -3, 3)
    btn.Time = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.Time:SetPoint("TOP", btn, "BOTTOM", 0, -2)

    btn:SetScript("PreClick", function(self, button, down)
        if not RealClick(down) then return end
        -- Dropping a food on the icon sets it instead of eating.
        if button == "LeftButton" and CursorItem() and not InCombat() then
            dropping = CursorItem(); self:SetAttribute("type1", nil)
        elseif button == "LeftButton" and settings().foodItem then
            StartLearning()
        end
    end)
    btn:SetScript("PostClick", function(self, button, down)
        if not RealClick(down) then return end
        if dropping then
            local id = dropping; dropping = nil
            if ClearCursor then ClearCursor() end
            Food.Set(id)
        elseif button == "RightButton" and IsShiftKeyDown and IsShiftKeyDown() then
            if InCombat() then J.Print("Clear the food after combat.") else Food.Clear() end
        end
    end)
    btn:SetScript("OnReceiveDrag", function()
        local id = CursorItem()
        if not id then return end
        if InCombat() then J.Print("Set the food after combat."); return end
        if ClearCursor then ClearCursor() end
        Food.Set(id)
    end)
    btn:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown and IsShiftKeyDown() and not InCombat() then self:StartMoving() end
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, r, x, y = self:GetPoint()
        settings().foodPoint = { a, r, x, y }
    end)
    btn:SetScript("OnEnter", Tooltip)
    btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    ApplyItem()
end

function Food.Toggle(show)
    if not J.DB then return end
    if InCombat() then J.Print("Show or hide the food icon after combat."); return end
    Build()
    if show == nil then show = not btn:IsShown() end
    settings().foodShown = show and true or false
    if show then
        Food.Sync()
        if not btn:IsShown() then J.Print("Food icon on - it pops up when your XP food has 1 minute left or runs out.") end
    else btn:Hide() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LOGIN", "UNIT_AURA", "PLAYER_REGEN_ENABLED", "BAG_UPDATE", "UNIT_SPELLCAST_SUCCEEDED" }) do
    pcall(events.RegisterEvent, events, ev)
end
events:SetScript("OnEvent", function(_, event, unit, _, spell)
    if not J.char then return end
    if event == "PLAYER_LOGIN" then
        Build()
        btn:Hide()
        Food.Update(); Food.Sync()
        if C_Timer and C_Timer.NewTicker then
            ticker = C_Timer.NewTicker(1, function() Check(); Food.Sync(); if btn:IsShown() then Food.Update() end end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then ApplyItem() end
        if syncLater then Food.Sync() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Ate the food from the bags instead of the icon: still learn its buff.
        local item = settings().foodItem
        if unit == "player" and item and not learn and tonumber(J.Readable(spell)) == ItemSpell(item) then StartLearning() end
    elseif event == "UNIT_AURA" then
        if unit == "player" then Check(); Food.Sync(); Food.Update() end
    else
        Food.Update()
    end
end)
