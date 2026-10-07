-- Settings sync (#52; docs/PLAN-SETTINGS.md): the registry, the ST1 format,
-- applying (only changes, defaults through the reset path), undo, the layout
-- through M2's offer, never-sent keys, the stopgap between kinds, and a round
-- trip against the real LibAccountSync-1.0 (test_sync's Peer).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- A clock the library's timers follow (its hellos, settle and ticker).
local clock, timers = 1760000000, {}
rawset(_G, "time", function() return clock end)
rawset(_G, "GetTime", function() return clock - 1759990000 end)
rawset(_G, "C_Timer", {
    After = function(s, fn) timers[#timers + 1] = { at = clock + s, fn = fn } end,
    NewTicker = function(s, fn)
        local t = { at = clock + s, fn = fn, every = s }
        timers[#timers + 1] = t
        return { Cancel = function() t.cancelled = true end }
    end,
})
local function advance(seconds)
    for _ = 1, seconds do
        clock = clock + 1
        WoW.now = clock
        local due = {}
        for i = #timers, 1, -1 do
            local t = timers[i]
            if t.cancelled then table.remove(timers, i)
            elseif t.at <= clock then
                if t.every then t.at = t.at + t.every else table.remove(timers, i) end
                table.insert(due, 1, t)
            end
        end
        for _, t in ipairs(due) do t.fn() end
    end
end

WoW.playerGUID, WoW.playerName = "Player-1-0000000A", "Karuzo Elegia"
WoW.loggedIn = true
local GC = loadAddon()
local AS, SS, Spam = GC.AccountSync, GC.SettingsSync, GC.Spam
local store = GlassChatSpamIgnoreSyncDB
local db, sdb = GlassChatDB, GlassChatSpamIgnoreDB

local T = LibStub("LibAccountSync-1.0")._test
local function sentTo(id, kind)
    local out = {}
    for _, m in ipairs(WoW.bnSent) do
        if (id == nil or m.target == id) and (kind == nil or m.text:sub(1, #kind) == kind) then out[#out + 1] = m end
    end
    return out
end
local function macFor(key, receiverNonce, senderGuid, project, region, tag, sid, n, payload)
    return T.HMAC256(key, "LibAccountSync-1.0|data|1|" .. receiverNonce .. "|" .. senderGuid .. "|" .. project
        .. "|" .. region .. "|" .. tag .. "|" .. sid .. "|" .. n .. "|" .. T.SHA256(payload)):sub(1, 32)
end
local Peer = { id = 3, name = "Karuzo Memphisto", guid = "Player-1-0000000B", realm = "Doomhowl",
               faction = "Alliance", key = "0123456789abcdef0123456789abcdef", nonce = "fedcba9876543210",
               project = 18, region = 90 }
WoW.bn.accounts[Peer.id] = { characterName = Peer.name, playerGuid = Peer.guid, isOnline = true,
    clientProgram = "WoW", wowProjectID = 18, regionID = 90, isInCurrentRegion = true,
    factionName = Peer.faction, realmName = Peer.realm, bnetAccountID = WoW.bn.me }
function Peer.ourNonce()
    local hs = sentTo(Peer.id, "H1|")
    local m = hs[#hs]
    if not m then return nil end
    local f = {}
    for x in (m.text .. "|"):gmatch("([^|]*)|") do f[#f + 1] = x end
    return f[8]
end
function Peer.deliver(text) WoW.fire("BN_CHAT_MSG_ADDON", "LibAcctSync", text, "WHISPER", Peer.id) end
function Peer.hello()
    Peer.deliver(table.concat({ "H1", "1", Peer.name, Peer.guid, Peer.faction, Peer.realm, "", Peer.nonce, "" }, "|"))
end
function Peer.send(payload, sid)
    local enc = T.Encode(payload)
    local bodies = { enc:sub(1, T.BODY_FIRST) }
    local pos = T.BODY_FIRST + 1
    while pos <= #enc do bodies[#bodies + 1] = enc:sub(pos, pos + T.BODY_REST - 1); pos = pos + T.BODY_REST end
    local mac = macFor(Peer.key, Peer.ourNonce() or "0000000000000000", Peer.guid, 18, 90, "GlassChat", sid, #bodies, payload)
    for i = 1, #bodies do
        Peer.deliver(table.concat({ "D1", "GlassChat", sid, tostring(i), tostring(#bodies), i == 1 and mac or "-", bodies[i] }, "|"))
    end
    advance(1)
end
function Peer.received()
    local streams, out = {}, {}
    for _, m in ipairs(sentTo(Peer.id, "D1|")) do
        local tag, sid, i, n, mac, body = m.text:match("^D1|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
        if tag == "GlassChat" then
            streams[sid] = streams[sid] or { n = tonumber(n), chunks = {} }
            streams[sid].chunks[tonumber(i)] = body
            if i == "1" then streams[sid].mac = mac end
        end
    end
    for sid, s in pairs(streams) do
        local payload = T.Decode(table.concat(s.chunks, "", 1, s.n))
        out[#out + 1] = { payload = payload, sid = sid,
            macOk = payload and s.mac == macFor(store.key, Peer.nonce, WoW.playerGUID, 18, 90, "GlassChat", sid, s.n, payload) }
    end
    return out
end


--------------------------------------------------------------------------------
-- The registry
--------------------------------------------------------------------------------
local secs = SS._test.sections
check(secs.core and secs.spam, "two sections: core, and the plugin's spam")
for _, k in ipairs({ "glass", "alpha", "lines", "classColors", "plainArrows", "history", "tabSize",
                     "shortChannels", "urls", "timestamps", "look.rim", "look.glowh" }) do
    check(secs.core.byKey[k], "core key " .. k)
end
for _, k in ipairs({ "cjk", "repeatWindow", "icon", "mirror", "score" }) do check(secs.spam.byKey[k], "spam key " .. k) end

--------------------------------------------------------------------------------
-- Building: values set, defaults as D, never the excluded keys
--------------------------------------------------------------------------------
db.timestamps, db.lines = true, 2000
db.glass = true                       -- set to its default: travels as D
db.look = { rim = 0.3 }
db.devMode, db.routes, db.routeNever = true, { ASProbe = true }, { X = true }
sdb.repeatWindow, sdb.score, sdb.collect, sdb.debug = 120, "hide", true, true
local body = SS.Build(false)
check(body:find("^ST1\nT\t%d+\n"), "format first, then the time")
check(body:find("\nV\tcore\ttimestamps\tb\t1\n"), "a boolean set")
check(body:find("\nV\tcore\tlines\ti\t2000\n"), "an integer set")
check(body:find("\nD\tcore\tglass\n"), "a value set to its default travels as D")
check(body:find("\nD\tcore\turls\n"), "an unset key as D")
check(body:find("\nV\tcore\tlook%.rim\tn\t0%.3\n"), "a tune value")
check(body:find("\nV\tspam\trepeatWindow\ti\t120\n"), "the repeat window in seconds")
check((body .. "\n"):find("\nV\tspam\tscore\te\thide\n"), "the score mode")
for _, never in ipairs({ "devMode", "routes", "routeNever", "collect", "debug", "key", "accountSync",
                         "layout", "export", "settingsUndo", "settingsApplied" }) do
    check(not body:find("\t" .. never .. "[\t\n]") and not body:find("\t" .. never .. "$"), "never sent: " .. never)
end
check(not body:find("\nL\t"), "no layout unless asked")
db.devMode, db.routes, db.routeNever, sdb.collect, sdb.debug = nil, nil, nil, nil, nil

--------------------------------------------------------------------------------
-- Parsing
--------------------------------------------------------------------------------
local function P(lines) return SS.Parse(table.concat(lines, "\n")) end
local ok = P({ "ST1", "T\t1", "V\tcore\ttimestamps\tb\t0", "D\tcore\tlines" })
check(ok and #ok.items == 2 and #ok.skipped == 0, "a good payload")
local function refuses(lines, label)
    local snap, why = P(lines)
    check(snap == nil and why, "refused: " .. label .. (why and (" (" .. why .. ")") or ""))
end
refuses({ "ST2", "T\t1" }, "unknown format")
refuses({ "ST1", "X\t1" }, "unknown record")
refuses({ "ST1", "V\tcore\ttimestamps\tb" }, "a V with a field missing")
refuses({ "ST1", "V\tcore\ttimestamps\tz\t1" }, "an unknown type mark")
refuses({ "ST1", "V\tcore\ttimestamps\tb\tyes" }, "a bad boolean")
refuses({ "ST1", "V\tcore\tlines\ti\t12.5" }, "a non-integer for an integer")
refuses({ "ST1", "V\tcore\talpha\tn\tnan" }, "a non-finite number")
refuses({ "ST1", "V\tcore\talpha\tn\t1e999" }, "an infinite number")
refuses({ "ST1", "V\tcore\ttimestamps\tb\t1", "D\tcore\ttimestamps" }, "a V and a D for one key")
refuses({ "ST1", "D\tcore\turls", "D\tcore\turls" }, "a duplicate")
refuses({ "ST1", "T\t1", string.rep("x", 300) }, "a line over the cap")
local many = { "ST1" }
for i = 1, SS.RECORDS_MAX + 1 do many[#many + 1] = "D\tx\tk" .. i end
refuses(many, "too many records")
refuses({ "ST1", "L\tW\t1\tpoint\te\tTOPLEFT", "L\tW\t1\tx\tn\t10", "L\tW\t1\ty\tn\t10" }, "the main window's place, even complete")
refuses({ "ST1", "L\tW\t1\twidth\tn\t300", "L\tW\t1\theight\tn\t100" }, "the main window's size")
refuses({ "ST1", "L\tW\t2\tr\tn\t0.5" }, "an incomplete colour")
refuses({ "ST1", "L\tW\t2\tpoint\te\tTOPLEFT" }, "an incomplete position")
refuses({ "ST1", "L\tW\t99\tname\ts\tX" }, "a window out of range")
refuses({ "ST1", "L\tC\t2\tbad|channel" }, "a channel with a pipe")
-- A value this copy can't take is skipped and reported; the rest applies.
local snap = P({ "ST1", "V\tcore\thistory\ti\t600", "V\tspam\tscore\te\tparanoid", "V\tcore\tnewThing\tb\t1",
                 "V\tfuture\tx\tb\t1", "V\tcore\ttimestamps\tb\t0" })
check(snap, "out of range, unknown choices, unknown keys and sections: not a refusal")
eq(#snap.items, 1, "only the value this copy can take is kept")
eq(#snap.skipped, 4, "the others are skipped")
check(table.concat(snap.skipped, "|"):find("sent history 600 is over 500 here", 1, true), "with the reason, in words")

--------------------------------------------------------------------------------
-- Applying: only changes, defaults through the reset path, undo
--------------------------------------------------------------------------------
db.timestamps, db.lines, db.glass, db.classColors, db.history = true, 2000, false, false, 100
db.look = { rim = 0.3 }
sdb.repeatWindow, sdb.score = 120, "hide"
local calls = {}
local realHistory = GC.Settings.SetHistory
GC.Settings.SetHistory = function(n) calls[#calls + 1] = n; realHistory(n) end
newChat()
SS.Receive(table.concat({ "ST1", "T\t1", "V\tcore\ttimestamps\tb\t1", "D\tcore\tlines", "D\tcore\tglass",
    "D\tcore\tclassColors", "V\tcore\thistory\ti\t100", "D\tcore\tlook.rim", "V\tspam\trepeatWindow\ti\t60",
    "D\tspam\tscore" }, "\n"), { guid = "Player-1-0000000B", name = "Karuzo Memphisto" }, "1760000000200")
GC.Settings.SetHistory = realHistory
eq(#calls, 0, "a value that doesn't change runs no setter (no trimming for nothing)")
eq(rawget(db, "timestamps"), true, "an unchanged value stays")
eq(rawget(db, "lines"), nil, "D resets: the raw value is cleared")
eq(db.lines, GC.DEFAULTS.lines, "and the default shows through")
eq(rawget(db, "glass"), nil, "glass back to its default (never stored as false)")
eq(db.glass, true, "so it's on")
eq(db.classColors, true, "class colours too")
eq(db.look.rim, nil, "a tune value reset")
eq(sdb.repeatWindow, 60, "the repeat window, in seconds")
eq(rawget(sdb, "score"), nil, "the score mode back to its default")
eq(sdb.score, "watch", "watch")
check(chatHas("settings now follow Karuzo Memphisto's choices: %d changed"), "the summary says follow, not match")
check(chatHas("settings undo puts yours back"), "and how to undo")
eq(db.settingsApplied["Player-1-0000000B"], 1760000000200, "the stream id is kept per sender")
-- Older: ignored.
newChat()
SS.Receive("ST1\nV\tcore\ttimestamps\tb\t0", { guid = "Player-1-0000000B", name = "Karuzo Memphisto" }, "1760000000100")
check(chatHas("ignored an older copy of your settings") and db.timestamps == true, "an older copy is ignored")
-- Undo: raw values back, "was unset" too.
newChat()
SlashCmdList.GLASSCHAT("settings undo")
eq(rawget(db, "lines"), 2000, "undo puts a reset value back")
eq(rawget(db, "glass"), false, "glass off again")
eq(db.look.rim, 0.3, "a tune value back")
eq(sdb.repeatWindow, 120, "the repeat window back")
eq(sdb.score, "hide", "the score mode back")
check(chatHas("can't come back"), "and it says what can't come back")
eq(rawget(db, "settingsUndo"), nil, "one undo per copy")
newChat()
SlashCmdList.GLASSCHAT("settings undo")
check(chatHas("nothing to undo"), "a second undo has nothing to do")

-- The same copy twice: nothing changes the second time.
local same = table.concat({ "ST1", "V\tcore\ttimestamps\tb\t1" }, "\n")
newChat()
SS.Receive(same, { guid = "Player-1-0000000B", name = "Karuzo Memphisto" }, "1760000000300")
check(chatHas("settings already the same"), "a copy that changes nothing says so")

-- A setter that throws: reported, the undo kept.
local realTabs = GC.Settings.SetTabSize
GC.Settings.SetTabSize = function() error("boom") end
newChat()
SS.Receive(table.concat({ "ST1", "V\tcore\ttabSize\ti\t16", "V\tcore\ttimestamps\tb\t0" }, "\n"),
    { guid = "Player-1-0000000B", name = "Karuzo Memphisto" }, "1760000000400")
GC.Settings.SetTabSize = realTabs
check(chatHas("1 of 2 applied; 1 failed"), "a failed setter is reported, never 'now follow'")
check(GC.failures["settings sync tabSize"], "and recorded")
GC.failures["settings sync tabSize"] = nil
check(type(rawget(db, "settingsUndo")) == "table", "the undo is kept")
db.timestamps = true

-- Skipped values are reported.
newChat()
SS.Receive(table.concat({ "ST1", "V\tcore\thistory\ti\t600" }, "\n"),
    { guid = "Player-1-0000000B", name = "Karuzo Memphisto" }, "1760000000500")
check(chatHas("1 setting%(s%) skipped: sent history 600 is over 500 here"), "a value this copy can't take is reported")

--------------------------------------------------------------------------------
-- The layout: through M2's offer, never applied
--------------------------------------------------------------------------------
db.layout = { id = 5, windows = { [1] = { name = "General", messages = {}, channels = {} } }, from = "Old", guid = "Player-1-0000000A" }
db.layoutRevision = 7
GlassChatCharDB.layoutAnswered = 5
local withLayout = table.concat({ "ST1",
    "L\tW\t1\tname\ts\tMain", "L\tW\t1\tdocked\ti\t1", "L\tW\t1\tshown\tb\t1", "L\tM\t1\tSAY", "L\tM\t1\tGUILD",
    "L\tW\t2\tname\ts\tTrade", "L\tW\t2\tpoint\te\tBOTTOMLEFT", "L\tW\t2\tx\tn\t10", "L\tW\t2\ty\tn\t200",
    "L\tW\t2\twidth\tn\t400", "L\tW\t2\theight\tn\t150", "L\tW\t2\tshown\tb\t1", "L\tC\t2\tTrade - City",
    "L\tW\t3\tname\ts\tEmpty" }, "\n")
local offered = 0
local realOffer = GC.Layout.Offer
GC.Layout.Offer = function() offered = offered + 1; return realOffer() end
newChat()
SS.Receive(withLayout, { guid = "Player-1-0000000B", name = "Karuzo Memphisto" }, "1760000000600")
GC.Layout.Offer = realOffer
eq(db.layout.id, 8, "a new id, after the account's own counter")
eq(db.layoutRevision, 8, "and the counter moves on")
check(db.layout.id ~= GlassChatCharDB.layoutAnswered, "so this character's old answer no longer holds")
eq(db.layout.guid, "Player-1-0000000B", "the sender's GUID (never a character here)")
check(db.layout.from:find("Karuzo Memphisto", 1, true), "and its name")
local w1, w2, w3 = db.layout.windows[1], db.layout.windows[2], db.layout.windows[3]
eq(w1.docked, 1, "docked stays a number")
eq(#w1.messages, 2, "message groups")
eq(w2.channels[1], "Trade - City", "channels")
check(w2.point == "BOTTOMLEFT" and w2.x == 10 and w2.y == 200 and w2.width == 400, "a floating window's place and size")
check(type(w3.messages) == "table" and type(w3.channels) == "table", "lists are always there, empty or not")
eq(w3.shown, false, "an absent shown is false")
eq(w3.docked, nil, "and an undocked window has no docked")
eq(offered, 1, "this character is offered it at once")
check(chatHas("is now this account's saved layout"), "and told")
-- Undo: the old layout back with its old id; the counter isn't rewound.
SlashCmdList.GLASSCHAT("settings undo")
eq(db.layout.id, 5, "undo puts the old layout back, with its id")
eq(db.layoutRevision, 8, "the counter isn't rewound")
-- Without layout: the saved layout is never touched.
newChat()
SS.Receive("ST1\nV\tcore\ttimestamps\tb\t0", { guid = "Player-1-0000000B", name = "Karuzo Memphisto" }, "1760000000700")
eq(db.layout.id, 5, "a settings-only copy leaves the saved layout alone")
db.timestamps = true

-- Built: the main window's place never goes; docked as a number.
db.layout = { id = 9, windows = {
    [1] = { name = "General", docked = 1, shown = true, x = 5, y = 6, point = "BOTTOMLEFT", width = 300, height = 100,
            messages = { "SAY" }, channels = {} },
    [2] = { name = "Trade", docked = 2, shown = true, messages = {}, channels = { "Trade - City" } } } }
local lb = SS.Build(true)
check(lb:find("\nL\tW\t1\tdocked\ti\t1"), "the main window's dock index goes (Matches compares it)")
check(not lb:find("\nL\tW\t1\tx\t") and not lb:find("\nL\tW\t1\twidth\t"), "its place and size never")
check(lb:find("\nL\tC\t2\tTrade %- City"), "channels go")
local back = SS.Parse(lb)
check(back and back.layout and back.layout[2].docked == 2, "and a built layout parses back")

--------------------------------------------------------------------------------
-- Sending: the plugin's store, the stopgap, the round trip
--------------------------------------------------------------------------------
store.key = nil

-- Without the plugin's store: the precise reason, nothing sent.
local saved = GlassChatSpamIgnoreSyncDB
GlassChatSpamIgnoreSyncDB = nil
newChat()
SlashCmdList.GLASSCHAT("settings send")
check(chatHas("settings sync needs the Spam & Ignore plugin"), "no store: says the plugin is needed")
GlassChatSpamIgnoreSyncDB = saved

advance(70)
Peer.hello()
advance(2)
AS._test.resetSent()
local before = #sentTo(Peer.id, "D1|")
newChat()
db.timestamps = true
SlashCmdList.GLASSCHAT("settings send")
check(chatHas("sending your settings %(.-KB%) to 1 other account"), "settings go to the other account")
local got = Peer.received()
local st
for _, g in ipairs(got) do if g.payload and g.payload:find("^ST\nST1\n") then st = g end end
check(st and st.macOk, "kind ST, format ST1, MAC'd for it")
check(st and st.payload:find("\nV\tcore\ttimestamps\tb\t1"), "with the settings")
-- The stopgap (LibAccountSync#17): a list send right after is refused.
newChat()
SlashCmdList.GLASSCHAT("ignore send empty")
check(chatHas("wait a moment: your settings are still on their way"), "a list send right after a settings send waits")
advance(AS.KIND_GAP + 1)
newChat()
SlashCmdList.GLASSCHAT("ignore send empty")
check(chatHas("sending your lists"), "and goes after KIND_GAP")
newChat()
SlashCmdList.GLASSCHAT("settings send")
check(chatHas("wait a moment: your lists are still on their way"), "and the other way round")
advance(AS.KIND_GAP + 1)
-- With layout, when none is saved: said, and the settings go alone.
db.layout = nil
newChat()
SlashCmdList.GLASSCHAT("settings send layout")
check(chatHas("no chat layout saved") and chatHas("sending your settings %("), "no layout: said, settings alone")

-- Receiving from the other account through the library.
newChat()
Peer.send("ST\nST1\nT\t1\nV\tcore\ttimestamps\tb\t0", "1760000009000")
eq(db.timestamps, false, "a copy from the other account, through the library, is applied")
check(chatHas("settings now follow Karuzo Memphisto's choices"), "and announced")

-- The help.
newChat()
SlashCmdList.GLASSCHAT("settings")
check(chatHas("/gchat settings send layout") and chatHas("/gchat ignore sync"), "/gchat settings lists its commands")

eq(next(GC.failures), nil, "nothing failed")
done("test_settings_sync")
