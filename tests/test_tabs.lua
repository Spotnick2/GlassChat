-- M3 smart tabs: who wrote a line, the offer, moving lines to the addon's
-- tab (session, always, never), and their limits.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- A new tab: the first unused window, named, shown and docked; its frame made.
local opened = 0
WoW.noRoom = false
function FCF_OpenNewWindow(name, noDefaultChannels)
    if WoW.noRoom then return nil end
    for i = 4, 10 do
        local w = WoW.window(i)
        if w.name == "" then
            opened = opened + 1
            w.name, w.shown, w.docked = name, true, i
            WoW.makeChatFrames(i)
            local f = _G["ChatFrame" .. i]
            -- As the client does (FloatingChatFrame.lua:847-849): select it, make its box active.
            FCFDock_SelectWindow(GENERAL_CHAT_DOCK, f)
            ChatFrameUtil.SetLastActiveWindow(f.editBox or f)
            return f
        end
    end
end

-- Stacks as the client prints them (FOREVER-PROBE 7): our hook first, then
-- the plumbing, then the writer; a frame line names its file twice.
local function frame(path, line) return "[" .. path .. "]:" .. line .. ": in function <" .. path .. ":" .. (line - 2) .. ">" end
local OURS = { frame("Interface/AddOns/GlassChat/Tabs.lua", 60) .. "\n(tail call): ?\n[C]: in function `pcall'",
    frame("Interface/AddOns/GlassChat/Chat.lua", 200) }
local function direct(addon)
    return table.concat({ OURS[1], OURS[2], frame("Interface/AddOns/Blizzard_SharedXML/ScrollingMessageFrame.lua", 12),
        frame("Interface/AddOns/" .. addon .. "/Probe.lua", 40), "[C]: ?" }, "\n")
end
local function printed(addon)
    return table.concat({ OURS[1], OURS[2], frame("Interface/AddOns/Blizzard_PrintHandler/PrintHandler.lua", 9),
        "[C]: in function `print'", frame("Interface/AddOns/" .. addon .. "/Core.lua", 77), "[C]: ?" }, "\n")
end

WoW.now = 1000
local GC = loadAddon({ db = { devMode = false } })   -- developer mode has its own section below
local Tabs = GC.Tabs
local main = ChatFrame1

local function emit(stack, text, f, ...)
    WoW.stack = stack
    ;(f or main):AddMessage(text, 1, 1, 1, ...)
    WoW.stack = nil
end
-- Chat said since the last newChat() (chatHas scans everything).
local mark = 0
local realNew = newChat
newChat = function() mark = #WoW.chat; return realNew() end
local function chatHas(p)
    for i = mark + 1, #WoW.chat do if WoW.chat[i]:find(p) then return true end end
    return false
