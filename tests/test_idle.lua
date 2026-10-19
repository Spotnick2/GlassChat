-- Idle (#108): with every line faded and nothing else going on, the window's
-- fills fade to db.idleAlpha, and come back for a new line, the mouse, a
-- scroll, typing or a window whose lines never fade. The rim stays.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.now = 1000
local GC = loadAddon()
local P = GC.Skin._test.panels
local f = ChatFrame1
local p, e = P[f], P[ChatFrame1EditBox]
local function reading() return p.g.tint._color[4] end
-- Time passes in rendered frames of 0.1 s.
local function run(secs)
    for _ = 1, math.floor(secs * 10 + 0.5) do
        WoW.now = WoW.now + 0.1
        WoW.tick(0.1)
    end
end
local function near(a, b) return math.abs(a - b) < 1e-6 end

eq(GC.db.idleAlpha, 0.2, "the idle opacity's default")
eq(reading(), 0.82, "awake at login: the reading opacity")
local rim = p.g.rim._alpha

run(100)
eq(reading(), 0.82, "a line still readable (120 s + 3 s fade) keeps it awake")
run(24)
local mid = reading()
check(mid < 0.82 and mid > 0.2, "past the lines' fade, it fades (" .. mid .. ")")
run(3)
check(near(reading(), 0.2), "idle: the reading area at the idle opacity")
check(near(p.header._color[4], 0.2), "  the tab strip too")
check(near(e.g.tint._color[4], 0.2), "  and the edit box")
eq(p.g.rim._alpha, rim, "  the rim stays: the glass is still there")

f:AddMessage("a new line")
run(0.5)
eq(reading(), 0.82, "a new line wakes it")
eq(p.header._color[4], 0.68, "  the tab strip back to the shell opacity")
eq(e.g.tint._color[4], 0.82, "  and the edit box")

run(130)
check(near(reading(), 0.2), "idle again once that line faded")
FCF_FadeInChatFrame(f)
run(0.5)
eq(reading(), 0.82, "the mouse over the window (Blizzard's fade in) wakes it")
run(200)
eq(reading(), 0.82, "  and keeps it awake while it stays")
FCF_FadeOutChatFrame(f)
run(3)
check(near(reading(), 0.2), "the mouse gone (fade out), old lines: idle")

f:ResetAllFadeTimes()
run(0.5)
eq(reading(), 0.82, "a scroll shows the lines again (ResetAllFadeTimes): awake")
run(130)
check(near(reading(), 0.2), "  until they fade again")

f._atBottom = false
run(0.5)
eq(reading(), 0.82, "scrolled up: awake")
f._atBottom = nil
run(3)
check(near(reading(), 0.2), "  back at the bottom with old lines: idle")

ChatFrame1EditBox:SetFocus()
run(0.5)
eq(reading(), 0.82, "typing: awake")
ChatFrame1EditBox:ClearFocus()
run(3)
check(near(reading(), 0.2), "  done typing: idle")

f._fading = false
run(0.5)
eq(reading(), 0.82, "lines that never fade: never idle")
f._fading = nil
run(3)

-- The setting.
GC.Settings.SetIdleAlpha(0.05)
check(near(reading(), 0.05), "a new idle opacity applies at once while idle")
SlashCmdList.GLASSCHAT("idle 1")
eq(GC.db.idleAlpha, 1, "/gchat idle 1")
eq(reading(), 0.82, "  an idle opacity above the reading one never darkens it: never fades")
eq(p.header._color[4], 0.68, "  nor the tab strip")
GC.Settings.SetIdleAlpha(0.2)
check(near(reading(), 0.2), "back to 0.2")

-- Glass off and on: nothing breaks, the stock look has no panel to fade.
GC.Settings.SetGlass(false)
run(1)
GC.Settings.SetGlass(true)
run(1)
eq(next(GC.failures), nil, "no failures")

-- A failure leaves every window awake, and the driver stops.
rawset(f, "GetFading", function() error("boom") end)
run(0.5)
check(GC.failures.idle and GC.failures.idle:find("boom", 1, true), "a failure is recorded")
eq(reading(), 0.82, "  and the window is awake again, for good")
rawset(f, "GetFading", nil)
run(130)
eq(reading(), 0.82, "  it no longer fades")

done("test_idle")
