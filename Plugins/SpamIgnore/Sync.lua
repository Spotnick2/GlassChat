-- Sync.lua (Spam & Ignore, S3 part 2): copy this account's lists to your
-- other WoW accounts, through GlassChat's LibAccountSync-1.0 link
-- (AccountSync.lua; docs/PLAN-SPAM.md S3).
--
-- /gchat ignore send sends a SNAPSHOT: the whole ignore list (by GUID), the
-- pending names, the mutes and your own characters. The receiver applies it
-- WHOLE, removals included, with no merge (no tombstones, no clock skew) --
-- except your own characters, which are only ever added: a snapshot can't
-- make one of yours ignorable again.
--
-- The payload is data from another client: never run, every field checked
-- (GUID shape, lengths, counts), and a snapshot with an unknown format, a
-- malformed line or a field out of bounds is refused WHOLE; the lists stay as
-- they were. The sender comes from the library (Blizzard's sender id), never
-- from the payload. Each sender's stream ids only grow, so the last applied
-- one per sender GUID keeps an older snapshot, arriving late, from undoing a
-- newer one.
--
-- Format "SI1": one record per line, fields split by tabs:
--   SI1                          the format, first
--   T <time()>                   when it was sent (shown, not trusted for order)
--   I <guid> <name>              an ignore
--   P <name>                     a pending ignore (a name not seen yet)
--   M <0|1> <phrase>             a mute (1: aggressive)
--   O <guid> <name>              one of your own characters

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local Spam = GC.Spam
local Sync = {}
GC.SpamSync = Sync

Sync.KIND = "SI"
Sync.FORMAT = "SI1"
Sync.NAME_MAX = 48
Sync.CAPS = { I = 2000, P = 500, M = 500, O = 500 }

local function say(msg) API.Print(msg) end

local function plainField(s, max)
    return type(s) == "string" and not API.IsSecret(s) and #s >= 1 and #s <= max and not s:find("[%c|]")
end
local function isGuid(s)
    return type(s) == "string" and not API.IsSecret(s) and #s <= 64 and s:find("^Player%-%d+%-%x+$") ~= nil
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

-- This account's snapshot, and how many entries couldn't be written (a
-- field that breaks the format: never expected from our own lists).
function Sync.Build()
    local db = Spam.db
    local out, skipped = { Sync.FORMAT, "T\t" .. time() }, 0
    local counts = { I = 0, P = 0, M = 0, O = 0 }
    -- One of yours is never sent as an ignore: a receiver that doesn't know it
    -- is yours (no AltStable there) would ignore it (review of #40).
    for guid, e in pairs(db.ignore) do
        if Spam.IsOwn(guid) then
            -- skipped silently: it's already shown as one of yours in /gchat ignores
        elseif isGuid(guid) and plainField(e.name, Sync.NAME_MAX) then
            out[#out + 1] = "I\t" .. guid .. "\t" .. e.name
            counts.I = counts.I + 1
        else skipped = skipped + 1 end
    end
    for l, e in pairs(db.pending) do
        if Spam.OwnByName(l) then
            -- likewise
        elseif plainField(e.name, Sync.NAME_MAX) then out[#out + 1] = "P\t" .. e.name; counts.P = counts.P + 1
        else skipped = skipped + 1 end
    end
    for _, m in ipairs(db.mutes) do
        if plainField(m.phrase, Spam.MUTE_MAX) then
            out[#out + 1] = "M\t" .. (m.aggressive and "1" or "0") .. "\t" .. m.phrase
            counts.M = counts.M + 1
        else skipped = skipped + 1 end
    end
    -- Your own characters: recorded here, and AltStable's, so the receiver
    -- protects them too.
    local own = {}
    for guid, e in pairs(db.own) do own[guid] = e.name end
    for guid, name in pairs(Spam.AltOwn()) do
        if own[guid] == nil and type(name) == "string" then own[guid] = name end
    end
    for guid, name in pairs(own) do
        if isGuid(guid) and plainField(name, Sync.NAME_MAX) then
            out[#out + 1] = "O\t" .. guid .. "\t" .. name
            counts.O = counts.O + 1
        end
    end
    return table.concat(out, "\n"), skipped, counts
end

--------------------------------------------------------------------------------
-- Reading: all or nothing
--------------------------------------------------------------------------------

-- The parsed snapshot, or nil and why. Nothing here touches the lists.
function Sync.Parse(body)
    if API.IsSecret(body) or type(body) ~= "string" then return nil, "not text" end
    local snap = { ignore = {}, pending = {}, mutes = {}, own = {}, counts = { I = 0, P = 0, M = 0, O = 0 } }
    local first = true
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        if first then
            if line ~= Sync.FORMAT then return nil, "unknown format" end
            first = false
        elseif line ~= "" then
            local f = {}
            for field in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = field end
            local kind = f[1]
            if kind == "T" then
                if #f ~= 2 or not f[2]:find("^%d+$") then return nil, "bad time" end
                snap.sentAt = tonumber(f[2])
            elseif kind == "I" or kind == "O" then
                if #f ~= 3 or not isGuid(f[2]) or not plainField(f[3], Sync.NAME_MAX) then
                    return nil, "bad " .. kind .. " line"
                end
                local into = kind == "I" and snap.ignore or snap.own
                into[f[2]] = f[3]
            elseif kind == "P" then
                if #f ~= 2 or not plainField(f[2], Sync.NAME_MAX) then return nil, "bad P line" end
                snap.pending[f[2]:lower()] = f[2]
            elseif kind == "M" then
                if #f ~= 3 or (f[2] ~= "0" and f[2] ~= "1") or not plainField(f[3], Spam.MUTE_MAX) then
                    return nil, "bad M line"
                end
                snap.mutes[#snap.mutes + 1] = { phrase = f[3], aggressive = f[2] == "1" or nil }
            else
                return nil, "unknown line"
            end
            if snap.counts[kind] then
                snap.counts[kind] = snap.counts[kind] + 1
                if snap.counts[kind] > Sync.CAPS[kind] then return nil, "too many " .. kind .. " lines" end
            end
        end
    end
    return snap
end

--------------------------------------------------------------------------------
-- Applying
--------------------------------------------------------------------------------

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- Replace the lists with the snapshot's (own characters: added only).
function Sync.Apply(snap)
    local db = Spam.db
    for guid, name in pairs(snap.own) do
        if not db.own[guid] then db.own[guid] = { name = name, seen = time(), note = "sync" } end
    end
    local ignore = {}
    for guid, name in pairs(snap.ignore) do
        if not Spam.IsOwn(guid) then   -- never one of yours, whatever the other account thinks
            local old = db.ignore[guid]
            ignore[guid] = old and old.name == name and old or { name = name, added = time(), note = "sync" }
        end
    end
    local pending = {}
    for l, name in pairs(snap.pending) do
        if not Spam.OwnByName(l) then pending[l] = db.pending[l] or { name = name, added = time(), note = "sync" } end
    end
    -- The lists replaced, kept for /gchat ignore sync undo (review of #40: a
    -- send from an empty install would otherwise lose them for good).
    db.syncUndo = { ignore = db.ignore, pending = db.pending, mutes = db.mutes, at = time() }
    db.ignore, db.pending, db.mutes = ignore, pending, snap.mutes
    Spam.RebuildMutes()
    Spam.ResetMemo()   -- old decisions about lines no longer hold
    if GC.SpamMirror then GC.SpamMirror.Check("sync") end
    return count(ignore), count(pending), #snap.mutes
end

-- A snapshot arriving: older than the last applied from that sender is
-- ignored; a malformed one refused whole.
function Sync.Receive(body, sender, sid)
    if type(sender) ~= "table" or not isGuid(sender.guid) then return end
    local n = tonumber(sid)
    if not n then return end
    Spam.db.syncApplied = type(Spam.db.syncApplied) == "table" and Spam.db.syncApplied or {}
    local last = tonumber(Spam.db.syncApplied[sender.guid])
    local who = (plainField(sender.name, 64) and sender.name) or "your other account"
    if last and n <= last then
        say("ignored an older copy of your lists from " .. who)
        return
    end
    local snap, why = Sync.Parse(body)
    if not snap then
        say("|cffff6060refused a copy of your lists from " .. who .. " (" .. why .. "): yours are unchanged|r")
        return
    end
    Spam.db.syncApplied[sender.guid] = n
    local i, p, m = Sync.Apply(snap)
    say(string.format("your lists now match %s: %d ignored, %d pending, %d muted phrases (/gchat ignore sync undo puts yours back)",
        who, i, p, m))
end

--------------------------------------------------------------------------------
-- Sending, and the commands
--------------------------------------------------------------------------------

Sync.WHY = {
    disabled = "account sync is off (/gchat ignore sync on)",
    ["no-peers"] = "none of your other accounts is online, or none is known yet (/gchat ignore sync status)",
    ["not-ready"] = "still connecting to your other accounts; try again in a few seconds",
    offline = "Battle.net is offline",
    ["no-route"] = "no way to reach your other accounts right now; try again in a few seconds",
}
-- Per account, from the library's result.
local PER = {
    offline = "it went offline",
    ["no-route"] = "no way to reach it right now",
    ["not-ready"] = "it isn't ready yet",
    ["too-large"] = "the lists are too large",
}

-- The library answers "disabled" also while Battle.net isn't usable or the
-- login hasn't finished: with the switch on, say that instead (review of #40).
local function whyNot(why)
    if why == "disabled" and GC.AccountSync.IsEnabled() then
        return "Battle.net isn't ready for account sync yet (logging in, or disconnected); try again in a few seconds"
    end
    return Sync.WHY[why] or ("couldn't send your lists (" .. tostring(why) .. ")")
end

-- The receiver's caps, checked before sending: over one, every receiver
-- would refuse it (review of #40).
local function overCap(body)
    local n = { I = 0, P = 0, M = 0, O = 0 }
    for kind in body:gmatch("\n(%u)\t") do if n[kind] then n[kind] = n[kind] + 1 end end
    for kind, cap in pairs(Sync.CAPS) do
        if n[kind] > cap then return kind, n[kind], cap end
    end
end
local KIND_NAME = { I = "ignored players", P = "pending names", M = "muted phrases", O = "own characters" }

-- force: send even empty lists (they would empty every other account's).
function Sync.Send(force)
    local body, skipped, counts = Sync.Build()
    -- Empty is what is SENT, not the raw lists: entries naming your own
    -- characters, or unwritable ones, aren't sent (Codex review of #40).
    if not force and counts.I + counts.P + counts.M == 0 then
        say("your lists are empty: sending them would empty the lists on your other accounts. "
            .. "/gchat ignore send empty to do it anyway")
        return nil, "empty"
    end
    local kind, have, cap = overCap(body)
    if kind then
        say(string.format("|cffff6060too many %s to send (%d; at most %d)|r", KIND_NAME[kind], have, cap))
        return nil, "over-cap"
    end
    -- The library can report a result while Send is still running (in game:
    -- it did): those wait, so the summary comes first and each result after.
    local inSend, waiting = true, {}
    local sent, why = GC.AccountSync.Send(Sync.KIND, body, function(peer, status, reason)
        local who = (type(peer) == "table" and plainField(peer.name, 64) and peer.name) or "your other account"
        local line
        if status == "sent" then
            line = "your lists were handed to Battle.net for " .. who .. " (there's no delivery receipt)"
        elseif reason == "not-ready" then
            line = who .. " isn't ready yet; try /gchat ignore send again in a few seconds"
        else
            line = "|cffff6060couldn't send your lists to " .. who .. ": " .. (PER[reason] or tostring(reason)) .. "|r"
        end
        if inSend then waiting[#waiting + 1] = line else say(line) end
    end)
    inSend = false
    if not sent then
        if why == "too-large" then
            say(string.format("|cffff6060your lists are too large to send (%.1f KB; at most %d KB)|r",
                #body / 1024, GC.AccountSync.MAX / 1024))
        else
            say(whyNot(why))
        end
        for _, line in ipairs(waiting) do say(line) end
        return nil, why
    end
    -- 0: every account found is still mid-handshake; each result says so.
    if sent > 0 then
        say(string.format("sending your lists (%.1f KB) to %d other account%s...", #body / 1024, sent,
            sent == 1 and "" or "s"))
    end
    if skipped > 0 then say(skipped .. " entries couldn't be written and weren't sent") end
    for _, line in ipairs(waiting) do say(line) end
    return sent
end

-- /gchat ignore sync [status|on|off]
function Sync.Undo()
    local u = Spam.db.syncUndo
    if type(u) ~= "table" or type(u.ignore) ~= "table" then say("nothing to undo"); return end
    Spam.db.ignore, Spam.db.pending, Spam.db.mutes = u.ignore, u.pending or {}, u.mutes or {}
    Spam.db.syncUndo = nil
    Spam.RebuildMutes()
    Spam.ResetMemo()
    if GC.SpamMirror then GC.SpamMirror.Check("sync undo") end
    say("your lists are back as they were before the last copy from another account")
end

function Sync.Command(arg)
    if arg == "undo" then Sync.Undo(); return end
    if arg == "on" or arg == "off" then
        GC.AccountSync.SetEnabled(arg == "on")
        say("account sync: " .. (GC.AccountSync.IsEnabled() and "on" or "off"))
        return
    end
    for _, line in ipairs(GC.AccountSync.Status()) do say(line) end
    say("/gchat ignore send - copy these lists to your other accounts online; /gchat ignore sync on|off|undo")
end

function Sync.Start()
    GC.AccountSync.On(Sync.KIND, Sync.Receive)
end

