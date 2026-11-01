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
check(lines[1] and lines[1]:find("1.60.1.70450", 1, true), "/gchat version names the measured build")

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

-- The build warning: at a real login on another build, in a dev build only
-- (owner: a player can't act on it). Never on /reload.
local realBuild = GetBuildInfo
GetBuildInfo = function() return "1.60.1", "99999", "Oct 9 2026", 16001 end
local function warned()   -- in the lines since the last call
    for _, l in ipairs(newChat()) do if l:find("differs from") then return true end end
    return false
end
newChat()
WoW.fire("PLAYER_ENTERING_WORLD", true, false)
check(warned(), "a dev build warns at login on another build")
WoW.fire("PLAYER_ENTERING_WORLD", false, true)
check(not warned(), "never on /reload")
WoW.addonVersion = "1.2.0"
WoW.fire("PLAYER_ENTERING_WORLD", true, false)
check(not warned(), "a release never warns")
SlashCmdList.GLASSCHAT("version")
local v = newChat()
check(v[1] and v[1]:find("99999", 1, true), "/gchat version still shows the client build")
WoW.addonVersion = "dev"
GetBuildInfo = realBuild

-- A protected call the client refused and blamed on us (#132 F2): counted,
-- said once, shown by /gchat failures. Another addon's, or a secret, isn't.
newChat()
WoW.fire("ADDON_ACTION_BLOCKED", "GlassChat", "SetPoint")
WoW.fire("ADDON_ACTION_BLOCKED", "GlassChat", "SetPoint")
WoW.fire("ADDON_ACTION_FORBIDDEN", "GlassChatSpamIgnore", "UNKNOWN()")
WoW.fire("ADDON_ACTION_BLOCKED", "SomeoneElse", "CastSpellByName")
WoW.fire("ADDON_ACTION_BLOCKED", "GlassChat", WoW.Secret("fn"))
WoW.fire("ADDON_ACTION_BLOCKED", WoW.Secret("addon"), "SetPoint")
eq(GC.failures["blocked SetPoint"], "refused by the client", "a block is a failure")
eq(GC.failureCounts["blocked SetPoint"], 2, "  counted")
eq(GC.failureCounts["forbidden UNKNOWN()"], 1, "the plugin's too, forbidden apart")
check(GC.failures["forbidden UNKNOWN()"]:find("GlassChatSpamIgnore", 1, true), "  naming the plugin")
eq(GC.failures["blocked CastSpellByName"], nil, "another addon's block isn't ours")
local said = 0
for _, l in ipairs(newChat()) do if l:find("the game refused SetPoint", 1, true) then said = said + 1 end end
eq(said, 1, "said once a session per function")
SlashCmdList.GLASSCHAT("failures")
check(chatHas("blocked SetPoint: refused by the client %(2 times%)"), "/gchat failures shows it with its count")
GC.API.Fail("test key", "first")
GC.API.Fail("test key", "second")
eq(GC.failures["test key"], "first", "a failure keeps its first message")
eq(GC.failureCounts["test key"], 2, "  and counts the rest")

done("test_boot")
