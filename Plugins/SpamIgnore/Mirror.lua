-- Mirror.lua (Spam & Ignore, S2b): keep each character's Blizzard ignore
-- list in step with the account-wide one, because the server ignore blocks
-- what a chat filter can't: invites and duels (docs/FOREVER-PROBE.md 12).
--
-- The rules (docs/PLAN-SPAM.md, S2b; why a plain login mirror is unsafe):
-- - LINKED entries: names on this character's Blizzard list that GlassChat
--   keeps in step (it added them, or found them already there). Only those
--   are ever removed by GlassChat; a name only on Blizzard's list is left
--   alone (import is explicit, /gchat ignore import).
-- - A linked name that leaves Blizzard's list (removed in Blizzard's UI)
--   counts as an UNIGNORE, on every character: it is never added back.
-- - A linked name no longer on the account list (/gchat unignore, on any
--   character) is removed from this character's list at its next check.
-- - Never before the list is READY: an IGNORELIST_UPDATE seen this session,
--   or READY_DELAY seconds after login (measured: nil at ADDON_LOADED); an
--   empty read with linked entries before then is never trusted.
-- - Writes are throttled, at most one in flight per name, and BOUNDED: a
--   name not on the list WRITE_WAIT s after its add is a try; after
--   MAX_TRIES (kept across logins) it's reported, not retried, and never
--   taken to mean the name is invalid (it stays ignored in chat).
-- - Never your own characters, nor this one (owner).
-- Blizzard's own "is now being ignored" lines for our writes are hidden
-- (by the name, while that write is in flight); one summary line instead.

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local Spam = GC.Spam
local Mirror = {}
GC.SpamMirror = Mirror

Mirror.READY_DELAY = 20
Mirror.WRITE_GAP = 0.5
Mirror.WRITE_WAIT = 10
Mirror.MAX_TRIES = 3

local function plainString(v)
    if API.IsSecret(v) or type(v) ~= "string" then return nil end
    return v
end

local ready, sawUpdate, loggedIn = false, false, false
local wrote = {}                    -- lname -> true: added by us this session, not yet seen
local queue, inFlight = {}, {}      -- queue: { op, lname, name }; inFlight[lname] = GetTime() of the write
local busy = false
local summary = { added = 0, removed = 0, unignored = {} }

local function charDB()
    local c = Spam.charDB
    if type(c.linked) ~= "table" then c.linked = {} end
    if type(c.tries) ~= "table" then c.tries = {} end
    return c
end

-- This character's Blizzard list, lname -> name; nil if unreadable.
function Mirror.ReadServer()
    local FL = C_FriendList
    if not (FL and FL.GetNumIgnores and FL.GetIgnoreName) then return nil end
    local ok, n = pcall(FL.GetNumIgnores)
    if not ok or API.IsSecret(n) or type(n) ~= "number" then return nil end
    local list = {}
    for i = 1, n do
        local okN, name = pcall(FL.GetIgnoreName, i)
        name = okN and plainString(name) or nil
        if name then list[name:lower()] = name end
    end
    return list, n
end

-- The account list, lname -> name, without your own characters or this one.
function Mirror.Wanted()
    local want = {}
    local me = plainString(UnitName("player"))
    me = me and me:lower()
    local function add(name)
        local l = name:lower()
        if l ~= me and not Spam.OwnByName(l) then want[l] = name end
    end
    for guid, e in pairs(Spam.db.ignore) do
        if not Spam.IsOwn(guid) then add(e.name) end
    end
    for _, e in pairs(Spam.db.pending) do add(e.name) end
    return want
end

local function say(msg) API.Print(msg) end

