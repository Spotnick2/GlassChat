-- wow_stubs.lua: a minimal WoW: Forever mock for Lua 5.1 unit tests.
-- dofile("tests/wow_stubs.lua") FIRST in every test; drive it via the WoW table.
-- Modelled on GlassPanel's and GlassRaidFrames' stubs, trimmed to what the
-- chat touches.
--
-- What it models, on purpose:
-- - STRICT globals: reading any global it does not define is an error. The
--   stub is the allowlist of APIs verified present in the API dump; defining
--   something Forever lacks is how a missing API survives into a build.
-- - SECRETS as newproxy userdata: arithmetic, ordering, tostring, concat and
--   string.format on one throw. Lua 5.1 cannot make a truth test or == throw,
--   so those two misuses are NOT caught here (only in game / in review).
-- - EVENT names: RegisterEvent throws on a name the API dump does not declare
--   (tests/events-70205.txt when the dump is absent, as on CI).
-- - METHOD calls: every widget method called is recorded (WoW.methodsCalled)
--   so test_methods.lua can check each against the dump's widget methods.

WoW = {}
local DUMP = os.getenv("GLASSCHAT_API_DUMP") or "C:/Projects/References/forever-api-1.60.1.70205.md"
WoW.DUMP = DUMP

--------------------------------------------------------------------------------
-- Secrets
--------------------------------------------------------------------------------

local secrets = setmetatable({}, { __mode = "k" })

function WoW.Secret(label)
    local p = newproxy(true)
    local mt = getmetatable(p)
    local function boom() error("secret value touched in Lua: " .. label, 2) end
    for _, k in ipairs({ "__tostring", "__concat", "__add", "__sub", "__mul", "__div", "__mod",
                         "__pow", "__unm", "__lt", "__le", "__len", "__index", "__newindex", "__call" }) do
        mt[k] = boom
    end
    secrets[p] = label
    return p
end

function issecretvalue(v) return secrets[v] ~= nil end

-- Mark an existing value secret for issecretvalue. The client's secrets keep
-- their type (a secret string is still type "string"), which a proxy can't
-- model; use this to reach `type(x) == "string"` branches.
function WoW.MarkSecret(v, label) secrets[v] = label or "marked" end

--------------------------------------------------------------------------------
-- Known events (from the dump when present, else the checked-in fixture)
--------------------------------------------------------------------------------

WoW.KNOWN_EVENTS = {}
WoW.dumpAvailable = false
do
    local f = io.open(DUMP, "r")
    if f then
        local inEvents = false
        for line in f:lines() do
            if line:match("^## Documented events") then inEvents = true
            elseif line:match("^## ") then inEvents = false
            elseif inEvents then
                local name = line:match("^([A-Z][A-Z0-9_]+)%s+%(")
                if name then WoW.KNOWN_EVENTS[name] = true end
            end
        end
        f:close()
        WoW.dumpAvailable = next(WoW.KNOWN_EVENTS) ~= nil
    end
    if not WoW.dumpAvailable then
        -- No dump (CI): the list generated from it, so validation stays
        -- exactly as strict. test_toc fails if the two ever drift.
        local fixture = io.open("tests/events-70205.txt", "r")
        assert(fixture, "tests/events-70205.txt missing: event validation needs the dump or the fixture")
        for line in fixture:lines() do
            local name = line:match("^([A-Z][A-Z0-9_]+)%s*$")
            if name then WoW.KNOWN_EVENTS[name] = true end
        end
        fixture:close()
    end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

function WoW.reset()
    WoW.frames = {}
    WoW.chat = {}
    WoW.methodsCalled = {}
    WoW.combat = false
    WoW.timers = {}
    WoW.cvars = { chatClassColorOverride = "0" }
    WoW.cvarSets = {}
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local Methods = {}   -- shared implementations, by method name

local function record(w, name)
    WoW.methodsCalled[w._type .. ":" .. name] = true
end

local widgetMT = {
    __index = function(w, k)
        if type(k) ~= "string" or not k:match("^%u") then return nil end  -- fields read as nil
        return function(self, ...)
            record(self, k)
            local impl = Methods[k]
            if impl then return impl(self, ...) end
            return nil
        end
    end,
}

