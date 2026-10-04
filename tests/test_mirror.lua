-- Spam & Ignore S2b: each character's Blizzard ignore list kept in step
-- with the account list, by the reconciliation rules in Mirror.lua.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Timers on a clock: advance(s) moves GetTime and runs what's due, in order.
local clock, timers = 0, {}
rawset(_G, "C_Timer", { After = function(s, fn) timers[#timers + 1] = { at = clock + s, fn = fn } end })
-- Wall-clock time() on the same clock (saved writes are timed with it).
rawset(_G, "time", function() return 1000000 + math.floor(clock) end)
local function advance(s)
    local stop = clock + s
    while true do
        table.sort(timers, function(a, b) return a.at < b.at end)
        local t = timers[1]
        if not t or t.at > stop then break end
        table.remove(timers, 1)
        clock = t.at; WoW.now = clock
        t.fn()
    end
    clock = stop; WoW.now = clock
end

-- The server list: AddIgnore / DelIgnore change it and fire IGNORELIST_UPDATE.
WoW.ignores = {}
local refuse, refuseDel, writes = {}, {}, {}
local function serverHas(name)
    for _, n in ipairs(WoW.ignores) do if n == name then return true end end
    return false
end
C_FriendList.AddIgnore = function(name)
    writes[#writes + 1] = "add " .. name
    if refuse[name] then return false end
    if not serverHas(name) then table.insert(WoW.ignores, name) end
    WoW.fire("IGNORELIST_UPDATE")
    return true
end
C_FriendList.DelIgnore = function(name)
    writes[#writes + 1] = "del " .. name
    if refuseDel[name] then return false end
    for i, n in ipairs(WoW.ignores) do
        if n == name then table.remove(WoW.ignores, i); WoW.fire("IGNORELIST_UPDATE"); return true end
    end
    return false
end
-- ShowFriends asks the server for the list; the test decides when it arrives.
local asked = 0
C_FriendList.ShowFriends = function() asked = asked + 1 end
local function blizzardRemoves(name)   -- the player, in Blizzard's UI
    for i, n in ipairs(WoW.ignores) do if n == name then table.remove(WoW.ignores, i) end end
    WoW.fire("IGNORELIST_UPDATE")
end

WoW.playerGUID = "Player-1-ME"
WoW.playerName = "Karuzo Elegia"
local db = {
    ignore = {
        ["Player-1-A"] = { name = "Annoying Person" },
        ["Player-1-B"] = { name = "Bad Actor" },
        ["Player-1-ALT"] = { name = "Zoruka Mortalis" },   -- an old entry for your own alt
    },
    pending = { ["future pest"] = { name = "Future Pest" },
        ["zoruka mortalis"] = { name = "Zoruka Mortalis" },   -- old pending entries naming
        ["karuzo elegia"] = { name = "Karuzo Elegia" } },     -- your alt, and this character
    own = { ["Player-1-ALT"] = { name = "Zoruka Mortalis" },
        ["Player-1-ALT2"] = { name = "?" } },                -- an alt whose name wasn't readable
}
db.ignore["Player-1-ME"] = { name = "Karuzo Elegia" }   -- and one for this character
db.ignore["Player-1-ALT2"] = { name = "Alt Two" }       -- your alt by GUID only
db.ignore["Player-1-AT"] = { name = "Already There" }   -- also on Blizzard's list already
db.pending["broken"] = { note = "no name" }               -- a corrupt saved entry
WoW.ignores = { "Blizzard Only", "Already There" }
local GC = loadAddon({ spamDB = db })
local Spam, Mirror = GC.Spam, GC.SpamMirror
local c = GlassChatSpamIgnoreCharDB

-- Not before the list is ready.
eq(#writes, 0, "nothing written at login")
advance(Mirror.READY_DELAY - 1)
SlashCmdList.GLASSCHAT("ignore Early Bird")
eq(#writes, 0, "nor before the list is ready, even for a new ignore")
newChat()
advance(60)
check(serverHas("Annoying Person") and serverHas("Bad Actor") and serverHas("Future Pest"),
    "once ready: the account list is added, pending names included")
check(not serverHas("Zoruka Mortalis"), "never one of your own characters")
check(not serverHas("Alt Two"), "known by GUID only")
check(not serverHas("Karuzo Elegia"), "nor this character")
check(serverHas("Blizzard Only"), "a name only on Blizzard's list is left alone")
check(c.linked["annoying person"] and c.linked["future pest"], "the names added are linked")
check(c.linked["blizzard only"] == nil, "the Blizzard-only one isn't")
check(c.linked["already there"] == nil, "nor a wanted name that was already there (the player's own)")
check(db.pending["broken"] == nil, "a corrupt saved entry is dropped on load")
check(chatHas("added 4"), "one summary line")

-- Blizzard's own "is now being ignored" lines are hidden while the write is in flight.
writes = {}
SlashCmdList.GLASSCHAT("ignore Future Pest")   -- already there: no write
eq(#writes, 0, "an entry already on the list isn't written again")
Mirror._test.inFlight()["new pest"] = { op = "add", at = time() }
check(Mirror.SystemFilter(nil, "CHAT_MSG_SYSTEM", "New Pest is now being ignored."), "Blizzard's line for our write is hidden")
check(not Mirror.SystemFilter(nil, "CHAT_MSG_SYSTEM", "Someone has come online."), "other system lines aren't")
check(not Mirror.SystemFilter(nil, "CHAT_MSG_SYSTEM", WoW.Secret("x")), "a secret line passes")
-- With Blizzard's own strings: only those exact lines, not others naming them.
rawset(_G, "ERR_IGNORE_ADDED_S", "%s is now being ignored.")
check(Mirror.SystemFilter(nil, "CHAT_MSG_SYSTEM", "New Pest is now being ignored."), "the exact line is hidden")
check(not Mirror.SystemFilter(nil, "CHAT_MSG_SYSTEM", "New Pest has come online."), "another line naming them isn't")
rawset(_G, "ERR_IGNORE_ADDED_S", nil)
advance(Mirror.QUIET)
check(not Mirror.SystemFilter(nil, "CHAT_MSG_SYSTEM", "New Pest is now being ignored."), "and only for a few seconds")
Mirror._test.inFlight()["new pest"] = nil

-- Removed in Blizzard's UI: an unignore everywhere, never added back.
newChat()
blizzardRemoves("Bad Actor")
check(db.ignore["Player-1-B"] == nil, "a linked name removed in Blizzard's UI is unignored on the account")
check(chatHas("no longer ignored on any of your characters"), "and that's said")
advance(60)
check(not serverHas("Bad Actor"), "and it isn't added back")

-- /gchat unignore: removed from this character's list too.
SlashCmdList.GLASSCHAT("unignore Annoying Person")
advance(60)
check(not serverHas("Annoying Person"), "/gchat unignore removes the linked name from Blizzard's list")
check(c.linked["annoying person"] == nil, "and unlinks it")

-- A name that was already on Blizzard's list: another character's unignore
-- leaves it alone; an unignore on this character removes it here.
db.ignore["Player-1-AT"] = nil
Mirror.Check("test")
advance(60)
check(serverHas("Already There"), "an unignore elsewhere leaves the player's own Blizzard entry alone")
db.ignore["Player-1-AT"] = { name = "Already There" }
SlashCmdList.GLASSCHAT("unignore Already There")
advance(60)
check(not serverHas("Already There"), "/gchat unignore on this character takes it off here")

-- Another character's unignore reaches this one at its next login.
table.insert(WoW.ignores, "Gone Elsewhere")
c.linked["gone elsewhere"] = "Gone Elsewhere"
Mirror._test.reset()
WoW.fire("PLAYER_LOGIN")
advance(60)
check(not serverHas("Gone Elsewhere"), "a linked name off the account list is removed at login")
check(serverHas("Blizzard Only"), "the Blizzard-only one still isn't touched")

-- An empty read before Blizzard's list has arrived is never trusted.
local saved = WoW.ignores
WoW.ignores = {}
db.ignore["Player-1-K"] = { name = "Kept Ignored" }
c.linked["kept ignored"] = "Kept Ignored"
Mirror._test.reset()
WoW.fire("PLAYER_LOGIN")
asked = 0
advance(Mirror.READY_DELAY + 5)   -- ready by the delay, but Blizzard's list hasn't arrived
check(db.ignore["Player-1-K"] ~= nil, "an empty list with linked names, before any update, doesn't unignore anyone")
eq(asked, 1, "GlassChat asks for the list once instead")
WoW.ignores = saved
table.insert(WoW.ignores, "Kept Ignored")
WoW.fire("IGNORELIST_UPDATE")
advance(60)
check(db.ignore["Player-1-K"] ~= nil and serverHas("Kept Ignored"), "and once it arrives, all is in step")

-- A bad read changes nothing: an unreadable entry, or many linked names gone at once.
for _, n in ipairs({ "M One", "M Two", "M Three", "M Four", "M Five" }) do
    db.ignore["Player-1-" .. n] = { name = n }
end
Mirror.Check("test")
advance(60)
check(serverHas("M Five") and c.linked["m five"], "five more added and linked")
local realGet = C_FriendList.GetIgnoreName
C_FriendList.GetIgnoreName = function(i) if WoW.ignores[i] == "M One" then return nil end return realGet(i) end
WoW.fire("IGNORELIST_UPDATE")
C_FriendList.GetIgnoreName = realGet
check(db.ignore["Player-1-M One"] and c.linked["m one"], "an unreadable entry (a linked one): no one unignored")
local keep = WoW.ignores
local short = {}
for _, n in ipairs(keep) do if not n:find("^M ") then short[#short + 1] = n end end
WoW.ignores = short
newChat()
WoW.fire("IGNORELIST_UPDATE")
local still = 0
for _, n in ipairs({ "M One", "M Two", "M Three", "M Four", "M Five" }) do
    if db.ignore["Player-1-" .. n] then still = still + 1 end
end
eq(still, 5, "five linked names gone at once: no one unignored")
check(chatHas("not syncing until it reads back fully"), "and that's said")
WoW.ignores = keep
WoW.fire("IGNORELIST_UPDATE")
advance(60)

-- A refused delete is kept linked and bounded, never forgotten silently.
refuseDel["M One"] = true
db.ignore["Player-1-M One"] = nil
writes = {}
for _ = 1, Mirror.MAX_TRIES + 1 do
    Mirror._test.reset()
    WoW.fire("PLAYER_LOGIN")
    advance(120)
end
local dels = 0
for _, w in ipairs(writes) do if w == "del M One" then dels = dels + 1 end end
eq(dels, Mirror.MAX_TRIES, "a refused delete is tried MAX_TRIES times")
check(c.linked["m one"], "and stays linked")
newChat()
SlashCmdList.GLASSCHAT("ignores")
check(chatHas("M One: couldn't be removed"), "/gchat ignores reports it")

-- /gchat ignore mirror only takes on|off: anything else is a name.
SlashCmdList.GLASSCHAT("ignore mirror smith")
check(db.pending["mirror smith"] ~= nil, "'/gchat ignore mirror smith' ignores Mirror Smith")
db.pending["mirror smith"] = nil

-- A refused add is bounded: MAX_TRIES across logins, then reported, never dropped.
refuse["Full Up"] = true
db.ignore["Player-1-F"] = { name = "Full Up" }
local tries = 0
for _ = 1, Mirror.MAX_TRIES + 2 do
    writes = {}
    Mirror._test.reset()
    WoW.fire("PLAYER_LOGIN")
    advance(120)
    for _, w in ipairs(writes) do if w == "add Full Up" then tries = tries + 1 end end
end
eq(tries, Mirror.MAX_TRIES, "a refused add is tried MAX_TRIES times, across logins")
check(db.ignore["Player-1-F"] ~= nil, "and the name stays ignored in chat")
newChat()
SlashCmdList.GLASSCHAT("ignores")
check(chatHas("Full Up: couldn't be added"), "/gchat ignores reports it")

-- Off: nothing written.
SlashCmdList.GLASSCHAT("ignore mirror off")
db.ignore["Player-1-O"] = { name = "Off Switch" }
writes = {}
advance(60)
SlashCmdList.GLASSCHAT("ignore Off Switch")
advance(60)
eq(#writes, 0, "with the mirror off, Blizzard's list isn't written")
SlashCmdList.GLASSCHAT("ignore mirror on")
advance(60)
check(serverHas("Off Switch"), "on again: brought in step")

-- From here: a small, fresh setup (no permanent Blizzard-only entry).
local function fresh(names)
    db.ignore, db.pending = {}, {}
    for _, n in ipairs(names) do db.ignore["Player-1-" .. n] = { name = n } end
    c.linked, c.tries, c.writes = {}, {}, {}
    WoW.ignores = {}
    Mirror._test.reset()
    WoW.fire("PLAYER_LOGIN")
    advance(Mirror.READY_DELAY)
    WoW.fire("IGNORELIST_UPDATE")   -- the list arrives, after the delay
    advance(60)
end

-- The last name removed leaves an empty list: that's trusted, and the sync goes on (Codex, #24).
fresh({ "Only One" })
check(serverHas("Only One") and c.linked["only one"], "one name added and linked")
SlashCmdList.GLASSCHAT("unignore Only One")
advance(60)
check(not serverHas("Only One") and c.linked["only one"] == nil, "/gchat unignore of the last name: removed and unlinked")
SlashCmdList.GLASSCHAT("ignore Next One")
advance(60)
check(serverHas("Next One"), "and the next ignore is still added")
blizzardRemoves("Next One")
advance(60)
check(db.pending["next one"] == nil, "the last name removed in Blizzard's UI is unignored on the account")

-- An update right after login with an empty list (not loaded yet) isn't trusted.
fresh({ "Early One" })
check(c.linked["early one"], "linked")
WoW.ignores = {}
Mirror._test.reset()
WoW.fire("PLAYER_LOGIN")
advance(1)
WoW.fire("IGNORELIST_UPDATE")
advance(5)
check(db.ignore["Player-1-Early One"] ~= nil and c.linked["early one"], "an empty list in an update just after login unignores no one")
table.insert(WoW.ignores, "Early One")
advance(60)

-- Off during a batch: the queue stops before its next write (Codex, #24).
fresh({})
writes = {}
for _, n in ipairs({ "Batch One", "Batch Two", "Batch Three" }) do db.ignore["Player-1-" .. n] = { name = n } end
Mirror.Check("test")
eq(#writes, 1, "the batch starts with one write")
SlashCmdList.GLASSCHAT("ignore mirror off")
advance(60)
eq(#writes, 1, "switched off: no further writes")
SlashCmdList.GLASSCHAT("ignore mirror on")
advance(60)
check(serverHas("Batch Two") and serverHas("Batch Three"), "on again: the rest are added")

-- Cancelled writes cost no tries: repeated off/on cycles still get every name in (Codex, #24).
fresh({})
local six = { "C One", "C Two", "C Three", "C Four", "C Five", "C Six" }
for _, n in ipairs(six) do db.ignore["Player-1-" .. n] = { name = n } end
for _ = 1, 3 do
    SlashCmdList.GLASSCHAT("ignore mirror on")
    SlashCmdList.GLASSCHAT("ignore mirror off")   -- after the first write
    advance(1)
end
SlashCmdList.GLASSCHAT("ignore mirror on")
advance(120)
local missing = 0
for _, n in ipairs(six) do if not serverHas(n) then missing = missing + 1 end end
eq(missing, 0, "after three cancelled batches, every name is still added")
eq(next(Mirror.Failed()), nil, "and none is reported as failed")

-- An AltStable update mid-batch: a queued add for a character just learned
-- to be yours is never written (Codex review of #34).
local altChars, altChanged = {}, nil
rawset(_G, "AltStable", { PUBLIC_API_VERSION = 1, GetCharacters = function() return altChars end,
    RegisterCallback = function(event, fn) altChanged = fn end })
Spam._test.reset()   -- so the login below hooks AltStable's callback
fresh({})
for _, n in ipairs({ "Q One", "Q Two", "Q Three" }) do db.ignore["Player-1-" .. n] = { name = n } end
writes = {}
Mirror.Check("test")
eq(#writes, 1, "the batch has started")
altChars[1] = { guid = "Player-1-Q Two", name = "Q Two" }   -- a sync from your other account
altChanged("CharactersChanged")
advance(60)
local wroteTwo = false
for _, w in ipairs(writes) do if w == "add Q Two" then wroteTwo = true end end
check(not wroteTwo, "the queued add for your own character is dropped")
check(serverHas("Q Three"), "the rest of the batch still goes")
check(not (c.tries["add:q two"] and c.tries["add:q two"].n > 0), "and the dropped one cost no try")
rawset(_G, "AltStable", nil)
Spam.RefreshAltStable()

-- A reload right after an add still knows the name is ours (Codex, #24).
fresh({})
db.ignore["Player-1-R"] = { name = "Reload Case" }
Mirror.Check("test")   -- the add is written at once; its check is 10 s away
check(serverHas("Reload Case") and c.linked["reload case"] == nil, "written, not yet confirmed")
Mirror._test.reset()   -- /reload: session state gone, saved tables kept
WoW.fire("PLAYER_LOGIN")
advance(Mirror.READY_DELAY)
WoW.fire("IGNORELIST_UPDATE")
advance(60)
check(c.linked["reload case"], "after the reload it's linked: GlassChat's own write")
db.ignore["Player-1-R"] = nil   -- unignored on another character
Mirror.Check("test")
advance(60)
check(not serverHas("Reload Case"), "so another character's unignore removes it here")

eq(next(GC.failures), nil, "nothing failed")
done("test_mirror")
