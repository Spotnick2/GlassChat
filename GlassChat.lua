-- GlassChat.lua: bootstrap, saved settings and the /gchat command.
--
-- Milestone 0: the skeleton only. Class colours, copy and search arrive in
-- later milestones, once the chat probe has measured what they rely on
-- (docs/PLAN.md).

local ADDON = ...
GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local say = API.Print

local DEFAULTS = {}

-- Read settings, fill missing keys. Nothing may REQUIRE a value to have
-- survived: SavedVariables were broken on builds before 70009.
local function ensureDefaults()
    if type(GlassChatDB) ~= "table" then GlassChatDB = {} end
    local db = GlassChatDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

local function failures()
    local any = false
    for key, err in pairs(GC.failures) do
        any = true
        say(key .. ": " .. err)
    end
    for _, line in ipairs(GC.eventFailures) do
        any = true
        say("event " .. line)
    end
    if not any then say("no failures recorded") end
end

local function slash(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "failures" then
        failures()
    elseif cmd == "version" then
        say("client " .. API.ClientBuild() .. ", measured on " .. GC.MEASURED_ON_BUILD)
    else
        say("/gchat failures - what failed to build or register")
        say("/gchat version - client build vs the measured one")
    end
end

SLASH_GLASSCHAT1 = "/gchat"
SLASH_GLASSCHAT2 = "/glasschat"
SlashCmdList.GLASSCHAT = slash

local boot = CreateFrame("Frame")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        GC.db = ensureDefaults()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- arg1 = isInitialLogin: warn at a real login, never on /reload.
        if arg1 and API.ClientBuild() ~= GC.MEASURED_ON_BUILD then
            say("client build " .. API.ClientBuild() .. " differs from the one this addon was measured on ("
                .. GC.MEASURED_ON_BUILD .. "). Things may misbehave until it is re-checked.")
        end
    end
end)
API.RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_ENTERING_WORLD" })

GC._test = { ensureDefaults = ensureDefaults }
