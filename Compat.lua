-- Compat.lua: the one place this addon touches client APIs that moved, may be
-- absent, or behave differently on WoW: Forever. Everything else calls through
-- GlassChat.API. Nothing is injected into _G.
--
-- Lifted in part from GlassRaidFrames' Compat.lua (same measured rules); only
-- what the chat uses is here. Lift more from there when needed.

GlassChat = GlassChat or {}
local GC = GlassChat
local API = {}
GC.API = API

-- The build the notes in docs/ were measured on. Bump only after re-measuring
-- in game; tests/test_toc.lua pins the same literal.
GC.MEASURED_ON_BUILD = "1.60.1.70205"

function API.Print(msg)
    print("|cff7fd4ffGlassChat|r " .. msg)
end

-- True for a Retail secret value. Such a value may be handed back to the
-- client (SetText, AddMessage) but never compared, concatenated, tostring'd,
-- pattern-matched or truth-tested in Lua.
function API.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

function API.ClientBuild()
    local version, build = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build)
end

-- RegisterEvent throws on an unknown name and returns false on a refusal.
-- Both count as failure, and every failure is reported: a silently missing
-- handler is the bug this exists to prevent.
GC.eventFailures = {}

local function report(name, why)
    table.insert(GC.eventFailures, name .. ": " .. why)
    API.Print("|cffff6060could not register|r " .. name .. " (" .. why .. ")")
end

function API.RegisterEvents(frame, events)
    for _, name in ipairs(events) do
        local ok, registered = pcall(frame.RegisterEvent, frame, name)
        if not ok then report(name, tostring(registered))
        elseif registered == false then report(name, "refused") end
    end
end

-- The one place failures are recorded (first error per key), read by
-- /gchat failures and the tests.
GC.failures = GC.failures or {}
function API.Fail(key, err)
    if GC.failures[key] == nil then GC.failures[key] = tostring(err) end
end

-- Class colour from the documented API (RAID_CLASS_COLORS is a FrameXML
-- table the dump cannot confirm). Returns r, g, b or nil.
function API.ClassColor(classFile)
    if API.IsSecret(classFile) then return nil end   -- before ANY test of it
    if not (classFile and C_ClassColor and C_ClassColor.GetClassColor) then return nil end
    local c = C_ClassColor.GetClassColor(classFile)
    if c then return c.r, c.g, c.b end
    return nil
end
