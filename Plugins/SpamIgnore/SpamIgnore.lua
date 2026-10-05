-- SpamIgnore.lua: the Spam & Ignore plugin's filter (docs/PLAN-SPAM.md, S1).
--
-- One message filter, two policies:
-- - EXPLICIT IGNORES (by GUID) on every player-chat event, guild and group
--   included: an ignored player stays ignored if they join your group;
-- - HEURISTICS (muted words, CJK, repeats) on PUBLIC chat only, never for
--   you, friends, guild, group, Battle.net friends or the allow list.
-- Measured (docs/FOREVER-PROBE.md 10-12): lineID (arg11) is plain, positive
-- and the same in every window that shows a line, so one decision per
-- (event, lineID) serves every window; senders (arg2) are "First Surname";
-- Blizzard's ignore list isn't readable before PLAYER_LOGIN.
-- Never: your own characters ignored, a secret read. Blizzard's server list
-- is kept in step by Mirror.lua (S2b).

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local Text = GC.SpamText
local Spam = {}
GC.Spam = Spam

Spam.ADDON = "GlassChatSpamIgnore"
Spam.MEMO_SIZE = 200
Spam.MUTE_MAX = 100   -- bytes; /gchat mute refuses longer, Load drops longer
Spam.LOG_SIZE = 200
Spam.REPEAT_CAP = 500
Spam.NAME_CAP = 500

-- Every value consumed is checked with IsSecret BEFORE any other use.
local function plainString(v)
    if API.IsSecret(v) or type(v) ~= "string" then return nil end
    return v
end
Spam.PlainString = plainString
local function plainNumber(v)
    if API.IsSecret(v) or type(v) ~= "number" then return nil end
    return v
end

Spam.IGNORE_EVENTS = { "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_WHISPER", "CHAT_MSG_DND", "CHAT_MSG_AFK", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }
Spam.PUBLIC = { CHAT_MSG_CHANNEL = true, CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_EMOTE = true }

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

-- icon: the tab-strip icon is opt-in (owner: "disabled by default and I will
-- turn it on"); the log is always /gchat spam log.
-- mirror: keep each character's Blizzard ignore list in step (S2b; owner:
-- "sync the Blizzard ignore list on every account").
local DEFAULTS = { cjk = true, repeatWindow = 300, icon = false, mirror = true }

function Spam.Load()
    if type(GlassChatSpamIgnoreDB) ~= "table" then GlassChatSpamIgnoreDB = {} end
    local db = GlassChatSpamIgnoreDB
    for _, k in ipairs({ "mutes", "ignore", "pending", "own", "allow" }) do
        if type(db[k]) ~= "table" then db[k] = {} end
    end
    -- Saved entries are checked on load: plain types and lengths only.
    for guid, e in pairs(db.ignore) do
        if type(guid) ~= "string" or type(e) ~= "table" or type(e.name) ~= "string" then db.ignore[guid] = nil end
    end
    for l, e in pairs(db.pending) do
        if type(l) ~= "string" or type(e) ~= "table" or type(e.name) ~= "string" then db.pending[l] = nil end
    end
    local mutes = {}
    for _, m in ipairs(db.mutes) do
        if type(m) == "table" and type(m.phrase) == "string" and #m.phrase <= Spam.MUTE_MAX then mutes[#mutes + 1] = m end
    end
    db.mutes = mutes
    setmetatable(db, { __index = DEFAULTS })
    if type(GlassChatSpamIgnoreCharDB) ~= "table" then GlassChatSpamIgnoreCharDB = {} end
    Spam.db, Spam.charDB = db, GlassChatSpamIgnoreCharDB
    Spam.RebuildMutes()
    return db
end

