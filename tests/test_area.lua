-- The chat's footprint (#122): GlassChat.Footprint() and the
-- "GlassChat.LayoutChanged" announcement, for the other Glass addons to keep
-- clear of the chat. The union of the window, its glass, tab strip, edit box
-- and button column, in UIParent units; announced out of combat only, past a
-- tolerance; never from an unreadable rect.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GC = loadAddon()
local P = GC.Skin._test.panels
local f, edit = ChatFrame1, ChatFrame1EditBox

local heard = {}
EventRegistry:RegisterCallback("GlassChat.LayoutChanged", function(_, fp) heard[#heard + 1] = fp end, {})
local function measure() WoW.tick(0.02) end

-- Before any rect is readable: nothing measured, nothing announced.
measure()
eq(GC.Footprint(), nil, "no footprint while the window's rect is unreadable")
eq(#heard, 0, "  and no announcement")

WoW.SetRect(f, 30, 60, 400, 180)                 -- 30..430, 60..240
WoW.SetRect(P[f].panel, 22, 60, 416, 219)        -- the glass: 22..438, up to 279 over the tabs
WoW.SetRect(edit, 30, 28, 400, 32)               -- under it: 28..60
WoW.SetRect(P[edit].panel, 22, 32, 416, 28)
WoW.SetRect(ChatFrame1ButtonFrame, 2, 60, 26, 180)
GC.Area.Request()
measure()
local fp = GC.Footprint()
check(fp ~= nil, "measured once the window reads")
eq(fp.left, 2, "  left: the button column")
eq(fp.right, 438, "  right: the glass panel")
eq(fp.top, 279, "  top: the glass over the tab strip")
eq(fp.bottom, 28, "  bottom: the edit box")
eq(#heard, 1, "the first measure is announced")
eq(heard[1].top, 279, "  with the footprint")

fp.top = 0
eq(GC.Footprint().top, 279, "Footprint() is a fresh table")

-- The edit box counts while hidden (IM style); a hidden button doesn't.
edit:Hide()
local menu = ChatFrameMenuButton
WoW.SetRect(menu, 2, 241, 26, 26)
menu:Hide()
GC.Area.Request(); measure()
eq(GC.Footprint().bottom, 28, "a hidden edit box still counts")
eq(GC.Footprint().top, 279, "a hidden button doesn't")
edit:Show()
menu:Show()
WoW.SetRect(menu, 2, 270, 26, 26)                -- up to 296
GC.Area.Request(); measure()
eq(GC.Footprint().top, 296, "a shown button counts")
eq(#heard, 2, "  and the change is announced")

-- Within the tolerance: no announcement.
WoW.SetRect(menu, 2, 270.3, 26, 26)
GC.Area.Request(); measure()
eq(#heard, 2, "a move within the tolerance isn't announced")

-- In combat: measured, announced only after it.
WoW.combat = true
WoW.SetRect(menu, 2, 300, 26, 26)                -- up to 326
GC.Area.Request(); measure()
eq(GC.Footprint().top, 326, "in combat the footprint is measured")
eq(#heard, 2, "  but not announced")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
measure()
eq(#heard, 3, "announced once combat ends")
eq(heard[3].top, 326, "  with the latest value")

-- A secret rect is skipped, never guessed. The client's secrets keep their
-- type, so a real number marked secret (a proxy would fail type() anyway).
local secretTop = 333.25
WoW.MarkSecret(secretTop, "top")
menu.GetTop = function() return secretTop end
GC.Area.Request(); measure()
eq(GC.Footprint().top, 279, "a frame with a secret side is skipped")
menu.GetTop = nil

-- Scale: a frame at scale 2 under a UIParent at 1 covers twice the units.
WoW.SetRect(menu, 1, 150, 13, 13, 2)             -- 2..28, 300..326
GC.Area.Request(); measure()
eq(GC.Footprint().top, 326, "a frame's scale is converted to UIParent units")

-- Glass off: the panels don't count.
GC.Settings.SetGlass(false)
measure()
eq(GC.Footprint().right, 430, "glass off: the window, not the panel")
GC.Settings.SetGlass(true)

-- The window unreadable: the last footprint stays, nothing is guessed.
local n = #heard
f._rect = nil
GC.Area.Request(); measure()
eq(#heard, n, "an unreadable window announces nothing")
check(GC.Footprint() ~= nil, "  and the last footprint stays")

eq(next(GC.failures), nil, "no failures")
done("test_area")
