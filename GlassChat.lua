-- GlassChat.lua: bootstrap, saved settings, the settings helpers and the
-- /gchat command. Loads last: every module is defined by now.

local ADDON = ...
GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local say = API.Print

-- Account-wide (GlassChatDB): the look and behaviour, the same on every
-- character (owner: no per-character setup). Per character
-- (GlassChatCharDB): only what you sent.
local DEFAULTS = {
    glass = true,          -- the glass panels (off: Blizzard's own background)
    alpha = 0.65,          -- panel darkness, 0..1 (charcoal; 0.45 and 0.55 let the scene compete with the text)
    lines = 1000,          -- scrollback per chat window (stock: 128)
    classColors = true,    -- keep chatClassColorOverride at "0"
    plainArrows = true,    -- Up/Down cycle what you sent (stock: Alt+Up/Down)
    history = 100,         -- sent lines kept (stock: 32)
    tabSize = 14,          -- tab name font size (stock GameFontNormalSmall, ~10)
    shortChannels = true,  -- "[1. General - The Barrens]" -> "[1. General]"
}

-- Read settings, fill missing keys. Nothing may REQUIRE a value to have
-- survived: SavedVariables were broken on builds before 70009.
local function ensureDefaults()
    if type(GlassChatDB) ~= "table" then GlassChatDB = {} end
    local db = GlassChatDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    if type(GlassChatCharDB) ~= "table" then GlassChatCharDB = {} end
    return db, GlassChatCharDB
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- Every setting goes through here: /gchat now, an options panel later.
local Settings = {}
GC.Settings = Settings

function Settings.SetGlass(on)
    GC.db.glass = on and true or false
    GC.Skin.Refresh()
end

function Settings.SetAlpha(a)
    GC.db.alpha = clamp(a, 0, 1)
    GC.Skin.Refresh()
end

function Settings.SetLines(n)
    GC.db.lines = clamp(math.floor(n), GC.Chat.MIN_LINES, GC.Chat.MAX_LINES)
    GC.Chat.Scan()
end

function Settings.SetClassColors(on)
    GC.db.classColors = on and true or false
    GC.Chat.ApplyClassColors()
end

function Settings.SetPlainArrows(on)
    GC.db.plainArrows = on and true or false
    GC.Chat.Scan()
end

function Settings.SetTabSize(n)
    GC.db.tabSize = clamp(math.floor(n), 10, 20)
    GC.Skin.Refresh()
end

-- The window surface (Skin.LOOK keys). nil value: back to the shipped one.
function Settings.SetLook(key, v)
    if type(GC.db.look) ~= "table" then GC.db.look = {} end
    if v ~= nil then v = clamp(v, 0, GC.Skin.LOOK_MAX[key] or 1) end
    GC.db.look[key] = v
    GC.Skin.Refresh()
end

function Settings.ResetLook()
    GC.db.look = {}
    GC.Skin.Refresh()
end

function Settings.SetShortChannels(on)
    GC.db.shortChannels = on and true or false
end

function Settings.SetHistory(n)
    GC.db.history = clamp(math.floor(n), GC.History.MIN, GC.History.MAX)
    GC.Chat.Scan()
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

local function onOff(v) return v and "on" or "off" end

local function help()
    local db = GC.db
    say("/gchat glass on|off - the glass panels (" .. onOff(db.glass) .. ")")
    say("/gchat alpha 0-1 - panel darkness (" .. db.alpha .. ")")
    say("/gchat lines N - lines kept per chat window (" .. db.lines .. ")")
    say("/gchat colors on|off - class-coloured names (" .. onOff(db.classColors) .. ")")
    say("/gchat arrows on|off - Up/Down recall what you sent (" .. onOff(db.plainArrows) .. ")")
    say("/gchat history N - sent lines kept (" .. db.history .. ")")
    say("/gchat channels on|off - drop the zone from channel names (" .. onOff(db.shortChannels) .. ")")
    say("/gchat tabsize N - tab name size, fits fully after /reload (" .. db.tabSize .. ")")
    say("/gchat tune - adjust the panel's edge, shadow and sheen live")
    say("/gchat failures - what failed to build or register")
    say("/gchat version - client build vs the measured one")
end

-- "on"/"off" -> true/false; anything else -> nil.
local function flag(arg)
    if arg == "on" then return true elseif arg == "off" then return false end
end

local TOGGLES = { glass = Settings.SetGlass, colors = Settings.SetClassColors, arrows = Settings.SetPlainArrows,
    channels = Settings.SetShortChannels }
local NUMBERS = { alpha = Settings.SetAlpha, lines = Settings.SetLines, history = Settings.SetHistory,
    tabsize = Settings.SetTabSize }

local LOOK_ORDER = { "shadow", "rim", "dark", "grain", "top", "glow", "glowh", "bottom" }

local function tuneCmd(arg)
    local key, value = arg:match("^(%S*)%s*(%S*)$")
    if key == "reset" then
        Settings.ResetLook()
        say("tune: back to the shipped look")
        return
    end
    if GC.Skin.LOOK[key] ~= nil then
        local v = tonumber(value)
        if v then
            Settings.SetLook(key, v)
            say("tune " .. key .. " " .. GC.Skin.Look(key))
            return
        end
    end
    for _, k in ipairs(LOOK_ORDER) do
        say(string.format("/gchat tune %s <0-%s> (%s, shipped %s)", k, tostring(GC.Skin.LOOK_MAX[k] or 1),
            tostring(GC.Skin.Look(k)), tostring(GC.Skin.LOOK[k])))
    end
    say("/gchat tune reset - back to the shipped look")
end

local function slash(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "tune" then
        tuneCmd(arg)
    elseif cmd == "failures" then
        failures()
    elseif cmd == "version" then
        say("client " .. API.ClientBuild() .. ", measured on " .. GC.MEASURED_ON_BUILD)
    elseif TOGGLES[cmd] then
        local v = flag(arg)
        if v == nil then say("/gchat " .. cmd .. " on|off"); return end
        TOGGLES[cmd](v)
        say(cmd .. " " .. onOff(v))
    elseif NUMBERS[cmd] then
        local v = tonumber(arg)
        if not v then say("/gchat " .. cmd .. " <number>"); return end
        NUMBERS[cmd](v)
        say(cmd .. " " .. tostring(GC.db[cmd == "tabsize" and "tabSize" or cmd]))
    else
        help()
    end
end

SLASH_GLASSCHAT1 = "/gchat"
SLASH_GLASSCHAT2 = "/glasschat"
SlashCmdList.GLASSCHAT = slash

local boot = CreateFrame("Frame")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        GC.db, GC.charDB = ensureDefaults()
        -- As early as possible, so the login lines already get the longer
        -- scrollback; PLAYER_LOGIN and the chat-window events re-apply.
        local ok, err = pcall(GC.Chat.Start)
        if not ok then API.Fail("start", err) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- arg1 = isInitialLogin: warn at a real login, never on /reload.
        if arg1 and API.ClientBuild() ~= GC.MEASURED_ON_BUILD then
            say("client build " .. API.ClientBuild() .. " differs from the one this addon was measured on ("
                .. GC.MEASURED_ON_BUILD .. "). Things may misbehave until it is re-checked.")
        end
    end
end)
API.RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_ENTERING_WORLD" })

GC._test = { ensureDefaults = ensureDefaults, DEFAULTS = DEFAULTS }
