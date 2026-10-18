-- ChatProbe's pearl procedure (/fp steps chat pearl, docs/PEARL-HANDOFF.md's
-- in-game checks): walked end to end on the real GlassChat and its plugin.
-- Each step sets what it says, its checks pass on the real settings, the
-- sample lines stay in General, and the owner's own values come back at the
-- end, also after a stopped run (/fp chat pearlrestore).
-- Needs a ForeverProbe checkout ($FOREVERPROBE, else ..\ForeverProbe).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Beyond the shared stub, each in the 70374 dump or Forever's FrameXML
-- (ChatTypeInfoConstants.lua, GlobalStrings).
rawset(_G, "ChatTypeInfo", { SAY = { r = 1, g = 1, b = 1, id = 1 }, GUILD = { r = 0.25, g = 1, b = 0.25, id = 4 },
    SYSTEM = { r = 1, g = 1, b = 0, id = 2 } })
rawset(_G, "CHAT_SAY_GET", "%s says: ")
rawset(_G, "GetInventoryItemLink", function(_, slot)
    if slot == 16 then return "|cff1eff00|Hitem:2488::::::::60:::::::|h[Gladius]|h|r" end
end)
rawset(_G, "GetInstanceInfo", function() return "Eastern Kingdoms", "none" end)
-- The host's screenshot queue shoots just after time()'s second changes, and
-- the stub has no Screenshot(): each shot fails at once, logged, as on a client
-- without one. A clock that moves on every read keeps the walk quick.
local clock = 1759500000
rawset(_G, "time", function() clock = clock + 1; return clock end)
rawset(_G, "C_ChatInfo", rawget(_G, "C_ChatInfo") or { InChatMessagingLockdown = function() return false end })

-- The owner's own look, which the procedure must put back.
local GC = loadAddon({ db = { alpha = 0.55, shellAlpha = 0.3, look = { top = 0.27 } } })
eq(GC.Spam.db.icon, false, "(the spam icon starts off, its default)")
local FP = loadForeverProbe()
local S = FP.Steps
ChatProbeDB = nil
local ns = {}
assert(loadfile("Tools/ChatProbe/ChatProbe.lua"))("ChatProbe", ns)
WoW.fire("ADDON_LOADED", "ChatProbe")
local function fp(msg) SlashCmdList.FOREVERPROBE(msg) end
local function settle() for _ = 1, 5 do WoW.tick(2) end end
local function logHas(pattern)
    for _, line in ipairs(ChatProbeDB.log) do if line:find(pattern, 1, true) then return true end end
    return false
end

fp("steps chat pearl")
local rec = ForeverProbeDB.steps.records["ChatProbe/pearl"]
local steps = FP.procedures["ChatProbe/pearl"].steps
check(rec and rec.status == "active", "/fp steps chat pearl starts the procedure")
eq(rec.results[1].check, "PASS", "1: LibGlass 11+ and the pearl preset, on arrival")
eq(ChatProbeDB.pearl.alpha, 0.55, "  the owner's reading opacity is kept to put back")
eq(ChatProbeDB.pearl.shellAlpha, 0.3, "  their shell opacity")
eq(ChatProbeDB.pearl.look.top, 0.27, "  their tune values")
eq(ChatProbeDB.pearl.icon, false, "  and their spam icon")

-- Walk it as the owner would: Run the buttons, Yes to the questions, Next
-- for the hand steps, a fight for the combat step.
local before = #(ChatFrame1._lines or {})
local seen = {}
while rec.status == "active" do
    local i = rec.at
    local step = steps[i]
    if seen[i] then for _, l in ipairs(ChatProbeDB.log) do io.write(l, "\n") end; error("stuck at step " .. i .. ": " .. tostring(rec.results[i] and rec.results[i].lastError)) end
    seen[i] = true
    if step.reload then break end
    if step.auto then
        -- ran on arrival
    elseif step.run then S.Run()
    elseif step.ask then S.Answer(true)
    elseif step.wait then
        WoW.combat = true; S.Poll()
        WoW.combat = false; S.Poll()
    else
        if step.text:find("Click the !", 1, true) then GC.Alerts.Open(); GC.SpamUI.Open() end
        S.Next()
    end
    settle()
    if step.check then
        eq(rec.results[i].check, "PASS", i .. ": " .. step.text:sub(1, 50))
        if rec.results[i].check ~= "PASS" then io.write("    " .. tostring(rec.results[i].checkDetail) .. "\n") end
    end
    if i == 3 then
        local lines = ChatFrame1._lines or {}
        eq(#lines - before, 7, "3: seven sample lines in General")
        local guild = lines[before + 2]
        check(guild and guild.m:find("Gladius", 1, true), "  with the player's own item link")
        eq(guild and guild.extra[7], "CHAT_MSG_GUILD", "  each with its chat event, as Blizzard's lines")
    end
    if i == 9 then
        check(GC.Alerts.unseen >= 3 and GC.Spam.unseen >= 3, "9: the ! and the spam icon have lines waiting")
    end
end
check(steps[rec.at].reload, "the walk ends at the reload step")
check(rec.results[2].detail ~= nil, "2: the comparison values were set")
check(logHas("14 your values are back"), "the second last step put the values back")
eq(GC.db.alpha, 0.55, "  the owner's reading opacity")
eq(GC.db.shellAlpha, 0.3, "  their shell opacity")
eq(GC.db.look.top, 0.27, "  their tune value")
eq(GC.db.glass, true, "  glass on")
eq(GC.Spam.db.icon, false, "  their spam icon")
eq(ChatProbeDB.pearl, nil, "  and the kept values are cleared")
eq(next(GC.failures), nil, "no GlassChat failures along the way")

-- A stopped run: /fp chat pearlrestore puts the values back, once.
fp("steps chat pearl")
rec = ForeverProbeDB.steps.records["ChatProbe/pearl"]
S.Run(); settle()
eq(GC.db.alpha, 0.82, "a new run sets the comparison values")
fp("steps stop")
fp("steps chat pearl")
eq(ChatProbeDB.pearl.alpha, 0.55, "a run after a stopped one keeps the first run's values, not 0.82")
fp("steps stop")
fp("chat pearlrestore")
eq(GC.db.alpha, 0.55, "/fp chat pearlrestore puts a stopped run's values back")
eq(GC.db.shellAlpha, 0.3, "  the shell too")
fp("chat pearlrestore")
check(logHas("14 nothing to put back"), "  a second restore has nothing to do")

-- The first step's check is real: an older library fails it.
GC.Glass.preset = "clear"
check(not (steps[1].check()), "a preset other than pearl fails step 1")
GC.Glass.preset = "pearl"
-- And a failure recorded along the way fails the failures step.
fp("steps chat pearl")
GC.failures["probe:test"] = "boom"
local ok, detail = steps[#steps - 2].check()
check(not ok and tostring(detail):find("probe:test", 1, true), "a new GlassChat failure fails the failures step")
GC.failures["probe:test"] = nil
fp("steps stop")
fp("chat pearlrestore")

local chat = 0
for _, line in ipairs(WoW.chat) do if line:find("^14 ") then chat = chat + 1 end end
eq(chat, 0, "the probe's own lines never go to chat")

done("test_probe_pearl")
