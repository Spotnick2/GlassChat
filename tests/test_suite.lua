-- Following Glass UI's suite look (#121): the body and the accent are the
-- suite's while following, live through LookChanged; a /gchat body or
-- accent is an override then; a saved /gchat alpha is its own backing; the
-- body numbers are Glass UI's; anything wrong on Glass UI's side falls back
-- to our own look.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- A fake Glass UI, its Body marked (backing 0.40 / 0.90) to tell it from our copy.
local reports = {}
local theme = { name = "pearl", preset = "pearl" }
local look = { tint = "clear", hover = "glow", press = "flash", emptySlots = "frosted", accent = "gold" }
local BODY = {
    clear  = { tint = { 0.13, 0.16, 0.22, 0.24 }, wash = 1, backing = { 0.04, 0.05, 0.07, 0.40 } },
    smoked = { tint = { 0.05, 0.06, 0.08, 0.62 }, wash = 0.7, backing = { 0.04, 0.05, 0.07, 0.90 } },
    class  = { classShade = 0.6, wash = 1, backing = { 0.04, 0.05, 0.07, 0.40 } },
}
local ACCENT = { gold = { 1, 0.82, 0 }, ice = { 0.65, 0.835, 0.905 } }
local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end
local Fake = {
    API = 1,
    Theme = function() return theme and copy(theme) end,
    Report = function(_, state) reports[#reports + 1] = state end,
    Look = function() return copy(look) end,
    Body = function(tint) return copy(BODY[tint or look.tint]) end,
    Accent = function(name) return copy(ACCENT[name or look.accent]) end,
}
rawset(_G, "GlassUI", { Suite = Fake })

local GC = loadAddon()
local S = GC.Suite
local P = GC.Skin._test.panels
local p = P[ChatFrame1]
local lit = GC.Skin._test.tabLit[ChatFrame1Tab]
local function last() return reports[#reports] end
local function backing() return p.body.backing._color[4] end
local function slash(s) SlashCmdList.GLASSCHAT(s) end
local function lookChanged(t)
    for k, v in pairs(t) do look[k] = v end
    WoW.callbacks["GlassUI.Suite.LookChanged"](nil, copy(look))
end

check(S.Following(), "following when Glass UI says so")
eq(S.Tint(), "clear", "  the suite's tint")
check(p.body.frame:IsShown() and not p.own:IsShown(), "  Glass UI's body shown")
eq(backing(), 0.40, "  with Glass UI's numbers, not our copy")
eq(lit.line._color[2], 0.82, "  the accent is the suite's gold")
local r = last()
eq(r.api, 1, "reported: api 1")
eq(r.built, "pearl", "  built Pearl")
eq(r.look.tint, "clear", "  the tint shown")
eq(r.look.accent, "gold", "  the accent shown")
eq(next(r.own), nil, "  nothing of its own")

-- Our own saved body and accent are kept and unused while following.
GC.db.body, GC.db.accent = "smoked", "ice"
GC.Skin.Refresh()
eq(backing(), 0.40, "a saved body of our own doesn't count while following")

-- Live.
lookChanged({ tint = "smoked", accent = "ice" })
eq(backing(), 0.90, "LookChanged: the new tint at once")
eq(lit.line._color[1], 0.65, "  and the new accent")
eq(last().look.tint, "smoked", "  reported")

-- The options page while following (#127): "Glass UI's" first, selected
-- while there's no override; a body of its own is the override; Open Glass UI.
local opened = false
Fake.Open = function() opened = true end
GC.Options.lookPage.frame:Show()
local radios = GC.Options._test.body
eq(radios[1].text:GetText(), "Glass UI's", "options: Glass UI's choice first")
check(radios[1]:GetChecked(), "  selected with no override")
radios[5]._scripts.OnClick(radios[5])
eq(GC.db.suiteOwn.tint, "chat", "  Charcoal is an override")
check(radios[5]:GetChecked() and not radios[1]:GetChecked(), "  and shows")
radios[1]._scripts.OnClick(radios[1])
eq(rawget(GC.db, "suiteOwn"), nil, "  Glass UI's clears it")
GC.Options._test.openSuite._scripts.OnClick(GC.Options._test.openSuite)
check(opened, "  Open Glass UI opens Glass UI's page")
eq(type(last().options), "function", "the report carries our options opener")

-- An override.
slash("body chat")
check(p.own:IsShown() and not p.body.frame:IsShown(), "/gchat body chat while following: our charcoal")
eq(GC.db.suiteOwn.tint, "chat", "  kept as an override")
eq(last().own.tint, true, "  reported as its own")
lookChanged({ tint = "class" })
check(p.own:IsShown(), "  the suite's change doesn't touch it")
slash("body suite")
eq(S.Tint(), "class", "/gchat body suite: the suite's again")
eq(rawget(GC.db, "suiteOwn"), nil, "  the override gone")
slash("accent gold")
eq(lit.line._color[2], 0.82, "an accent override")
slash("accent suite")
eq(lit.line._color[1], 0.65, "  and back to the suite's")
slash("body pink")
eq(S.Tint(), "class", "an unknown body changes nothing")

-- Its own backing.
lookChanged({ tint = "clear" })
GC.Settings.SetAlpha(0.9)
eq(backing(), 0.9, "a saved alpha is the backing's opacity")
eq(last().own.backing, true, "  reported as its own backing")
GC.db.alpha = nil
GC.Skin.Refresh()
eq(backing(), 0.40, "  without one, the body's")

-- An explicit alpha equal to the default is still the backing, after a
-- reload's pruning too (Codex on #124).
GC.Settings.SetAlpha(GC.DEFAULTS.alpha)
GC._test.ensureDefaults()
GC.Skin.Refresh()
eq(backing(), GC.DEFAULTS.alpha, "an explicit default alpha survives a reload's pruning")
eq(last().own.backing, true, "  still its own backing")
slash("alpha reset")
eq(rawget(GC.db, "alpha"), nil, "/gchat alpha reset: unset")
eq(backing(), 0.40, "  the body's backing again")
eq(last().own.backing, nil, "  reported as the body's")

-- Settings sync: an explicit default alpha travels as a value, and a reset
-- (a D, or an undo to unset) clears before the repaint and the report.
local SS = GC.SettingsSync
local from, sid = { guid = "Player-1-0000000B", name = "Karuzo Memphisto" }, 1760000000000
local function receive(...)
    sid = sid + 1
    SS.Receive(table.concat({ "ST1", ... }, "\n"), from, tostring(sid))
end
GC.Settings.SetAlpha(GC.DEFAULTS.alpha)
check(SS.Build():find("V\tcore\talpha\tn\t", 1, false) ~= nil, "an explicit default alpha is sent as a value")
slash("alpha reset")
receive("V\tcore\talpha\tn\t" .. GC.DEFAULTS.alpha)
eq(rawget(GC.db, "alpha"), GC.DEFAULTS.alpha, "  and received over an unset one")
GC.Settings.SetAlpha(0.9)
receive("D\tcore\talpha")
eq(rawget(GC.db, "alpha"), nil, "a received D unsets it")
eq(backing(), 0.40, "  the repaint after the clear: the body's backing")
eq(last().own.backing, nil, "  and the report too")
receive("V\tcore\talpha\tn\t0.9")
eq(backing(), 0.9, "a received alpha over an unset one")
slash("settings undo")
eq(rawget(GC.db, "alpha"), nil, "undo: unset again")
eq(backing(), 0.40, "  repainted at the body's backing")
eq(last().own.backing, nil, "  and reported")

-- Junk from Glass UI: our copy.
Fake.Body = function() return { backing = "dark" } end
lookChanged({ tint = "smoked" })
eq(backing(), GC.Skin.BODIES.smoked.backing, "a malformed Body falls back to our copy")
Fake.Body = function(tint) return copy(BODY[tint or look.tint]) end

-- Not following: our own settings again (a new session); an override is kept, unused.
slash("body smoked")
S._test.reset()
theme = nil
GC.db.body, GC.db.accent = "chat", "ice"
S.Start()
check(not S.Following(), "not following when Glass UI says no")
check(p.own:IsShown(), "  our charcoal, the kept override unused")
eq(GC.db.suiteOwn.tint, "smoked", "  the override still saved")
eq(last().built, nil, "  reported as its own look")
GC.Settings.SetBody("smoked")
eq(backing(), 0.90, "  our body, with Glass UI's numbers")
GC.Settings.SetBody("chat")

-- Theme throwing, or a Suite of another API: as if absent.
S._test.reset()
Fake.Theme = function() error("boom") end
theme = { name = "pearl", preset = "pearl" }
S.Start()
check(not S.Following(), "Theme throwing: not following")
S._test.reset()
Fake.Theme = function() return copy(theme) end
Fake.API = 2
local n = #reports
S.Start()
check(not S.Following(), "API 2: absent")
eq(#reports, n, "  and nothing reported")

eq(next(GC.failures), nil, "no failures")
done("test_suite")