local function newWidget(wtype, parent, name)
    return setmetatable({ _type = wtype, _parent = parent, _shown = true, _points = {},
                          _scripts = {}, _events = {},
                          _level = parent and parent._level and (parent._level + 1) or 1,
                          _width = 0, _height = 0, _name = name }, widgetMT)
end
WoW.newWidget = newWidget

function CreateFrame(ftype, name, parent, template)
    local w = newWidget(ftype, parent, name)
    w._template = template
    if ftype == "StatusBar" then w._min, w._max, w._value = 0, 1, 0 end
    table.insert(WoW.frames, w)
    if name then rawset(_G, name, w) end
    return w
end

function Methods.Show(w) w._shown = true; if w._scripts.OnShow then w._scripts.OnShow(w) end end
function Methods.Hide(w)
    local was = w._shown
    w._shown = false
    if was and w._scripts.OnHide then w._scripts.OnHide(w) end
end
function Methods.SetShown(w, v) if v then Methods.Show(w) else Methods.Hide(w) end end
function Methods.IsShown(w) return w._shown end
function Methods.IsVisible(w)
    local p = w
    while p do if not p._shown then return false end; p = p._parent end
    return true
end
function Methods.SetPoint(w, ...) table.insert(w._points, { ... }) end
function Methods.ClearAllPoints(w) w._points = {} end
function Methods.GetPoint(w, i)
    local p = w._points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Methods.SetAllPoints(w, rel) table.insert(w._points, { "ALL", rel }) end
function Methods.SetSize(w, x, y) w._width, w._height = x, y end
function Methods.SetWidth(w, x) w._width = x end
function Methods.SetHeight(w, y) w._height = y end
function Methods.GetWidth(w) return w._width end
function Methods.GetHeight(w) return w._height end
function Methods.SetAlpha(w, a) w._alpha = a end
function Methods.GetAlpha(w) return w._alpha or 1 end
function Methods.GetParent(w) return w._parent end
function Methods.SetParent(w, p) w._parent = p end
function Methods.GetFrameLevel(w) return w._level end
function Methods.SetFrameLevel(w, l) w._level = l end
function Methods.SetFrameStrata(w, s) w._strata = s end
function Methods.GetFrameStrata(w) return w._strata or "MEDIUM" end
function Methods.EnableMouse(w, v) w._mouse = v end
function Methods.IsMouseEnabled(w) return w._mouse == true end
function Methods.GetName(w) return w._name end
function Methods.GetDebugName(w) return w._name or ("<" .. w._type .. ">") end
function Methods.IsForbidden(w) return false end

function Methods.SetScript(w, name, fn) w._scripts[name] = fn end
function Methods.GetScript(w, name) return w._scripts[name] end
function Methods.HookScript(w, name, fn)
    local old = w._scripts[name]
    w._scripts[name] = function(...) if old then old(...) end; fn(...) end
end
function Methods.RegisterEvent(w, e)
    if not WoW.KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"", 2) end
    w._events[e] = true
    return true
end
function Methods.UnregisterEvent(w, e) w._events[e] = nil end
function Methods.IsEventRegistered(w, e) return w._events[e] == true end

-- Regions.
function Methods.CreateTexture(w, name, layer, template, sublevel)
    local t = newWidget("Texture", w)
    t._layer, t._sublevel = layer, sublevel
    return t
end
function Methods.CreateMaskTexture(w) return newWidget("MaskTexture", w) end
function Methods.CreateFontString(w) return newWidget("FontString", w) end
function Methods.SetTexture(t, file) t._file = file; return true end
function Methods.SetColorTexture(t, r, g, b, a) t._color = { r, g, b, a } end
function Methods.AddMaskTexture(t, m) t._masks = t._masks or {}; table.insert(t._masks, m) end
function Methods.SetGradient(t, orientation, c1, c2) t._gradient = { orientation, c1, c2 } end
function Methods.SetTextureSliceMargins(t, l, tp, r, b) t._slice = { l, tp, r, b } end

