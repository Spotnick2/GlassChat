-- Glass off at login, then on: the Copy buttons appear without a reload
-- (every setting change re-runs the full scan).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GC = loadAddon({ db = { glass = false } })
eq(GC.Copy._test.buttons[ChatFrame1], nil, "no Copy button with glass off")
GC.Settings.SetGlass(true)
check(GC.Copy._test.buttons[ChatFrame1] ~= nil, "glass on: the Copy button appears at once")
eq(next(GC.failures), nil, "nothing failed")
done("test_copy_glassoff")
