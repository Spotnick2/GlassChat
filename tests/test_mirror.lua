-- Spam & Ignore S2b: each character's Blizzard ignore list kept in step
-- with the account list, by the reconciliation rules in Mirror.lua.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Timers on a clock: advance(s) moves GetTime and runs what's due, in order.
local clock, timers = 0, {}
rawset(_G, "C_Timer", { After = function(s, fn) timers[#timers + 1] = { at = clock + s, fn = fn } end })
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
local refuse, writes = {}, {}
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
    for i, n in ipairs(WoW.ignores) do
        if n == name then table.remove(WoW.ignores, i); WoW.fire("IGNORELIST_UPDATE"); return true end
    end
    return false
end
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
WoW.ignores = { "Blizzard Only" }
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
check(chatHas("added 4"), "one summary line")

-- Blizzard's own "is now being ignored" lines are hidden while the write is in flight.
writes = {}
SlashCmdList.GLASSCHAT("ignore Future Pest")   -- already there: no write
eq(#writes, 0, "an entry already on the list isn't written again")
Mirror._test.inFlight()["new pest"] = WoW.now
check(Mirror.SystemFilter(nil, "CHAT_MSG_SYSTEM", "New Pest is now being ignored."), "Blizzard's line for our write is hidden")
check(not Mirror.SystemFilter(nil, "CHAT_MSG_SYSTEM", "Someone has come online."), "other system lines aren't")
check(not Mirror.SystemFilter(nil, "CHAT_MSG_SYSTEM", WoW.Secret("x")), "a secret line passes")
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
advance(Mirror.READY_DELAY + 5)   -- ready by the delay, but Blizzard's list hasn't arrived
check(db.ignore["Player-1-K"] ~= nil, "an empty list with linked names, before any update, doesn't unignore anyone")
WoW.ignores = saved
table.insert(WoW.ignores, "Kept Ignored")
WoW.fire("IGNORELIST_UPDATE")
advance(60)
check(db.ignore["Player-1-K"] ~= nil and serverHas("Kept Ignored"), "and once it arrives, all is in step")

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

eq(next(GC.failures), nil, "nothing failed")
done("test_mirror")
