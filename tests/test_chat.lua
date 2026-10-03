-- M1: scrollback, class colours, the glass skin and sent-message history,
-- on stock chat windows (extended, never replaced).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.cvars.chatClassColorOverride = "2"   -- per chat type: names uncoloured
local secretLine = WoW.Secret("sent")
local GC = loadAddon({ charDB = { sent = { "/cprobe state", "/run print(1)" } } })
local db = GC.db

-- Scrollback: every window, 128 -> the setting, clamped.
for i = 1, 3 do eq(_G["ChatFrame" .. i]:GetMaxLines(), 1000, "ChatFrame" .. i .. " keeps 1000 lines") end
GC.Settings.SetLines(50)
eq(ChatFrame1:GetMaxLines(), 128, "lines never go under the stock 128")
GC.Settings.SetLines(99999)
eq(ChatFrame2:GetMaxLines(), 5000, "lines are capped at 5000")
GC.Settings.SetLines(1000)

-- A tab opened later gets the same setup through the FCF_OpenNewWindow hook.
WoW.makeChatFrames(4)   -- ChatFrame4 now exists, as FCF_OpenNewWindow would leave it
FCF_OpenNewWindow("Probe")
eq(ChatFrame4:GetMaxLines(), 1000, "a new tab gets the longer scrollback")
check(GC.Skin._test.panels[ChatFrame4] ~= nil, "a new tab gets the glass panel")