-- FontString: the client formats natively and accepts secrets. With any
-- secret argument, keep the arguments unformatted instead of calling
-- string.format (which would throw on the proxy).
function Methods.SetText(fs, text) fs._text = text end
function Methods.SetTextColor(fs, r, g, b, a) fs._textColor = { r, g, b, a } end
function Methods.GetText(fs) return fs._text end
function Methods.SetFormattedText(fs, fmt, ...)
    local n = select("#", ...)
    for i = 1, n do
        if secrets[(select(i, ...))] then fs._text = { secretFormat = fmt, n = n }; return end
    end
    fs._text = string.format(fmt, ...)
end
function Methods.SetFont(fs, file, size, flags) fs._font = { file, size, flags }; return true end
function Methods.GetFont(fs)
    local f = fs._font or { "Fonts\FRIZQT__.TTF", 10, "" }
    return f[1], f[2], f[3]
end
function Methods.GetFontString(b) return b._fontString end
-- One line of text is as tall as its font size here: enough to check the
-- line-fitting arithmetic.
function Methods.GetLineHeight(fs) return (select(2, Methods.GetFont(fs))) end

-- ScrollingMessageFrame: the line limit (stock 128, ChatFrameOverrides.lua:3).
function Methods.SetMaxLines(f, n) f._maxLines = n end
function Methods.GetMaxLines(f) return f._maxLines or 128 end

-- EditBox: arrow mode and the sent history, kept like the client: newest
-- last, capped at the history size (stock 32, ChatFrameEditBox.xml:3).
function Methods.SetAltArrowKeyMode(e, v) e._altArrows = v end
function Methods.GetAltArrowKeyMode(e) return e._altArrows ~= false end
function Methods.SetHistoryLines(e, n)
    e._historyLines = n
    e._history = e._history or {}
    while #e._history > n do table.remove(e._history, 1) end
end
function Methods.GetHistoryLines(e) return e._historyLines or 32 end
function Methods.AddHistoryLine(e, text)
    e._history = e._history or {}
    table.insert(e._history, text)
    while #e._history > Methods.GetHistoryLines(e) do table.remove(e._history, 1) end
end

-- StatusBar.
function Methods.SetMinMaxValues(b, lo, hi) b._min, b._max = lo, hi end
function Methods.SetStatusBarColor(b, r, g, bl, a) b._color = { r, g, bl, a } end
function Methods.GetValue(b) return b._value end
function Methods.SetValue(b, v) b._value = v end
function Methods.SetStatusBarTexture(b, file)
    b._fill = b._fill or newWidget("Texture", b)
    b._fill._file = file
    return true
end
function Methods.GetStatusBarTexture(b) return b._fill end

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

UIParent = newWidget("Frame", nil, "UIParent")
UIParent._level = 0

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    table.insert(WoW.chat, table.concat(parts, " "))
end

SlashCmdList = {}
Enum = { UITextureSliceMode = { Stretched = 0, Tiled = 1 } }
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end

-- FrameXML's background pieces of a chat window (FloatingChatFrame.lua:43).
CHAT_FRAME_TEXTURES = { "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture",
    "BottomRightTexture", "LeftTexture", "RightTexture", "BottomTexture", "TopTexture",
    "ButtonFrameBackground", "ButtonFrameTopLeftTexture", "ButtonFrameBottomLeftTexture",
    "ButtonFrameTopRightTexture", "ButtonFrameBottomRightTexture", "ButtonFrameLeftTexture",
    "ButtonFrameRightTexture", "ButtonFrameBottomTexture", "ButtonFrameTopTexture" }
Constants = { ChatFrameConstants = { MaxChatWindows = 10 } }

-- Blizzard's list of every chat window's name, temporary ones included
-- (FloatingChatFrame.lua:93, 445).
CHAT_FRAMES = {}

-- A temporary whisper window: ChatFrame11 and up (FloatingChatFrame.lua:975).
function WoW.makeTemporaryWindow(i)
    local saved = rawget(_G, "ChatFrame1")
    for n = 1, i - 1 do
        if not rawget(_G, "ChatFrame" .. n) then rawset(_G, "ChatFrame" .. n, false) end
    end
    WoW.makeChatFrames(i)
    for n = 1, i - 1 do
        if rawget(_G, "ChatFrame" .. n) == false then rawset(_G, "ChatFrame" .. n, nil) end
    end
    return rawget(_G, "ChatFrame" .. i), saved
