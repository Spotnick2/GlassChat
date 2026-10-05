-- Spam & Ignore S3 part 2: the lists to your other accounts through the
-- embedded LibAccountSync-1.0, end to end against the real library (loaded
-- through its XML): a send, a receive, ordering, refusals, the store.
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

-- The store getter is nil until GlassChat's SavedVariables load.
check(rawget(_G, "GlassChatDB") == nil, "(before load)")

WoW.playerGUID, WoW.playerName = "Player-1-0000000A", "Karuzo Elegia"
WoW.loggedIn = true
-- The household key's store lives in the Spam & Ignore plugin's SavedVariables
-- (its own file), never in GlassChat.lua, which holds focus mode's shareable
-- export: the client writes one file per addon (Codex review of #40). A store
-- an earlier build left in GlassChat.lua moves over, its key kept.
GlassChatSyncDB = { key = "bbbb", keyAt = 1 }   -- the previous build's location
local GC = loadAddon({ db = { accountSync = { key = "aaaa", keyAt = 1 } } })
local AS, Sync, Spam = GC.AccountSync, GC.SpamSync, GC.Spam
local store = GlassChatSpamIgnoreSyncDB
check(type(store) == "table", "the store is the plugin's GlassChatSpamIgnoreSyncDB")
eq(store.key, "bbbb", "an earlier store moves over, its key kept (the trust built survives)")
eq(rawget(GlassChatDB, "accountSync"), nil, "nothing of it is left in GlassChatDB")
eq(rawget(_G, "GlassChatSyncDB"), nil, "nor in GlassChatSyncDB: GlassChat.lua is written without the key")
local pluginToc = io.open("Plugins/SpamIgnore/GlassChatSpamIgnore.toc"):read("*a")
check(pluginToc:find("## SavedVariables:[^\n]*GlassChatSpamIgnoreSyncDB"), "the plugin declares the store (its own file)")
local coreToc = io.open("GlassChat.toc"):read("*a")
check(not coreToc:find("GlassChatSpamIgnoreSyncDB", 1, true), "GlassChat's own TOC doesn't (its file holds the export)")
-- Nothing GlassChat.lua's file will hold carries a key.
local function hasKey(t, depth)
    if type(t) ~= "table" or depth > 4 then return false end
    for k, v in pairs(t) do
        if k == "key" or k == "trusted" then return true end
        if hasKey(v, depth + 1) then return true end
    end
    return false
end
check(not hasKey(GlassChatDB, 0) and not hasKey(GlassChatCharDB, 0), "GlassChat.lua's tables hold no key")
eq(AS._test.store(), store, "the library's getter returns the store")
local saved = GlassChatSpamIgnoreSyncDB
GlassChatSpamIgnoreSyncDB = nil
eq(AS._test.store(), nil, "the getter is nil while SavedVariables aren't loaded (at login)")
GlassChatSpamIgnoreSyncDB = saved
store.key = nil   -- let the library choose its own for the rest of the test
check(AS.inst ~= nil, "a LibAccountSync instance, tag GlassChat")

--------------------------------------------------------------------------------
-- The other account (the library harness's Peer, written from its plan's
-- formulas: docs/PLAN.md 5.1, 5.3)
--------------------------------------------------------------------------------
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
-- Sending
--------------------------------------------------------------------------------
local db = Spam.db
db.ignore = { ["Player-1-00000AAA"] = { name = "Annoying Person" }, ["Player-1-00000BBB"] = { name = "Bad Actor" } }
db.pending = { ["future pest"] = { name = "Future Pest" } }
db.mutes = { { phrase = "profession kit" }, { phrase = "gold", aggressive = true } }
Spam.RebuildMutes()

-- Before anyone is known: the reasons, in words.
newChat()
SlashCmdList.GLASSCHAT("ignore send")
check(chatHas("none of your other accounts") or chatHas("still connecting") or chatHas("no way to reach"),
    "before discovery, send says why nothing went")
eq(#sentTo(Peer.id, "D1|"), 0, "and sends nothing")

advance(70)   -- the friends list settles, the scan finds the other account, we greet it
check(#sentTo(Peer.id, "H1|") > 0, "the library greets the other account")
newChat()
SlashCmdList.GLASSCHAT("ignore send")
check(chatHas("isn't ready yet") or chatHas("still connecting"), "before its hello: not ready, try again in a few seconds")
check(not chatHas("to 0 of your other accounts"), "and no 'sending to 0 accounts'")

Peer.hello()
advance(2)
newChat()
SlashCmdList.GLASSCHAT("ignore send")
check(chatHas("sending your lists %(.-KB%) to 1 other account%.%.%."), "with its hello in: the lists go (1 other account)")
-- In game the library reported the result while Send was still running:
-- the summary comes first, the result after (owner's two-account check).
local iSend, iSent
for i, l in ipairs(WoW.chat) do
    if l:find("sending your lists", 1, true) then iSend = i end
    if l:find("handed to Battle.net for", 1, true) then iSent = i end
end
check(iSend and iSent and iSend < iSent, "the summary prints before the per-account result")
check(chatHas("handed to Battle.net for Karuzo Memphisto") and chatHas("no delivery receipt"),
    "and 'sent' is worded as handed over, not delivered")
local got = Peer.received()
eq(#got, 1, "one stream to the other account")
check(got[1] and got[1].macOk, "MAC'd for it, over its nonce")
local payload = got[1] and got[1].payload or ""
check(payload:find("^SI\nSI1\n"), "kind SI, format SI1 first")
check(payload:find("\nI\tPlayer%-1%-00000AAA\tAnnoying Person"), "the ignores, by GUID")
check(payload:find("\nP\tFuture Pest"), "the pending names")
check(payload:find("\nM\t0\tprofession kit") and payload:find("\nM\t1\tgold"), "the mutes, aggressive flagged")
check(payload:find("\nO\tPlayer%-1%-0000000A\tKaruzo Elegia"), "and this character as one of yours")

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------
local function snapshot(lines) return "SI\n" .. table.concat(lines, "\n") end
newChat()
Peer.send(snapshot({ "SI1", "T\t1760000100", "I\tPlayer-1-00000CCC\tNew Pest", "P\tSomeone Later",
    "M\t0\tcheap boost", "O\tPlayer-1-0000000B\tKaruzo Memphisto", "I\tPlayer-1-0000000A\tKaruzo Elegia" }), "1760000000101")
check(chatHas("your lists now match Karuzo Memphisto: 1 ignored, 1 pending, 1 muted"), "a snapshot from the other account is applied")
check(db.ignore["Player-1-00000CCC"] and not db.ignore["Player-1-00000AAA"], "whole: removals included")
check(db.pending["someone later"] and not db.pending["future pest"], "pending too")
eq(#db.mutes, 1, "and the mutes")
eq(db.mutes[1].phrase, "cheap boost", "replaced")
check(db.own["Player-1-0000000B"], "its own characters are added to yours")
check(db.ignore["Player-1-0000000A"] == nil, "and an ignore naming one of yours is dropped")
check(Spam.Judge("CHAT_MSG_CHANNEL", "cheap boost now", "Rando Seller", "Player-1-00000DDD") ~= nil, "the new mutes take effect")

-- Older than the last applied from that sender: ignored.
newChat()
Peer.send(snapshot({ "SI1", "I\tPlayer-1-00000EEE\tStale One" }), "1760000000050")
check(db.ignore["Player-1-00000EEE"] == nil and db.ignore["Player-1-00000CCC"], "an older stream changes nothing (the library drops it)")
-- GlassChat's own check, saved across sessions (the library's is this session's).
eq(Spam.db.syncApplied["Player-1-0000000B"], 1760000000101, "the last applied stream id is saved per sender")
newChat()
Sync.Receive("SI1\nI\tPlayer-1-00000EEE\tStale One", { guid = "Player-1-0000000B", name = "Karuzo Memphisto" }, "1760000000090")
check(chatHas("ignored an older copy") and db.ignore["Player-1-00000EEE"] == nil, "an older snapshot after a reload is ignored too")

-- Refused whole: a bad format, a bad line, a bad GUID, too many lines.
local function refused(lines, sid, label)
    newChat()
    local before = db.ignore
    Peer.send(snapshot(lines), sid)
    check(chatHas("refused a copy of your lists") and db.ignore == before, label .. ": refused whole, lists unchanged")
end
refused({ "SI9", "I\tPlayer-1-00000FFF\tX Y" }, "1760000000201", "an unknown format")
refused({ "SI1", "I\tPlayer-1-00000FFF\tFine One", "Z\tnonsense" }, "1760000000202", "an unknown line")
refused({ "SI1", "I\tnot-a-guid\tBad Guid" }, "1760000000203", "a malformed GUID")
refused({ "SI1", "M\t2\tphrase" }, "1760000000204", "a bad mute flag")
refused({ "SI1", "P\t" .. string.rep("x", 60) }, "1760000000205", "a name too long")
local many = { "SI1" }
for i = 1, Sync.CAPS.M + 1 do many[#many + 1] = "M\t0\tphrase" .. i end
refused(many, "1760000000206", "too many mutes")
eq(#db.mutes, 1, "(the mutes are still the applied ones)")

-- A payload of a kind GlassChat doesn't know reaches no handler.
local before = db.ignore
Peer.send("ZZ" .. string.char(10) .. "SI1" .. string.char(10) .. "I" .. string.char(9) .. "Player-1-00000FFF" .. string.char(9) .. "Other Kind", "1760000000301")
check(db.ignore == before, "an unknown kind is ignored")

-- Parse is all-or-nothing on its own too.
check(Sync.Parse("SI1\nI\tPlayer-1-00000AAA\tA Name"), "a good body parses")
check(not Sync.Parse(WoW.Secret("x")), "a secret body is never read")
check(not Sync.Parse(""), "nor an empty one")

-- Undo: the lists the last snapshot replaced come back.
newChat()
SlashCmdList.GLASSCHAT("ignore sync undo")
check(chatHas("your lists are back"), "/gchat ignore sync undo restores the lists a snapshot replaced")
check(db.ignore["Player-1-00000AAA"] and db.ignore["Player-1-00000CCC"] == nil, "the ignores as they were")
newChat()
SlashCmdList.GLASSCHAT("ignore sync undo")
check(chatHas("nothing to undo"), "and only once")

--------------------------------------------------------------------------------
-- Review of #40: what the sender sends, and refuses to
--------------------------------------------------------------------------------
-- One of yours (known through AltStable) is never sent as an ignore; it's sent as own.
rawset(_G, "AltStable", { PUBLIC_API_VERSION = 1,
    GetCharacters = function() return { { guid = "Player-1-0000A1F9", name = "Alt Elsewhere" } } end,
    RegisterCallback = function() end })
Spam.RefreshAltStable()
db.ignore["Player-1-0000A1F9"] = { name = "Alt Elsewhere" }   -- ignored before AltStable knew it
db.pending["alt elsewhere"] = { name = "Alt Elsewhere" }
local body = Sync.Build()
check(not body:find("\nI\tPlayer%-1%-0000A1F9"), "an ignore naming one of yours isn't sent")
check(not body:find("\nP\tAlt Elsewhere"), "nor a pending one")
check(body:find("\nO\tPlayer%-1%-0000A1F9\tAlt Elsewhere"), "it's sent as one of your own instead")
db.ignore["Player-1-0000A1F9"], db.pending["alt elsewhere"] = nil, nil
rawset(_G, "AltStable", nil)

-- Empty lists aren't sent unless asked: they'd empty every other account.
local keepI, keepP, keepM = db.ignore, db.pending, db.mutes
db.ignore, db.pending, db.mutes = {}, {}, {}
newChat()
SlashCmdList.GLASSCHAT("ignore send")
check(chatHas("your lists are empty") and chatHas("/gchat ignore send empty"), "empty lists: refused, with how to force it")
local before = #sentTo(Peer.id, "D1|")
SlashCmdList.GLASSCHAT("ignore send empty")
check(#sentTo(Peer.id, "D1|") > before, "/gchat ignore send empty sends them")
db.ignore, db.pending, db.mutes = keepI, keepP, keepM

-- Empty is what would be SENT (Codex review of #40): lists holding only your
-- own characters, or only entries that can't be written, are empty too.
db.ignore, db.pending, db.mutes = { ["Player-1-0000000A"] = { name = "Karuzo Elegia" } }, {}, {}
newChat()
SlashCmdList.GLASSCHAT("ignore send")
check(chatHas("your lists are empty"), "an ignore list holding only one of your own characters counts as empty")
db.ignore, db.pending, db.mutes = { ["not-a-guid"] = { name = "Bad Entry" } }, { ["x"] = { name = "a" .. string.rep("b", 60) } }, {}
newChat()
before = #sentTo(Peer.id, "D1|")
SlashCmdList.GLASSCHAT("ignore send")
check(chatHas("your lists are empty"), "and so do lists holding only entries that can't be written")
eq(#sentTo(Peer.id, "D1|"), before, "nothing sent without asking")
db.ignore, db.pending, db.mutes = keepI, keepP, keepM

-- Over a receiver's cap: refused here, not by every receiver.
for i = 1, Sync.CAPS.P + 1 do db.pending["pending" .. i] = { name = "Pending Name" .. i } end
newChat()
SlashCmdList.GLASSCHAT("ignore send")
check(chatHas("too many pending names to send"), "over a cap: the sender says so")
for i = 1, Sync.CAPS.P + 1 do db.pending["pending" .. i] = nil end

--------------------------------------------------------------------------------
-- Sizes, the switch, the status
--------------------------------------------------------------------------------
local function sized(nIgnore, nMute)
    db.ignore, db.pending, db.mutes = {}, {}, {}
    for i = 1, nIgnore do db.ignore[string.format("Player-1-%08X", i)] = { name = "Somename Longsurname" .. i } end
    for i = 1, nMute do db.mutes[i] = { phrase = "a muted phrase number " .. i } end
    return #(Sync.Build())
end
local realistic, large = sized(50, 10), sized(500, 40)
io.write(string.format("  sizes: 50 ignores + 10 mutes = %d bytes; 500 ignores + 40 mutes = %d bytes\n", realistic, large))
check(large < AS.MAX, "500 ignores and 40 mutes fit in one payload")
sized(800, 0)
newChat()
SlashCmdList.GLASSCHAT("ignore send")
check(chatHas("too large to send") and chatHas("KB"), "lists over the ceiling: a clear message, nothing truncated")

newChat()
SlashCmdList.GLASSCHAT("ignore sync off")
check(chatHas("account sync: off") and not AS.IsEnabled(), "/gchat ignore sync off turns it off")
SlashCmdList.GLASSCHAT("ignore send")
check(chatHas("account sync is off"), "and send says so")
-- On, but the library still says "disabled" (Battle.net not usable): not "turn it on".
SlashCmdList.GLASSCHAT("ignore sync on")
local realSend = AS.inst.Send
AS.inst.Send = function() return nil, "disabled" end
newChat()
SlashCmdList.GLASSCHAT("ignore send")
local lastLine = WoW.chat[#WoW.chat]
check(lastLine:find("Battle.net isn't ready for account sync", 1, true) and not lastLine:find("account sync is off", 1, true),
    "with the switch on, 'disabled' says Battle.net isn't ready, not 'turn it on'")
AS.inst.Send = realSend
SlashCmdList.GLASSCHAT("ignore sync on")
check(AS.IsEnabled(), "on again")
newChat()
SlashCmdList.GLASSCHAT("ignore sync")
check(chatHas("account sync: on"), "/gchat ignore sync shows the status")
check(#WoW.chat > 3, "with the library's diagnostics")

eq(next(GC.failures), nil, "nothing failed")
done("test_sync")
