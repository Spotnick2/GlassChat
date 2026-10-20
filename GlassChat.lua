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
    alpha = 0.82,          -- reading area and edit box; saved user values still win
    shellAlpha = 0.68,     -- tab strip and pills, independently of reading opacity
    idleAlpha = 0.2,       -- the window's fills with nothing to read, near the material's own glass (#108)
    lines = 1000,          -- scrollback per chat window (stock: 128)
    classColors = true,    -- keep chatClassColorOverride at "0"
    plainArrows = true,    -- Up/Down cycle what you sent (stock: Alt+Up/Down)
    history = 100,         -- sent lines kept (stock: 32)
    tabSize = 14,          -- tab name font size (stock GameFontNormalSmall, ~10)
    shortChannels = true,  -- "[1. General - The Barrens]" -> "[1. General]"
    urls = true,           -- web addresses in chat become click-to-copy links
    timestamps = false,    -- HH:MM:SS on every line, addon output included (owner: off by default)
    levels = true,         -- "[60:Name]": a known player's level before their name (Prat's default)
    alerts = true,         -- a sound when chat mentions you or your words (#83)
    alertName = "first",   -- first / full / off: which of your names counts
    alertSound = "lfg",    -- lfg (LFG Bulletin Board's, owner's pick) / raid / ready / tell / off
    alertFlash = true,     -- blink the game in the taskbar on an alert
    whisperSound = true,   -- the tell sound on every whisper, as with Prat (stock: 5 min apart; #92)
    tabsCatch = true,      -- an open tab named after an addon catches its lines (#81)
    body = "clear",        -- the glass body: Glass UI's clear (owner's pick, #121), smoked, class, or chat (our charcoal)
    accent = "gold",       -- the selected tab and the strip icons: gold (Blizzard's, owner's pick, #121) or ice (Pearl's)
}
GC.DEFAULTS = DEFAULTS   -- read by settings sync, to reset a key to its default

-- Read settings. Only what the player SET is saved: everything else falls
-- through to DEFAULTS, so a changed default reaches everyone (the first
-- version copied every default into the saved table, which froze them:
-- measured, a new default opacity never showed). Saved keys still equal to
-- the default are dropped once, so they follow future defaults too.
-- Nothing may REQUIRE a value to have survived: SavedVariables were broken
-- on builds before 70009.
local function ensureDefaults()
    if type(GlassChatDB) ~= "table" then GlassChatDB = {} end
    local db = GlassChatDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == v then db[k] = nil end
    end
    if type(db.look) == "table" then
        for k, v in pairs(db.look) do
            if GC.Skin.LOOK[k] == v then db.look[k] = nil end
        end
    end
    setmetatable(db, { __index = DEFAULTS })
    GC.AccountSync.EnsureStore(db)   -- the account-wide store LibAccountSync-1.0 keeps its key in
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
    GC.Suite.Report()   -- over a Glass UI body, its own backing
end

function Settings.SetShellAlpha(a)
    GC.db.shellAlpha = clamp(a, 0, 1)
    GC.Skin.Refresh()
end

function Settings.SetIdleAlpha(a)
    GC.db.idleAlpha = clamp(a, 0, 1)
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

-- The body and the accent when not following Glass UI (#121; Suite.lua):
-- while following, /gchat sets an override there instead.
function Settings.SetBody(name)
    if name ~= "chat" and not GC.Skin.BODIES[name] then return false end
    GC.db.body = name
    GC.Suite.Changed()
    return true
end

function Settings.SetAccent(name)
    if not GC.Skin.ACCENTS[name] then return false end
    GC.db.accent = name
    GC.Suite.Changed()
    return true
end

function Settings.SetTimestamps(on)
    GC.db.timestamps = on and true or false
    GC.Chat.ApplyTimestamps()
end

-- Developer mode (owner): a dev build, by its version ("dev" from the deploy
-- script, or the packager's token not replaced); GlassChatDB.devMode
-- overrides it (true or false). In it, our own probes get their own tab at
-- once (Tabs.lua). Not exposed as a command yet.
function GC.IsDev()
    local forced = GC.db and rawget(GC.db, "devMode")
    if forced ~= nil then return forced == true end
    -- A version that can't be read is NOT dev (review of #36): fail closed, or
    -- every player of a release would let addons take tabs unasked.
    local v = API.AddOnVersion("GlassChat")
    return v ~= nil and (v == "dev" or v:find("@project%-version@") ~= nil)
end

-- Public: an addon asks for its own chat tab (smart tabs, #35). See Tabs.Request.
function GC.RequestTab(addonName) return GC.Tabs.Request(addonName) end

function Settings.SetUrls(on)
    GC.db.urls = on and true or false
end

function Settings.SetLevels(on)
    GC.db.levels = on and true or false
end

function Settings.SetAlerts(on)
    GC.db.alerts = on and true or false
    GC.Chat.Scan()   -- the button beside the chat
end

-- The choices are checked here too: settings sync calls the same setters.
function Settings.SetAlertName(v)
    if GC.Alerts.OneOf(GC.Alerts.NAME_MODES, v) then GC.db.alertName = v end
end

function Settings.SetAlertSound(v)
    if GC.Alerts.OneOf(GC.Alerts.SOUND_NAMES, v) then GC.db.alertSound = v end
end

function Settings.SetAlertFlash(on)
    GC.db.alertFlash = on and true or false
end

function Settings.SetWhisperSound(on)
    GC.db.whisperSound = on and true or false
end

function Settings.SetTabsCatch(on)
    GC.db.tabsCatch = on and true or false
end

function Settings.SetShortChannels(on)
    GC.db.shortChannels = on and true or false
end

function Settings.SetHistory(n)
    GC.db.history = clamp(math.floor(n), GC.History.MIN, GC.History.MAX)
    GC.History.Trim()
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

-- Plugins add their own /gchat subcommands (Spam & Ignore: mute, ignore...).
-- help: lines for /gchat's help.
local pluginSlash, pluginHelp = {}, {}
function GC.RegisterSlash(sub, fn, help)
    pluginSlash[sub] = fn
    for _, line in ipairs(help or {}) do pluginHelp[#pluginHelp + 1] = line end
end

local function help()
    local db = GC.db
    say("/gchat glass on/off - the glass panels (" .. onOff(db.glass) .. ")")
    say("/gchat alpha 0-1 - reading area and input darkness (" .. db.alpha .. ")")
    say("/gchat shellalpha 0-1 - tab strip and pills darkness (" .. db.shellAlpha .. ")")
    say("/gchat idle 0-1 - darkness with nothing to read, 1 = never fades (" .. db.idleAlpha .. ")")
    say("/gchat lines N - lines kept per chat window (" .. db.lines .. ")")
    say("/gchat colors on/off - class-coloured names (" .. onOff(db.classColors) .. ")")
    say("/gchat arrows on/off - Up/Down recall what you sent (" .. onOff(db.plainArrows) .. ")")
    say("/gchat history N - sent lines kept (" .. db.history .. ")")
    say("/gchat channels on/off - drop the zone from channel names (" .. onOff(db.shortChannels) .. ")")
    say("/gchat urls on/off - click a web address in chat to copy it (" .. onOff(db.urls) .. ")")
    say("/gchat levels on/off - a player's level before their name, once seen (" .. onOff(db.levels) .. ")")
    say("/gchat alert - a sound when chat mentions your name or your words (" .. onOff(db.alerts) .. ")")
    say("/gchat stamps on/off - a time on every line, addon output too (" .. onOff(db.timestamps) .. ")")
    say("/gchat body chat/clear/smoked/class - the glass body: ours, or Glass UI's (" .. GC.Suite.Tint() .. ")")
    say("/gchat accent ice/gold - the selected tab's colour (" .. GC.Suite.AccentName() .. ")")
    say("/gchat tabsize N - tab name size, fits fully after /reload (" .. db.tabSize .. ")")
    say("/gchat layout - save this character's chat windows for your other characters")
    say("/gchat tabs - chatty addons with their own tab (offered in chat)")
    say("/gchat focus [text] - freeze this window to search, filter, copy and export (or the magnifier)")
    say("/gchat focus from <Addon> - only that addon's lines (or click its [Name] in chat)")
    say("/gchat copy - this window's lines, selected for Ctrl+C (or the Copy button)")
    say("/gchat tune - adjust the panel's edge, shadow and sheen live")
    say("/gchat failures - what failed to build or register")
    say("/gchat version - client build vs the measured one")
    for _, line in ipairs(pluginHelp) do say(line) end
end

-- "on"/"off" -> true/false; anything else -> nil.
local function flag(arg)
    if arg == "on" then return true elseif arg == "off" then return false end
end

local TOGGLES = { glass = Settings.SetGlass, colors = Settings.SetClassColors, arrows = Settings.SetPlainArrows,
    channels = Settings.SetShortChannels, stamps = Settings.SetTimestamps, urls = Settings.SetUrls,
    levels = Settings.SetLevels }
local NUMBERS = { alpha = Settings.SetAlpha, shellalpha = Settings.SetShellAlpha, idle = Settings.SetIdleAlpha, lines = Settings.SetLines, history = Settings.SetHistory,
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
        if v and v == v then
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

-- /gchat body and /gchat accent: our own setting, or while following Glass
-- UI an override of the suite's ("suite" goes back to it).
local LOOK_CMD = { body = { key = "tint", set = Settings.SetBody, choices = "chat/clear/smoked/class" },
    accent = { key = "accent", set = Settings.SetAccent, choices = "ice/gold" } }
local function lookCmd(cmd, arg)
    local c, S = LOOK_CMD[cmd], GC.Suite
    local function now()
        local v = cmd == "body" and S.Tint() or S.AccentName()
        if not S.Following() then return v end
        return v .. (S.Own(c.key) and " (its own; \"suite\" follows Glass UI again)" or " (Glass UI's)")
    end
    if arg == "" then say(cmd .. " " .. now()); return end
    local ok
    if S.Following() then ok = S.SetOwn(c.key, arg) else ok = c.set(arg) end
    if ok then
        say(cmd .. " " .. now())
    else
        say("/gchat " .. cmd .. " " .. c.choices .. (S.Following() and "/suite" or ""))
    end
end

local function slash(msg, editBox)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    -- A plugin's subcommand gets the rest of the line as typed (case kept:
    -- names and phrases matter).
    if pluginSlash[cmd] then
        local raw = (msg or ""):match("^%s*%S+%s*(.-)%s*$") or ""
        pluginSlash[cmd](raw, editBox)
        return
    end
    if cmd == "tune" then
        tuneCmd(arg)
    elseif cmd == "body" or cmd == "accent" then
        lookCmd(cmd, arg)
    elseif cmd == "layout" then
        GC.Layout.Command(arg)
    elseif cmd == "focus" then
        -- The window the command was typed in, as /gchat copy does; the search keeps its case.
        local f = editBox and editBox.GetParent and editBox:GetParent()
        f = f and f.GetMessageInfo and f or nil
        local raw = (msg or ""):match("^%s*%S+%s*(.-)%s*$") or ""
        -- "from <Addon>": only that addon's lines (#78), by its folder name in any
        -- case. One word after "from"; anything else is a search ("from the bank").
        local name = raw:match("^[Ff][Rr][Oo][Mm]%s+(%S+)$")
        if raw:lower() == "from" then
            say("/gchat focus from <Addon> - only that addon's lines (its folder name)")
        elseif name then
            local real = API.AddOnName(name)
            if real then
                GC.Focus.Open(f, "", real)
            else
                -- Not an addon: the search it was before #78 ("from Bob"; review of #79).
                say("no addon named " .. name .. ": searching for \"" .. raw .. "\"")
                GC.Focus.Open(f, raw)
            end
        else
            GC.Focus.Open(f, raw)
        end
    elseif cmd == "alert" or cmd == "alerts" then
        GC.Alerts.Command((msg or ""):match("^%s*%S+%s*(.-)%s*$") or "")
    elseif cmd == "tabs" then
        GC.Tabs.Command((msg or ""):match("^%s*%S+%s*(.-)%s*$") or "")   -- addon names keep their case
    elseif cmd == "copy" then
        -- The window the command was typed in (an undocked one included).
        local f = editBox and editBox.GetParent and editBox:GetParent()
        GC.Copy.Open(f and f.GetMessageInfo and f or nil)
    elseif cmd == "failures" then
        failures()
    elseif cmd == "version" then
        say("client " .. API.ClientBuild() .. ", measured on " .. GC.MEASURED_ON_BUILD)
    elseif TOGGLES[cmd] then
        local v = flag(arg)
        if v == nil then say("/gchat " .. cmd .. " on/off"); return end
        TOGGLES[cmd](v)
        say(cmd .. " " .. onOff(v))
    elseif NUMBERS[cmd] then
        local v = tonumber(arg)
        -- v ~= v: the client's tonumber accepts "nan", which no clamp catches.
        if not v or v ~= v then say("/gchat " .. cmd .. " <number>"); return end
        NUMBERS[cmd](v)
        local key = cmd == "tabsize" and "tabSize" or cmd == "shellalpha" and "shellAlpha"
            or cmd == "idle" and "idleAlpha" or cmd
        say(cmd .. " " .. tostring(GC.db[key]))
    else
        help()
    end
end

-- /rl: /reload in two letters (owner; Method Raid Tools had it). ReloadUI is
-- protected on Forever (porting guide); C_UI.Reload is documented with no
-- restrictions (UIManagerDocumentation.lua:65), so it goes first.
function GC.Reload()
    local ui = rawget(_G, "C_UI")
    if ui and ui.Reload then ui.Reload() else ReloadUI() end
end
SLASH_GLASSCHATRELOAD1 = "/rl"
SlashCmdList.GLASSCHATRELOAD = function() GC.Reload() end

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
        ok, err = pcall(GC.Layout.Start)
        if not ok then API.Fail("start layout", err) end
        ok, err = pcall(GC.Tabs.Start)
        if not ok then API.Fail("start tabs", err) end
        ok, err = pcall(GC.Url.Start)
        if not ok then API.Fail("start urls", err) end
        ok, err = pcall(GC.Levels.Start)
        if not ok then API.Fail("start levels", err) end
        ok, err = pcall(GC.Alerts.Start)
        if not ok then API.Fail("start alerts", err) end
        ok, err = pcall(GC.SettingsSync.Start)
        if not ok then API.Fail("start settings sync", err) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- arg1 = isInitialLogin: warn and offer at a real login, never on /reload.
        if arg1 and GC.Layout then GC.Layout.ScheduleOffer() end
        -- The build warning, likewise, and in a dev build only (owner): it asks
        -- the developer to re-measure; a player can't act on it.
        -- /gchat version still shows both builds.
        if arg1 and GC.IsDev() and API.ClientBuild() ~= GC.MEASURED_ON_BUILD then
            say("client build " .. API.ClientBuild() .. " differs from the one this addon was measured on ("
                .. GC.MEASURED_ON_BUILD .. "). Things may misbehave until it is re-checked.")
        end
    end
end)
API.RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_ENTERING_WORLD" })

GC._test = { ensureDefaults = ensureDefaults, DEFAULTS = DEFAULTS }
