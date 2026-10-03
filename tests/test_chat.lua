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
eq(p.g.tint._color[4], 0.45, "the panel is dark at the default alpha")
eq(p.g.tint._color[1] + p.g.tint._color[2] + p.g.tint._color[3], 0, "and black, not the material's blue tint")

ChatFrame1EditBox._scripts.OnEditFocusGained(ChatFrame1EditBox)
eq(e.g.rim._alpha, GC.Skin.RIM_FOCUS, "focus brightens the edit box rim")
ChatFrame1EditBox._scripts.OnEditFocusLost(ChatFrame1EditBox)
eq(e.g.rim._alpha, GC.Skin.RIM_IDLE, "and losing focus dims it")

GC.Settings.SetAlpha(0.7)
eq(p.g.tint._color[4], 0.7, "the opacity setting reaches every panel")
GC.Settings.SetAlpha(5)
eq(db.alpha, 1, "opacity is clamped to 1")
GC.Settings.SetAlpha(0.45)

GC.Settings.SetGlass(false)
check(not p.panel:IsShown() and not e.panel:IsShown(), "glass off hides the panels")
check(ChatFrame1Background:IsShown(), "and gives Blizzard's background back")
eq(ChatFrame1EditBoxMid._alpha, 1, "and the edit box border")
GC.Settings.SetGlass(true)
check(p.panel:IsShown() and not ChatFrame1Background:IsShown(), "glass on again")

-- Tabs, after the owner's mockup: the panel reaches up over the tab strip
-- with a separator line; the stock tab art is invisible; the selected tab
-- gets a faint fill and a gold underline, the others plain grey names.
local tab, text = ChatFrame1Tab, ChatFrame1Tab:GetFontString()
eq(select(5, p.panel:GetPoint(1)), GC.Skin.PAD_Y + GC.Skin.TAB_STRIP, "the panel reaches up over the tabs")
check(p.separator ~= nil, "a separator line runs under the tabs")
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
