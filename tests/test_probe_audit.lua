-- ChatProbe's audit procedure (/fp steps chat audit, #132 PR 4): walked end
-- to end on the real GlassChat and its plugin. Each measurement runs and is
-- recorded, its checks pass where the stub can answer, the probe's own tab
-- catches its lines, and the owner's settings come back at the end, also
-- after a stopped run (/fp chat auditrestore). It never writes its findings
-- to chat. Needs a ForeverProbe checkout ($FOREVERPROBE, else ..\ForeverProbe).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Beyond the shared stub, each in the 70532 dump.
local instance = "none"
rawset(_G, "GetInstanceInfo", function() return "Somewhere", instance end)
rawset(_G, "GetFramerate", function() return 58 end)
-- The host's screenshot queue shoots just after time()'s second changes; a
-- clock that moves on every read keeps the walk quick (test_probe_pearl).
local clock = 1759500000
rawset(_G, "time", function() clock = clock + 1; return clock end)
-- A new chat tab, as the client makes one (test_tabs' model).
function FCF_OpenNewWindow(name)
    for i = 4, 10 do
        local w = WoW.window(i)
        if w.name == "" then
            w.name, w.shown, w.docked = name, true, i
            WoW.makeChatFrames(i)
            return _G["ChatFrame" .. i]
        end
    end
end
WoW.guildRoster = { { name = "Guild Mate", level = 42, guid = "Player-1-0000000C" } }

-- The owner's own settings, which the procedure must put back.
-- They chose Never for the probe's lines (Codex on #135: the tab step clears it).
local GC = loadAddon({ db = { lines = 2000, routeNever = { ChatProbe = true } } })
GC.Tabs._test.loaded()   -- past the loading quiet, as minutes into a session
local FP = loadForeverProbe()
local S = FP.Steps
ChatProbeDB = nil
local ns = {}
for _, file in ipairs({ "ChatProbe.lua", "Audit.lua" }) do
    assert(loadfile("Tools/ChatProbe/" .. file))("ChatProbe", ns)
end
WoW.fire("ADDON_LOADED", "ChatProbe")
local function fp(msg) SlashCmdList.FOREVERPROBE(msg) end
local function settle() for _ = 1, 3 do WoW.tick(2) end end
local function logHas(pattern)
    for _, line in ipairs(ChatProbeDB.log) do if line:find(pattern, 1, true) then return true end end
    return false
end
local edit = ChatFrame1EditBox
-- Lines the probe writes are its own: the stack names it, as in game.
WoW.stack = "[Interface/AddOns/ChatProbe/Audit.lua]:1: in function <Interface/AddOns/ChatProbe/Audit.lua:1>\n"

fp("steps chat audit")
local rec = ForeverProbeDB.steps.records["ChatProbe/audit"]
local steps = FP.procedures["ChatProbe/audit"].steps
check(rec and rec.status == "active", "/fp steps chat audit starts the procedure")
eq(ChatProbeDB.audit.saved.lines, 2000, "the owner's scrollback is kept to put back")
eq(ChatProbeDB.audit.saved.timestamps, nil, "  their timestamps (unset)")
eq(ChatProbeDB.audit.saved.keep, nil, "  their kept chat (unset)")
eq(ChatProbeDB.audit.saved.icon, false, "  their spam icon")
eq(ChatProbeDB.audit.saved.route, "never", "  and their Never for the probe's lines")

-- Walk it as the owner would.
local NO_STUB_ANSWER = { [2] = true }   -- the stub's message frame doesn't model Blizzard's buffer
local seen, exited = {}, false
while rec.status == "active" do
    local i = rec.at
    local step = steps[i]
    if seen[i] then for _, l in ipairs(ChatProbeDB.log) do io.write(l, "\n") end; error("stuck at step " .. i .. ": " .. tostring(rec.results[i] and rec.results[i].lastError)) end
    seen[i] = true
    if step.reload == true then break end
    local t = step.text
    if step.auto then
        -- ran on arrival
    elseif step.run then S.Run()
    elseif step.ask then S.Answer(true)
    elseif step.event then WoW.fire(step.event)
    elseif step.reload == "exit" then
        exited = true
        S.Next()   -- the host resumes at the next step after the relog
    elseif step.wait then
        if t:find("unfinished whisper", 1, true) then
            edit._focused, edit._attrs = true, { chatType = "WHISPER" }
            WoW.activeBox = edit
            S.Poll()
            -- The whisper is sent a few steps on, closing the box: GlassChat opens
            -- no tab while one is being typed in (Tabs.lua, Codex on #26).
            WoW.activeBox, edit._focused = nil, false
        elseif t:find("dungeon", 1, true) then
            instance = "party"
            WoW.combat = true; S.Poll()
            WoW.combat = false; S.Poll()
            instance = "none"
        elseif t:find("other account", 1, true) then
            GC.db.settingsApplied = { ["Player-1-0000000B"] = 1760000099999 }
            S.Poll()
        else
            WoW.combat = true; S.Poll()
            WoW.combat = false; S.Poll()
        end
    else
        if t:find("Apply it", 1, true) then
            GC.db.layout = { id = 99, windows = {} }
            GC.charDB.layoutAnswered = 99
        end
        S.Next()
    end
    settle()
    if step.check and not NO_STUB_ANSWER[i] then
        eq(rec.results[i].check, "PASS", i .. ": " .. t:sub(1, 50))
        if rec.results[i].check ~= "PASS" then io.write("    " .. tostring(rec.results[i].checkDetail) .. "\n") end
    end
end
check(exited, "the walk went through the logout step")
check(steps[rec.at].reload == true, "the walk ends at the reload step")

-- What it measured.
local A = ChatProbeDB.audit
check(A.buffer and A.buffer.control and A.buffer.shrunk and A.buffer.noop, "15.9: the three buffer cases are recorded")
check(logHas("15.9 shrunk to 128 while full"), "  and logged")
check(A.hot and A.hot["lines 2000"] and A.hot["lines 5000"], "15.1: timed at the owner's scrollback and at 5000")
local hot = A.hot["lines 2000"]
eq(hot.n, hot.max, "  General was filled to its maximum before the timed lines")
check(type(hot.stamped) == "number" and type(hot.walk) == "number" and type(hot.source) == "number", "  every cost is a number")
eq(GC.Chat.Route, GC.Tabs.Route, "  and routing is back on afterwards")
check(GC.guildRosterRequested ~= nil or WoW.guildRosterRequested, "15.5: the roster was asked for")
check(logHas("15.5 ") and logHas("4th a level: true") and logHas("17th a player GUID: true"),
    "  its order logged by type: the level 4th, the GUID 17th")
check(not logHas("Guild Mate"), "  never the guildmate's name")
check(A.history and A.history.polls > 0, "15.10: combat polls recorded")
local tab
for i = 4, 10 do if WoW.window(i).name == "ChatProbe" then tab = _G["ChatFrame" .. i] end end
check(tab and tab:GetNumMessages() >= 2, "15.6: the probe's own tab caught its lines, before and after the logout")

-- The owner's settings are back.
eq(rawget(GC.db, "lines"), 2000, "their scrollback")
eq(rawget(GC.db, "timestamps"), nil, "  timestamps unset again")
eq(rawget(GC.db, "keep"), nil, "  kept chat unset again")
eq(GC.Spam.db.icon, false, "  their spam icon")
eq(GC.db.routeNever.ChatProbe, true, "  their Never for the probe's lines")
eq(GC.db.routes.ChatProbe, nil, "  and no Always in its place")
check(not GC.Tabs.IsRouted("ChatProbe"), "  so the probe's lines stay in the main chat")
eq(ChatProbeDB.audit.saved, nil, "  and the kept values cleared")
eq(next(GC.failures), nil, "no GlassChat failures along the way")

-- A stopped run: /fp chat auditrestore puts the values back, once.
GC.Tabs.SetRule("ChatProbe", "always")   -- this time they chose Always
fp("steps chat audit")
S.Run(); settle()   -- the buffer step
fp("steps stop")
GC.Settings.SetLines(3000)
GC.Tabs.SetRule("ChatProbe", "session")  -- as the tab step does, had the run got there
fp("chat auditrestore")
eq(rawget(GC.db, "lines"), 2000, "/fp chat auditrestore puts a stopped run's scrollback back")
eq(GC.db.routes.ChatProbe, true, "  and their Always for the probe's lines")
fp("chat auditrestore")
check(logHas("15 nothing to put back"), "  a second restore has nothing to do")

-- Its findings never go to chat (the stimulus lines do, on purpose).
local chat = 0
for _, line in ipairs(WoW.chat) do if line:find("^15") then chat = chat + 1 end end
eq(chat, 0, "the probe's own lines never go to chat")

done("test_probe_audit")
