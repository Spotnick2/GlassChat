-- ChatProbe: every command runs on the stubbed client without throwing, logs
-- to its saved table, never logs what someone said, and survives secrets.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- What the probe touches beyond the shared stub (all in the 70205 dump or
-- Forever's FrameXML: ChatTypeInfoConstants.lua, ChatFrameFilters.lua).
local clipboard
rawset(_G, "GetTime", function() return 12.5 end)
rawset(_G, "time", function() return 1759500000 end)
rawset(_G, "IsShiftKeyDown", function() return false end)
rawset(_G, "GetInstanceInfo", function() return "Eastern Kingdoms", "none" end)
rawset(_G, "C_CVar", { GetCVar = function(name) return name == "chatClassColorOverride" and "2" or nil end })
rawset(_G, "C_ChatInfo", { InChatMessagingLockdown = function() return false end })
rawset(_G, "ChatTypeInfo", { SAY = { colorNameByClass = true }, GUILD = { colorNameByClass = false } })
rawset(_G, "Constants", { ChatFrameConstants = { MaxChatWindows = 3 } })
rawset(_G, "CopyToClipboard", function(text) clipboard = text; return #text end)
rawset(_G, "GetPlayerInfoByGUID", function() return "Mage", "MAGE" end)
local filters, nameFilters = {}, {}
rawset(_G, "ChatFrameUtil", {
    AddMessageEventFilter = function(e, fn) filters[e] = fn end,
    AddSenderNameFilter = function(fn) nameFilters[#nameFilters + 1] = fn end,
    ShouldColorChatByClass = function(info) return info.colorNameByClass end,
})
local callbacks = {}
rawset(_G, "EventRegistry", { RegisterCallback = function(self, e, fn, owner) callbacks[e] = fn end })
rawset(_G, "SetItemRef", function() end)
-- The server ignore list (C_FriendList, 70205 dump :1610-1630), kept like the
-- client: a list of names, IsIgnoredByGuid by the GUIDs added.
local ignoreList, ignoredGuids, targetGuid = { "Old Grudge" }, {}, "Player-1-T"
rawset(_G, "C_FriendList", {
    GetNumIgnores = function() return #ignoreList end,
    GetIgnoreName = function(i) return ignoreList[i] end,
    AddIgnore = function(name) table.insert(ignoreList, name); ignoredGuids[targetGuid] = true; return true end,
    DelIgnore = function(name)
        for i, n in ipairs(ignoreList) do if n == name then table.remove(ignoreList, i); ignoredGuids[targetGuid] = nil; return true end end
        return false
    end,
    IsIgnoredByGuid = function(guid) return ignoredGuids[guid] == true end,
})
local target = nil   -- { first, surname, full }
rawset(_G, "UnitIsPlayer", function(u) return u == "target" and target ~= nil end)
rawset(_G, "UnitIsUnit", function() return false end)
rawset(_G, "UnitName", function(u) if u == "target" and target then return target[1], target[2] end end)
rawset(_G, "GetUnitName", function(u) if u == "target" and target then return target[3] end end)
rawset(_G, "UnitGUID", function(u) if u == "target" then return targetGuid end end)
rawset(_G, "RegionalUniqueNamesEnabled", function() return true end)
-- No "Probe" tab yet on this character (item 8 opens one; item 9 reuses it).
-- windows[i] = { name, shown, docked }, GetChatWindowInfo's 1st, 7th and 9th.
local windows = {}
rawset(_G, "GetChatWindowInfo", function(i)
    local w = windows[i] or { "General", true, true }
    return w[1], 14, 1, 1, 1, 1, w[2], false, w[3]
end)

-- Two chat frames with a scrollback; line 2 of frame 1 is secret.
local secretLine = WoW.Secret("chat line")
local function chatFrame(name, lines)
    local f = CreateFrame("ScrollingMessageFrame", name, UIParent)
    f._copyable = false
    rawset(f, "GetNumMessages", function() return #lines end)
    rawset(f, "GetMessageInfo", function(_, i) return lines[i], 1, 1, 1, i end)
    rawset(f, "GetMaxLines", function() return 128 end)
    rawset(f, "SetTextCopyable", function(self, v) self._copyable = v end)
    rawset(f, "IsTextCopyable", function(self) return self._copyable end)
    rawset(f, "HasSecretValues", function() return true end)
    -- A real buffer for item 9: AddMessage appends { m, seq }, oldest first;
    -- the predicate sees the message and walks OLDEST to newest, like
    -- CircularBufferMixin:RemoveIf (CircularBuffer.lua:89). seq tells two
    -- identical lines apart.
    f._lines = {}
    rawset(f, "AddMessage", function(self, msg)
        WoW.seq = (WoW.seq or 0) + 1
        table.insert(self._lines, { m = msg, seq = WoW.seq })
    end)
    rawset(f, "RemoveMessagesByPredicate", function(self, pred)
        local keep = {}
        for _, e in ipairs(self._lines) do if not pred(e.m) then keep[#keep + 1] = e end end
        self._lines = keep
    end)
    return f
end
chatFrame("ChatFrame1", { "hello there", secretLine, "a much longer line of text" })
chatFrame("ChatFrame2", {})
chatFrame("ChatFrame3", {})   -- the tab item 8 "opens"

ChatProbeDB = nil
local ns = {}
assert(loadfile("Tools/ChatProbe/ChatProbe.lua"))("ChatProbe", ns)
local T = ns._test
check(rawget(_G, "ChatProbe_test") == nil, "the test seam stays off _G")
WoW.fire("ADDON_LOADED", "ChatProbe")
eq(type(ChatProbeDB.log), "table", "the probe keeps its log in saved variables")
eq(ChatProbeDB.loads, 1, "it counts its loads (persistence check)")
local function logHas0(pattern)
    for _, l in ipairs(ChatProbeDB.log) do if l:find(pattern, 1, true) then return true end end
end
check(logHas0("12 ignores at ADDON_LOADED: 1"), "12 counts the ignore list at ADDON_LOADED (no names)")

local function logHas(pattern)
    for _, line in ipairs(ChatProbeDB.log) do if line:find(pattern, 1, true) then return true end end
    return false
end

for _, cmd in ipairs({ "", "state", "clip", "copyable", "link", "watch", "history", "report" }) do
    SlashCmdList.CHATPROBE(cmd)
end
check(logHas("chatClassColorOverride = 2"), "1 logs the class-colour CVar")
check(logHas("ChatTypeInfo.SAY.colorNameByClass = true"), "1 logs per-type class colouring")
check(clipboard and clipboard:find("GlassChat probe", 1, true), "2 copies its test string")
check(ChatFrame1._copyable == true, "3 turns drag-select copy on")
check(callbacks.SetItemRef ~= nil, "4 listens for addon links through EventRegistry")
check(logHas("ChatFrame1 messages=3 plain=2 secret=1 longest=26"), "6 counts plain and secret lines")

-- 4: a click on our link is logged; anyone else's is ignored.
callbacks.SetItemRef(nil, "addon:chatprobe:hello", "[ChatProbe link]", "RightButton")
check(logHas("link=addon:chatprobe:hello button=RightButton"), "4 logs a click on its link")

-- 5: payloads are described by shape only, secrets included, and the
-- filters are installed and counted.
check(filters.CHAT_MSG_SAY ~= nil and #nameFilters == 1, "5 installs a message filter and a sender-name filter")
-- The client's argument order (ChatFrameFilters.lua:36): the decorated name
-- must come back unchanged, never the event token.
eq(nameFilters[1]("CHAT_MSG_SAY", "|cff3fc7ebKaruzo|r", "hello"), "|cff3fc7ebKaruzo|r",
    "5 the sender-name filter returns the decorated name it was given")
local secretSender = WoW.Secret("sender")
WoW.fire("CHAT_MSG_SAY", "my secret plans", "Karuzo Surname", "", "", "", "", 0, 0, "", 0, 7, "Player-1-ABC")
WoW.fire("CHAT_MSG_SAY", WoW.Secret("text"), secretSender, "", "", "", "", 0, 0, "", 0, WoW.Secret("id"), WoW.Secret("guid"))
check(logHas("text=str15 sender=str14 lineID=number guid=str12 class=MAGE"), "5 logs a plain payload's shape and class")
check(logHas("text=<secret> sender=<secret> lineID=<secret> guid=<secret> class=?"), "5 logs a secret payload without touching it")
check(not logHas("my secret plans") and not logHas("Karuzo"), "5 never logs what was said or who said it")
filters.CHAT_MSG_SAY(nil, "CHAT_MSG_SAY", "x")
SlashCmdList.CHATPROBE("report")
check(logHas("events=2 messageFilter calls=1"), "5 reports events against filter calls")

-- 7: the print handler names the calling addon from the stack, skipping
-- itself and the print plumbing, and passes the line on untouched.
local handler, passedOn = nil, {}
local stack = ""
rawset(_G, "getprinthandler", function() return handler or function(...) passedOn[#passedOn + 1] = strjoin(" ", ...) end end)
rawset(_G, "setprinthandler", function(fn) handler = fn end)
rawset(_G, "debugstack", function() return stack end)
rawset(_G, "strjoin", function(sep, ...) return table.concat({ ... }, sep) end)
rawset(_G, "tostringall", function(...) return ... end)
-- Each frame line names its file twice, as the client's do: that is what
-- made every line come out as ChatProbe on 70205.
-- And the probe's own frames come first, more than one (sourceOf, then the
-- handler or hook), as in the 70205 sample stack.
local function via(path) return '[Interface/AddOns/ChatProbe/ChatProbe.lua]:289: in function <Interface/AddOns/ChatProbe/ChatProbe.lua:287>\n'
    .. '[Interface/AddOns/ChatProbe/ChatProbe.lua]:313: in function <Interface/AddOns/ChatProbe/ChatProbe.lua:312>\n'
    .. '[C]: in function \'pcall\'\n'
    .. '[Interface/AddOns/Blizzard_PrintHandler/Blizzard_PrintHandler.lua]:90: in function <Interface/AddOns/Blizzard_PrintHandler/Blizzard_PrintHandler.lua:86>\n'
    .. '[Interface/AddOns/' .. path .. ']:12: in function <Interface/AddOns/' .. path .. ':10>\n' end
SlashCmdList.CHATPROBE("sources")
check(handler == T.printHandler, "7 installs its print handler")
stack = via("ASProbe/ASProbe.lua")
handler("ASProbe", "line one")
handler("ASProbe", "line two")
eq(passedOn[#passedOn], "ASProbe line two", "7 passes print lines on to the original handler")
-- A direct AddMessage with no chat event counts as direct; one carrying an
-- event (Blizzard's chat handler) or inside print does not.
stack = via("OtherAddon/Other.lua")
ChatFrame1:AddMessage("direct", 1, 1, 1, nil, nil, nil, nil)
ChatFrame1:AddMessage("said", 1, 1, 1, 1, nil, 1, "CHAT_MSG_SAY")
-- One of Blizzard's own 5-argument lines (no event, only chat plumbing
-- above the hook) is bucketed as Blizzard, not as an unknown addon.
stack = '[Interface/AddOns/ChatProbe/ChatProbe.lua]:289: in function <Interface/AddOns/ChatProbe/ChatProbe.lua:287>\n'
    .. '[Interface/AddOns/ChatProbe/ChatProbe.lua]:313: in function <Interface/AddOns/ChatProbe/ChatProbe.lua:312>\n'
    .. "[C]: in function 'AddMessage'\n"
    .. '[Interface/AddOns/Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua]:259: in function <Interface/AddOns/Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua:250>\n'
ChatFrame1:AddMessage("You are now Away", 1, 1, 0, 1)
SlashCmdList.CHATPROBE("sources")
check(logHas("7 AddMessage (no chat event) from Blizzard = 1"), "7 buckets Blizzard's own 5-argument lines")
check(logHas("7 print from ASProbe = 2"), "7 counts print lines per source addon")
check(logHas("7 AddMessage (no chat event) from OtherAddon = 1"), "7 counts direct AddMessage lines per addon")

-- 8: a new empty tab gets ChatProbe's own lines; other addons' don't move.
local tab = ChatFrame3
local function texts(f)
    local out = {}
    for _, e in ipairs(f._lines) do out[#out + 1] = e.m end
    return out
end
local function routed() return texts(tab) end
tab.messageTypeList = {}
windows[3] = { "", false, false }   -- an unused window slot
rawset(_G, "FCF_OpenNewWindow", function(name, noDefault) tab._tabName, tab._noDefault = name, noDefault; return tab end)
SlashCmdList.CHATPROBE("route")
check(tab._tabName == "Probe" and tab._noDefault == true, "8 opens an empty 'Probe' tab")
local before = #passedOn
stack = via("ChatProbe/ChatProbe.lua")
handler("ChatProbe", "mine")
local r = routed()
eq(r[#r], "ChatProbe mine", "8 routes ChatProbe's lines to the tab")
stack = via("ASProbe/ASProbe.lua")
handler("ASProbe", "theirs")
eq(#passedOn, before + 1, "8 leaves other addons' lines in the main chat")
SlashCmdList.CHATPROBE("route")
stack = via("ChatProbe/ChatProbe.lua")
handler("ChatProbe", "back")
eq(passedOn[#passedOn], "ChatProbe back", "8 routing off returns lines to the main chat")

-- 9: an addon's direct AddMessage lines move to the Probe tab: copied
-- there, and the copy just added removed from General, not an older
-- identical line. A CLOSED Probe tab (name kept, hidden, undocked) is not
-- reused; a shown one is.
local opened = 0
rawset(_G, "FCF_OpenNewWindow", function() opened = opened + 1; return tab end)
windows[3] = { "Probe", false, false }
SlashCmdList.CHATPROBE("move AltStableProbe")
eq(opened, 1, "9 doesn't reuse a closed Probe tab")
SlashCmdList.CHATPROBE("move")
windows[3] = { "Probe", true, true }
opened = 0
SlashCmdList.CHATPROBE("sources")   -- tracing on too: the probe's own copies must not count
SlashCmdList.CHATPROBE("move AltStableProbe")
eq(opened, 0, "9 reuses the character's shown Probe tab")
tab._lines = {}
ChatFrame1._lines = { { m = "old line", seq = -2 }, { m = "[ASProbe] dup", seq = -1 } }
stack = via("AltStableProbe/Probe.lua")
ChatFrame1:AddMessage("[ASProbe] dup", 1, 1, 1)
ChatFrame1:AddMessage("[ASProbe] two", 1, 1, 1)
stack = via("OtherAddon/Other.lua")
ChatFrame1:AddMessage("other line", 1, 1, 1)
eq(table.concat(routed(), ","), "[ASProbe] dup,[ASProbe] two", "9 copies the addon's lines to the tab")
eq(table.concat(texts(ChatFrame1), ","), "old line,[ASProbe] dup,other line",
    "9 removes one copy per moved line from General and leaves the rest")
eq(ChatFrame1._lines[2].seq, -1, "9 removes the line just added, not the older identical one")
SlashCmdList.CHATPROBE("sources")
-- The stub's stack is static, so a counted copy would show up as two more
-- AltStableProbe lines: only the 2 originals may count.
check(logHas("7 AddMessage (no chat event) from AltStableProbe = 2"), "9 the probe's own copies aren't counted as AddMessage output")
SlashCmdList.CHATPROBE("move")
check(logHas("9 moving off: 2 lines moved from AltStableProbe, 0 copied but not removed"), "9 reports the counts")
stack = via("AltStableProbe/Probe.lua")
ChatFrame1:AddMessage("[ASProbe] after", 1, 1, 1)
eq(#routed(), 2, "9 off: lines stay where they were added")

SlashCmdList.CHATPROBE("watch")
check(not T.watcher:IsEventRegistered("CHAT_MSG_SAY"), "5 watch toggles off")
-- 5: filters count only while watching (they can't be removed), and a
-- refused registration is reported.
local calls = T.P.filterCalls
filters.CHAT_MSG_SAY(nil, "CHAT_MSG_SAY", "x")
check(not T.P.watching and T.P.filterCalls == calls, "5 filters don't count while not watching")
rawset(T.watcher, "RegisterEvent", function() return false end)
SlashCmdList.CHATPROBE("watch")
check(logHas("RegisterEvent CHAT_MSG_SAY: refused"), "5 a refused registration is reported")
SlashCmdList.CHATPROBE("watch")
SlashCmdList.CHATPROBE("clear")
eq(#ChatProbeDB.log, 1, "clear empties the log (leaving its own line)")


-- 10: line identity per event. One line seen by two windows is one line with
-- two filter calls; a reused lineID with different text is a collision; a
-- missing lineID or a non-player GUID is counted; nothing said is logged.
local T10 = ns._test
SlashCmdList.CHATPROBE("lines")
local f10 = filters.CHAT_MSG_SAY
check(f10 == T10.identityFilter, "10 a filter is installed on each traced event")
local function line(event, text, sender, lineID, guid)
    T10.identityFilter(nil, event, text, sender, "", "", "", "", 0, 0, "", 0, lineID, guid)
end
line("CHAT_MSG_SAY", "hello there", "Kaleid Sumner", 101, "Player-1-AB")
line("CHAT_MSG_SAY", "hello there", "Kaleid Sumner", 101, "Player-1-AB")   -- the same line, second window
line("CHAT_MSG_SAY", "something else", "Kaleid Sumner", 101, "Player-1-AB") -- same id, other text
line("CHAT_MSG_CHANNEL", "wts kits", "Bob Seller-Doomhowl", 0, "Player-1-CD")
line("CHAT_MSG_TEXT_EMOTE", "waves", "Kaleid Sumner", 102, "Creature-0-1")
SlashCmdList.CHATPROBE("lines")
check(logHas("10 CHAT_MSG_SAY: 1 lines, 3 filter calls"), "10 a line in two windows counts once, its calls twice")
check(logHas("10 lineID collisions (same id, different text) = 1"), "10 a reused lineID with other text is a collision")
check(logHas("10 CHAT_MSG_CHANNEL: 0 lines, 1 filter calls (0.0 per line), badID=1"), "10 a missing lineID is counted")
check(logHas("badGUID=1"), "10 a non-player GUID is counted")
check(logHas("11 sender shape: CHAT_MSG_SAY words=2 dash=false"), "11 the sender's shape is logged")
check(not logHas("Kaleid") and not logHas("hello") and not logHas("Bob"), "10/11 no name or text is logged")

-- 10 survives a /reload: the trace is in ChatProbeDB, resumes after the
-- reload, and the report covers lines from both sides of it.
SlashCmdList.CHATPROBE("lines")
line("CHAT_MSG_YELL", "before reload", "Kaleid Sumner", 201, "Player-1-AB")
check(ChatProbeDB.ids.on, "10 the trace state is saved")
local ns2 = {}
assert(loadfile("Tools/ChatProbe/ChatProbe.lua"))("ChatProbe", ns2)   -- the reload
WoW.fire("ADDON_LOADED", "ChatProbe")
check(logHas("10 line-identity trace resumed after the reload"), "10 the trace resumes after a reload")
T10 = ns2._test
line("CHAT_MSG_YELL", "after reload", "Kaleid Sumner", 202, "Player-1-AB")
SlashCmdList.CHATPROBE("lines")
check(logHas("10 CHAT_MSG_YELL: 2 lines"), "10 the report counts lines from both sides of the reload")
check(not ChatProbeDB.ids.on, "10 and the trace is off after the report")

-- 11: the server ignore test on the target: added as "First Surname", read
-- back, checked by GUID, removed again; only the target's entry is logged.
SlashCmdList.CHATPROBE("ignoretest")
check(logHas("11 target another player first"), "11 needs a target")
target = { "Kaleid", "Sumner", "Kaleid" }   -- GetUnitName without the surname, as on Forever
SlashCmdList.CHATPROBE("ignoretest")
check(logHas("AddIgnore(Kaleid Sumner) ok=true"), "11 adds the 'First Surname' form")
T10.blockWatch._scripts.OnEvent(T10.blockWatch, "IGNORELIST_UPDATE")
check(logHas("exact entry Kaleid Sumner present = true"), "11 reads the entry back")
check(logHas("IsIgnoredByGuid(target) = true"), "11 checks it by GUID")
check(logHas("DelIgnore(Kaleid Sumner) ok=true returned=true"), "11 removes it again")
eq(#ignoreList, 1, "11 the ignore list is as it was")
check(not logHas("Old Grudge"), "11 the rest of the ignore list is never logged")

-- 11 never touches an ignore the player already has, and allows one test
-- at a time (Codex, #16).
ignoreList = { "Old Grudge", "Kaleid Sumner" }
ignoredGuids[targetGuid] = true
SlashCmdList.CHATPROBE("ignoretest")
check(logHas("11 your target is already on your ignore list"), "11 an already-ignored target is left alone")
eq(#ignoreList, 2, "11 and the player's own entry stays")
ignoreList, ignoredGuids = { "Old Grudge" }, {}
rawset(_G, "C_FriendList", setmetatable({ AddIgnore = function() return false end }, { __index = C_FriendList }))
SlashCmdList.CHATPROBE("ignoretest")
check(logHas("11 not added, so nothing to clean up"), "11 a refused add schedules no removal")
check(T10.P.ignoreTest == nil, "11 nothing pending after a refused add")
rawset(_G, "C_FriendList", getmetatable(C_FriendList).__index)
SlashCmdList.CHATPROBE("ignoretest")
SlashCmdList.CHATPROBE("ignoretest")
check(logHas("11 an ignore test is still waiting"), "11 a second test is refused while one is pending")
T10.blockWatch._scripts.OnEvent(T10.blockWatch, "IGNORELIST_UPDATE")
eq(#ignoreList, 1, "11 the pending test cleaned up its own entry only")
-- No other name from the list is logged, not even one sharing the first name.
ignoreList = { "Kaleid Other" }
SlashCmdList.CHATPROBE("ignoretest")
T10.blockWatch._scripts.OnEvent(T10.blockWatch, "IGNORELIST_UPDATE")
check(not logHas("Kaleid Other"), "11 a similar name on the list is never logged")

-- 12: CHAT_MSG_IGNORED's sender is arg2, not its text.
T10.blockWatch._scripts.OnEvent(T10.blockWatch, "CHAT_MSG_IGNORED", "this is a long text", "Karuzo Elegia")
check(logHas("12 CHAT_MSG_IGNORED (from words=2 dash=false)"), "12 CHAT_MSG_IGNORED's sender comes from arg2")

-- 12: invites and duels that arrive are logged by sender shape.
T10.blockWatch._scripts.OnEvent(T10.blockWatch, "PARTY_INVITE_REQUEST", "Ignored Alt")
check(logHas("12 PARTY_INVITE_REQUEST (from words=2 dash=false)"), "12 an arriving invite is logged without the name")

done("test_probe")
