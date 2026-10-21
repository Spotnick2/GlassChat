-- The kept chat (#125): player chat saved at logout and reload, put back
-- above the next session's lines; never addon, system, secret or combat-log
-- lines; Battle.net names rebuilt for the new session; off by default.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GC = loadAddon({ charDB = {} })
local K, T = GC.Keep, GC.Keep._test
local f1, f2, f3 = ChatFrame1, ChatFrame2, ChatFrame3
local function slash(s) SlashCmdList.GLASSCHAT(s) end
local function logout() WoW.fire("PLAYER_LOGOUT") end
local function say(f, text, event) f:AddMessage(text, 0.25, 1, 0.25, 4, 7, 9, event, {}, function() end) end
local function texts(f)
    local out = {}
    for i, e in ipairs(f._lines or {}) do out[i] = e.m end
    return out
end
local function kept(i)
    local k = GC.charDB.kept
    return k and k.windows[i] and k.windows[i].lines or {}
end

-- Battle.net: a friend, account 42 this session.
WoW.bn.friendAccounts = { { bnetAccountID = 42, accountName = "|Kq7|k", battleTag = "Friend#1234" } }
WoW.bn.friends = { {} }
rawset(_G, "COMBATLOG", f2)

-- Off by default: nothing saved.
check(not GC.db.keep, "off by default")
say(f1, "[Guild] Bob: hello", "CHAT_MSG_GUILD")
logout()
eq(GC.charDB.kept, nil, "off: nothing kept")

slash("keep on")
check(GC.db.keep, "/gchat keep on")
f1._lines = {}
say(f1, "[Guild] Bob: hello", "CHAT_MSG_GUILD")
f1:AddMessage("|cff00ccff[ASProbe]|r line 1")                     -- an addon's line: no event, no id
f1:AddMessage("You receive loot: [Linen Cloth].", 0, 0.67, 0, 3)     -- Blizzard's system line: an id, no event
say(f1, WoW.Secret("chat"), "CHAT_MSG_SAY")
say(f1, "|HBNplayer:|Kq7|k:42:9:BN_WHISPER:|Kq7|k|h[|Kq7|k]|h whispers: yo |Kq8|k", "CHAT_MSG_BN_WHISPER")
say(f1, "[2. Trade] Ann: wts", "CHAT_MSG_CHANNEL")
say(f2, "[Guild] in the combat log window", "CHAT_MSG_GUILD")
say(f3, "Bob whispers: psst", "CHAT_MSG_WHISPER")
logout()

local l1 = kept(1)
eq(#l1, 3, "player chat only: the addon, system and secret lines left out")
eq(l1[1].text, "[Guild] Bob: hello", "  oldest first")
eq(l1[1].event, "CHAT_MSG_GUILD", "  with its event")
eq(l1[1].g, 1, "  and its colour")
eq(l1[2].text, "\2BN_WHISPER\3Friend#1234\2 whispers: yo ?", "a Battle.net name saved as its BattleTag, no token")
eq(l1[3].text, "[2. Trade] Ann: wts", "  channels kept")
eq(GC.charDB.kept.windows[2], nil, "never the combat log")
eq(kept(3)[1].text, "Bob whispers: psst", "each window its own")
eq(GC.charDB.kept.windows[3].name, "Whispers", "  with its name")

-- The next session.
local before = GC.charDB.kept.saved
GC.charDB.kept.saved = before - 600
for _, l in ipairs(kept(1)) do l.t = before - 3600 end
WoW.bn.friendAccounts = { { bnetAccountID = 77, accountName = "|Kq99|k", battleTag = "Friend#1234" } }
f1._lines, f2._lines, f3._lines = {}, {}, {}
say(f1, "[Guild] Ann: back already", "CHAT_MSG_GUILD")   -- printed at login, before the restore
local count = GC.Chat.LineCount(f1)
T.reset()
K.Restore()
local t = texts(f1)
eq(#t, 5, "the history, the divider and the login line")
eq(t[1], "[Guild] Bob: hello", "the history first")
eq(t[2], "|HBNplayer:|Kq99|k:77:0:BN_WHISPER:|Kq99|k|h[|Kq99|k]|h whispers: yo ?",
    "  the Battle.net link rebuilt with this session's name and id")
eq(t[4], "--- previous session, 10 min ago ---", "  then the divider")
eq(t[5], "[Guild] Ann: back already", "  above this session's lines")
eq(f1._lines[1].extra[7], "CHAT_MSG_GUILD", "  each line with its event")
eq(f1._lines[1].extra[10], before - 3600, "  and its time")
eq(GC.Chat.LineCount(f1), count, "  never through AddMessage: not counted as new")
local kinds = {}
for _, e in ipairs(GC.Focus.Snapshot(f1)) do kinds[#kinds + 1] = e.kind end
eq(table.concat(kinds, ","), "Guild,Whisper,Channel,Addons,Guild", "focus mode still sorts them")
eq(texts(f3)[1], "Bob whispers: psst", "window 3 too")
eq(#texts(f3), 2, "  under its divider")

K.Restore()
eq(#texts(f1), 5, "once a session")

-- Saved again: the restored lines keep their time; the divider isn't kept.
logout()
l1 = kept(1)
eq(#l1, 4, "the history and the new line, no divider")
eq(l1[1].t, before - 3600, "a restored line keeps its time")
eq(l1[2].text, "\2BN_WHISPER\3Friend#1234\2 whispers: yo ?", "  its rebuilt link saved as the BattleTag again")
check(os.time() - l1[4].t < 5, "  a new line gets the save's time")

-- Too old, renamed, a friend gone, junk.
l1[1].t = os.time() - K.MAX_AGE - 1
l1[3].event = "CHAT_MSG_ADDON"
l1[4].text = 42
WoW.window(3).name = "Other"
WoW.bn.friendAccounts, WoW.bn.friends = {}, {}
f1._lines, f3._lines = {}, {}
T.reset()
K.Restore()
t = texts(f1)
eq(#t, 2, "a line too old, of another kind or broken is dropped")
eq(t[1], "[Friend] whispers: yo ?", "a friend gone: the BattleTag's name, plain")
eq(#texts(f3), 0, "a renamed window gets nothing")
WoW.window(3).name = "Whispers"

-- The newest Keep.MAX per window.
f1._lines = {}
for i = 1, K.MAX + 10 do say(f1, "line " .. i, "CHAT_MSG_SAY") end
logout()
eq(#kept(1), K.MAX, "at most Keep.MAX lines")
eq(kept(1)[1].text, "line 11", "  the newest")

-- Older chat under more than Copy.MAX addon lines is still found (Codex on #126).
f1._lines = {}
for i = 1, 3 do say(f1, "guild " .. i, "CHAT_MSG_GUILD") end
for i = 1, GC.Copy.MAX + 50 do f1:AddMessage("|cff00ccff[ASProbe]|r spam " .. i) end
logout()
eq(#kept(1), 3, "chat older than Copy.MAX addon lines is kept")
eq(kept(1)[1].text, "guild 1", "  oldest first")

-- Off forgets at once.
slash("keep off")
eq(GC.charDB.kept, nil, "/gchat keep off: forgotten")
logout()
eq(GC.charDB.kept, nil, "  and nothing saved")

eq(next(GC.failures), nil, "no failures")
done("test_keep")
