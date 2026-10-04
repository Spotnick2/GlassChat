-- Copy this window: plain text out of a chat window, selected for Ctrl+C,
-- never a secret line.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GC = loadAddon()
local Copy = GC.Copy

-- Plain text: colours, links, textures, atlases and protected names out.
eq(Copy.Plain("|cff00ccff[AltStable]|r hello"), "[AltStable] hello", "colour codes go")
eq(Copy.Plain("loot |cffa335ee|Hitem:19019::::|h[Thunderfury]|h|r!"), "loot [Thunderfury]!", "a link keeps its text")
eq(Copy.Plain("|TInterface\\Icons\\INV_Misc_QuestionMark:0|t gold"), " gold", "a texture goes")
eq(Copy.Plain("|A:raidtarget-skull:0:0|a pull"), " pull", "an atlas goes")
eq(Copy.Plain("from |Kq42|k"), "from ?", "a protected Battle.net name becomes ?")
eq(Copy.Plain("a||b"), "a|b", "an escaped pipe is a pipe")
eq(Copy.Plain(WoW.Secret("line")), nil, "a secret is never read")
WoW.MarkSecret("marked secret string")
eq(Copy.Plain("marked secret string"), nil, "nor a secret string")

-- A window's lines, oldest first; a secret one is counted, never copied.
ChatFrame1._messages = { "|cff00ccff[ASProbe]|r first", WoW.Secret("chat"), "third" }
local lines, hidden = Copy.Lines(ChatFrame1)
eq(table.concat(lines, "|"), "[ASProbe] first|" .. Copy.HIDDEN .. "|third", "lines in order, the secret one hidden")
eq(hidden, 1, "one hidden line counted")

-- The window: the text selected and focused, named after the chat window.
Copy.Open(ChatFrame1)
local win = Copy._test.window()
check(win:IsShown(), "the copy window opens")
eq(win.edit:GetText(), "[ASProbe] first\n" .. Copy.HIDDEN .. "\nthird", "with the window's plain text")
check(win.edit._focused and win.edit._highlighted, "focused and selected for Ctrl+C")
eq(win.title:GetText(), "Copy: General", "titled with the chat window's name")
check(win.status:GetText():find("1 hidden", 1, true), "the status says how many lines were hidden")
check(win:GetFrameStrata() == "FULLSCREEN_DIALOG", "above everything else")
local escape = false
for _, n in ipairs(UISpecialFrames) do if n == "GlassChatCopyWindow" then escape = true end end
check(escape, "Escape closes it")

-- Read-only: typing puts the text back, selected.
win.edit._text = "typed over"
win.edit._highlighted = false
win.edit._scripts.OnTextChanged(win.edit, true)
eq(win.edit:GetText(), win.text, "typing into it restores the text")
check(win.edit._highlighted, "selected again")
win.edit._scripts.OnEscapePressed(win.edit)
check(not win:IsShown(), "Esc in the box closes the window")