-- A dev or test build keeps the debug log (owner: "until we make an official
-- release"): the packager replaces @project-version@, the deploy script
-- writes "dev". /gchat spam debug on|off overrides it.
function Spam.IsDebug()
    local forced = Spam.db and Spam.db.debug
    if forced ~= nil then return forced end
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    local ok, v = false, nil
    if get then ok, v = pcall(get, Spam.ADDON, "Version") end
    v = ok and plainString(v) or nil
    return v == nil or v == "dev" or v:find("@project%-version@") ~= nil
end

--------------------------------------------------------------------------------
-- Session state: the memo, the repeat keys, names seen, the log
--------------------------------------------------------------------------------

local memo, memoOrder = {}, {}
local repeats, repeatOrder = {}, {}
local names, nameOrder = {}, {}   -- lower-case "first surname" -> guid
local log = {}
Spam.unseen = 0
Spam.onHidden = nil   -- set by the UI: repaint the icon

local function remember(store, order, key, value, cap)
    if store[key] == nil then
        order[#order + 1] = key
        if #order > cap then store[table.remove(order, 1)] = nil end
    end
    store[key] = value
end

local function now() return GetTime() end

--------------------------------------------------------------------------------
-- Who is who
--------------------------------------------------------------------------------

local groupGUIDs = {}
function Spam.RefreshGroup()
    groupGUIDs = {}
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if type(n) ~= "number" or API.IsSecret(n) then return end
    local prefix = IsInRaid and IsInRaid() and "raid" or "party"
    for i = 1, n do
        local g = plainString(UnitGUID(prefix .. i))
        if g then groupGUIDs[g] = true end
    end
end

local function playerGUID() return plainString(UnitGUID("player")) end

-- Your own characters, account-wide (owner: never ignore them).
function Spam.RecordSelf()
    local g = playerGUID()
    if not g then return end
    local name = API.PlayerFullName()   -- "First Surname", whichever shape the client gives (AltStable #56)
    Spam.db.own[g] = { name = name or "?", seen = time() }
end

-- Your characters on your OTHER WoW accounts, from AltStable when it's
-- installed (S3): its public API lists every character it has synced, by
-- GUID and full name (AltStable docs/PUBLIC-API.md, version 1 only). Read at
-- login and again on its CharactersChanged callback, never per chat line
-- (GetCharacters builds fresh copies). Without AltStable this stays empty.
-- Names count only while the client says names are unique in the region
-- (RegionalUniqueNamesEnabled, measured true: FOREVER-PROBE 11; AltStable
-- syncs within one region) and only with a surname: a bare first name from
-- an older AltStable peer is never a name match (review of #34).
local alt = { guids = {}, names = {} }
local function altStableV1()
    local AS = rawget(_G, "AltStable")
    if type(AS) == "table" and AS.PUBLIC_API_VERSION == 1 then return AS end
end
local function namesUnique()
    local fn = rawget(_G, "RegionalUniqueNamesEnabled")
    if not fn then return false end
    local ok, v = pcall(fn)
    return ok and not API.IsSecret(v) and v == true
end
local function readAltStable(AS)
    local list = AS.GetCharacters()
    if type(list) ~= "table" then return end
    local guids, names, unique = {}, {}, namesUnique()
    for _, c in ipairs(list) do
        if type(c) == "table" then
            local g, n = plainString(c.guid), plainString(c.name)
            if g and g:sub(1, 7) == "Player-" then
                guids[g] = true
                if unique and n and n:find("%S %S") then names[n:lower()] = true end
            end
        end
    end
    alt.guids, alt.names = guids, names
end
function Spam.RefreshAltStable()
    local AS = altStableV1()
    if not AS or type(AS.GetCharacters) ~= "function" then return end
    local ok, err = pcall(readAltStable, AS)
    if not ok then API.Fail("spam altstable read", err) end
end
local altHooked = false
local function hookAltStable()
    local AS = altStableV1()
    if altHooked or not AS or type(AS.RegisterCallback) ~= "function" then return end
    local ok, err = pcall(AS.RegisterCallback, "CharactersChanged", function()
        Spam.RefreshAltStable()
        -- A character just learned to be yours may be linked on Blizzard's list here.
        if GC.SpamMirror then GC.SpamMirror.Check("altstable") end
    end)
    if ok then altHooked = true else API.Fail("spam altstable hook", err) end
end

local function isOwn(guid)
    return guid == playerGUID() or Spam.db.own[guid] ~= nil or alt.guids[guid] ~= nil
end
-- With a GUID known, only the GUID says whose a character is; a name is the
-- fallback for a player not seen yet (pending). Key on the GUID (CLAUDE.md).

local function ownByName(lname)
    if alt.names[lname] then return true end
    for _, e in pairs(Spam.db.own) do
        if type(e.name) == "string" and e.name:lower() == lname then return true end
    end
    return false
end
Spam.IsOwn, Spam.OwnByName = isOwn, ownByName

-- Exempt from heuristics: you, friends, guild, group, Battle.net friends,
-- the allow list. Each lookup is guarded; an error means "not exempt".
local function exempt(guid)
    if isOwn(guid) or Spam.db.allow[guid] or groupGUIDs[guid] then return true end
    local function yes(fn)
        if not fn then return false end
        local ok, v = pcall(fn, guid)
        return ok and not API.IsSecret(v) and v and true or false
    end
    return yes(C_FriendList and C_FriendList.IsFriend) or yes(IsGuildMember)
        or yes(C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID)
end

--------------------------------------------------------------------------------
-- Rules
--------------------------------------------------------------------------------

local muteForms = {}
function Spam.RebuildMutes()
    muteForms = {}
    for _, m in ipairs(Spam.db.mutes) do
        local form = m.aggressive and Text.Aggressive(m.phrase) or Text.Visible(m.phrase)
        if form ~= "" then muteForms[#muteForms + 1] = { form = form, aggressive = m.aggressive, phrase = m.phrase } end
    end
end

local function mutedBy(text)
    local visible, aggressive
    for _, m in ipairs(muteForms) do
        if m.aggressive then
            aggressive = aggressive or Text.Aggressive(text)
            if aggressive:find(m.form, 1, true) then return m.phrase end
        else
            visible = visible or Text.Visible(text)
            if Text.HasPhrase(visible, m.form, true) then return m.phrase end
        end
    end
end

-- Repeats: timed from the last SHOWN post, so a sender gets one post per
-- window and is never hidden for ever (Codex's review of the plan).
local function isRepeat(event, guid, text)
    local key = event .. "|" .. guid .. "|" .. Text.RepeatKey(text)
    local last = repeats[key]
    if last and now() - last < Spam.db.repeatWindow then return true end
    remember(repeats, repeatOrder, key, now(), Spam.REPEAT_CAP)
    return false
end

--------------------------------------------------------------------------------
-- The decision
--------------------------------------------------------------------------------

-- nil = show; else the reason it's hidden. stateless: only the checks that
-- give the same answer each time (ignores, mutes, CJK), never the repeat
-- state, for a line with no usable lineID (the plan; Codex review of #20).
function Spam.Judge(event, text, sender, guid, stateless)
    local lname = sender and sender:lower()
    -- Explicit ignores: every player-chat event, never your own characters.
    if not isOwn(guid) then
        if Spam.db.ignore[guid] then return "ignored" end
        if lname and Spam.db.pending[lname] then   -- the GUID isn't ours (above): the name can't make it so
            -- A pending ignore (imported, or typed before we saw them) meets
            -- its GUID: from now on it's by GUID.
            Spam.db.ignore[guid] = { name = sender, added = time(), note = Spam.db.pending[lname].note }
            Spam.db.pending[lname] = nil
            return "ignored"
        end
    end
    if not Spam.PUBLIC[event] or exempt(guid) then return nil end
    local phrase = mutedBy(text)
    if phrase then return "muted: " .. phrase end
    if Spam.db.cjk and Text.IsCJK(text) then return "cjk" end
    if not stateless and isRepeat(event, guid, text) then return "repeat" end
    return nil
end

local function record(event, text, sender, guid, reason)
    local entry = { t = date("%H:%M:%S"), event = event:gsub("^CHAT_MSG_", ""), sender = sender or "?",
                    reason = reason, text = GC.Copy.Plain(text) or "", guid = guid }
    log[#log + 1] = entry
    if #log > Spam.LOG_SIZE then table.remove(log, 1) end
    Spam.unseen = Spam.unseen + 1
    if Spam.onHidden then pcall(Spam.onHidden) end
end

-- The message filter: (chatFrame, event, arg1..arg14). Returns true to hide.
function Spam.Filter(_, event, ...)
    local text, sender = plainString((select(1, ...))), plainString((select(2, ...)))
    local lineID, guid = plainNumber((select(11, ...))), plainString((select(12, ...)))
    if not (text and guid) or guid:sub(1, 7) ~= "Player-" then return false end
    if sender then remember(names, nameOrder, sender:lower(), guid, Spam.NAME_CAP) end
    -- One decision per (event, lineID): a line shown in two windows is
    -- judged and logged once (measured: each line reaches the filter once per
    -- window). Without a usable lineID there's no memo, so the line may be
    -- judged once per window: only the stateless checks run, and it isn't
    -- logged or counted (it can't be told apart from another copy).
    local key = lineID and lineID > 0 and (event .. "#" .. lineID) or nil
    if key and memo[key] ~= nil then return memo[key] ~= false end
    local ok, reason = pcall(Spam.Judge, event, text, sender, guid, key == nil)
    if not ok then API.Fail("spam judge", reason); reason = nil end
    if key then remember(memo, memoOrder, key, reason or false, Spam.MEMO_SIZE) end
    if reason and key then record(event, text, sender, guid, reason) end
    return reason ~= nil
end

--------------------------------------------------------------------------------
-- The ignore list
--------------------------------------------------------------------------------

-- A name -> GUID: the target, else someone seen in chat this session.
function Spam.Resolve(name)
    local lname = name:lower()
    if UnitIsPlayer and UnitIsPlayer("target") then
        local tname = plainString(GetUnitName("target", true))
        if tname and tname:lower() == lname then return plainString(UnitGUID("target")), tname end
    end
    return names[lname], name
end

-- Returns a message for the player.
function Spam.Ignore(name)
    if name == "" then return "/gchat ignore <First Surname>" end
    local guid, shown = Spam.Resolve(name)
    if (guid and isOwn(guid)) or (not guid and ownByName(name:lower())) then
        return "that's one of your own characters: not ignored"
    end
    if guid then
        Spam.db.ignore[guid] = { name = shown, added = time() }
        Spam.db.pending[name:lower()] = nil
        return "ignoring " .. shown .. " on all your characters"
    end
    Spam.db.pending[name:lower()] = { name = name, added = time() }
    return "ignoring " .. name .. " (pending: their next line confirms who they are)"
end

-- Forget every per-line decision (the lists changed under them).
function Spam.ResetMemo() memo, memoOrder = {}, {} end

function Spam.Unignore(name)
    local lname = name:lower()
    local found = false
    for guid, e in pairs(Spam.db.ignore) do
        if e.name:lower() == lname then Spam.db.ignore[guid] = nil; found = true end
    end
    if Spam.db.pending[lname] then Spam.db.pending[lname] = nil; found = true end
    -- A hidden line from them is no longer hidden by an old decision.
    memo, memoOrder = {}, {}
    return found and ("no longer ignoring " .. name) or (name .. " isn't on your list")
end

-- Explicit import of this character's Blizzard list (never before
-- PLAYER_LOGIN: measured nil at ADDON_LOADED).
function Spam.Import()
    local list = GC.SpamMirror.ReadServer()
    if not list then return "Blizzard's ignore list isn't ready yet; try again in a moment" end
    local added, pending, own = 0, 0, 0
    for _, name in pairs(list) do
        do
            local lname = name:lower()
            local guid = names[lname]
            if (guid and isOwn(guid)) or (not guid and ownByName(lname)) then
                own = own + 1
            elseif guid then
                Spam.db.ignore[guid] = { name = name, added = time(), note = "imported" }
                added = added + 1
            elseif not Spam.db.pending[lname] then
                Spam.db.pending[lname] = { name = name, added = time(), note = "imported" }
                pending = pending + 1
            end
        end
    end
    Spam.charDB.imported = time()
    return string.format("imported %d (%d pending until they speak)%s", added + pending, pending,
        own > 0 and (", skipped " .. own .. " of your own characters") or "")
end

--------------------------------------------------------------------------------
-- The log
--------------------------------------------------------------------------------

function Spam.Log() return log end

function Spam.LogText(debug)
    local lines = {}
    for i = #log, 1, -1 do
        local e = log[i]
        if debug then
            lines[#lines + 1] = string.format("%s  [%s] %s (%s): %s", e.t, e.reason, e.sender, e.event, e.text)
        else
            lines[#lines + 1] = string.format("%s  [%s] %s: %s", e.t, e.reason, e.sender, e.text)
        end
    end
    return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= Spam.ADDON then return end
        Spam.Load()
        if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
            for _, e in ipairs(Spam.IGNORE_EVENTS) do ChatFrameUtil.AddMessageEventFilter(e, Spam.Filter) end
        end
        if GC.SpamMirror then GC.SpamMirror.Start() end
        if GC.SpamSync then GC.SpamSync.Start() end
        if GC.SpamUI then GC.SpamUI.Start() end
    elseif event == "PLAYER_LOGIN" then
        Spam.RecordSelf()
        Spam.RefreshGroup()
        hookAltStable()
        Spam.RefreshAltStable()
    elseif event == "GROUP_ROSTER_UPDATE" then
        Spam.RefreshGroup()
    end
end)
API.RegisterEvents(f, { "ADDON_LOADED", "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE" })

Spam._test = {
    reset = function()
        memo, memoOrder, repeats, repeatOrder, names, nameOrder, log = {}, {}, {}, {}, {}, {}, {}
        alt, altHooked = { guids = {}, names = {} }, false
        Spam.unseen = 0
    end,
    names = function() return names end,
}
