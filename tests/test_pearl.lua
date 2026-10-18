-- Pearl's reading surface and shell must stay independent on live refresh,
-- including the two custom pills that can be created after login.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GC = loadAddon({ db = { alpha = 0.55, look = { top = 0.27 } } })
local P = GC.Skin._test.panels
local p, e = P[ChatFrame1], P[ChatFrame1EditBox]
eq(GC.Glass.preset, "pearl", "the shared r11 preset is selected")
check(GC.Glass.STYLE.thinRim, "Pearl supplies the thin rim")
eq(p.g.tint._color[4], 0.55, "a saved reading opacity survives")
eq(p.edge.top._color[4], 0.27, "a saved edge override survives")
eq(p.header._color[4], 0.68, "the new shell setting gets its default")
check(not p.g.wash:IsShown() and not e.g.wash:IsShown(), "no wash over chat or typed words")

-- Adjacent fills: no full-panel tint behind the lighter header, and no
-- header under the reading area. Both use the original panel mask.
local bodyTop, bodyBottom = p.g.tint._points[1], p.g.tint._points[2]
local headerTop, headerBottom = p.header._points[1], p.header._points[2]
eq(bodyTop[1], "TOPLEFT", "body has its own upper boundary")
eq(headerBottom[3], "TOPRIGHT", "header ends relative to the panel top")
eq(bodyTop[2], p.panel, "body boundary follows the panel")
eq(headerBottom[2], p.panel, "header boundary follows the same panel")
eq(bodyTop[5], headerBottom[5], "the two fills meet without overlap")
check(bodyTop[5] < 0, "header occupies a real strip above the body")
eq(headerTop[1], "TOPLEFT", "header begins at the panel top")
eq(headerTop[5], 0, "no uncovered strip above the header")
eq(bodyBottom[1], "BOTTOMRIGHT", "body extends to the panel bottom")
eq(bodyBottom[5], 0, "no uncovered strip below the body")
eq(p.header._masks[1], p.g.mask, "header uses the same rounded mask")

local standard = GC.Buttons._test.pills
local alert = GC.Alerts._test.button()
local five = {
    standard[ChatFrameMenuButton].g, standard[ChatFrameChannelButton].g,
    standard[QuickJoinToastButton].g, alert.pill.glassPill,
}
local function surfaces(reading, shell)
    eq(p.g.tint._color[4], reading, "reading opacity")
    eq(e.g.tint._color[4], reading, "edit opacity")
    eq(p.header._color[4], shell, "header opacity")
    for i, g in ipairs(five) do
        eq(g.tint._color[4], shell, "pill " .. i .. " shell opacity")
        eq(g.rim._vertex[2], GC.Skin.PEARL[2], "pill " .. i .. " Pearl rim")
        eq(g.grain._alpha, 0, "pill " .. i .. " clear glyph backing")
    end
end
GC.Settings.SetAlpha(1)
GC.Settings.SetShellAlpha(0)
surfaces(1, 0)
-- The opt-in fifth pill is created after the change, then refreshed again.
SlashCmdList.GLASSCHAT("spam icon on")
local spam = GC.SpamUI._test.button()
five[5] = spam.pill.glassPill
surfaces(1, 0)
GC.Settings.SetAlpha(0)
GC.Settings.SetShellAlpha(1)
surfaces(0, 1)
GC.Chat.Scan()
GC.Chat.Scan()
surfaces(0, 1)
eq(P[ChatFrame1].header, p.header, "scans reuse the header")
eq(#p.header._masks, 1, "scans do not accumulate masks")
alert._level = 30
GC.Chat.Scan()
eq(alert.pill:GetFrameLevel(), 29, "custom pills relevel under their symbols")

SlashCmdList.GLASSCHAT("shellalpha 0.61")
surfaces(0, 0.61)
check(chatHas("shellalpha 0%.61"), "command confirms the applied value")
SlashCmdList.GLASSCHAT("shellalpha nonsense")
eq(GC.db.shellAlpha, 0.61, "invalid input leaves the setting alone")
SlashCmdList.GLASSCHAT("shellalpha 9")
eq(GC.db.shellAlpha, 1, "upper clamp")
SlashCmdList.GLASSCHAT("shellalpha -2")
eq(GC.db.shellAlpha, 0, "lower clamp")
GC.Settings.SetShellAlpha(0.61)
check(GC.SettingsSync.Build(false):find("V\tcore\tshellAlpha\tn\t0%.61"), "shell setting is included in settings sync")

GC.Settings.SetGlass(false)
check(not p.panel:IsShown() and not e.panel:IsShown(), "glass off hides both surfaces with their hosts")
check(not alert.pill:IsShown() and not spam.pill:IsShown(), "glass off hides both custom pill surfaces")
eq(ChatFrameMenuButton._normal._alpha, 1, "stock menu art is restored")
GC.Settings.SetGlass(true)
check(p.panel:IsShown() and alert.pill:IsShown() and spam.pill:IsShown(), "glass on restores the surfaces")
surfaces(0, 0.61)
eq(next(GC.failures), nil, "no handler failed")
done("test_pearl")
