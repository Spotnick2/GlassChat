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
ChatFrame2._messages = { "combat line" }
b._scripts.OnClick(b)
eq(win.edit:GetText(), "combat line", "the button copies its own window")
eq(win.title:GetText(), "Copy: Combat Log", "and says which")

-- /gchat copy: the window being looked at.
GeneralDockManager._selected = ChatFrame3
ChatFrame3._messages = { "a whisper" }
SlashCmdList.GLASSCHAT("copy")
eq(win.edit:GetText(), "a whisper", "/gchat copy opens the selected window")

eq(next(GC.failures), nil, "nothing failed")
done("test_copy")