end
local function lines(f)
    local out = {}
    for _, e in ipairs(f._lines or {}) do out[#out + 1] = e.m end
    return out
end
local function has(f, text)
    for _, m in ipairs(lines(f)) do if m == text then return true end end
    return false
end

-- Who wrote it.
WoW.stack = direct("AltStableProbe")
eq(Tabs.SourceOf(), "AltStableProbe", "a direct AddMessage names its addon")
WoW.stack = printed("ASProbe")
eq(Tabs.SourceOf(), "ASProbe", "print names its caller, past Blizzard's print handler")
WoW.stack = table.concat({ OURS[1], OURS[2], frame("Interface/AddOns/Blizzard_ChatFrameBase/ChatFrame.lua", 300) }, "\n")
eq(Tabs.SourceOf(), "Blizzard", "only Blizzard's code: Blizzard")
WoW.stack = table.concat({ OURS[1], OURS[2], frame("Interface/AddOns/GlassChatSpamIgnore/UI.lua", 9) }, "\n")
eq(Tabs.SourceOf(), "GlassChatSpamIgnore", "our plugin, past our own leading frames")
WoW.stack = table.concat({ OURS[1], OURS[2], frame("Interface/AddOns/Ace3/AceConsole-3.0/AceConsole-3.0.lua", 50),
    frame("Interface/AddOns/RealAddon/Core.lua", 9) }, "\n")
eq(Tabs.SourceOf(), "RealAddon", "a standalone library isn't the writer: the addon that called it is")
WoW.stack = nil

-- Chatty: 20 lines within a minute brings one offer.
newChat()
for i = 1, Tabs.CHATTY - 1 do emit(direct("ASProbe"), "probe line " .. i); WoW.now = WoW.now + 1 end
check(not chatHas("printed 20 lines"), "19 lines: no offer yet")
emit(direct("ASProbe"), "probe line 20")
check(chatHas("ASProbe printed 20 lines in a minute"), "the 20th line in a minute brings the offer")
check(chatHas("|Haddon:GlassChat:tabs:session:ASProbe|h") and chatHas("|Haddon:GlassChat:tabs:always:ASProbe|h")
    and chatHas("|Haddon:GlassChat:tabs:never:ASProbe|h"), "with its three links")
newChat()
for i = 1, 30 do emit(direct("ASProbe"), "more " .. i) end
check(not chatHas("printed 20 lines"), "and only once a session")
check(has(main, "more 30"), "unrouted lines stay where they were")

-- Slow writers, Blizzard, our own addons and chat-event lines are never offered.
newChat()
for i = 1, 40 do emit(direct("SlowAddon"), "slow " .. i); WoW.now = WoW.now + 4 end
for i = 1, 40 do emit(direct("GlassChatSpamIgnore"), "ours " .. i) end
for i = 1, 40 do emit(table.concat({ OURS[1], OURS[2], frame("Interface/AddOns/Blizzard_ChatFrameBase/ChatFrame.lua", 300) }, "\n"), "sys " .. i) end
for i = 1, 40 do emit(direct("ChattyChat"), "[Bob]: hi " .. i, main, 1, nil, 1, "CHAT_MSG_SAY") end
check(not chatHas("printed 20 lines"), "no offer for a slow addon, Blizzard, GlassChat's own or chat-event lines")

-- This session: the next lines move to a new "ASProbe" tab.
emit(direct("ASProbe"), "same text")   -- an identical older line, before routing
emit(direct("OtherAddon"), "between")
GENERAL_CHAT_DOCK._selected, WoW.lastActive = main, "main box"
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:tabs:session:ASProbe")
-- While the player is typing, no tab is created (it would clear their draft).
WoW.activeBox = "main box"
emit(direct("ASProbe"), "while typing")
eq(opened, 0, "no new tab while the player is typing")
check(has(main, "while typing"), "the line stays in the main chat")
eq(WoW.lastActive, "main box", "and the active edit box isn't touched")
WoW.activeBox = nil
emit(direct("ASProbe"), "same text")
local tab = ChatFrame4
eq(opened, 1, "one tab opened")
eq(FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK), main, "the player's selected tab is put back")
eq(WoW.lastActive, "main box", "and their active edit box")
eq(WoW.window(4).name, "ASProbe", "named after the addon")
check(has(tab, "same text"), "the line is in its tab")
local n = 0
for _, m in ipairs(lines(main)) do if m == "same text" then n = n + 1 end end
eq(n, 1, "and removed from the main chat, the older identical line kept")
eq(main._lines[#main._lines].m, "while typing", "the one removed is the newest (the older one sits before the lines after it)")
emit(printed("ASProbe"), "via print")
check(has(tab, "via print") and not has(main, "via print"), "print lines move too")
eq(opened, 1, "the same tab is reused")
emit(direct("OtherAddon"), "not routed")
check(has(main, "not routed"), "other addons stay in the main chat")
emit(direct("ASProbe"), WoW.Secret("secret"))
eq(next(GC.failures), nil, "a secret line is left alone")

-- The tab closed by the player: back to the main chat for the session.
WoW.window(4).shown, WoW.window(4).docked = false, nil
newChat()
emit(direct("ASProbe"), "after close")
check(has(main, "after close"), "a closed tab: the line stays in the main chat")
check(chatHas("tab was closed"), "and that's said once")
newChat()
emit(direct("ASProbe"), "after close 2")
check(not chatHas("tab was closed"), "only once")

-- Always: saved, and the next session reuses the window of that name.
WoW.window(4).shown, WoW.window(4).docked = true, 4
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:tabs:always:ASProbe")
eq(GC.db.routes.ASProbe, true, "Always is saved account-wide")
Tabs._test.reset()   -- a new session
emit(direct("ASProbe"), "next session")
check(has(tab, "next session"), "next session: routed again")
eq(opened, 1, "into the existing ASProbe window, not a new one")

-- No room for another tab: the lines stay.
WoW.noRoom = true
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:tabs:session:Crowded")
newChat()
emit(direct("Crowded"), "crowded line")
check(has(main, "crowded line") and chatHas("no room for another chat tab"), "no room: the line stays, and that's said")
WoW.noRoom = false

-- The combat log is never walked.
local walked = 0
local realSource = Tabs.SourceOf
Tabs.SourceOf = function() walked = walked + 1; return realSource() end
COMBATLOG = ChatFrame2
for i = 1, 5 do emit(direct("ASProbe"), "combat " .. i, ChatFrame2) end
eq(walked, 0, "no stack walk for combat log lines")
Tabs.SourceOf, COMBATLOG = realSource, nil

-- An error opening a tab is recorded, not reported as "no room".
local realOpen = FCF_OpenNewWindow
FCF_OpenNewWindow = function() error("boom") end
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:tabs:session:Broken")
newChat()
emit(direct("Broken"), "broken line")
check(GC.failures["tab open"] ~= nil, "an error opening a tab goes to /gchat failures")
check(not chatHas("no room"), "and isn't called no room")
GC.failures["tab open"] = nil
FCF_OpenNewWindow = realOpen

-- No after a tab rule: the rule goes too.
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:tabs:session:Flipper")
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:tabs:never:Flipper")
check(not Tabs.IsRouted("Flipper"), "No after Own tab: no longer routed")

-- Never: not asked again; /gchat tabs lists and forgets.
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:tabs:never:Spammy")
eq(GC.db.routeNever.Spammy, true, "No is saved")
newChat()
for i = 1, 30 do emit(direct("Spammy"), "s " .. i) end
check(not chatHas("Spammy printed"), "and Spammy isn't offered")
newChat()
SlashCmdList.GLASSCHAT("tabs")
check(chatHas("own tab, always: ASProbe") and chatHas("never asked: Spammy"), "/gchat tabs lists the rules")
SlashCmdList.GLASSCHAT("tabs Forget asprobe")
check(GC.db.routes.ASProbe == nil, "/gchat tabs forget drops the rule, in any case")
emit(direct("ASProbe"), "forgotten")
check(has(main, "forgotten"), "and its lines stay in the main chat again")

-- Timestamps: a moved line is stamped in its tab, once.
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:tabs:session:ASProbe")
SlashCmdList.GLASSCHAT("stamps on")
emit(direct("ASProbe"), "stamped move")
local last = tab._lines[#tab._lines].m
check(last:find("^%[%d%d:%d%d:%d%d%] stamped move$"), "a moved line is stamped in its tab")
check(not has(main, "stamped move"), "and gone from the main chat")
SlashCmdList.GLASSCHAT("stamps off")

-- Who wrote a line is remembered in two generations: a full one becomes the
-- previous one, still answered from, and older ones are forgotten.
local cap = Tabs.SOURCE_CAP
Tabs.SOURCE_CAP = 3
SlashCmdList.GLASSCHAT("tabs forget ASProbe")
for i = 1, 5 do emit(direct("GenAddon"), "gen " .. i) end
eq(Tabs.SourceFor("gen 2"), "GenAddon", "a line in the previous generation is still known")
eq(Tabs.SourceFor("gen 5"), "GenAddon", "and the newest")
for i = 6, 9 do emit(direct("GenAddon"), "gen " .. i) end
eq(Tabs.SourceFor("gen 1"), nil, "two generations back is forgotten")
Tabs.SOURCE_CAP = cap

-- #35: an addon's coloured prefix becomes a link; right-click it for a tab.
SlashCmdList.GLASSCHAT("tabs forget AltStable")
emit(direct("AltStable"), "|cff33bbff[AltStable]|r Sync with Karuzo Memphisto complete.")
local line = main._lines[#main._lines].m
eq(line, "|cff33bbff|Haddon:GlassChat:src:AltStable|h[AltStable]|h|r Sync with Karuzo Memphisto complete.",
    "the prefix is a link, its colour and text kept")
eq(GC.Copy.Plain(line), "[AltStable] Sync with Karuzo Memphisto complete.", "copied text is unchanged")
emit(direct("RestedXP"), "RestedXP Guides: Targeting macro updated")
eq(main._lines[#main._lines].m, "RestedXP Guides: Targeting macro updated", "a line without a coloured prefix: no link")
emit(table.concat({ OURS[1], OURS[2], frame("Interface/AddOns/Blizzard_ChatFrameBase/ChatFrame.lua", 300) }, string.char(10)),
    "|cffffff00Looting set to Free for All.|r")
eq(main._lines[#main._lines].m, "|cffffff00Looting set to Free for All.|r", "never Blizzard's own lines")
emit(direct("AltStable"), "|cff33bbff[AltStable]|r one")
COMBATLOG = ChatFrame2
emit(direct("AltStable"), "|cff00ff00[Combat]|r hit", ChatFrame2)
eq(ChatFrame2._lines[#ChatFrame2._lines].m, "|cff00ff00[Combat]|r hit", "a combat log line never gets the previous line's link")
COMBATLOG = nil
emit(direct("AltStable"), "|cffa335ee|Hitem:1|h[Sword]|h|r for sale")
eq(main._lines[#main._lines].m, "|cffa335ee|Hitem:1|h[Sword]|h|r for sale", "a prefix that is already a link isn't wrapped again")
SlashCmdList.GLASSCHAT("stamps on")
emit(direct("AltStable"), "|cff33bbff[AltStable]|r stamped too")
check(main._lines[#main._lines].m:find("^%[%d%d:%d%d:%d%d%] |cff33bbff|Haddon:GlassChat:src:AltStable|h"),
    "with timestamps on: stamp, then the linked prefix, in one rewrite")
SlashCmdList.GLASSCHAT("stamps off")

WoW.menu = nil
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:src:AltStable", "[AltStable]", "LeftButton")
eq(WoW.menu, nil, "a left-click opens nothing")
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:src:AltStable", "[AltStable]", "RightButton")
check(WoW.menu and WoW.menu.title == "AltStable", "a right-click opens its menu")
eq(#WoW.menu.buttons, 2, "two choices while it has no tab")
WoW.menu.buttons[1].fn()
check(Tabs.IsRouted("AltStable"), "'Own tab for this session' routes it")
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:src:AltStable", "[AltStable]", "RightButton")
eq(WoW.menu.buttons[#WoW.menu.buttons].text, "Back to the main chat", "now it offers the way back")
WoW.menu.buttons[#WoW.menu.buttons].fn()
check(not Tabs.IsRouted("AltStable"), "which drops the rule")
SlashCmdList.GLASSCHAT("tabs route RestedXP always")
eq(GC.db.routes.RestedXP, true, "/gchat tabs route <Addon> always: the same without the mouse")
SlashCmdList.GLASSCHAT("tabs forget RestedXP")

-- Developer mode: probes by name, and any addon asking (owner: "we could do both").
GC.db.devMode = true
Tabs._test.reset()
newChat()
emit(direct("GlassProbe"), "probe says hi")
check(Tabs.IsRouted("GlassProbe") and chatHas("developer mode: GlassProbe"), "dev mode: a *Probe addon gets its tab at once")
emit(direct("NormalAddon"), "hello")
check(not Tabs.IsRouted("NormalAddon"), "an addon not named *Probe isn't")
SlashCmdList.GLASSCHAT("tabs forget GlassProbe")
emit(direct("GlassProbe"), "probe again")
check(not Tabs.IsRouted("GlassProbe"), "and once forgotten, stays in the main chat this session")
check(GC.RequestTab("MyTool"), "an addon can ask for its tab: granted in dev mode")
check(Tabs.IsRouted("MyTool"), "and routed")
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:tabs:never:Pushy")
check(not GC.RequestTab("Pushy"), "a player's No wins over a request")
check(not GC.RequestTab("GlassChatSpamIgnore"), "never for GlassChat's own")
GC.db.devMode = false
Tabs._test.reset()
newChat()
check(not GC.RequestTab("OtherTool"), "outside dev mode a request isn't granted")
check(chatHas("OtherTool asks for its own chat tab") and chatHas("|Haddon:GlassChat:tabs:session:OtherTool|h"),
    "the player is offered the tab instead, saying why")
emit(direct("GlassProbe"), "not dev")
check(not Tabs.IsRouted("GlassProbe"), "and probe names aren't special")

-- Review of #36. Here print reaches the chat as in the client (Blizzard's
-- print handler calls DEFAULT_CHAT_FRAME:AddMessage), so GlassChat's own
-- notices go through the line hook too, with GlassChat's stack.
local stubPrint = print
print = function(...)
    stubPrint(...)
    local outer = WoW.stack
    WoW.stack = table.concat({ OURS[1], OURS[2], frame("Interface/AddOns/Blizzard_PrintHandler/PrintHandler.lua", 9),
        frame("Interface/AddOns/GlassChat/Compat.lua", 18) }, string.char(10))
    ChatFrame1:AddMessage(table.concat({ ... }, " "), 1, 1, 1)
    WoW.stack = outer
end
-- A notice printed while handling a line doesn't cost that line its link.
GC.db.devMode = true
Tabs._test.reset()
emit(direct("ChatProbe"), "|cff33ff99ChatProbe|r 12 ignores at login")
local probeTab
for i = 4, 10 do if WoW.window(i).name == "ChatProbe" then probeTab = _G["ChatFrame" .. i] end end
check(probeTab and probeTab._lines[#probeTab._lines].m:find("|Haddon:GlassChat:src:ChatProbe|h", 1, true),
    "the probe's first line, moved with a dev-mode notice, keeps its right-clickable name")
local inMain = false
for _, e in ipairs(main._lines) do
    if type(e.m) == "string" and e.m:find("12 ignores at login", 1, true) then inMain = true end
end
check(not inMain, "and it's only in its tab, not left in the main chat too (Codex, #36)")
-- After "Back to the main chat", the probe's next request doesn't undo it.
Tabs.SetRule("ChatProbe", "main")
check(not GC.RequestTab("ChatProbe"), "a request after Back to the main chat isn't granted")
check(not Tabs.IsRouted("ChatProbe"), "and the choice stands")
-- A closed tab: the menu offers it again, the request says no.
Tabs.SetRule("AltStable", "session")
emit(direct("AltStable"), "x")
for i = 4, 10 do if WoW.window(i).name == "AltStable" then WoW.window(i).shown, WoW.window(i).docked = false, nil end end
emit(direct("AltStable"), "|cff33bbff[AltStable]|r after close")
local afterClose
for _, e in ipairs(main._lines) do if type(e.m) == "string" and e.m:find("after close", 1, true) then afterClose = e.m end end
check(afterClose and afterClose:find("|Haddon:GlassChat:src:AltStable|h", 1, true), "the line that brings the tab-closed notice keeps its link")
check(not GC.RequestTab("AltStable"), "a request for a closed tab says no")
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:src:AltStable", "[AltStable]", "RightButton")
eq(WoW.menu.buttons[1].text, "Own tab for this session", "the menu offers the tab again after it was closed")
for _, b in ipairs(WoW.menu.buttons) do check(b.text ~= "Back to the main chat", "and not the way back: " .. b.text) end
-- Codex review of #36, round 2.
-- A probe with a SAVED rule, forgotten, stays in the main chat.
GC.db.routes.ChatProbe = true
Tabs._test.reset()
emit(direct("ChatProbe"), "|cff33ff99ChatProbe|r saved rule")
SlashCmdList.GLASSCHAT("tabs forget ChatProbe")
emit(direct("ChatProbe"), "|cff33ff99ChatProbe|r after forget")
check(not Tabs.IsRouted("ChatProbe"), "forgetting a saved probe rule isn't undone by developer mode")
-- Always, then session only: the saved rule goes.
Tabs.SetRule("Keeper", "always")
Tabs.SetRule("Keeper", "session")
eq(GC.db.routes.Keeper, nil, "choosing this session only drops a saved Always")
Tabs._test.reset()
check(not Tabs.IsRouted("Keeper"), "so the next session doesn't route it")
-- A permanent tab closed, then a right-click before any new line: reopen offered.
Tabs.SetRule("Shut", "always")
emit(direct("Shut"), "|cffaaaaff[Shut]|r one")
for i = 4, 10 do if WoW.window(i).name == "Shut" then WoW.window(i).shown, WoW.window(i).docked = false, nil end end
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:src:Shut", "[Shut]", "RightButton")
eq(WoW.menu.buttons[1].text, "Own tab for this session", "right after closing it, the menu offers the tab again")
WoW.menu.buttons[1].fn()
emit(direct("Shut"), "|cffaaaaff[Shut]|r two")
local reopened = false
for i = 4, 10 do if WoW.window(i).name == "Shut" and WoW.window(i).shown then reopened = true end end
check(reopened, "and choosing it opens a tab, not the stale closed one")
for i = 4, 10 do if WoW.window(i).name == "Shut" then WoW.window(i).shown, WoW.window(i).docked = false, nil end end
SlashCmdList.GLASSCHAT("tabs route Shut")   -- no menu: straight to the rule
emit(direct("Shut"), "|cffaaaaff[Shut]|r three")
check(Tabs.IsRouted("Shut"), "/gchat tabs route right after closing it routes it again, not stuck on the closed tab")
SlashCmdList.GLASSCHAT("tabs forget Shut")

GC.db.devMode = false
-- The line that brings the chatty offer keeps its link too.
for i = 1, Tabs.CHATTY do emit(direct("Chatter"), "|cffaaaaff[Chatter]|r line " .. i) end
local twentieth
for _, e in ipairs(main._lines) do
    if type(e.m) == "string" and e.m:find("line " .. Tabs.CHATTY .. "$") then twentieth = e.m end
end
check(twentieth and twentieth:find("|Haddon:GlassChat:src:Chatter|h", 1, true), "the line that brings the offer keeps its link")
-- Only a name is linked, not a sentence.
SlashCmdList.GLASSCHAT("tabs forget AltStable")
emit(direct("AltStable"), "|cffffff00Your bags are full, 3 items were not looted|r")
eq(main._lines[#main._lines].m, "|cffffff00Your bags are full, 3 items were not looted|r", "a line coloured end to end isn't one big link")
-- /gchat tabs route: the folder as spelled; never ours, never a non-name.
SlashCmdList.GLASSCHAT("tabs route altstable always")
eq(GC.db.routes.AltStable, true, "route resolves the folder's real spelling")
eq(GC.db.routes.altstable, nil, "not the case as typed")
SlashCmdList.GLASSCHAT("tabs forget AltStable")
newChat()
SlashCmdList.GLASSCHAT("tabs route GlassChat")
check(chatHas("no tab for GlassChat"), "GlassChat's own is refused")
-- Developer mode fails closed.
GC.db.devMode = nil
WoW.addonVersion = nil
check(not GC.IsDev(), "a version that can't be read isn't developer mode")
WoW.addonVersion = "1.0.0"
check(not GC.IsDev(), "a release isn't")
WoW.addonVersion = "dev"
check(GC.IsDev(), "dev is")
print = stubPrint

eq(next(GC.failures), nil, "nothing failed")
done("test_tabs")
