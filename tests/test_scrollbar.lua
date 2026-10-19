-- The scroll bar (#112): with glass, Blizzard's atlases at alpha 0 under our
-- fills (arrows, track, thumb, jump arrow over a bar), accent on hover, the
-- jump arrow accent while lines wait below (Blizzard's flash, hidden by its
-- vertex alpha, starts and stops it). Glass off puts the stock art back.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GC = loadAddon()
local Skin = GC.Skin
local f = ChatFrame1
local bar, jump = f.ScrollBar, f.ScrollToBottomButton
local track, thumb = bar.Track, bar.Track.Thumb
local s = Skin._test.scrollArt[f]
check(s ~= nil, "the scroll bar is styled")

local stock = { track.Begin, track.Middle, track.End, thumb.Begin, thumb.Middle, thumb.End,
    bar.Back.Texture, bar.Forward.Texture, jump._normal, jump._pushed, jump._highlight, jump._disabled }
local function allAlpha(a)
    for _, t in ipairs(stock) do if t._alpha ~= a then return false end end
    return true
end
check(allAlpha(0), "every stock atlas at alpha 0 (" .. #stock .. ")")
eq(table.concat(jump.Flash._color, ","), "0,0,0,0", "Blizzard's flash painted transparent black")
eq(jump.Flash._blend, "ADD", "  which, drawn ADD, adds nothing")

local function widths(list)
    local w = {}
    for i, t in ipairs(list) do w[i] = t._width end
    return table.concat(w, ",")
end
eq(widths(s.fwd), "7,5,3,1", "the down arrow: rows narrowing downward")
local function topY(t) return t._points[1][5] end
check(topY(s.back[1]) < topY(s.back[4]), "the up arrow: its widest row at the bottom")
check(topY(s.fwd[1]) > topY(s.fwd[4]), "the down arrow: its widest row at the top")
eq(#s.jump, 5, "the jump arrow, and its bar")
eq(s.track._color[4], Skin.TRACK_ALPHA, "a faint track")
eq(s.track._width, 1, "  1 px")
eq(s.thumb[1]._width, Skin.THUMB_W, "a slim thumb")
eq(s.thumb[1]._points[1][2], thumb, "  that follows Blizzard's thumb")

local grey, accent = Skin.TAB_GREY[1], Skin.ACCENT[1]
eq(s.back[1]._color[1], grey, "grey at rest")
for _, part in ipairs({ { bar.Back, s.back, "the up arrow" }, { bar.Forward, s.fwd, "the down arrow" },
    { thumb, s.thumb, "the thumb" }, { jump, s.jump, "the jump arrow" } }) do
    part[1]._scripts.OnEnter(part[1])
    eq(part[2][1]._color[1], accent, part[3] .. ": accent on hover")
    part[1]._scripts.OnLeave(part[1])
    eq(part[2][1]._color[1], grey, "  grey after")
end

-- Lines wait below: Blizzard starts the flash; the jump arrow goes accent.
ChatFrameUtil.StartFlash(jump.Flash, {})
eq(s.jump[1]._color[1], accent, "lines below (Blizzard's flash starts): the jump arrow is accent")
eq(s.jump[5]._color[1], accent, "  its bar too")
jump._scripts.OnEnter(jump); jump._scripts.OnLeave(jump)
eq(s.jump[1]._color[1], accent, "  and stays so after a hover")
ChatFrameUtil.StopFlash(jump.Flash, {}, false)
eq(s.jump[1]._color[1], grey, "back at the bottom (it stops): grey")
ChatFrameUtil.StartFlash(GeneralDockManager.overflowButton._highlight, {})
eq(s.jump[1]._color[1], grey, "another flash leaves it alone")

GC.Settings.SetGlass(false)
check(allAlpha(1), "glass off: every stock atlas back")
eq(jump.Flash._atlas, Skin.JUMP_FLASH, "  the flash's own art again")
eq(jump.Flash._color, nil, "  not the black")
check(not s.fwd[1]._shown and not s.thumb[1]._shown and not s.track._shown and not s.jump[5]._shown, "  ours hidden")
bar.Back._scripts.OnEnter(bar.Back)
eq(s.back[1]._color[1], grey, "  a hover doesn't paint it")
bar.Back._scripts.OnLeave(bar.Back)

GC.Settings.SetGlass(true)
check(allAlpha(0), "glass on again: styled again")
eq(table.concat(jump.Flash._color, ","), "0,0,0,0", "  the flash black again")
check(s.fwd[1]._shown and s.track._shown, "  ours shown")
eq(Skin._test.scrollArt[f], s, "  not built twice")
check(Skin._test.scrollArt[ChatFrame2] ~= nil, "every window gets it")

eq(next(GC.failures), nil, "nothing failed")
done("test_scrollbar")
