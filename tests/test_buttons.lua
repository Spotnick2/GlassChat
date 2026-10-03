-- The buttons beside the chat: voice-style ones lose their metal frame and
-- sit on a small glass pill; glass off gives the stock look back.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GC = loadAddon()
local b = ChatFrameChannelButton
local p = GC.Buttons._test.pills[b]
check(p and p.pill:IsShown(), "the channel button has a glass pill")
eq(p.pill:GetParent(), b, "the pill is our own child of the button")
check(p.pill:GetFrameLevel() < b:GetFrameLevel(), "under the button's symbol")
eq(b._normal._alpha, 0, "the metal frame (normal art) is invisible")
eq(b._pushed._alpha, 0, "and the pushed art")
eq(b._highlight._alpha, GC.Buttons.HIGHLIGHT, "the hover highlight is softened, not gone")
eq(p.g.tint._color[4], GC.db.alpha, "the pill uses the panel's darkness")

GC.Settings.SetAlpha(0.8)
eq(p.g.tint._color[4], 0.8, "and follows it")
GC.Settings.SetGlass(false)
check(not p.pill:IsShown(), "glass off hides the pill")
eq(b._normal._alpha, 1, "and gives the frame back")
eq(b._highlight._alpha, 1, "and the full highlight")
GC.Settings.SetGlass(true)
eq(b._normal._alpha, 0, "glass on again")

eq(next(GC.failures), nil, "nothing failed")
done("test_buttons")
