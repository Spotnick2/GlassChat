-- The dock's overflow button (#110): with glass, a grey arrow drawn from
-- fills over the hidden file art, accent on hover, and the highlight kept
-- (its FlashAnim is the alert pulse) as a soft accent glow. Glass off puts
-- Blizzard's art back.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GC = loadAddon()
local Skin = GC.Skin
local b = GeneralDockManager.overflowButton
local normal, glow = b._normal, b._highlight

-- Our arrow: the 1 px rows created on the button.
local function arrowRows()
    local list = {}
    for _, t in ipairs(b._created or {}) do if t._color and t._height == 1 then list[#list + 1] = t end end
    return list
end

eq(normal._alpha, 0, "glass: Blizzard's framed arrow is hidden")
eq(glow._file, nil, "the highlight's file art is replaced")
eq(glow._color[4], Skin.OVERFLOW_GLOW, "  by a soft accent glow")
eq(glow._color[1], Skin.ACCENT[1], "  in the accent")
check(rawget(b, "_highlight") == glow, "the same highlight texture, so its pulse animation still runs")

local arrow = arrowRows()
eq(#arrow, #Skin.OVERFLOW_ROWS, "an arrow of " .. #Skin.OVERFLOW_ROWS .. " rows")
local widths = {}
for i, t in ipairs(arrow) do widths[i] = t._width end
eq(table.concat(widths, ","), "9,7,5,3,1", "  narrowing downward")
eq(arrow[1]._color[1], Skin.TAB_GREY[1], "  grey at rest, as the strip icons")
b._scripts.OnEnter(b)
eq(arrow[1]._color[1], Skin.ACCENT[1], "  accent on hover")
b._scripts.OnLeave(b)
eq(arrow[1]._color[1], Skin.TAB_GREY[1], "  grey again after")

GC.Settings.SetGlass(false)
eq(normal._alpha, 1, "glass off: Blizzard's arrow is back")
eq(glow._file, Skin.OVERFLOW_HIGHLIGHT, "  and its highlight art")
check(not arrow[1]._shown, "  ours is hidden")
b._scripts.OnEnter(b)
eq(arrow[1]._color[1], Skin.TAB_GREY[1], "  and a hover doesn't paint it")
b._scripts.OnLeave(b)

GC.Settings.SetGlass(true)
eq(normal._alpha, 0, "glass on again: styled again")
check(arrow[1]._shown, "  our arrow shown")
eq(#arrowRows(), #Skin.OVERFLOW_ROWS, "  and not built twice")

eq(next(GC.failures), nil, "nothing failed")
done("test_overflow")
