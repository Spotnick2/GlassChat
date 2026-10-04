-- Glass off at login: the buttons beside the chat are never touched.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GC = loadAddon({ db = { glass = false } })
eq(GC.Buttons._test.pills[ChatFrameChannelButton], nil, "no pill")
eq(ChatFrameChannelButton._normal._alpha, nil, "the stock frame art is never written to")
GC.Settings.SetGlass(true)
check(GC.Buttons._test.pills[ChatFrameChannelButton] ~= nil, "glass on: the pill appears at once")
eq(next(GC.failures), nil, "nothing failed")
done("test_buttons_glassoff")
