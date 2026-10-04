-- Bootstrap: saved settings, the login build warning and the /gchat command.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Missing SavedVariables (the pre-70009 client lost them) still load.
GlassChatDB = nil
local GC = loadAddon()
eq(type(GlassChatDB), "table", "missing saved variables become a table")
eq(GC.db, GlassChatDB, "the addon keeps the saved table")
check(not chatHas("differs from"), "no build warning on the measured build")

-- Only what the player set is saved; the rest follows the shipped defaults.
eq(rawget(GlassChatDB, "alpha"), nil, "an untouched setting isn't saved")
eq(GC.db.alpha, GC._test.DEFAULTS.alpha, "it reads the shipped default")
GC.Settings.SetAlpha(0.8)
eq(rawget(GlassChatDB, "alpha"), 0.8, "a setting the player changed is saved")
-- A saved copy of a default (the first version saved them all) is dropped.
GlassChatDB = { lines = 1000, alpha = 0.55 }
GC._test.ensureDefaults()
eq(rawget(GlassChatDB, "lines"), nil, "a saved value equal to the default is dropped")
eq(rawget(GlassChatDB, "alpha"), 0.55, "a real choice is kept")
GlassChatDB = { look = { rim = GC.Skin.LOOK.rim, top = 0.9 } }
GC._test.ensureDefaults()
eq(GlassChatDB.look.rim, nil, "a tuned value equal to the shipped look is dropped")
eq(GlassChatDB.look.top, 0.9, "a real tuning is kept")
check(GC.Glass ~= nil, "the glass material loaded into the namespace")

-- /gchat
newChat()
SlashCmdList.GLASSCHAT("")
check(#newChat() >= 2, "/gchat prints help")
SlashCmdList.GLASSCHAT("failures")
local lines = newChat()
check(lines[1] and lines[1]:find("no failures"), "/gchat failures reports none")
SlashCmdList.GLASSCHAT("version")
lines = newChat()
check(lines[1] and lines[1]:find("1.60.1.70205", 1, true), "/gchat version names the measured build")

-- A failure recorded anywhere shows up in /gchat failures.
GC.API.Fail("demo", "boom")
SlashCmdList.GLASSCHAT("failures")
lines = newChat()
check(lines[1] and lines[1]:find("demo: boom", 1, true), "/gchat failures lists recorded failures")

-- /rl reloads through C_UI.Reload (documented without restrictions).
local reloads = 0
rawset(_G, "C_UI", { Reload = function() reloads = reloads + 1 end })
SlashCmdList.GLASSCHATRELOAD("")
eq(reloads, 1, "/rl reloads the UI")
eq(SLASH_GLASSCHATRELOAD1, "/rl", "on /rl")

done("test_boot")
