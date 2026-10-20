-- Suite.lua: following Glass UI's suite look (#121; Glass UI's docs/SUITE.md
-- and docs/SUITE-LOOK.md). The owner, 2026-10-19: the chat in Glass UI's
-- damage meter and quest tracker look, synced from Glass UI, its text
-- colours set there or back to Blizzard's gold.
--
-- A player follows with Glass UI's "Use Glass UI appearance" switch, read
-- here once per session through GlassUI.Suite.Theme, at PLAYER_LOGIN (every
-- ADDON_LOADED has run by then, Glass UI's included: GAB's way). The material
-- is Pearl either way: Glass.lua builds it at load, as the suite's only
-- theme asks, so the decision changes the body and the accent only, both
-- repainted live. While following:
--   - the body is the suite look's tint (clear, smoked or class) and the
--     accent its accent (gold or ice), updated live by
--     EventRegistry "GlassUI.Suite.LookChanged";
--   - a key the player sets in GlassChat (/gchat body, /gchat accent) is an
--     override, kept in GlassChatDB.suiteOwn, never pruned against our
--     defaults ("suite" clears it). GlassChat's own body and accent stay
--     saved and unused;
--   - a saved /gchat alpha is the backing's opacity over the body's, reported
--     as own.backing ("its own backing" on Glass UI's page).
-- Not following (no Glass UI, an older one, the switch off): db.body and
-- db.accent, exactly as before.
--
-- The body numbers are Glass UI's (Suite.Body), whoever picked the tint, so
-- the tuning lives in one place. Skin.BODIES and Skin.ACCENTS are the copies
-- for a player without Glass UI.

local ADDON = ...
GlassChat = GlassChat or {}
local GC = GlassChat
local Suite = {}
GC.Suite = Suite

Suite.ADDON = ADDON or "GlassChat"
Suite.EVENT = "GlassUI.Suite.LookChanged"

local suite                 -- GlassUI.Suite when it speaks API 1
local following = false
local suiteLook = {}        -- the suite's tint and accent, copied (the payload is read-only)
local bodies, colours = {}, {}   -- name -> Body / Accent result (false: none), until the look changes

-- Glass UI's suite API, when it speaks version 1 (anything else counts as absent).
local function suiteAPI()
    local G = rawget(_G, "GlassUI")
    if type(G) ~= "table" then return nil end
    local S = rawget(G, "Suite")
    if type(S) ~= "table" or rawget(S, "API") ~= 1 then return nil end
    if type(rawget(S, "Theme")) ~= "function" or type(rawget(S, "Report")) ~= "function" then return nil end
    return S
end

function Suite.ValidTint(v) return v == "chat" or (type(v) == "string" and GC.Skin.BODIES[v] ~= nil) end
function Suite.ValidAccent(v) return type(v) == "string" and GC.Skin.ACCENTS[v] ~= nil end
local VALID = { tint = Suite.ValidTint, accent = Suite.ValidAccent }

function Suite.Following() return following end

local function overrides()
    local t = GC.db and rawget(GC.db, "suiteOwn")
    return type(t) == "table" and t or nil
end

-- The player's override for a key while following ("tint" | "accent"), or nil.
function Suite.Own(key)
    local o = following and overrides()
    local v = o and o[key]
    if VALID[key](v) then return v end
end

-- The effective tint: "chat" (our charcoal) or a body name.
function Suite.Tint()
    local v = Suite.Own("tint")
    if v then return v end
    if following and suiteLook.tint then return suiteLook.tint end
    return GC.db.body
end

function Suite.AccentName()
    local v = Suite.Own("accent")
    if v then return v end
    if following and suiteLook.accent then return suiteLook.accent end
    return GC.db.accent
end

local function rgba(t, n)
    if type(t) ~= "table" then return false end
    for i = 1, n do
        if type(t[i]) ~= "number" or t[i] < 0 or t[i] > 1 then return false end
    end
    return true
end

-- Glass UI's answer, checked: anything else falls back to our copy.
local function validBody(b)
    return type(b) == "table" and rgba(b.backing, 4) and type(b.wash) == "number"
        and (rgba(b.tint, 4) or (b.tint == nil and type(b.classShade) == "number"))
end

-- Our copy, in Suite.Body's shape.
local function ownBody(name)
    local b, c = GC.Skin.BODIES[name], GC.Skin.BACKING
    if not b then return nil end
    return { tint = b.tint, classShade = b.classShade, wash = b.wash, backing = { c[1], c[2], c[3], b.backing } }
end

-- The body for a tint name, nil for "chat": { tint | classShade, wash, backing }.
function Suite.Body(name)
    if name == "chat" or name == nil then return nil end
    if bodies[name] == nil then
        local b
        if suite and type(rawget(suite, "Body")) == "function" then
            local ok, r = pcall(suite.Body, name)
            if ok and validBody(r) then b = r end
        end
        bodies[name] = b or ownBody(name) or false
    end
    return bodies[name] or nil
end

-- The accent's { r, g, b }.
function Suite.AccentColor()
    local name = Suite.AccentName()
    if colours[name] == nil then
        local c
        if suite and type(rawget(suite, "Accent")) == "function" then
            local ok, r = pcall(suite.Accent, name)
            if ok and rgba(r, 3) then c = r end
        end
        colours[name] = c or GC.Skin.ACCENTS[name] or false
    end
    return colours[name] or GC.Skin.ACCENTS.ice
end

-- The backing's opacity: a saved /gchat alpha, else the body's.
function Suite.Backing(body)
    local own = GC.db and rawget(GC.db, "alpha")
    if type(own) == "number" then return own end
    return body.backing[4]
end

local function copyLook(look)
    for key, valid in pairs(VALID) do
        local v = type(look) == "table" and look[key]
        suiteLook[key] = (key ~= "tint" or v ~= "chat") and valid(v) and v or nil
    end
end

-- What we show, for Glass UI's page (plain values only).
function Suite.Report()
    if not suite then return end
    local tint = Suite.Tint()
    local own = {
        tint = Suite.Own("tint") and true or nil,
        accent = Suite.Own("accent") and true or nil,
        backing = (tint ~= "chat" and type(rawget(GC.db, "alpha")) == "number") or nil,
    }
    local state = {
        api = 1,
        built = following and GC.glassPreset or nil,
        reason = following and GC.glassPreset ~= "pearl" and "library-too-old" or nil,
        minor = GC.glassMinor,
        look = { tint = tint, accent = Suite.AccentName() },
        own = own,
    }
    pcall(suite.Report, Suite.ADDON, state)
end

-- Every change: repaint (combat-safe: our own textures, colours and alphas,
-- and the chat frames, which aren't protected), then report.
function Suite.Changed()
    for k in pairs(bodies) do bodies[k] = nil end
    for k in pairs(colours) do colours[k] = nil end
    GC.Skin.Refresh()
    Suite.Report()
end

local function onLookChanged(_, look)
    copyLook(look)
    local ok, err = pcall(Suite.Changed)
    if not ok then GC.API.Fail("suite:look", err) end
end

-- Set or clear ("suite") an override while following.
function Suite.SetOwn(key, v)
    if not following or not VALID[key] then return false end
    if v ~= "suite" and not VALID[key](v) then return false end
    local o = overrides() or {}
    o[key] = v ~= "suite" and v or nil
    GC.db.suiteOwn = next(o) and o or nil
    Suite.Changed()
    return true
end

-- PLAYER_LOGIN: decide following once for the session.
function Suite.Start()
    suite = suiteAPI()
    if suite then
        local ok, answer = pcall(suite.Theme, Suite.ADDON)
        following = ok and type(answer) == "table" and type(answer.preset) == "string"
    end
    if following and type(rawget(suite, "Look")) == "function" then
        if EventRegistry and EventRegistry.RegisterCallback then
            EventRegistry:RegisterCallback(Suite.EVENT, onLookChanged, Suite)
        end
        local ok, look = pcall(suite.Look)
        if ok then copyLook(look) end
    end
    Suite.Changed()
end

local boot = CreateFrame("Frame")
boot:SetScript("OnEvent", function()
    local ok, err = pcall(Suite.Start)
    if not ok then GC.API.Fail("suite", err) end
end)
GC.API.RegisterEvents(boot, { "PLAYER_LOGIN" })

Suite._test = { suiteLook = suiteLook, reset = function() suite, following = nil, false end }
