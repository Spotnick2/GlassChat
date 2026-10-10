-- Alerts.lua (#83): a sound when chat mentions your name or one of your
-- words, as Prat's PopupMessage does (modules\PopupMessage.lua:258-271), for
-- a character with two names ("First Surname") whose first name isn't unique.
--
-- One message filter on public and group chat, read-only: it returns false
-- and nothing else, so the line goes on unchanged (ChatFrameFilters.lua
-- ProcessFilters). It goes in at PLAYER_LOGIN: the Spam & Ignore plugin adds
-- its filters at its own ADDON_LOADED, before that, and a filter that hides a
-- line stops the loop, so a hidden spam line never alerts. Never whispers
-- (Blizzard's tell sound plays), Battle.net lines or TEXT_EMOTE (Blizzard
-- builds "waves at you" itself), and never your own lines.

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local Alerts = {}
GC.Alerts = Alerts

Alerts.EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_CHANNEL" }
-- SOUNDKIT ids (SoundKitConstants.lua:71-85), long-standing UI kits, and
-- 1210, the one LFG Bulletin Board notifies with (GroupBulletinBoard.lua:17;
-- no SOUNDKIT name for it), the default: owner's pick after hearing all four.
Alerts.SOUNDS = { raid = 8959, ready = 8960, tell = 3081, lfg = 1210 }   -- RAID_WARNING, READY_CHECK, TELL_MESSAGE
Alerts.SOUND_NAMES = { "raid", "ready", "tell", "lfg", "off" }
Alerts.NAME_MODES = { "first", "full", "off" }
Alerts.EVERY = 5                         -- seconds between two alerts; a match inside is dropped
Alerts.MAX_WORDS, Alerts.MAX_WORD = 20, 40   -- words kept, bytes per word

local function plain(v) return not API.IsSecret(v) end
local function say(msg) API.Print(msg) end

--------------------------------------------------------------------------------
-- Matching
--------------------------------------------------------------------------------

-- Your names, lower-cased, read at login and never saved: each character
-- watches its own. With no surname, first and full are the same.
local me
function Alerts.ReadNames()
    local full = API.PlayerFullName()
    if not full then me = nil; return end
    full = full:lower():gsub("%s+", " ")
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not plain(realm) or type(realm) ~= "string" then realm = nil end
    me = { full = full, first = full:match("^(%S+)"), realm = realm and realm:lower() }
end

-- Is a player link's name (its first field, "First Surname" as Blizzard
-- passes it: LinkUtil.lua:154) you? Only your full name, or it with your own
-- realm: the same name on another realm isn't you (Codex, #83).
local function isMe(name)
    name = name:lower():gsub("%s+", " ")
    return name == me.full or (me.realm ~= nil and name == me.full .. "-" .. me.realm)
end