local function flushSummary()
    local parts = {}
    if summary.added > 0 then parts[#parts + 1] = "added " .. summary.added end
    if summary.removed > 0 then parts[#parts + 1] = "removed " .. summary.removed end
    if #parts > 0 then say("Blizzard's ignore list on this character: " .. table.concat(parts, ", ")) end
    for _, name in ipairs(summary.unignored) do
        say(name .. " was taken off Blizzard's ignore list here, so they're no longer ignored on any of your characters")
    end
    summary = { added = 0, removed = 0, unignored = {} }
end

local pump
local function schedule(delay, fn)
    if C_Timer and C_Timer.After then C_Timer.After(delay, fn) end
end

-- One write per WRITE_GAP; the check that follows sees what took.
pump = function()
    local w = table.remove(queue, 1)
    if not w then
        busy = false
        schedule(Mirror.WRITE_WAIT, function() Mirror.Check("after writes") end)
        return
    end
    busy = true
    local FL = C_FriendList
    if w.op == "add" then
        inFlight[w.lname] = GetTime()
        wrote[w.lname] = true
        local ok, res = pcall(FL.AddIgnore, w.name)
        if not ok then API.Fail("ignore mirror add", res) end
    else
        inFlight[w.lname] = GetTime()
        local ok, res = pcall(FL.DelIgnore, w.name)
        if not ok then API.Fail("ignore mirror remove", res) end
        charDB().linked[w.lname] = nil
        summary.removed = summary.removed + 1
    end
    schedule(Mirror.WRITE_GAP, pump)
end

local function enqueue(op, lname, name)
    for _, w in ipairs(queue) do if w.lname == lname then return end end
    queue[#queue + 1] = { op = op, lname = lname, name = name }
end

-- Compare and act. Runs on IGNORELIST_UPDATE, once ready, and after writes.
function Mirror.Check(why)
    if not (loggedIn and Spam.db and Spam.db.mirror) then return end
    if not ready then return end
    if busy then return end
    local server, n = Mirror.ReadServer()
    if not server then return end
    local c = charDB()
    if n == 0 and next(c.linked) and not sawUpdate then return end   -- not trusted yet
    local t = GetTime()
    for l, at in pairs(inFlight) do
        if t - at >= Mirror.WRITE_WAIT or server[l] ~= nil then inFlight[l] = nil end
    end
    local want = Mirror.Wanted()

    -- Writes that took, and adds that didn't (a try each).
    for l in pairs(c.tries) do
        if server[l] then c.tries[l] = nil end
    end

    for l, name in pairs(c.linked) do
        if not inFlight[l] then
            if not server[l] then
                -- Removed in Blizzard's UI: an unignore, everywhere.
                c.linked[l] = nil
                if want[l] then
                    Spam.Unignore(name)
                    want[l] = nil
                    table.insert(summary.unignored, name)
                end
            elseif not want[l] then
                enqueue("del", l, server[l])
            end
        end
    end

    for l, name in pairs(want) do
        if server[l] then
            if wrote[l] and not c.linked[l] then summary.added = summary.added + 1 end
            wrote[l] = nil
            c.linked[l] = server[l]
        elseif not inFlight[l] then
            local tries = c.tries[l]
            if not (tries and tries.n >= Mirror.MAX_TRIES) then
                c.tries[l] = { name = name, n = (tries and tries.n or 0) + 1 }
                enqueue("add", l, name)
            end
        end
    end
    -- A try that's no longer wanted is forgotten.
    for l in pairs(c.tries) do if not want[l] then c.tries[l] = nil end end

    if #queue > 0 then
        pump()
    else
        flushSummary()
    end
end

-- Names GlassChat couldn't add here (for /gchat ignores).
function Mirror.Failed()
    local out = {}
    if not Spam.charDB then return out end
    for l, e in pairs(charDB().tries) do
        if e.n >= Mirror.MAX_TRIES then out[l] = e.name end
    end
    return out
end

-- Hide Blizzard's own line about a write in flight (matched by its name).
function Mirror.SystemFilter(_, _, text)
    if API.IsSecret(text) or type(text) ~= "string" or not next(inFlight) then return false end
    local t, lower = GetTime(), text:lower()
    for l, at in pairs(inFlight) do
        if t - at < Mirror.WRITE_WAIT and lower:find(l, 1, true) then return true end
    end
    return false
end

function Mirror.Start()
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_SYSTEM", Mirror.SystemFilter)
    end
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then
            loggedIn = true
            schedule(Mirror.READY_DELAY, function()
                ready = true
                Mirror.Check("ready")
            end)
        elseif event == "IGNORELIST_UPDATE" then
            if not loggedIn then return end
            sawUpdate, ready = true, true
            Mirror.Check("update")
        end
    end)
    API.RegisterEvents(f, { "PLAYER_LOGIN", "IGNORELIST_UPDATE" })
end

Mirror._test = {
    reset = function()
        ready, sawUpdate, loggedIn, busy = false, false, false, false
        queue, inFlight, wrote = {}, {}, {}
        summary = { added = 0, removed = 0, unignored = {} }
    end,
    inFlight = function() return inFlight end,
    queue = function() return queue end,
}