-- The Copy button: on each window's glass panel, in the tabs' strata, and
-- it copies ITS window.
local b = Copy._test.buttons[ChatFrame2]
check(b ~= nil, "each chat window has a Copy button")
eq(b:GetParent(), GC.Skin.Panel(ChatFrame2).panel, "on its glass panel, so it shows and hides with it")
eq(b:GetFrameStrata(), "MEDIUM", "raised to the tabs' strata")
eq(#b.icon.lines, 8, "a copy icon: two page outlines, four lines each")
eq(b.icon.lines[1]._color[1], GC.Skin.TAB_GREY[1], "grey at rest, like the tab names")
b._scripts.OnEnter(b)
eq(b.icon.lines[1]._color[2], GC.Skin.TAB_GOLD[2], "gold on hover")
eq(GameTooltip._text, "Copy this window", "with a tooltip saying what it does")
b._scripts.OnLeave(b)
eq(b.icon.lines[1]._color[1], GC.Skin.TAB_GREY[1], "grey again after")
check(not GameTooltip:IsShown(), "and the tooltip goes")
ChatFrame2._messages = { "combat line" }
b._scripts.OnClick(b)
eq(win.edit:GetText(), "combat line", "the button copies its own window")
eq(win.title:GetText(), "Copy: Combat Log", "and says which")

-- /gchat copy: the window being looked at.
GeneralDockManager._selected = ChatFrame3
ChatFrame3._messages = { "a whisper" }
SlashCmdList.GLASSCHAT("copy")
eq(win.edit:GetText(), "a whisper", "/gchat copy opens the selected window")

-- An escaped pipe is literal text, never half of a code.
eq(Copy.Plain("a||rb"), "a|rb", "a||rb keeps its r (the pipe was escaped)")
eq(Copy.Plain("x||cffff0000y"), "x|cffff0000y", "an escaped colour code stays text")

-- The client's stripper keeps brackets (maintainBrackets), and protected
-- names are replaced before it runs.
local stripCalls = {}
rawset(_G, "C_StringUtil", { StripHyperlinks = function(t, keepColor, keepBrackets)
    stripCalls[#stripCalls + 1] = { t = t, brackets = keepBrackets }
    if keepBrackets then return (t:gsub("|H.-|h(.-)|h", "%1")) end
    return (t:gsub("|H.-|h%[?(.-)%]?|h", "%1"))
end })
eq(Copy.Plain("|Hitem:1|h[Thunderfury]|h from |Kq9|k"), "[Thunderfury] from ?", "brackets kept, protected name replaced")
check(stripCalls[1].brackets == true, "StripHyperlinks is asked to keep brackets")
check(not stripCalls[1].t:find("|K", 1, true), "the |K name was replaced before the client's stripper ran")
rawset(_G, "C_StringUtil", nil)

-- Only the newest Copy.MAX lines go in the box, and the status says so.
local many = {}
for i = 1, Copy.MAX + 5 do many[i] = "line " .. i end
ChatFrame1._messages = many
Copy.Open(ChatFrame1)
check(win.edit:GetText():find("^line 6\n"), "the oldest lines past the cap are left out")
check(win.status:GetText():find("of " .. (Copy.MAX + 5), 1, true), "the status says how many there were")
eq(win.scroll._vscroll, 0, "the view opens at the top")

-- A line that fails to read is a failure, not a 'hidden' secret.
ChatFrame1._messages = { "ok" }
rawset(ChatFrame1, "GetMessageInfo", function() error("boom") end)
local _, h = Copy.Lines(ChatFrame1)
eq(h, 0, "a read error isn't counted as hidden")
check(GC.failures["copy read"] ~= nil, "it's recorded as a failure")
GC.failures["copy read"] = nil
rawset(ChatFrame1, "GetMessageInfo", nil)

-- A temporary whisper window is titled with its tab's text.
local temp = WoW.makeTemporaryWindow(11)
ChatFrame11Tab._tabText = "Bob"
temp._messages = { "hi" }
Copy.Open(temp)
eq(win.title:GetText(), "Copy: Bob", "a whisper window is named after its tab")

-- /gchat copy copies the window it was typed in.
ChatFrame2._messages = { "typed here" }   -- ChatFrame3 is the selected window
SlashCmdList.GLASSCHAT("copy", ChatFrame2EditBox)
eq(win.edit:GetText(), "typed here", "/gchat copy uses the window it was typed in")

-- The dock stops short of the Copy button; glass off gives it back.
eq(select(4, GeneralDockManager:GetPoint(2)), -GC.Skin.DOCK_RESERVE, "the tab dock leaves room for the Copy button")
GC.Settings.SetGlass(false)
eq(select(4, GeneralDockManager:GetPoint(2)), 0, "glass off: the dock spans the window again")
GC.Settings.SetGlass(true)

eq(next(GC.failures), nil, "nothing failed")
done("test_copy")