end

-- Chat windows 1..n as FloatingChatFrameTemplate builds them: ChatFrameN with its
-- named background textures, and ChatFrameNEditBox with its border art.
function WoW.makeChatFrames(n)
    for i = 1, n do
        local name = "ChatFrame" .. i
        if not rawget(_G, name) then   -- only the missing ones, as a new tab adds one
            local f = CreateFrame("ScrollingMessageFrame", name, UIParent)
            table.insert(CHAT_FRAMES, name)
            f._level = 5
            for _, t in ipairs(CHAT_FRAME_TEXTURES) do rawset(_G, name .. t, Methods.CreateTexture(f)) end
            f.Background = _G[name .. "Background"]
            -- The lines live in a clipping child that covers the frame
            -- (ScrollingMessageFrame.xml:10); 200 px tall, 14 pt font.
            f._height, f._font = 200, { "Fonts\ARIALN.TTF", 14, "" }
            f.FontStringContainer = CreateFrame("Frame", nil, f)
            f.FontStringContainer._points = { { "ALL", f } }
            -- The tab: ChatTabTemplate, its name in a ButtonText 8 px tall
            -- (FloatingChatFrame.xml:432), its art as parentKeys.
            local tab = CreateFrame("Button", name .. "Tab", UIParent)
            tab._fontString = Methods.CreateFontString(tab)
            tab._fontString._height = 8
            for _, k in ipairs({ "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
                "HighlightLeft", "HighlightMiddle", "HighlightRight" }) do
                tab[k] = Methods.CreateTexture(tab)
            end
            local e = CreateFrame("EditBox", name .. "EditBox", f)
            for _, t in ipairs({ "Left", "Right", "Mid", "FocusLeft", "FocusRight", "FocusMid" }) do
                rawset(_G, name .. "EditBox" .. t, Methods.CreateTexture(e))
            end
        end
    end
end
-- Tab opacities, as ChatFrameUtil keeps them (ChatFrameUtil.lua:78-92), and
-- Blizzard's own per-tab updates the addon hooks.
WoW.tabAlphas = {}
WoW.messageFilters = {}
ChatFrameUtil = {
    AddMessageEventFilter = function(event, fn)
        WoW.messageFilters[event] = WoW.messageFilters[event] or {}
        table.insert(WoW.messageFilters[event], fn)
    end,
    SetTabAlphas = function(tab, over, rest) WoW.tabAlphas[tab] = { over, rest } end,
    GetTabAlphas = function(tab)
        local a = WoW.tabAlphas[tab]
        if a then return a[1], a[2] end
    end,
}
function FCFTab_UpdateAlpha(chatFrame)
    local tab = _G[chatFrame:GetName() .. "Tab"]
    local selected = chatFrame == ChatFrame1
    ChatFrameUtil.SetTabAlphas(tab, selected and 1 or 0.6, selected and 0.4 or 0.2)
    tab:SetAlpha(selected and 0.4 or 0.2)
end
function FCFTab_UpdateColors(tab, selected) end
-- The dock that holds the docked tabs, anchored on its primary window's
-- Background (FCFDock_SetPrimary, FloatingChatFrame.lua:2263-2266).
GeneralDockManager = newWidget("Frame", UIParent, "GeneralDockManager")
GENERAL_CHAT_DOCK = GeneralDockManager
GeneralDockManager._docked = {}
function FCFDock_SetPrimary(dock, chatFrame)
    dock.primary = chatFrame
    dock:SetPoint("BOTTOMLEFT", chatFrame.Background, "TOPLEFT")
end
function FCFDock_GetChatFrames(dock) return dock._docked end
-- The name-suggestion list under the edit box (Blizzard_AutoComplete).
AutoCompleteBox = newWidget("Frame", UIParent, "AutoCompleteBox")
AutoCompleteBox._shown = false
function FCF_SetChatWindowFontSize(self, chatFrame, fontSize)
    local file, _, flags = chatFrame:GetFont()
    chatFrame:SetFont(file, fontSize, flags)
