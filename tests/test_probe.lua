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
rawset(_G, "Constants", { ChatFrameConstants = { MaxChatWindows = 2 } })
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
    return f
end
chatFrame("ChatFrame1", { "hello there", secretLine, "a much longer line of text" })
chatFrame("ChatFrame2", {})

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

SlashCmdList.CHATPROBE("watch")
check(not ChatProbe_test.watcher:IsEventRegistered("CHAT_MSG_SAY"), "5 watch toggles off")
SlashCmdList.CHATPROBE("clear")
eq(#ChatProbeDB.log, 1, "clear empties the log (leaving its own line)")

done("test_probe")
