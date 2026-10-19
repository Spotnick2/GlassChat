-- Glass off at login, then on: the Copy buttons appear without a reload
-- (every setting change re-runs the full scan).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GC = loadAddon({ db = { glass = false } })
eq(GC.Copy._test.buttons[ChatFrame1], nil, "no Copy button with glass off")
local overflow = GeneralDockManager.overflowButton
eq(overflow._normal._alpha, nil, "the dock's overflow button, never styled, is never touched")
eq(overflow._highlight._file, [[Interface\ChatFrame\chat-tab-arrow-on]], "  nor its highlight")
eq(ChatFrame1.ScrollBar.Track.Thumb.Begin._alpha, nil, "the scroll bar, never styled, is never touched")
eq(ChatFrame1.ScrollToBottomButton.Flash._atlas, "minimal-scrollbar-arrow-returntobottom", "  nor the jump button's flash")
-- Scrolled up before glass comes on: Blizzard's flash is already playing and
-- won't start again, so the jump arrow must read the scroll position (Codex, #113).
ChatFrame1._atBottom = false
GC.Settings.SetGlass(true)
local jumpArrow = GC.Skin._test.scrollArt[ChatFrame1].jump
eq(jumpArrow[1]._color[1], GC.Skin.ACCENT[1], "glass on while scrolled up: the jump arrow is accent at once")
eq(GC.Skin._test.scrollArt[ChatFrame2].jump[1]._color[1], GC.Skin.TAB_GREY[1], "  a window at the bottom stays grey")
ChatFrame1._atBottom = nil
check(GC.Copy._test.buttons[ChatFrame1] ~= nil, "glass on: the Copy button appears at once")
eq(overflow._normal._alpha, 0, "  and the overflow button gets its arrow")
eq(next(GC.failures), nil, "nothing failed")
done("test_copy_glassoff")
