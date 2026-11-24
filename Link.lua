-- VoidMark Journey: your other WoW account's characters in the Alts list.
-- Each WoW account keeps its own saved data, so Journey on one account never
-- sees the other. While a character from each account is online at the same
-- time, the two exchange their character summaries by addon whisper.
-- Trust: only your Market sync partner, a character you linked with
-- /journey link, and characters those already listed are accepted.
local J = VoidMarkJourney
local PREFIX = "VMJrn1"
local PROBE_MIN, PROBE_MAX = 10, 60 -- seconds between tries while nobody answers
local CONTACT_FOR = 90              -- an answer within this counts as connected
local REFRESH_EVERY = 60            -- connected: resend this character's line

local L = { queue = {}, probed = {}, delay = PROBE_MIN, nextProbe = 0, turn = 0, hyphen = {} }
J.Link = L

local function Norm(name)
    if type(name) ~= "string" then return nil end
    if J.Readable and not J.Readable(name) then return nil end
    -- "Voidmark Bank", "Voidmark-Bank", "Voidmark Bank-Realm" or "Voidmark-Bank-Realm" -> "voidmark bank"
    local s = name
    local a, b = s:match("^(.-)%-(.+)$")
    if a then
        if a:find(" ") then s = a
        else
            local surname = b:match("^([^%-]+)%-.+$")
            if surname then s = a .. " " .. surname
            elseif b:find(" ") then s = a
            else s = a .. " " .. b end
        end
    end
    s = s:gsub("%s+", " "):lower():match("^%s*(.-)%s*$")
    return s ~= "" and s or nil
end
L.Norm = Norm

local function DB() return J.db end
local function Store()
    local db = DB(); if not db then return end
    db.remote = type(db.remote) == "table" and db.remote or {}
    db.link = type(db.link) == "table" and db.link or {}
    db.link.manual = type(db.link.manual) == "table" and db.link.manual or {}
    return db
end

local function IsLocal(norm)
    for _, c in pairs(DB().characters) do
        if type(c) == "table" and Norm(c.name) == norm then return true end
    end
end

