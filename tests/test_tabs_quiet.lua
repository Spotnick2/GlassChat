-- Smart tabs: the quiet while the game loads always ends, even when no
-- loading screen of a login or /reload is ever seen (review of #42).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- The only PLAYER_ENTERING_WORLD reads as zoning: nothing starts a quiet of LOAD_QUIET.
local GC = loadAddon({ initialLogin = false })
local Tabs = GC.Tabs
check(Tabs.Loading(), "quiet from the start")
WoW.flushTimers(Tabs.LOAD_QUIET)
check(Tabs.Loading(), "no loading screen seen: still quiet after LOAD_QUIET")
WoW.flushTimers(Tabs.LOAD_BACKSTOP)
check(not Tabs.Loading(), "but the backstop ends it")

eq(next(GC.failures), nil, "nothing failed")
done("test_tabs_quiet")
