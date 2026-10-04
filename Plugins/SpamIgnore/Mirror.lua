-- Mirror.lua (Spam & Ignore, S2b): keep each character's Blizzard ignore
-- list in step with the account-wide one, because the server ignore blocks
-- what a chat filter can't: invites and duels (docs/FOREVER-PROBE.md 12).
--
-- The rules (docs/PLAN-SPAM.md, S2b; why a plain login mirror is unsafe):
-- - LINKED entries: names GlassChat itself added to this character's
--   Blizzard list. Only those are ever removed by a sync; a name that was
--   already there is the player's own and is left alone (review of #24).
--   The one exception is explicit: /gchat unignore on THIS character also
--   takes the name off this character's list.
-- - A linked name that leaves Blizzard's list (removed in Blizzard's UI)
--   counts as an UNIGNORE, on every character: it is never added back.
-- - A linked name no longer on the account list (/gchat unignore, on any
--   character) is removed from this character's list at its next check.
-- - A read is TRUSTED only when every entry from 1 to GetNumIgnores() reads
--   as a plain name, the list is ready (an IGNORELIST_UPDATE this session,
--   or READY_DELAY s after login; measured: nil at ADDON_LOADED), and no
--   more than MASS_LOSS linked names vanish at once. An EMPTY read with names
--   linked is trusted only once the list is SETTLED: an update that came
--   READY_DELAY s or more after login, or one our own write caused; until
--   then GlassChat asks for the list (ShowFriends) and waits. A distrusted
--   read changes nothing (review of #24: one bad read must never unignore
--   the whole list).
-- - Writes are throttled, at most one in flight per name, and checked: a
--   write counts once the list shows it, and a write that hasn't shown up
--   WRITE_WAIT s later is a try. After MAX_TRIES (kept across logins) it's
--   reported, not retried, and never taken to mean the name is invalid (it
--   stays ignored in chat). Writes in flight are SAVED (charDB.writes), so a
--   reload right after an add still knows the name is ours (Codex, #24).
-- - Turning the mirror off stops the queue before its next write.
-- - Never your own characters (owner): db.own, which holds this one too.
-- Blizzard's own lines about our writes are hidden while they're in flight;
-- one summary line instead.

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local Spam = GC.Spam
local plainString = Spam.PlainString
local Mirror = {}
GC.SpamMirror = Mirror

Mirror.READY_DELAY = 20
Mirror.WRITE_GAP = 0.5
Mirror.WRITE_WAIT = 10
Mirror.QUIET = 3          -- s after a write during which its system lines are hidden
Mirror.MAX_TRIES = 3
Mirror.MASS_LOSS = 3      -- more linked names than this gone at once: distrust the read

local ready, loggedIn, settled, asked = false, false, false, false
local loginAt, wroteThisSession = nil, false
local queue = {}          -- { op = "add"|"del", lname, name }
local busy, warnedMass = false, false
local summary = { added = 0, removed = 0, unignored = {} }

local function charDB()
    local c = Spam.charDB
    for _, k in ipairs({ "linked", "tries", "writes" }) do
        if type(c[k]) ~= "table" then c[k] = {} end
    end
    for l, w in pairs(c.writes) do
        if type(w) ~= "table" or (w.op ~= "add" and w.op ~= "del") or type(w.at) ~= "number" then c.writes[l] = nil end
    end
    return c
end

-- Writes in flight, lname -> { op, at = time() }: saved, so they outlive a reload.
local function inFlight() return charDB().writes end

-- This character's Blizzard list, lname -> name, and its size; nil unless
-- every entry read as a plain name (GetIgnoreName is nullable).
function Mirror.ReadServer()
    local FL = C_FriendList
    if not (FL and FL.GetNumIgnores and FL.GetIgnoreName) then return nil end
    local ok, n = pcall(FL.GetNumIgnores)
    if not ok or API.IsSecret(n) or type(n) ~= "number" then return nil end
    local list = {}
    for i = 1, n do
        local okN, name = pcall(FL.GetIgnoreName, i)
        name = okN and plainString(name) or nil
        if not name then return nil end
        list[name:lower()] = name
    end
    return list, n
end

-- The account list, lname -> name, without your own characters.
function Mirror.Wanted()
    local want = {}
    -- A GUID entry: its GUID decides. A pending one (no GUID yet): its name.
    for guid, e in pairs(Spam.db.ignore) do
        if type(e.name) == "string" and not Spam.IsOwn(guid) then want[e.name:lower()] = e.name end
    end
    for _, e in pairs(Spam.db.pending) do
        if type(e.name) == "string" and not Spam.OwnByName(e.name:lower()) then want[e.name:lower()] = e.name end
    end
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

local function canRun()
    return C_Timer and C_Timer.After and C_FriendList and C_FriendList.AddIgnore and C_FriendList.DelIgnore
end

local function guarded(why, fn)
    local ok, err = pcall(fn)
    if not ok then API.Fail("ignore mirror " .. why, err) end
end

-- Tries per write, kept across logins: a write may be queued while it has
-- tries left, and a try is spent only when pump really makes the call, so a
-- queue dropped by "mirror off" costs nothing (Codex review of #24).
local function canTry(c, key)
    local t = c.tries[key]
    return not (t and t.n >= Mirror.MAX_TRIES)
end
local function spend(c, key, name)
    local t = c.tries[key]
    c.tries[key] = { name = name, n = (t and t.n or 0) + 1 }
end

-- One write per WRITE_GAP; the check that follows sees what took.
local pump
pump = function()
    local w = table.remove(queue, 1)
    if not w then
        busy = false
        C_Timer.After(Mirror.WRITE_WAIT, function() Mirror.Check("after writes") end)
        return
    end
    if not Spam.db.mirror then   -- switched off: the rest of the queue is dropped
        queue, busy = {}, false
        return
    end
    busy, wroteThisSession = true, true
    spend(charDB(), w.op .. ":" .. w.lname, w.name)
    inFlight()[w.lname] = { op = w.op, at = time() }
    local fn = w.op == "add" and C_FriendList.AddIgnore or C_FriendList.DelIgnore
    local ok, res = pcall(fn, w.name)
    if not ok then API.Fail("ignore mirror " .. w.op, res) end
    C_Timer.After(Mirror.WRITE_GAP, function() guarded("pump", pump) end)
end

local function enqueue(op, lname, name)
    for _, w in ipairs(queue) do if w.lname == lname then return end end
    queue[#queue + 1] = { op = op, lname = lname, name = name }
end


local function check(why)
    if not (loggedIn and ready and not busy and Spam.db and Spam.db.mirror and canRun()) then return end
    local server, n = Mirror.ReadServer()
    if not server then return end
    local c = charDB()
    if n == 0 and next(c.linked) and not settled then
        -- A list not loaded yet reads empty: ask for it, and wait for its update.
        if not asked and C_FriendList.ShowFriends then
            asked = true
            pcall(C_FriendList.ShowFriends)
        end
        return
    end
    local inFlight = inFlight()

    -- Writes in flight: done once the list shows them, a lapsed try after WRITE_WAIT.
    local t = time()
    for l, w in pairs(inFlight) do
        local landed = (w.op == "add") == (server[l] ~= nil)
        if landed then
            inFlight[l] = nil
            c.tries[w.op .. ":" .. l] = nil
            if w.op == "add" then
                c.linked[l] = server[l]
                summary.added = summary.added + 1
            else
                c.linked[l] = nil
                summary.removed = summary.removed + 1
            end
        elseif t - w.at >= Mirror.WRITE_WAIT then
            inFlight[l] = nil
        end
    end

    -- Linked names gone from the list: removed in Blizzard's UI. Too many at
    -- once is a bad read, not the player's doing: change nothing.
    local gone = {}
    for l in pairs(c.linked) do
        if not server[l] and not inFlight[l] then gone[#gone + 1] = l end
    end
    if #gone > Mirror.MASS_LOSS then
        if not warnedMass then
            warnedMass = true
            say("|cffffd100Blizzard's ignore list here is missing " .. #gone ..
                " names GlassChat added; not syncing until it reads back fully.|r")
        end
        return
    end

    local want = Mirror.Wanted()
    for _, l in ipairs(gone) do
        local name = c.linked[l]
        c.linked[l] = nil
        if want[l] then
            Spam.Unignore(want[l])
            want[l] = nil
            table.insert(summary.unignored, name)
        end
    end

    -- Linked names off the account list: remove them here.
    for l in pairs(c.linked) do
        if server[l] and not want[l] and not inFlight[l] and canTry(c, "del:" .. l) then
            enqueue("del", l, server[l])
        end
    end

    -- Wanted names not on the list: add them. Already there: the player's own, left alone.
    for l, name in pairs(want) do
        if not server[l] and not inFlight[l] and canTry(c, "add:" .. l) then
            enqueue("add", l, name)
        end
    end

    -- Tries for names no longer in question are forgotten.
    for key in pairs(c.tries) do
        local op, l = key:match("^(%a+):(.*)$")
        if not op or (op == "add" and (server[l] or not want[l])) or (op == "del" and not server[l]) then
            c.tries[key] = nil
        end
    end

    if #queue > 0 then pump() else flushSummary() end
end

-- Compare and act. Runs on IGNORELIST_UPDATE, once ready, after writes and commands.
function Mirror.Check(why) guarded(why or "check", function() check(why) end) end

-- /gchat unignore on this character: also off this character's list, if
-- it's there, linked or not (an explicit request, here).
function Mirror.UnignoreHere(name)
    if not (Spam.db.mirror and canRun()) then return end
    local server = Mirror.ReadServer()
    local l = name:lower()
    if server and server[l] and not inFlight()[l] then
        charDB().linked[l] = server[l]   -- so the check removes it
    end
    Mirror.Check("unignore")
end

-- Names GlassChat couldn't add or remove here (for /gchat ignores).
function Mirror.Failed()
    local out = {}
    if not Spam.charDB then return out end
    for key, e in pairs(charDB().tries) do
        if type(e) == "table" and e.n >= Mirror.MAX_TRIES then out[key] = e.name end
    end
    return out
end

-- Blizzard's own lines about a write in flight. With its strings available,
-- only those exact lines for that name; else lines naming it. Lines that
-- name no one (list full, not found) are hidden only within QUIET s.
local function blizzardLines(name)
    local out = {}
    for _, key in ipairs({ "ERR_IGNORE_ADDED_S", "ERR_IGNORE_REMOVED_S", "ERR_IGNORE_ALREADY_S" }) do
        local fmt = rawget(_G, key)
        if type(fmt) == "string" and not API.IsSecret(fmt) then out[#out + 1] = fmt:format(name) end
    end
    for _, key in ipairs({ "ERR_IGNORE_FULL", "ERR_IGNORE_NOT_FOUND", "ERR_IGNORE_SELF", "ERR_IGNORE_AMBIGUOUS" }) do
        local s = rawget(_G, key)
        if type(s) == "string" and not API.IsSecret(s) then out[#out + 1] = s end
    end
    return out
end

function Mirror.SystemFilter(_, _, text)
    if API.IsSecret(text) or type(text) ~= "string" or not Spam.charDB then return false end
    local writes = inFlight()
    if not next(writes) then return false end
    local t, lower = time(), text:lower()
    for l, w in pairs(writes) do
        if t - w.at < Mirror.QUIET then
            local exact = blizzardLines(l)
            if #exact > 0 then
                for _, s in ipairs(exact) do if s:lower() == lower then return true end end
            elseif lower:find(l, 1, true) then
                return true
            end
        end
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
            loggedIn, loginAt = true, GetTime()
            if C_Timer and C_Timer.After then
                C_Timer.After(Mirror.READY_DELAY, function()
                    ready = true
                    Mirror.Check("ready")
                end)
            end
        elseif event == "IGNORELIST_UPDATE" then
            if not loggedIn then return end
            ready = true
            if wroteThisSession or GetTime() - loginAt >= Mirror.READY_DELAY then settled = true end
            Mirror.Check("update")
        end
    end)
    API.RegisterEvents(f, { "PLAYER_LOGIN", "IGNORELIST_UPDATE" })
end

Mirror._test = {
    reset = function()
        ready, loggedIn, busy, warnedMass, settled, asked = false, false, false, false, false, false
        loginAt, wroteThisSession, queue = nil, false, {}
        summary = { added = 0, removed = 0, unignored = {} }
    end,
    inFlight = function() return inFlight() end,
    queue = function() return queue end,
}