-- Separators outside ASCII still end a word (Codex, #83): no-break space,
-- curly quotes, guillemets, en and em dashes, the ellipsis.
local SEPARATORS = { "\194\160", "\226\128\152", "\226\128\153", "\226\128\156", "\226\128\157",
    "\194\171", "\194\187", "\226\128\147", "\226\128\148", "\226\128\166" }

-- The text as seen on screen, lower-cased, spaces collapsed. For your name,
-- player links naming someone else become a space first ("[Example Othername]"
-- isn't you); an escaped pipe ("||") is set aside so it's never read as one.
local ESC = "\2"
local function visible(msg, forName)
    local s = msg:gsub("||", ESC)
    if forName then
        s = s:gsub("|Hplayer:([^|]*)|h.-|h", function(data)
            if isMe(data:match("^[^:]*")) then return nil end
            return " "
        end)
    end
    s = GC.Copy.Plain(s) or ""
    s = s:gsub(ESC, "|"):lower()
    for _, sep in ipairs(SEPARATORS) do s = s:gsub(sep, " ") end
    return (s:gsub("%s+", " "))
end

-- A phrase at word edges. Bytes >= 0x80 are word bytes, so "examplé" never
-- matches "exampl"; lower() is ASCII-only, so "Élise" and "élise" differ.
local function isWord(b) return b and ((b >= 48 and b <= 57) or (b >= 97 and b <= 122) or b >= 128) end
function Alerts.HasPhrase(text, phrase)
    local start = 1
    while true do
        local a, b = text:find(phrase, start, true)
        if not a then return false end
        if not isWord(text:byte(a - 1)) and not isWord(text:byte(b + 1)) then return true end
        start = a + 1
    end
end

local function words()
    local db = GC.db
    if type(rawget(db, "alertWords")) ~= "table" then db.alertWords = {} end
    return db.alertWords
end

-- Does this message mention you or one of your words? Plain strings only.
function Alerts.Matches(msg)
    if not me then Alerts.ReadNames() end
    local mode = GC.db.alertName
    if me and (mode == "first" or mode == "full") then
        if Alerts.HasPhrase(visible(msg, true), mode == "first" and me.first or me.full) then return true end
    end
    local list = words()
    if #list == 0 then return false end
    local text = visible(msg, false)
    for _, w in ipairs(list) do
        if Alerts.HasPhrase(text, w) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- The alert
--------------------------------------------------------------------------------

function Alerts.Play(name)
    local kit = Alerts.SOUNDS[name]
    if not kit then return end
    local ok, willPlay = pcall(PlaySound, kit, "Master")   -- "Master": plays with sound effects off
    if not ok or not willPlay then API.Fail("alert sound", "sound did not play (kit " .. kit .. ")") end
end

-- The lines that alerted, this session (owner: "highlight the button so I
-- can click it and see the alerts"): newest last, at most LOG_SIZE, plain
-- strings only. unseen counts those since the button was last clicked.
Alerts.LOG_SIZE = 100
local log = {}
Alerts.unseen = 0
local function where(event, channel)
    if event == "CHAT_MSG_CHANNEL" and plain(channel) and type(channel) == "string" and channel ~= "" then
        return channel   -- the client's own label, shown, never compared
    end
    return (event:gsub("^CHAT_MSG_", ""):lower())
end
function Alerts.Record(event, msg, sender, channel)
    local who = (plain(sender) and type(sender) == "string" and sender ~= "") and sender or "?"
    log[#log + 1] = date("%H:%M:%S") .. " [" .. where(event, channel) .. "] " .. who .. ": " .. (GC.Copy.Plain(msg) or "")
    if #log > Alerts.LOG_SIZE then table.remove(log, 1) end
    Alerts.unseen = Alerts.unseen + 1
end
function Alerts.Log() return log end

-- Sound and flash together, at most once per EVERY seconds; nothing queued.
local last
function Alerts.Fire()
    if Alerts.Lit then Alerts.Lit() end   -- the button, every time (the throttle is for the noise)
    local now = GetTime()
    if last and now - last < Alerts.EVERY then return end
    last = now
    Alerts.Play(GC.db.alertSound)
    if GC.db.alertFlash and FlashClientIcon then
        local ok, err = pcall(FlashClientIcon)
        if not ok then API.Fail("alert flash", err) end
    end
end

-- At most one alert per (event, lineID): a line reaches the filter once per
-- window that shows it (FOREVER-PROBE 10). Every decision is remembered.
Alerts.MEMO_SIZE = 200
local memo, memoOrder = {}, {}
local function remember(key)
    memoOrder[#memoOrder + 1] = key
    memo[key] = true
    if #memoOrder > Alerts.MEMO_SIZE then memo[table.remove(memoOrder, 1)] = nil end
end

function Alerts.Filter(_, event, msg, ...)
    if not GC.db.alerts then return false end
    if not plain(event) or type(event) ~= "string" or not plain(msg) or type(msg) ~= "string" then return false end
    local sender, _, channel = ...          -- arg2, arg4
    local lineID, guid = select(10, ...)   -- arg11, arg12
    if not plain(guid) then return false end
    local mine = UnitGUID("player")
    if not plain(mine) then return false end
    if guid ~= nil and guid == mine then return false end
    local key
    if plain(lineID) and type(lineID) == "number" and lineID > 0 then key = event .. "#" .. lineID end
    if key then
        if memo[key] then return false end
        remember(key)
    end
    if Alerts.Matches(msg) then
        Alerts.Record(event, msg, sender, channel)
        Alerts.Fire()
    end
    return false
end

--------------------------------------------------------------------------------
-- /gchat alert
--------------------------------------------------------------------------------

local function oneOf(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end
Alerts.OneOf = oneOf

-- A word as kept: trimmed, spaces collapsed, lower-cased.
local function normalize(p) return (p:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "):lower()) end

function Alerts.Command(arg)
    local db = GC.db
    local sub, rest = arg:match("^(%S*)%s*(.-)%s*$")
    sub = sub:lower()
    if sub == "on" or sub == "off" then
        GC.Settings.SetAlerts(sub == "on")
        say("alerts " .. sub)
    elseif sub == "add" then
        local w, list = normalize(rest), words()
        if w == "" then say("/gchat alert add <word or phrase>")
        elseif #w > Alerts.MAX_WORD then say("too long: at most " .. Alerts.MAX_WORD .. " letters")
        elseif oneOf(list, w) then say("already watched: " .. w)
        elseif #list >= Alerts.MAX_WORDS then say("at most " .. Alerts.MAX_WORDS .. " words: remove one first")
        else list[#list + 1] = w; say("alert on: " .. w) end
    elseif sub == "remove" then
        local w, list = normalize(rest), words()
        for i, x in ipairs(list) do
            if x == w then table.remove(list, i); say("no longer watched: " .. w); return end
        end
        say("not watched: " .. w)
    elseif sub == "name" and oneOf(Alerts.NAME_MODES, rest:lower()) then
        GC.Settings.SetAlertName(rest:lower())
        say("your name: " .. rest:lower())
    elseif sub == "sound" and oneOf(Alerts.SOUND_NAMES, rest:lower()) then
        GC.Settings.SetAlertSound(rest:lower())
        Alerts.Play(rest:lower())   -- a sample
        say("alert sound: " .. rest:lower())
    elseif sub == "flash" and (rest == "on" or rest == "off") then
        GC.Settings.SetAlertFlash(rest == "on")
        say("taskbar flash " .. rest)
    else
        local onOff = function(v) return v and "on" or "off" end
        say("alerts are " .. onOff(db.alerts) .. "; your name: " .. db.alertName .. "; sound: " .. db.alertSound
            .. "; taskbar flash: " .. onOff(db.alertFlash))
        local list = words()
        say(#list > 0 and ("your words: " .. table.concat(list, ", ")) or "no words of your own yet")
        say("/gchat alert on/off - a sound when public, guild or group chat mentions you (not whispers)")
        say("/gchat alert name first/full/off - your first name alone, or First Surname")
        say("/gchat alert add/remove <words> - your own words, on all your characters (not sent by settings send)")
        say("/gchat alert sound raid/ready/tell/lfg/off - which sound, plays a sample (lfg: LFG Bulletin Board's)")
        say("/gchat alert flash on/off - blink the game in the taskbar")
        say("accented capitals count as different letters: write a word as people type it")
    end
end

--------------------------------------------------------------------------------
-- The button: a side button beside the chat (Buttons.Side), just above
-- Blizzard's chat-menu bubble. Gold at rest; green, pulsing, with a count
-- while alerts wait; a click lists them.
--------------------------------------------------------------------------------

function Alerts.Open()
    local status = #log .. " this session, newest last"
    if #log == 0 then status = "nothing has mentioned you this session" end
    GC.Copy.Show("Alerts: chat that mentioned you", table.concat(log, "\n"), status)
    Alerts.unseen = 0
    Alerts.Lit()
end

function Alerts.Lit() GC.Buttons.PaintSide("alerts") end

GC.Buttons.Side("alerts", {
    order = 1,
    text = "!",   -- no frameless bell is known on this client
    tooltip = "Alerts: chat that mentioned you",
    count = function() return Alerts.unseen end,
    shown = function() return GC.db.alerts end,
    onClick = function() Alerts.Open() end,
})

local started = false
function Alerts.Start()
    if started then return end
    started = true
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function()
        Alerts.ReadNames()
        -- After Url's, explicitly: the order doesn't rest on two frames' event order.
        if GC.Url and GC.Url.AddFilters then GC.Url.AddFilters() end
        if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
            for _, e in ipairs(Alerts.EVENTS) do ChatFrameUtil.AddMessageEventFilter(e, Alerts.Filter) end
        end
    end)
    API.RegisterEvents(f, { "PLAYER_LOGIN" })
end

Alerts._test = {
    reset = function() memo, memoOrder, last, me, log = {}, {}, nil, nil, {}; Alerts.unseen = 0 end,
    button = function() return GC.Buttons._test.side("alerts") end,
}