-- Characters believed to be on your other account, newest contact first.
function L.Candidates()
    local db = Store(); if not db then return {} end
    local out, seen = {}, {}
    local function add(name, at)
        local n = Norm(name)
        if n and not seen[n] and not IsLocal(n) then seen[n] = true; out[#out + 1] = { name = name, norm = n, at = at or 0 } end
    end
    for _, c in pairs(db.remote) do if type(c) == "table" then add(c.name, tonumber(c.heardAt) or 0) end end
    for name in pairs(db.link.manual) do add(name, 0) end
    local market = rawget(_G, "VoidMarkMarketDB")
    if type(market) == "table" then add(market.syncAddress and tostring(market.syncAddress):match("^([^%-]+)") or market.syncPeer, 0) end
    table.sort(out, function(a, b) if a.at ~= b.at then return a.at > b.at end return a.norm < b.norm end)
    return out
end
local function Trusted(norm)
    for _, c in ipairs(L.Candidates()) do if c.norm == norm then return true end end
end

local function Send(body, target)
    local api = C_ChatInfo
    if not (api and api.SendAddonMessage and target) or #body > 250 then return false end
    local ok = pcall(api.SendAddonMessage, PREFIX, body, "WHISPER", target)
    return ok
end
local function Queue(body, target) L.queue[#L.queue + 1] = { body = body, target = target } end

local function Field(v) return (tostring(v == nil and "" or v):gsub("[\t|]", " ")) end
function L.Line(c)
    return table.concat({ "C", Field(c.name), Field(c.realm), Field(c.level or 0), Field(math.floor(tonumber(c.xp) or 0)),
        Field(math.floor(tonumber(c.maxXP) or 0)), Field(math.floor(tonumber(c.rested) or 0)), c.resting and "1" or "0",
        Field(c.class or ""), Field(math.floor(tonumber(c.savedAt) or 0)) }, "\t")
end
local function QueueAll(target)
    for _, c in pairs(DB().characters) do
        if type(c) == "table" and c.name and c.level then Queue(L.Line(c), target) end
    end
end

local function Apply(f, sender)
    local name, realm = f[2], f[3]
    local level, xp, maxXP, rested = tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[7])
    local savedAt = tonumber(f[10])
    if not (name and name ~= "" and #name <= 60 and realm and #realm <= 60) then return end
    if not (level and level >= 1 and level <= 100 and savedAt and savedAt > 0) then return end
    local norm = Norm(name); if not norm or IsLocal(norm) then return end
    local db = DB()
    local key = name .. " - " .. realm
    local old = db.remote[key]
    if type(old) == "table" and (tonumber(old.savedAt) or 0) > savedAt then old.heardAt = time(); return end
    db.remote[key] = { name = name, realm = realm, level = level, xp = xp or 0, maxXP = maxXP or 0, rested = rested or 0,
        resting = f[8] == "1", class = f[9] ~= "" and f[9] or nil, savedAt = savedAt, heardAt = time(), remote = true,
        via = Norm(sender) }
end

function L.Receive(prefix, msg, channel, sender)
    if prefix ~= PREFIX or channel ~= "WHISPER" or type(msg) ~= "string" or not DB() then return end
    local from = Norm(sender); if not from or not Trusted(from) then return end
    Store()
    local f = {}; for v in (msg .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = v end
    local first = not L.contact or GetTime() - (L.contactAt or 0) > CONTACT_FOR
    L.contact, L.contactAt, L.delay = sender, GetTime(), PROBE_MIN
    if f[1] == "H" then
        QueueAll(sender)
        -- Ask back once, so both accounts fill in.
        -- (only when their characters have not arrived lately; never in a loop).
        if (first or GetTime() - (L.rowsAt or 0) > CONTACT_FOR) and GetTime() - (L.askedAt or 0) > 30 then
            L.askedAt = GetTime(); Queue("H", sender)
        end
    elseif f[1] == "C" and #f == 10 then
        Apply(f, sender); L.rowsAt = GetTime()
        if J.Refresh then pcall(J.Refresh) end
        if J.RefreshList then pcall(J.RefreshList) end
    end
end

function L.Connected() return L.contact ~= nil and GetTime() - (L.contactAt or 0) <= CONTACT_FOR end

-- Called every second.
function L.Tick()
    if not DB() then return end
    for _ = 1, 4 do -- a few messages per second keeps under the client limit
        local m = table.remove(L.queue, 1); if not m then break end
        Send(m.body, m.target)
    end
    local now = GetTime()
    if L.Connected() then
        if now >= (L.refreshAt or 0) and J.char then
            L.refreshAt = now + REFRESH_EVERY
            Queue(L.Line(J.char), L.contact)
        end
        return
    end
    if now < L.nextProbe then return end
    local list = L.Candidates()
    if #list == 0 then return end
    L.turn = L.turn % #list + 1
    local c = list[L.turn]
    -- Forever whispers sometimes only reach "First-Surname": alternate the forms.
    L.hyphen[c.norm] = not L.hyphen[c.norm]
    local target = c.name:match("^([^%-]+)") or c.name
    target = target:gsub("^%s+", ""):gsub("%s+$", "")
    if L.hyphen[c.norm] == false then target = target:gsub(" ", "-", 1) end
    L.probed[c.norm] = now
    Send("H", target)
    if L.turn == #list then L.delay = math.min(PROBE_MAX, L.delay * 2) end
    L.nextProbe = now + (#list > 1 and L.turn < #list and 2 or L.delay)
end

-- Hide "No player named X is currently playing" for our own quiet probes.
function L.HideOffline(msg)
    if type(msg) ~= "string" then return false end
    local pattern = rawget(_G, "ERR_CHAT_PLAYER_NOT_FOUND_S") or rawget(_G, "ERR_CHAT_PLAYER_NOT_FOUND")
    if type(pattern) ~= "string" or not pattern:find("%s", 1, true) then pattern = "No player named '%s' is currently playing." end
    local esc = pattern:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)")
    local who = msg:match("^" .. esc .. "$"); if not who then return false end
    local n = Norm(who)
    return n ~= nil and L.probed[n] ~= nil and GetTime() - L.probed[n] < 15
end

function L.LinkName(name)
    local db = Store(); if not db then return end
    name = tostring(name or ""):match("^%s*(.-)%s*$")
    if name == "" then
        local names = {}
        for _, c in ipairs(L.Candidates()) do names[#names + 1] = c.name end
        J.Print(#names > 0 and ("Other account: " .. table.concat(names, ", ") .. (L.Connected() and " (connected)" or " (waiting for one to be online)"))
            or "No other account linked. Type /journey link First Surname (a character on your other account).")
        return
    end
    if name:lower() == "off" then db.link.manual = {}; db.remote = {}; J.Print("Other account unlinked and its characters removed."); return end
    if not name:find(" ") then J.Print("Use the full name: First Surname."); return end
    db.link.manual[name] = true; L.nextProbe = 0; L.delay = PROBE_MIN
    J.Print("Linked " .. name .. ". Its account's characters appear once it is online at the same time as this one.")
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "CHAT_MSG_ADDON")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if not Store() then return end
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
        if ChatFrame_AddMessageEventFilter then
            ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg) return L.HideOffline(msg) end)
        end
        if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, function() pcall(L.Tick) end) end
    else
        local ok, err = pcall(L.Receive, ...)
        if not ok and J.Print then J.Print("Link error: " .. tostring(err)) end
    end
end)