-- Class colours: PLAYER_LOGIN switched the CVar to "0" (always).
eq(WoW.cvars.chatClassColorOverride, "0", "class colours on at login")
WoW.cvarSets = {}
WoW.fire("PLAYER_LOGIN")
eq(#WoW.cvarSets, 0, "an already-on CVar isn't set again")
GC.Settings.SetClassColors(false)
WoW.cvars.chatClassColorOverride = "1"
WoW.fire("PLAYER_LOGIN")
eq(WoW.cvars.chatClassColorOverride, "1", "colours off: the CVar is left alone")
GC.Settings.SetClassColors(true)
eq(WoW.cvars.chatClassColorOverride, "0", "turning colours back on applies at once")

-- The skin: a panel per window and edit box; Blizzard's background hidden,
-- the edit box border made invisible; all of it reversible.
local P = GC.Skin._test.panels
local p, e = P[ChatFrame1], P[ChatFrame1EditBox]
check(p and p.panel:IsShown(), "ChatFrame1 has a shown glass panel")
check(e and e.panel:IsShown(), "its edit box has one too")
eq(p.panel:GetParent(), UIParent, "the window panel is our own frame, not a child of the chat frame")
eq(p.panel:GetFrameStrata(), "BACKGROUND", "in BACKGROUND strata, under the chat text and the MEDIUM-strata tabs")
ChatFrame1:Hide()
check(not p.panel:IsShown(), "it hides with its chat window (another tab selected)")
ChatFrame1:Show()
check(p.panel:IsShown(), "and shows with it")
eq(e.panel:GetParent(), ChatFrame1EditBox, "the edit box panel stays a child of its box")
eq(select(2, p.panel:GetPoint(1)), ChatFrame1Background, "the panel covers Blizzard's background rectangle")
check(not ChatFrame1Background:IsShown() and not ChatFrame1ButtonFrameBackground:IsShown(),
    "Blizzard's background pieces are hidden")
eq(ChatFrame1EditBoxMid._alpha, 0, "the edit box border is invisible")
eq(ChatFrame1EditBoxFocusLeft._alpha, 0, "its focus art too")
eq(p.g.tint._color[4], 0.65, "the panel is dark at the default alpha")
check(p.g.tint._color[1] <= 0.06 and p.g.tint._color[3] <= 0.06, "a neutral charcoal, not the material's blue tint")
eq(p.g.wash._alpha, 0, "no milky wash over the header")
eq(p.g.rim._alpha, GC.Skin.LOOK.rim, "the material's thick rim is dimmed on the window")
eq(p.g.shadow._alpha, GC.Skin.LOOK.shadow, "and its broad drop shadow")
check(p.edge and p.edge.top._color[4] > p.edge.bottom._color[1], "a fine bright top edge and a dark bottom one")

-- Whole lines only: the clipping container's top comes down to a whole
-- number of lines (200 px, 14 px lines, 2 px gap: 14 lines = 196, 4 px off)
-- plus a 2 px trim into the first line's empty top, so the descenders of the
-- line above don't show; refit when the font size changes, and given back
-- with glass off.
local box = ChatFrame1.FontStringContainer
local _, _, _, _, y = box:GetPoint(1)
eq(y, -6, "the line box starts 6 px down: 14 whole lines, trimmed")
FCF_SetChatWindowFontSize(nil, ChatFrame1, 18)
_, _, _, _, y = box:GetPoint(1)
eq(y, -4, "refit at 18 pt: 11 whole lines, trimmed")

-- /gchat tune: the window surface, live and saved, clamped, and reset.
SlashCmdList.GLASSCHAT("tune shadow 0.1")
eq(p.g.shadow._alpha, 0.1, "/gchat tune shadow applies at once")
eq(GlassChatDB.look.shadow, 0.1, "and is saved")
SlashCmdList.GLASSCHAT("tune glowh 99")
eq(p.edge.glow._height, 20, "glow height is capped")
SlashCmdList.GLASSCHAT("tune rim 3")
eq(p.g.rim._alpha, 1, "opacities are capped at 1")
newChat()
SlashCmdList.GLASSCHAT("tune")
check(chatHas("/gchat tune shadow"), "/gchat tune lists the keys")
SlashCmdList.GLASSCHAT("tune reset")
eq(p.g.shadow._alpha, GC.Skin.LOOK.shadow, "tune reset brings the shipped look back")

ChatFrame1EditBox._scripts.OnEditFocusGained(ChatFrame1EditBox)
eq(e.g.rim._alpha, GC.Skin.RIM_FOCUS, "focus brightens the edit box rim")
ChatFrame1EditBox._scripts.OnEditFocusLost(ChatFrame1EditBox)
eq(e.g.rim._alpha, GC.Skin.RIM_IDLE, "and losing focus dims it")

GC.Settings.SetAlpha(0.7)
eq(p.g.tint._color[4], 0.7, "the opacity setting reaches every panel")
GC.Settings.SetAlpha(5)
eq(db.alpha, 1, "opacity is clamped to 1")
GC.Settings.SetAlpha(0.65)

GC.Settings.SetGlass(false)
check(not p.panel:IsShown() and not e.panel:IsShown(), "glass off hides the panels")
eq(box:GetPoint(1), "ALL", "glass off gives the line box back its full frame")
eq(select(5, GeneralDockManager:GetPoint(1)), 0, "glass off puts the tabs back where Blizzard had them")
check(ChatFrame1Background:IsShown(), "and gives Blizzard's background back")
eq(ChatFrame1EditBoxMid._alpha, 1, "and the edit box border")
GC.Settings.SetGlass(true)
check(p.panel:IsShown() and not ChatFrame1Background:IsShown(), "glass on again")

-- Tabs, after the owner's mockup: the panel reaches up over the tab strip
-- with a separator line; the stock tab art is invisible; the selected tab
-- gets a faint fill and a gold underline, the others plain grey names.
local tab, text = ChatFrame1Tab, ChatFrame1Tab:GetFontString()
eq(select(5, p.panel:GetPoint(1)), GC.Skin.PAD_Y + GC.Skin.TAB_STRIP + GC.Skin.TAB_GAP, "the panel reaches up over the raised tabs")
check(p.separator ~= nil, "a separator line runs under the tabs")
-- Space between the tabs and the text: the dock is raised by the gap, also
-- when Blizzard re-anchors it; a floating window's own tab too; a docked
-- one is left to the dock.
local gapY = GC.Skin.TAB_GAP
eq(select(5, GeneralDockManager:GetPoint(1)), gapY, "the tab dock sits TAB_GAP px higher")
FCFDock_SetPrimary(GeneralDockManager, ChatFrame1)
eq(select(5, GeneralDockManager:GetPoint(1)), gapY, "and stays there when Blizzard re-anchors it")
ChatFrame3.isDocked = false
FCF_SetTabPosition(ChatFrame3, 0)
eq(select(5, ChatFrame3Tab:GetPoint(1)), gapY, "a floating window's tab is raised too")
ChatFrame3.isDocked = true
FCF_SetTabPosition(ChatFrame3, 0)
eq(select(5, ChatFrame3Tab:GetPoint(1)), 0, "a docked tab is left to the dock")
eq(select(2, text:GetFont()), 14, "the tab name is 14 pt")
eq(text:GetHeight(), 18, "and its 8 px box is grown so it isn't clipped")
eq(tab.Middle._alpha, 0, "the stock tab art is invisible")
eq(tab.ActiveMiddle._alpha, 0, "the stock selected art too")
check(P[tab] == nil, "no glass pill per tab any more")
local lit = GC.Skin._test.tabLit[tab]
FCFTab_UpdateColors(tab, true)
check(lit.fill:IsShown() and lit.line:IsShown(), "the selected tab is lit with an underline")
eq(text._textColor and text._textColor[2], 0.82, "in gold")
FCFTab_UpdateColors(tab, false)
check(not lit.fill:IsShown() and not lit.line:IsShown(), "an unselected tab isn't lit")
eq(text._textColor and text._textColor[1], 0.8, "and its name is grey")
FCFTab_UpdateAlpha(ChatFrame1)
FCFTab_UpdateAlpha(ChatFrame2)
eq(ChatFrame1Tab._alpha, 1, "the selected tab rests at full (stock 0.4)")
eq(ChatFrame2Tab._alpha, 0.9, "the others at 0.9 (stock 0.2)")
eq(WoW.tabAlphas[ChatFrame2Tab][1], 1, "mouse-over brings any tab to full")
GC.Settings.SetTabSize(30)
eq(select(2, text:GetFont()), 20, "tab size is capped at 20")
GC.Settings.SetGlass(false)
eq(select(2, text:GetFont()), 10, "glass off gives the tab its stock font back")
eq(text:GetHeight(), 8, "and its stock height")
eq(tab.Middle._alpha, 1, "and its stock art")
FCFTab_UpdateColors(tab, true)
check(not lit.fill:IsShown(), "and no lit look")
GC.Settings.SetGlass(true)
GC.Settings.SetTabSize(14)

-- Sent history: plain arrows, a longer list, replayed from the character's
-- saved lines, and every new send recorded (once, never a secret).
local edit = ChatFrame1EditBox
eq(edit:GetAltArrowKeyMode(), false, "plain Up/Down cycle the history")
eq(edit:GetHistoryLines(), 100, "the edit box keeps 100 lines")
eq(table.concat(edit._history, "|"), "/cprobe state|/run print(1)", "saved lines are replayed into the edit box")
eq(#GlassChatCharDB.sent, 2, "replaying doesn't record the lines again")
edit:AddHistoryLine("/cprobe sources")
edit:AddHistoryLine("/cprobe sources")
eq(GlassChatCharDB.sent[3], "/cprobe sources", "a sent line is recorded")
eq(#GlassChatCharDB.sent, 3, "the same line twice in a row is kept once")
WoW.MarkSecret("hidden text")
edit:AddHistoryLine("hidden text")
eq(#GlassChatCharDB.sent, 3, "a secret line is never saved")
edit:AddHistoryLine(secretLine)
eq(#GlassChatCharDB.sent, 3, "nor a secret value")
GC.Settings.SetHistory(10)
for i = 1, 15 do edit:AddHistoryLine("line " .. i) end
eq(#GlassChatCharDB.sent, 10, "the saved list is capped at the history size")
eq(GlassChatCharDB.sent[10], "line 15", "keeping the newest")
-- Up/Down walk OUR list (the native history ignores plain arrows on this
-- client, measured): Up older, Down newer, past the newest back to the draft.
local function arrow(key) edit._scripts.OnArrowPressed(edit, key) end
GlassChatCharDB.sent = { "first", "second", "third" }
edit:SetText("half-typed")
arrow("UP")
eq(edit:GetText(), "third", "Up recalls the newest sent line")
arrow("UP"); arrow("UP"); arrow("UP")
eq(edit:GetText(), "first", "Up stops at the oldest")
arrow("DOWN")
eq(edit:GetText(), "second", "Down goes one newer")
arrow("DOWN"); arrow("DOWN")
eq(edit:GetText(), "half-typed", "Down past the newest gives back what was being typed")
arrow("DOWN")
eq(edit:GetText(), "half-typed", "Down when not browsing changes nothing")
arrow("UP")
edit:AddHistoryLine("fourth")   -- a send
edit:SetText("")
arrow("UP")
eq(edit:GetText(), "fourth", "after a send, Up starts again from the newest")
edit._scripts.OnEditFocusLost(edit)
arrow("UP")
eq(edit:GetText(), "fourth", "losing focus resets browsing too")
WoW.chatLockdown = true
edit:SetText("x")
arrow("UP")
eq(edit:GetText(), "x", "no SetText during chat messaging lockdown")
WoW.chatLockdown = false
arrow("LEFT")
eq(edit:GetText(), "x", "other arrows are left to the edit box")
GC.Settings.SetPlainArrows(false)
eq(edit:GetAltArrowKeyMode(), true, "arrows off gives back Alt+Up/Down")
edit:SetText("y")
arrow("UP")
eq(edit:GetText(), "y", "and our Up/Down stand down")

-- Channel names lose the zone: CHAT_MSG_CHANNEL's arg4 is rewritten by a
-- message filter, every other argument passed through; custom channels
-- (zone channel ID 0) and secrets are left alone.
local filter = WoW.messageFilters.CHAT_MSG_CHANNEL and WoW.messageFilters.CHAT_MSG_CHANNEL[1]
check(filter ~= nil, "a CHAT_MSG_CHANNEL filter is installed")
local function run(...) return { filter(ChatFrame1, "CHAT_MSG_CHANNEL", ...) } end
local r = run("LFM", "Rat War", "", "1. General - The Barrens", "Rat War", "", 1, 1, "General", 0, 77, "Player-1-AB")
eq(r[1], false, "the message is kept")
eq(r[5], "1. General", "the zone is dropped from the channel label")
eq(r[2], "LFM", "the text is passed through")
eq(r[9], 1, "the channel number (the click link) is untouched")
eq(r[13], "Player-1-AB", "and so is everything after it")
eq(#r, 13, "no argument is lost or added")
r = run("hi", "Bob", "", "5. MyGuildAlts - Raid", "Bob", "", 0, 5, "MyGuildAlts - Raid", 0, 78, "Player-1-CD")
eq(#r, 1, "a custom channel (zone ID 0) is left alone")
r = run("hi", "Bob", "", WoW.Secret("chan"), "Bob", "", 1, 1, "General", 0, 79, "x")
eq(#r, 1, "a secret channel name is left alone")
GC.Settings.SetShortChannels(false)
r = run("LFM", "Rat War", "", "1. General - The Barrens", "Rat War", "", 1, 1, "General", 0, 80, "x")
eq(#r, 1, "channels off: nothing is rewritten")
GC.Settings.SetShortChannels(true)

-- /gchat drives the same settings.
newChat()
SlashCmdList.GLASSCHAT("alpha 0.6")
eq(db.alpha, 0.6, "/gchat alpha sets the opacity")
SlashCmdList.GLASSCHAT("glass off")
eq(db.glass, false, "/gchat glass off")
SlashCmdList.GLASSCHAT("glass maybe")
check(chatHas("/gchat glass on|off"), "a bad value prints the usage")
SlashCmdList.GLASSCHAT("lines lots")
eq(db.lines, 1000, "a non-number leaves the setting alone")
SlashCmdList.GLASSCHAT("")
check(chatHas("panel darkness %(0.6%)"), "help shows the current values")

eq(next(GC.failures), nil, "nothing failed")
done("test_chat")
