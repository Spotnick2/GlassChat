-- The suite look trial: /gchat body shows Glass UI's damage meter body (a
-- band behind the tabs, the body under it, an opaque backing) in place of our
-- charcoal, and /gchat accent recolours the selected tab.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.now = 1000
local GC = loadAddon()
local P = GC.Skin._test.panels
local f = ChatFrame1
local p, e = P[f], P[ChatFrame1EditBox]
local function near(a, b) return math.abs(a - b) < 1e-6 end

eq(GC.db.body, "chat", "our own body by default")
check(p.own:IsShown() and not p.band.frame:IsShown() and not p.body.frame:IsShown(), "  our glass shown, Glass UI's hidden")
check(e.own:IsShown() and not e.body.frame:IsShown(), "  the edit box too")

check(GC.Settings.SetBody("clear"), "clear is a body")
check(not p.own:IsShown() and p.band.frame:IsShown() and p.body.frame:IsShown(), "clear: Glass UI's band and body shown")
check(not e.own:IsShown() and e.body.frame:IsShown(), "  the edit box's body too")
local B = GC.Skin.BODIES.clear
eq(p.body.g.tint._color[4], B.tint[4], "  the tint at clear's alpha")
eq(p.body.backing._color[4], B.backing, "  the backing at clear's opacity")
eq(p.band.backing._color[4], B.backing, "  the band's backing too")
eq(e.body.backing._color[4], B.backing, "  the edit box's backing too")

GC.Settings.SetBody("smoked")
eq(p.body.backing._color[4], GC.Skin.BODIES.smoked.backing, "smoked repaints live")

GC.Settings.SetBody("class")
local c = p.body.g.tint._color
local r = C_ClassColor.GetClassColor("WARRIOR")
check(near(c[1], r.r * 0.6) and near(c[2], r.g * 0.6), "class: the player's class colour, shaded")

check(not GC.Settings.SetBody("bogus"), "an unknown body is refused")
eq(GC.db.body, "class", "  and changes nothing")

-- Idle fades Glass UI's fills to idleAlpha of themselves.
GC.Settings.SetBody("clear")
for _ = 1, 1500 do WoW.now = WoW.now + 0.1; WoW.tick(0.1) end
check(near(p.body.backing._color[4], B.backing * GC.db.idleAlpha), "idle: the backing at idleAlpha of clear's")

GC.Settings.SetBody("chat")
check(p.own:IsShown() and not p.body.frame:IsShown(), "chat: our glass back")

-- The accent.
local tab = ChatFrame1Tab
local lit = GC.Skin._test.tabLit[tab]
check(GC.Settings.SetAccent("gold"), "gold is an accent")

eq(GC.Skin.ACCENT[1], 1, "  the shared accent is gold")
eq(lit.line._color[2], 0.82, "  the selected tab's underline is gold")
check(not GC.Settings.SetAccent("pink"), "an unknown accent is refused")
GC.Settings.SetAccent("ice")
eq(lit.line._color[1], 0.65, "ice: back to Pearl's")

eq(next(GC.failures), nil, "no failures")
done("test_body")
