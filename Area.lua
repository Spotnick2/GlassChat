-- Area.lua: the screen area the chat occupies, for the other Glass
-- addons (#122; the shape agreed with Glass UI, 2026-10-19). Their frames
-- (GlassUnitFrames' player frame in a later group layout) can keep clear of
-- the chat: we announce, they follow, and neither depends on the other. The
-- pattern is GlassPanel's EdgeState / EdgeChanged and GlassActionBars'
-- EdgesChanged.
--
--   GlassChat.Footprint() -> { left, right, top, bottom }, a fresh table, in
--     UIParent units from the screen's bottom-left, or nil before the first
--     measure. The latest measure, one taken in combat included.
--   EventRegistry "GlassChat.LayoutChanged" (footprint): at the first
--     measure, then out of combat when a side moved more than TOLERANCE from
--     the last one announced. A change in combat is announced at
--     PLAYER_REGEN_ENABLED. Every listener gets the same table: read it,
--     never keep or edit it. Consumers apply the latest value each time.
--
-- What counts: the union of what the main window (ChatFrame1) shows and
-- answers clicks on:
-- - the window, and with glass its panel, which reaches up over the tabs;
-- - its tab and the dock's tab strip (GeneralDockManager), while shown;
-- - its edit box, shown or not: in the IM chat style the box hides between
--   messages, and the footprint must not move every time the player types;
--   with glass, the box's panel;
-- - the button column (ChatFrame1ButtonFrame; the voice, menu and friends
--   buttons) and our side buttons, while shown.
-- Blizzard's toasts in ChatAlertFrame come and go: they don't count.
--
-- A frame's scale is converted to UIParent units. A rect with any unreadable
-- (secret) value is skipped, never guessed; with the window itself
-- unreadable there is no measure at all.

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local Area = {}
GC.Area = Area   -- the module; GlassChat.Footprint() is the public getter

Area.EVENT = "GlassChat.LayoutChanged"
Area.TOLERANCE = 0.5
Area.EVERY = 1   -- s, the safety net for a change nothing tells us about

local published   -- the last footprint announced
local measured    -- the latest one measured
local wanted, pending = false, false

local function num(v)
    if API.IsSecret(v) then return nil end   -- before any other test of it
    if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then return v end
end

-- A frame's rectangle in UIParent units, or nil (anything unreadable).
local function rectOf(frame)
    if type(frame) ~= "table" or type(frame.GetLeft) ~= "function" then return nil end
    local s, ui = num(frame:GetEffectiveScale()), num(UIParent:GetEffectiveScale())
    local l, r, t, b = num(frame:GetLeft()), num(frame:GetRight()), num(frame:GetTop()), num(frame:GetBottom())
    if not (s and ui and l and r and t and b) or s <= 0 or ui <= 0 or r < l or t < b then return nil end
    local k = s / ui
    return { left = l * k, right = r * k, top = t * k, bottom = b * k }
end
Area.RectOf = rectOf

local function shown(frame)
    if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then return false end
    local v = frame:IsShown()
    return not API.IsSecret(v) and v == true
end

-- The frames beyond the window, by name: shown ones only.
local function named()
    local B = GC.Buttons
    local out = { "ChatFrame1Tab", "GeneralDockManager", "ChatFrame1ButtonFrame", B.MENU, B.FRIENDS }
    for _, n in ipairs(B.VOICE) do out[#out + 1] = n end
    return out
end

function Area.Measure()
    local main = rawget(_G, "ChatFrame1")
    local box = rectOf(main)
    if not box then return nil end
    local function add(frame)
        local r = rectOf(frame)
        if not r then return end
        box.left, box.right = math.min(box.left, r.left), math.max(box.right, r.right)
        box.top, box.bottom = math.max(box.top, r.top), math.min(box.bottom, r.bottom)
    end
    local glass = GC.db and GC.db.glass
    local p = GC.Skin.Panel(main)
    if glass and p then add(p.panel) end
    local edit = rawget(_G, "ChatFrame1EditBox")
    add(edit)
    local e = edit and GC.Skin.Panel(edit)
    if glass and e then add(e.panel) end
    for _, name in ipairs(named()) do
        local f = rawget(_G, name)
        if shown(f) then add(f) end
    end
    for _, b in ipairs(GC.Buttons.SideFrames()) do
        if shown(b) then add(b) end
    end
    return box
end

local function copy(f) return { left = f.left, right = f.right, top = f.top, bottom = f.bottom } end

local function moved(a, b)
    local T = Area.TOLERANCE
    return math.abs(a.left - b.left) > T or math.abs(a.right - b.right) > T
        or math.abs(a.top - b.top) > T or math.abs(a.bottom - b.bottom) > T
end

local function update()
    local now = Area.Measure()
    if not now then return end
    measured = now
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    if published and not moved(now, published) then return end
    published = now
    if EventRegistry and EventRegistry.TriggerEvent then
        EventRegistry:TriggerEvent(Area.EVENT, copy(now))
    end
end

-- Public: the latest footprint, as a fresh table (nil before the first measure).
function GC.Footprint()
    if not measured then return nil end
    return copy(measured)
end

local driver = CreateFrame("Frame")
local function onUpdate()
    driver:SetScript("OnUpdate", nil)
    if not wanted then return end
    wanted = false
    local ok, err = pcall(update)
    if not ok then API.Fail("footprint", err) end
end

-- A measure on the next frame (coalesced).
function Area.Request()
    wanted = true
    driver:SetScript("OnUpdate", onUpdate)
end

local started = false
function Area.Start()
    if started then return end
    started = true
    driver:SetScript("OnEvent", function(_, event)
        if event ~= "PLAYER_REGEN_ENABLED" or pending then Area.Request() end
    end)
    API.RegisterEvents(driver, { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UI_SCALE_CHANGED",
        "DISPLAY_SIZE_CHANGED" })
    local main = rawget(_G, "ChatFrame1")
    if main and main.HookScript then main:HookScript("OnSizeChanged", Area.Request) end
    -- A move (Edit Mode), a dock change or a button shown: within a second.
    C_Timer.NewTicker(Area.EVERY, Area.Request)
    Area.Request()
end

-- Every scan (a setting, a window opened, the side buttons re-stacked).
GC.Chat.AfterScan("footprint", Area.Request)

Area._test = { published = function() return published end }
