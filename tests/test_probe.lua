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
-- No "Probe" tab yet on this character (item 8 opens one; item 9 reuses it).
local windowNames = {}
rawset(_G, "GetChatWindowInfo", function(i) return windowNames[i] or "General" end)

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
    -- A real buffer for item 9: AddMessage appends, the predicate removes.
    f._lines = {}
    rawset(f, "AddMessage", function(self, msg) table.insert(self._lines, msg) end)
    rawset(f, "RemoveMessagesByPredicate", function(self, pred)
        local keep = {}
        for _, m in ipairs(self._lines) do if not pred(m) then keep[#keep + 1] = m end end
        self._lines = keep
    end)
    return f
end
chatFrame("ChatFrame1", { "hello there", secretLine, "a much longer line of text" })
chatFrame("ChatFrame2", {})
chatFrame("ChatFrame3", {})   -- the tab item 8 "opens"

ChatProbeDB = nil
assert(loadfile("Tools/ChatProbe/ChatProbe.lua"))("ChatProbe", {})
WoW.fire("ADDON_LOADED", "ChatProbe")
eq(type(ChatProbeDB.log), "table", "the probe keeps its log in saved variables")
eq(ChatProbeDB.loads, 1, "it counts its loads (persistence check)")

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
check(handler == ChatProbe_test.printHandler, "7 installs its print handler")
stack = via("ASProbe/ASProbe.lua")
handler("ASProbe", "line one")
handler("ASProbe", "line two")
eq(passedOn[#passedOn], "ASProbe line two", "7 passes print lines on to the original handler")
-- A direct AddMessage with no chat event counts as direct; one carrying an
-- event (Blizzard's chat handler) or inside print does not.
stack = via("OtherAddon/Other.lua")
ChatFrame1:AddMessage("direct", 1, 1, 1, nil, nil, nil, nil)
ChatFrame1:AddMessage("said", 1, 1, 1, 1, nil, 1, "CHAT_MSG_SAY")
SlashCmdList.CHATPROBE("sources")
check(logHas("7 print from ASProbe = 2"), "7 counts print lines per source addon")
check(logHas("7 AddMessage (no chat event) from OtherAddon = 1"), "7 counts direct AddMessage lines per addon")

-- 8: a new empty tab gets ChatProbe's own lines; other addons' don't move.
local routed = {}
local tab = ChatFrame3
rawset(tab, "AddMessage", function(_, msg) routed[#routed + 1] = msg end)
tab.messageTypeList = {}
rawset(_G, "FCF_OpenNewWindow", function(name, noDefault) tab._tabName, tab._noDefault = name, noDefault; return tab end)
SlashCmdList.CHATPROBE("route")
check(tab._tabName == "Probe" and tab._noDefault == true, "8 opens an empty 'Probe' tab")
local before = #passedOn
stack = via("ChatProbe/ChatProbe.lua")
handler("ChatProbe", "mine")
eq(routed[#routed], "ChatProbe mine", "8 routes ChatProbe's lines to the tab")
stack = via("ASProbe/ASProbe.lua")
handler("ASProbe", "theirs")
eq(#passedOn, before + 1, "8 leaves other addons' lines in the main chat")
SlashCmdList.CHATPROBE("route")
stack = via("ChatProbe/ChatProbe.lua")
handler("ChatProbe", "back")
eq(passedOn[#passedOn], "ChatProbe back", "8 routing off returns lines to the main chat")

-- 9: an addon's direct AddMessage lines move to the existing Probe tab:
-- copied there, removed from General (one copy only), others untouched.
windowNames[3] = "Probe"
local opened = 0
rawset(_G, "FCF_OpenNewWindow", function() opened = opened + 1; return tab end)
routed = {}
SlashCmdList.CHATPROBE("move AltStableProbe")
eq(opened, 0, "9 reuses the character's existing Probe tab")
ChatFrame1._lines = { "old line", "[ASProbe] dup" }
stack = via("AltStableProbe/Probe.lua")
ChatFrame1:AddMessage("[ASProbe] dup", 1, 1, 1)
ChatFrame1:AddMessage("[ASProbe] two", 1, 1, 1)
stack = via("OtherAddon/Other.lua")
ChatFrame1:AddMessage("other line", 1, 1, 1)
eq(table.concat(routed, ","), "[ASProbe] dup,[ASProbe] two", "9 copies the addon's lines to the tab")
eq(table.concat(ChatFrame1._lines, ","), "old line,[ASProbe] dup,other line",
    "9 removes one copy per moved line from General and leaves the rest")
SlashCmdList.CHATPROBE("move")
check(logHas("9 moving off: 2 lines moved from AltStableProbe, 0 copied but not removed"), "9 reports the counts")
stack = via("AltStableProbe/Probe.lua")
ChatFrame1:AddMessage("[ASProbe] after", 1, 1, 1)
eq(#routed, 2, "9 off: lines stay where they were added")

SlashCmdList.CHATPROBE("watch")
check(not ChatProbe_test.watcher:IsEventRegistered("CHAT_MSG_SAY"), "5 watch toggles off")
SlashCmdList.CHATPROBE("clear")
eq(#ChatProbeDB.log, 1, "clear empties the log (leaving its own line)")

done("test_probe")
