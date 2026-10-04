-- M4 focus mode: the frozen snapshot, kinds, the source filter, search with
-- and without context, new lines, export, the magnifier.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function frame(path, line) return "[" .. path .. "]:" .. line .. ": in function <" .. path .. ":" .. (line - 2) .. ">" end
local function by(addon)
    return table.concat({ frame("Interface/AddOns/GlassChat/Tabs.lua", 60), "(tail call): ?", "[C]: in function `pcall'",
        frame("Interface/AddOns/GlassChat/Chat.lua", 200), frame("Interface/AddOns/" .. addon .. "/Core.lua", 9) }, "\n")
end

local GC = loadAddon()
local Focus = GC.Focus
local main = ChatFrame1
main._lines = {}

local function chat(text, event) main:AddMessage(text, 1, 1, 1, 1, nil, 1, event) end
local function addon(name, text) WoW.stack = by(name); main:AddMessage(text, 1, 1, 1); WoW.stack = nil end

chat("[Bob]: hello there", "CHAT_MSG_SAY")
chat("[Guildie]: raid at 8", "CHAT_MSG_GUILD")
chat("[1. General] [Ann]: |cffa335ee|Hitem:19019|h[Thunderfury]|h|r anyone?", "CHAT_MSG_CHANNEL")
main:AddMessage("You receive loot: [Linen Cloth].", 0, 0.67, 0, 23)   -- as Blizzard adds it: info.id, no event
addon("ASProbe", "[ASProbe] scan 1: 12 bags")
addon("ASProbe", "[ASProbe] scan 2: 13 bags")
addon("OtherAddon", "Other says hi")
chat("[Bob]: bags are full", "CHAT_MSG_SAY")
main._lines[#main._lines + 1] = { m = WoW.Secret("secret line"), extra = { n = 0 } }

-- Kinds, sources, plain text.
local snap = Focus.Snapshot(main)
eq(#snap, 9, "a snapshot of every line")
eq(snap[1].kind, "Say", "SAY is Say")
eq(snap[2].kind, "Guild", "GUILD is Guild")
eq(snap[3].kind, "Channel", "CHANNEL is Channel")
eq(snap[3].text, "[1. General] [Ann]: [Thunderfury] anyone?", "plain text: colours and links out, the link's text kept")
eq(snap[4].kind, "System", "a Blizzard line with no event but a chat-type id is System, not Addons")
eq(snap[5].kind, "Addons", "no event: Addons")
eq(snap[5].source, "ASProbe", "with the addon that wrote it")
eq(snap[7].source, "OtherAddon", "each its own")
check(snap[9].hidden and snap[9].text == GC.Copy.HIDDEN, "a secret line is hidden")

-- Filters.
local function texts(list) local o = {} for i, e in ipairs(list) do o[i] = e.text end return table.concat(o, "|") end
eq(#Focus.Filter(snap, {}, nil, "", false), 9, "no filter: everything")
eq(texts(Focus.Filter(snap, { Say = true }, nil, "", false)), "[Bob]: hello there|[Bob]: bags are full", "a kind")
eq(#Focus.Filter(snap, { Say = true, Guild = true }, nil, "", false), 3, "two kinds")
eq(texts(Focus.Filter(snap, {}, "ASProbe", "", false)), "[ASProbe] scan 1: 12 bags|[ASProbe] scan 2: 13 bags", "one addon")
eq(texts(Focus.Filter(snap, {}, nil, "BAGS", false)), "[ASProbe] scan 1: 12 bags|[ASProbe] scan 2: 13 bags|[Bob]: bags are full",
    "search: plain, any case")
eq(#Focus.Filter(snap, {}, nil, "[", false), 7, "no patterns: [ is a character")
eq(#Focus.Filter(snap, {}, nil, "hidden", false), 0, "a secret line is never matched, not even by its placeholder")
local ctx = Focus.Filter(snap, {}, nil, "loot", true)
eq(texts(ctx), table.concat({ snap[2].text, snap[3].text, snap[4].text, snap[5].text, snap[6].text }, "|"),
    "with context: two lines either side")

-- The window: opened on the window in view, with a search.
SlashCmdList.GLASSCHAT("focus Bags")
local win = Focus._test.window()
check(win:IsShown(), "/gchat focus opens it")
eq(win.search:GetText(), "Bags", "with the search, as typed")
eq(win.edit:GetText(), "[ASProbe] scan 1: 12 bags\n[ASProbe] scan 2: 13 bags\n[Bob]: bags are full", "showing the matches")
check(win.status:GetText():find("^3 of 9 lines"), "and how many")
win.search:SetText(""); WoW.flushTimers()
win.chips.Say._scripts.OnClick(win.chips.Say)
eq(win.edit:GetText(), "[Bob]: hello there\n[Bob]: bags are full", "a kind chip filters")
eq(win.chips.Guild:GetAlpha(), 0.4, "unselected chips are dimmed")
win.chips.Say._scripts.OnClick(win.chips.Say)
eq(win.chips.Guild:GetAlpha(), 1, "none selected: all bright again")
win.from._scripts.OnClick(win.from)
eq(win.from:GetText(), "From: ASProbe", "From cycles through the addons in view")
eq(win.edit:GetText(), "[ASProbe] scan 1: 12 bags\n[ASProbe] scan 2: 13 bags", "and filters on it")
win.from._scripts.OnClick(win.from)
eq(win.from:GetText(), "From: OtherAddon", "the next")
win.from._scripts.OnClick(win.from)
eq(win.from:GetText(), "From: any", "and back to any")

-- Frozen: new lines don't change the view until asked.
chat("[Bob]: a newer line", "CHAT_MSG_SAY")
chat("[Bob]: and another", "CHAT_MSG_SAY")
win._scripts.OnUpdate(win, 1)
check(not win.edit:GetText():find("newer line"), "the view is frozen")
check(win.newer:IsShown() and win.newer:GetText() == "2 new lines", "a button says how many arrived")
win.newer._scripts.OnClick(win.newer)
check(win.edit:GetText():find("and another"), "clicking it takes them in")
check(not win.newer:IsShown(), "and hides it")

-- Typing: one rebuild after the pause, not one per keystroke.
local sets, realSet = 0, win.edit.SetText
win.edit.SetText = function(self, t) sets = sets + 1; return realSet(self, t) end
for _, t in ipairs({ "b", "ba", "bag", "bags" }) do win.search:SetText(t) end
eq(sets, 0, "no rebuild while typing")
WoW.flushTimers()
eq(sets, 1, "one rebuild after the pause")
win.edit.SetText = nil
win.search:SetText(""); WoW.flushTimers()

-- Select all, then a new view: the hint no longer says "Selected".
win.select._scripts.OnClick(win.select)
check(win.hint:GetText():find("^Selected"), "Select all says it's selected")
win.chips.Say._scripts.OnClick(win.chips.Say)
check(not win.hint:GetText():find("^Selected"), "a new view clears that")
win.chips.Say._scripts.OnClick(win.chips.Say)

-- Read-only: typing puts the text back.
local before = win.edit:GetText()
win.edit._text = "typed over"
win.edit._scripts.OnTextChanged(win.edit, true)
eq(win.edit:GetText(), before, "the view is read-only")

-- Export: the filtered view, plain lines, no secrets.
win.search:SetText("bags"); WoW.flushTimers()
win.export._scripts.OnClick(win.export)
local ex = GC.db.export
eq(#ex.lines, 3, "export writes the lines shown")
eq(ex.search, "bags", "with the search")
eq(ex.kinds, "all", "and the filters")
for _, l in ipairs(ex.lines) do check(type(l) == "string", "plain strings only") end
win.search:SetText(""); WoW.flushTimers()
win.export._scripts.OnClick(win.export)
for _, l in ipairs(GC.db.export.lines) do check(l ~= GC.Copy.HIDDEN, "a hidden line is never exported") end

-- With timestamps on, addon lines keep their writer (review of #28).
SlashCmdList.GLASSCHAT("stamps on")
addon("ASProbe", "[ASProbe] scan 3: stamped")
SlashCmdList.GLASSCHAT("stamps off")
local snap2 = Focus.Snapshot(main)
local last = snap2[#snap2]
check(last.text:find("^%[%d%d:%d%d:%d%d%] %[ASProbe%] scan 3"), "the line is stamped")
eq(last.source, "ASProbe", "and still credited to ASProbe")

-- A line moved to its own tab isn't a new line in this window.
win.newer._scripts.OnClick(win.newer)
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:tabs:session:Mover")
function FCF_OpenNewWindow(name) WoW.window(5).name, WoW.window(5).shown, WoW.window(5).docked = name, true, 5
    WoW.makeChatFrames(5); return ChatFrame5 end
addon("Mover", "moved away")
win._scripts.OnUpdate(win, 1)
check(not win.newer:IsShown(), "a line routed to its tab doesn't count as new here")

-- The chat behind it is untouched.
eq(#main._lines, 12, "the chat window still has every line (the moved one gone)")

-- The magnifier, left of the copy icon; the tabs leave room for both.
local b = Focus._test.buttons[ChatFrame1]
check(b, "a magnifier on the tab strip")
eq(select(4, b:GetPoint(1)), -14 - GC.Skin.STRIP_ICON_STEP, "left of the copy icon")
eq(GC.Skin.DOCK_RESERVE, 30 + 2 * GC.Skin.STRIP_ICON_STEP, "the tabs leave room for both icons")
win:Hide()
b._scripts.OnClick(b)
check(win:IsShown(), "clicking it opens focus mode")

eq(next(GC.failures), nil, "nothing failed")
done("test_focus")