end
function FCF_SetTabPosition(chatFrame, x)
    local tab = _G[chatFrame:GetName() .. "Tab"]
    tab:ClearAllPoints()
    tab:SetPoint("BOTTOMLEFT", chatFrame:GetName() .. "Background", "TOPLEFT", x + 2, 0)
end
-- Blizzard's chat window functions the addon hooks (both in the dump).
function FCF_OpenNewWindow(name) WoW.newWindows = (WoW.newWindows or 0) + 1 end
function FCF_OpenTemporaryWindow() end

-- Chat messaging lockdown (Retail 12.x; never seen on Forever so far).
C_ChatInfo = { InChatMessagingLockdown = function() return WoW.chatLockdown == true end }

-- CVars: the value and every set, recorded.
C_CVar = {
    GetCVar = function(name) return WoW.cvars[name] end,
    SetCVar = function(name, v) WoW.cvars[name] = tostring(v); table.insert(WoW.cvarSets, name) ; return true end,
}

C_ClassColor = { GetClassColor = function(classFile)
    local c = ({ MAGE = { 0.25, 0.78, 0.92 }, PRIEST = { 1, 1, 1 }, WARRIOR = { 0.78, 0.61, 0.43 } })[classFile]
    if c then return { r = c[1], g = c[2], b = c[3] } end
end }

function GetBuildInfo() return "1.60.1", "70205", "Oct 2 2026", 16001 end
function InCombatLockdown() return WoW.combat == true end

function hooksecurefunc(t, name, fn)
    if type(t) == "string" then t, name, fn = _G, t, name end
    local orig = rawget(t, name) or t[name]
    rawset(t, name, function(...)
        local r = { orig(...) }
        fn(...)
        return unpack(r)
    end)
end

-- Timers keep their delay: WoW.flushTimers(upTo) runs those due within upTo
-- seconds (all when nil) and keeps the rest.
C_Timer = { After = function(s, fn) table.insert(WoW.timers, { s = s, fn = fn }) end }
function WoW.flushTimers(upTo)
    local run, keep = {}, {}
    for _, t in ipairs(WoW.timers) do
        if upTo == nil or t.s <= upTo then run[#run + 1] = t else keep[#keep + 1] = t end
    end
    WoW.timers = keep
    for _, t in ipairs(run) do t.fn() end
end

--------------------------------------------------------------------------------
-- Driving
--------------------------------------------------------------------------------

-- Fire an event at every frame registered for it. Errors are NOT caught: a
-- handler that throws fails the test.
function WoW.fire(event, ...)
    for _, w in ipairs(WoW.frames) do
        local handler = w._scripts.OnEvent
        if handler and w._events[event] then handler(w, event, ...) end
    end
end

-- Every event any frame registered, fired once with no payload: strict
-- globals only catch code that actually runs.
function WoW.fireAllRegistered()
    local seen = {}
    for _, w in ipairs(WoW.frames) do
        for e in pairs(w._events) do seen[e] = true end
    end
    for e in pairs(seen) do WoW.fire(e) end
end

-- One rendered frame: OnUpdate on every visible frame.
function WoW.tick(elapsed)
    elapsed = elapsed or 0.02
    local list = {}
    for _, w in ipairs(WoW.frames) do list[#list + 1] = w end
    for _, w in ipairs(list) do
        local fn = w._scripts.OnUpdate
        if fn and Methods.IsVisible(w) then fn(w, elapsed) end
    end
end

WoW.reset()

-- Strict globals: any read of an undefined global is an error, except the
-- addon's own globals that are legitimately nil before first assignment.
local allowNil = { GlassChat = true, GlassChatDB = true, GlassChatCharDB = true, ChatProbeDB = true }
setmetatable(_G, { __index = function(_, k)
    if allowNil[k] then return nil end
    error("read of undefined global '" .. tostring(k) .. "' (not stubbed: is it in the API dump?)", 2)
end })
