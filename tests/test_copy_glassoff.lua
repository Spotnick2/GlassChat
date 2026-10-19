-- Glass off at login, then on: the Copy buttons appear without a reload
-- (every setting change re-runs the full scan).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GC = loadAddon({ db = { glass = false } })
eq(GC.Copy._test.buttons[ChatFrame1], nil, "no Copy button with glass off")
local overflow = GeneralDockManager.overflowButton
eq(overflow._normal._alpha, nil, "the dock's overflow button, never styled, is never touched")
eq(overflow._highlight._file, [[Interface\ChatFrame\chat-tab-arrow-on]], "  nor its highlight")
GC.Settings.SetGlass(true)
check(GC.Copy._test.buttons[ChatFrame1] ~= nil, "glass on: the Copy button appears at once")
eq(overflow._normal._alpha, 0, "  and the overflow button gets its arrow")
eq(next(GC.failures), nil, "nothing failed")
done("test_copy_glassoff")
