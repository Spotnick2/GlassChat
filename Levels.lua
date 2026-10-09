-- Levels.lua (#71): a player's level before their name in chat, "[60:Name]",
-- as Prat's PlayerNames module does (modules\PlayerNames.lua:718).
--
-- A chat event doesn't carry the sender's level, so we keep a session cache,
-- keyed by GUID, filled from every place the client gives one: you, your
-- group, your target and mouseover, your friends and your guild. A sender we
-- never saw gets no level. No /who queries of our own (Prat's LibWho option):
-- they're throttled, and their answers carry no GUID.
--
-- The display goes through ChatFrameUtil.AddSenderNameFilter: the filters run
-- last in GetDecoratedSenderName (ChatFrameUtil.lua:1112) with
-- (event, decoratedName, arg1..arg14), arg12 being the sender's GUID. The
-- name we return goes inside the player link's brackets
-- (ChatFrameOverrides.lua:576-585); the link itself (arg2) is never
-- touched. Emotes print it without brackets (same lines), so they get no
-- level: "60:Name waves" reads as stray text. Blizzard skips the filter when
-- the name is secret (ChatFrameFilters.lua:36-41), and a nil return keeps
-- the name as it was.

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local Levels = {}
GC.Levels = Levels

Levels.MAX_LEVEL = 200   -- above any level a player can have; rejects junk
local byGUID = {}

local function plain(v) return not API.IsSecret(v) end

-- Record one player's level. Secrets, non-players and unknown levels (0, or
-- -1 for "??") are ignored.
function Levels.Note(guid, level)
    if not plain(guid) or not plain(level) then return end
    if type(guid) ~= "string" or not guid:find("^Player%-") then return end
    if type(level) ~= "number" or level < 1 or level > Levels.MAX_LEVEL then return end
    byGUID[guid] = math.floor(level)
end

function Levels.Of(guid)
    if not plain(guid) or type(guid) ~= "string" then return nil end
    return byGUID[guid]
end

function Levels.NoteUnit(unit)
    local ok, isPlayer = pcall(UnitIsPlayer, unit)
    if not ok or not plain(isPlayer) or not isPlayer then return end
    local guid, level = UnitGUID(unit), UnitLevel(unit)
    Levels.Note(guid, level)
end

-- Not "player": UnitLevel can lag PLAYER_LEVEL_UP, and a roster change right
-- after a level-up would put the old level back (review of #72). You are
-- noted at login and by your own level events.
function Levels.NoteGroup()
    local n = GetNumGroupMembers()
    if not plain(n) or type(n) ~= "number" or n == 0 then return end
    local prefix, count = "party", 4
    if IsInRaid() then prefix, count = "raid", 40 end
    for i = 1, count do Levels.NoteUnit(prefix .. i) end
end

function Levels.NoteFriends()
    local n = C_FriendList.GetNumFriends()
    if not plain(n) or type(n) ~= "number" then return end
    for i = 1, n do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if type(info) == "table" then Levels.Note(info.guid, info.level) end
    end
end

-- GetGuildRosterInfo is in the dump's _G walk with no documented signature
-- (no FrameXML calls it here): Retail's returns level 4th and the GUID 17th.
-- Unmeasured on Forever, so each value is checked: a GUID that isn't a
-- player's is dropped by Note.
function Levels.NoteGuild()
    if not IsInGuild() then return end
    local n = GetNumGuildMembers()
    if not plain(n) or type(n) ~= "number" then return end
    for i = 1, n do
        local _, _, _, level, _, _, _, _, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
        Levels.Note(guid, level)
    end
end

-- Ask for the guild roster (GUILD_ROSTER_UPDATE follows), at most once per
-- Levels.ROSTER_EVERY seconds: at login, when the guild info arrives
-- (PLAYER_GUILD_UPDATE, often after PLAYER_LOGIN), and on a guild line, so a
-- guildmate's level-up shows without the guild window open (review of #72).
Levels.ROSTER_EVERY = 120
local lastRoster
function Levels.RequestRoster()
    if not IsInGuild() then return end
    local now = GetTime()
    if lastRoster and now - lastRoster < Levels.ROSTER_EVERY then return end
    lastRoster = now
    C_GuildInfo.GuildRoster()
end

-- The difficulty colour for a level, as hex; nil when the client gives none.
-- Under pcall as a whole: the colour's fields are the client's.
local function hexOf(level)
    local c = GetQuestDifficultyColor(level)
    if type(c) ~= "table" or not plain(c.r) or not plain(c.g) or not plain(c.b) then return nil end
    if type(c.r) ~= "number" or type(c.g) ~= "number" or type(c.b) ~= "number" then return nil end
    return string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end
local function colorOf(level)
    local ok, hex = pcall(hexOf, level)
    return ok and hex or nil
end

function Levels.Decorate(name, level)
    local hex = colorOf(level)
    local text = hex and ("|c" .. hex .. level .. "|r") or tostring(level)
    return text .. ":" .. name
end

-- Emotes show the name unbracketed; a Battle.net line names the account, not
-- a character (Prat treats it apart, PlayerNames.lua:741-749).
local function skipped(event)
    return event == "CHAT_MSG_EMOTE" or event == "CHAT_MSG_TEXT_EMOTE"
        or event:sub(1, 12) == "CHAT_MSG_BN_"
end

function Levels.Filter(event, name, ...)
    if not GC.db.levels then return nil end
    if not plain(event) or type(event) ~= "string" or skipped(event) then return nil end
    local level = Levels.Of((select(12, ...)))   -- arg12: senderGUID
    if not level or not plain(name) or type(name) ~= "string" or name == "" then return nil end
    return Levels.Decorate(name, level)
end

local EVENTS = { "PLAYER_LOGIN", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "GROUP_ROSTER_UPDATE",
    "UNIT_LEVEL", "PLAYER_LEVEL_UP", "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER" }

local function onEvent(_, event, arg1)
    if event == "PLAYER_TARGET_CHANGED" then
        Levels.NoteUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Levels.NoteUnit("mouseover")
    elseif event == "UNIT_LEVEL" then
        if plain(arg1) and type(arg1) == "string" then Levels.NoteUnit(arg1) end
    elseif event == "PLAYER_LEVEL_UP" then
        -- UnitLevel("player") can still be the old level here; the event's own is new.
        Levels.Note(UnitGUID("player"), arg1)
    elseif event == "FRIENDLIST_UPDATE" then
        Levels.NoteFriends()
    elseif event == "GUILD_ROSTER_UPDATE" then
        Levels.NoteGuild()
    elseif event == "PLAYER_GUILD_UPDATE" or event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then
        Levels.RequestRoster()
    else   -- PLAYER_LOGIN, GROUP_ROSTER_UPDATE
        Levels.NoteGroup()
        if event == "PLAYER_LOGIN" then
            Levels.NoteUnit("player")
            Levels.NoteFriends()
            Levels.RequestRoster()
        end
    end
end

local started = false
function Levels.Start()
    if started then return end
    started = true
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(...)
        local ok, err = pcall(onEvent, ...)
        if not ok then API.Fail("levels", err) end
    end)
    API.RegisterEvents(f, EVENTS)
    if ChatFrameUtil and ChatFrameUtil.AddSenderNameFilter then
        ChatFrameUtil.AddSenderNameFilter(Levels.Filter)
    end
end

Levels._test = { reset = function() byGUID, lastRoster = {}, nil end, onEvent = onEvent }
