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
