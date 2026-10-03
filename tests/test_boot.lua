-- Bootstrap: saved settings, the login build warning and the /gchat command.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Missing SavedVariables (the pre-70009 client lost them) still load.
GlassChatDB = nil
local GC = loadAddon()
eq(type(GlassChatDB), "table", "missing saved variables become a table")
eq(GC.db, GlassChatDB, "the addon keeps the saved table")
check(not chatHas("differs from"), "no build warning on the measured build")
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

done("test_boot")
