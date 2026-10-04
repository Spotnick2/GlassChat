-- The buttons beside the chat: voice-style ones lose their metal frame and
-- sit on a small glass pill under their gold symbol; glass off gives the
-- stock look back, and a button never styled is never touched.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GC = loadAddon()
local pills = GC.Buttons._test.pills
for _, b in ipairs({ ChatFrameChannelButton, TextToSpeechButton }) do
    local name = b:GetName()
    local p = pills[b]
    check(p ~= nil, name .. " has a glass pill")
    if p then
        check(p.pill:IsShown(), name .. ": the pill shows")
        eq(p.pill:GetParent(), b, name .. ": the pill is our own child of the button")
        check(p.pill:GetFrameLevel() < b:GetFrameLevel(), name .. ": under the button")
        check(p.g.top:GetFrameLevel() < b:GetFrameLevel(), name .. ": its rims too, never over the gold symbol")
        eq(b._normal._alpha, 0, name .. ": the metal frame (normal art) is invisible")
        eq(b._pushed._alpha, 0, name .. ": and the pushed art")
        eq(b._highlight._alpha, GC.Buttons.HIGHLIGHT, name .. ": the hover highlight is softened, not gone")
        eq(p.g.tint._color[4], GC.db.alpha, name .. ": the pill uses the panel's darkness")
    end
end
eq(TextToSpeechButton.Background._alpha, 0, "TTS's black Background square is gone too")

-- Blizzard re-sets the highlight on a state change: softened again after.
TextToSpeechButton:UpdateHighlight()
eq(TextToSpeechButton._highlight._alpha, GC.Buttons.HIGHLIGHT, "the highlight stays soft after Blizzard's UpdateHighlight")

-- The pill follows the button if its level moves.
ChatFrameChannelButton._level = 20
GC.Chat.Scan()
eq(pills[ChatFrameChannelButton].pill:GetFrameLevel(), 19, "the pill re-syncs under a moved button")

GC.Settings.SetAlpha(0.8)
eq(pills[ChatFrameChannelButton].g.tint._color[4], 0.8, "the pill follows the darkness setting")
GC.Settings.SetGlass(false)
check(not pills[TextToSpeechButton].pill:IsShown(), "glass off hides the pill")
eq(TextToSpeechButton._normal._alpha, 1, "and gives the frame back")
eq(TextToSpeechButton._pushed._alpha, 1, "and the pushed art")
eq(TextToSpeechButton.Background._alpha, 1, "and TTS's Background")
eq(TextToSpeechButton._highlight._alpha, 1, "and the full highlight")
GC.Settings.SetGlass(true)
eq(TextToSpeechButton._normal._alpha, 0, "glass on again")

-- #7: the chat menu and the friends button.
local M, F = ChatFrameMenuButton, QuickJoinToastButton
check(pills[M] and pills[M].pill:IsShown(), "the chat menu sits on a glass pill")
eq(M._normal._alpha, 0, "its framed bubble art is invisible")
eq(M._disabled._alpha, 0, "the disabled art too")
local parts = GC.Buttons._test.bubbles[M]
check(parts and #parts == 4, "a drawn bubble instead")
for _, t in ipairs(parts) do check(t:IsShown() and t._color[2] == GC.Skin.TAB_GOLD[2], "in gold") end
check(pills[F] and pills[F].pill:IsShown(), "the friends button sits on a pill")
eq(F.FriendsButton._atlas, "socialqueuing-icon-group", "with the frameless friends symbol (probe 13, #2)")
F._scripts.OnMouseDown(F)
eq(F.FriendsButton._atlas, "socialqueuing-icon-group", "and keeps it when pressed (Blizzard's framed -down art replaced after)")
F._scripts.OnMouseUp(F)
eq(F.FriendsButton._atlas, "socialqueuing-icon-group", "and released")
GC.Settings.SetGlass(false)
eq(M._normal._alpha, 1, "glass off: the chat menu's art comes back")
for _, t in ipairs(parts) do check(not t:IsShown(), "and the drawn bubble goes") end
eq(F.FriendsButton._atlas, "quickjoin-button-friendslist-up", "the friends button's stock art comes back")
check(F.FriendsButton._points[1] and F.FriendsButton._points[1][1] == "ALL", "filling the button again")
F._scripts.OnMouseDown(F)
eq(F.FriendsButton._atlas, "quickjoin-button-friendslist-down", "and Blizzard's presses work as before")
GC.Settings.SetGlass(true)

eq(next(GC.failures), nil, "nothing failed")
done("test_buttons")
