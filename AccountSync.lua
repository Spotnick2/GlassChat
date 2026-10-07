-- AccountSync.lua: GlassChat's link to your other WoW accounts, through the
-- embedded LibAccountSync-1.0 (Spotnick2/LibAccountSync; the TOC loads its
-- XML first). GlassChat is the library's pilot consumer.
--
-- One instance, tag "GlassChat" (wire-visible and permanent: never change
-- it). Its store holds the household key, so it must never be written into
-- SavedVariables\GlassChat.lua: that file holds focus mode's export, which is
-- meant to be shared. The client writes ONE file per addon, whatever the
-- number of variables (Codex review of #40), so the store is declared by the
-- Spam & Ignore plugin, the only feature that sends: GlassChatSpamIgnoreSyncDB,
-- in SavedVariables\GlassChatSpamIgnore.lua. Without the plugin there's no
-- store, and the library never chooses a key (it fails closed). The getter
-- reads it raw, nil until those SavedVariables load (the library asks for it
-- again on every access).
--
-- A payload is "<kind>\n<body>", so features share the one tag: Spam &
-- Ignore's list snapshot registers kind "SI". The library gives the sender
-- from Blizzard's own sender id, never from the payload, and the payload is
-- data: handlers validate it and never run it.

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local AS = {}
GC.AccountSync = AS

AS.TAG = "GlassChat"
AS.MAX = 32768          -- the wire ceiling; Spam & Ignore's large lists need more than the 16 KB default
AS.REPORTS = 20

local handlers = {}
local reports = {}

local function report(text, kind)
    if API.IsSecret(text) or type(text) ~= "string" then return end
    reports[#reports + 1] = { text = text, kind = kind }
    if #reports > AS.REPORTS then table.remove(reports, 1) end
    if kind == "error" then API.Fail("account sync", text) end
    if kind == "error" or (GC.IsDev and GC.IsDev()) then API.Print("account sync: " .. text) end
end

local function store()
    local t = rawget(_G, "GlassChatSpamIgnoreSyncDB")
    return type(t) == "table" and t or nil
end

local function dispatch(payload, sender, sid)
    if API.IsSecret(payload) or type(payload) ~= "string" then return end
    local kind, body = payload:match("^(%w+)\n(.*)$")
    local fn = kind and handlers[kind]
    if not fn then return end   -- a kind this copy doesn't know: ignored
    local ok, err = pcall(fn, body, sender, sid)
    if not ok then API.Fail("account sync " .. kind, err) end
end

local lib = rawget(_G, "LibStub") and LibStub("LibAccountSync-1.0", true)
if lib then
    local ok, inst = pcall(lib.New, lib, { addon = AS.TAG, store = store, report = report, maxPayload = AS.MAX })
    if ok and inst then
        AS.inst = inst
        inst.OnMessage(dispatch)
    else
        API.Fail("account sync", inst or "no instance")
    end
end

-- GlassChat's ADDON_LOADED: a store an earlier build kept in GlassChat.lua
-- (GlassChatDB.accountSync, then GlassChatSyncDB) is taken out of it, held for
-- the plugin's ADDON_LOADED, and never written back there.
local pending
function AS.EnsureStore(db)
    local old = rawget(db, "accountSync")
    local older = rawget(_G, "GlassChatSyncDB")
    pending = (type(older) == "table" and older) or (type(old) == "table" and old) or nil
    db.accountSync = nil
    GlassChatSyncDB = nil
end

-- The plugin's ADDON_LOADED: its own SavedVariables hold the store from now
-- on; one moved out of GlassChat.lua is adopted with its key (so the trust the
-- accounts built survives).
function AS.AdoptStore()
    if type(rawget(_G, "GlassChatSpamIgnoreSyncDB")) ~= "table" then
        GlassChatSpamIgnoreSyncDB = pending or {}
    end
    pending = nil
end

-- A feature's payloads: fn(body, sender, sid).
function AS.On(kind, fn) handlers[kind] = fn end

-- Send a feature's body to every own account online: the library's
-- (count) or (nil, reason).
function AS.Send(kind, body, onResult)
    if not AS.inst then return nil, "not-ready" end
    return AS.inst.Send(kind .. "\n" .. body, onResult)
end

-- Send, telling the player how it went, for every feature alike (the lists'
-- wording, #40). what: "your lists"; again: the command to retry with. The
-- library can report a result while Send is still running (in game: it
-- did): those wait, so the summary comes first and each result after.
-- Returns the library's (count) or (nil, reason).
AS.WHY = {
    disabled = "account sync is off (/gchat ignore sync on)",
    ["no-peers"] = "none of your other accounts is online, or none is known yet (/gchat ignore sync status)",
    ["not-ready"] = "still connecting to your other accounts; try again in a few seconds",
    offline = "Battle.net is offline",
    ["no-route"] = "no way to reach your other accounts right now; try again in a few seconds",
}
local PER = {
    offline = "it went offline",
    ["no-route"] = "no way to reach it right now",
    ["not-ready"] = "it isn't ready yet",
    ["too-large"] = "%s too large",
}
local function plainName(s)
    return type(s) == "string" and not API.IsSecret(s) and #s >= 1 and #s <= 64 and not s:find("[%c|]")
end
-- The library answers "disabled" also while Battle.net isn't usable or the
-- login hasn't finished: with the switch on, say that instead (review of #40).
function AS.WhyNot(why, what)
    if why == "disabled" and AS.IsEnabled() then
        return "Battle.net isn't ready for account sync yet (logging in, or disconnected); try again in a few seconds"
    end
    return AS.WHY[why] or ("couldn't send " .. what .. " (" .. tostring(why) .. ")")
end
-- after: a line printed right after the summary (the lists' "couldn't be
-- written" count).
function AS.SendReported(kind, body, what, again, after)
    local say = API.Print
    local inSend, waiting = true, {}
    local sent, why = AS.Send(kind, body, function(peer, status, reason)
        local who = (type(peer) == "table" and plainName(peer.name) and peer.name) or "your other account"
        local line
        if status == "sent" then
            line = what .. " were handed to Battle.net for " .. who .. " (there's no delivery receipt)"
        elseif reason == "not-ready" then
            line = who .. " isn't ready yet; try " .. again .. " again in a few seconds"
        else
            local per = PER[reason] and PER[reason]:format("the " .. (what:gsub("^your ", "")) .. " are") or tostring(reason)
            line = "|cffff6060couldn't send " .. what .. " to " .. who .. ": " .. per .. "|r"
        end
        if inSend then waiting[#waiting + 1] = line else say(line) end
    end)
    inSend = false
    if not sent then
        if why == "too-large" then
            say(string.format("|cffff6060%s are too large to send (%.1f KB; at most %d KB)|r",
                what, #body / 1024, AS.MAX / 1024))
        else
            say(AS.WhyNot(why, what))
        end
        for _, line in ipairs(waiting) do say(line) end
        return nil, why
    end
    -- 0: every account found is still mid-handshake; each result says so.
    if sent > 0 then
        say(string.format("sending %s (%.1f KB) to %d other account%s...", what, #body / 1024, sent,
            sent == 1 and "" or "s"))
    end
    if after then say(after) end
    for _, line in ipairs(waiting) do say(line) end
    return sent
end

function AS.IsEnabled() return AS.inst ~= nil and AS.inst.IsEnabled() == true end
function AS.SetEnabled(on) if AS.inst then AS.inst.SetEnabled(on and true or false) end end
function AS.Rescan() if AS.inst then AS.inst.Rescan() end end
function AS.Peers() return AS.inst and AS.inst.Peers() or {} end

-- The readout: whether it's on, the library's diagnostics (who counts as
-- yours and why), and its recent reports.
function AS.Status()
    local out = {}
    if not AS.inst then
        out[1] = "the account-sync library isn't loaded"
        return out
    end
    out[#out + 1] = "account sync: " .. (AS.IsEnabled() and "on" or "off")
    local ok, err = pcall(function()
        for line in AS.inst.Diagnostics() do out[#out + 1] = line end
    end)
    if not ok then out[#out + 1] = "diagnostics failed: " .. tostring(err) end
    for _, r in ipairs(reports) do out[#out + 1] = "(" .. (r.kind or "info") .. ") " .. r.text end
    return out
end

AS._test = { dispatch = dispatch, reports = reports, store = store }
