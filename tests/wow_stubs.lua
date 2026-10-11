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
--   (tests/events-70291.txt when the dump is absent, as on CI).
-- - METHOD calls: every widget method called is recorded (WoW.methodsCalled)
--   so test_methods.lua can check each against the dump's widget methods.

WoW = {}
local DUMP = os.getenv("GLASSCHAT_API_DUMP") or "C:/Projects/WoW/References/forever-api-1.60.1.70291.md"
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
        local fixture = io.open("tests/events-70291.txt", "r")
        assert(fixture, "tests/events-70291.txt missing: event validation needs the dump or the fixture")
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
    -- The template's bar, shown by default as on the client.
    if template == "UIPanelScrollFrameTemplate" then w.ScrollBar = newWidget("Slider", w) end
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

-- Attributes: recorded; like the client, refused on a protected frame in
-- combat (the chat edit box isn't one).
function Methods.SetAttribute(w, k, v)
    if WoW.combat and w._protected then return end
    w._attrs = w._attrs or {}
    w._attrs[k] = v
end
function Methods.GetAttribute(w, k) return w._attrs and w._attrs[k] end
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
function Methods.SetVertexColor(t, r, g, b, a) t._vertex = { r, g, b, a } end
function Methods.AddMaskTexture(t, m) t._masks = t._masks or {}; table.insert(t._masks, m) end
function Methods.SetGradient(t, orientation, c1, c2) t._gradient = { orientation, c1, c2 } end
function Methods.SetTextureSliceMargins(t, l, tp, r, b) t._slice = { l, tp, r, b } end
-- Animations: groups record whether they play.
function Methods.CreateAnimationGroup(w) return newWidget("AnimationGroup", w) end
function Methods.CreateAnimation(ag, atype) return newWidget(atype or "Animation", ag) end
function Methods.Play(ag) ag._playing = true end
function Methods.Stop(ag) ag._playing = false end
function Methods.IsPlaying(ag) return ag._playing == true end

-- FontString: the client formats natively and accepts secrets. With any
-- secret argument, keep the arguments unformatted instead of calling
-- string.format (which would throw on the proxy).
-- An EditBox runs its OnTextChanged on SetText, as the client does (the
-- chat box re-parses its text there).
function Methods.SetText(fs, text)
    fs._text = text
    if fs._type == "EditBox" and fs._scripts.OnTextChanged then fs._scripts.OnTextChanged(fs, false) end
end
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

-- ScrollingMessageFrame: its lines, oldest first, as GetMessageInfo
-- numbers them (ScrollingMessageFrame.lua:30-31). f._messages = { text, ... }.
-- Without _messages, the lines AddMessage stored (f._lines).
function Methods.GetNumMessages(f) return #(f._messages or f._lines or {}) end
function Methods.GetMessageInfo(f, i)
    if not f._messages then
        local e = f._lines and f._lines[i]
        if e and e.extra and e.extra.n > 0 then return e.m, unpack(e.extra, 1, e.extra.n) end
        if e then return e.m, 1, 1, 1 end
        return
    end
    local m = f._messages[i]
    if m ~= nil then return m, 1, 1, 1 end
end
function Methods.GetID(w) return w._id or 0 end
function Methods.SetFocus(e) e._focused = true end
function Methods.ClearFocus(e) e._focused = false end
function Methods.HighlightText(e) e._highlighted = true end
function Methods.GetVerticalScrollRange(w) return w._yrange or 0 end
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

-- A "|" the client would misread (#55, review of #56): it reads "|x" as an
-- escape and drops it ("off|watch|hide" showed as "offatchide", "|n" is a
-- newline). Only well-formed escapes are taken out: "||", colour pairs
-- (|cAARRGGBB or |cn...: up to |r), links (|H...|h...|h), textures,
-- atlases and |K names. Any "|" left is stray.
function WoW.StrayPipe(line)
    local s = line:gsub("||", "")
    s = s:gsub("|H[^|]*|h(.-)|h", "%1"):gsub("|T[^|]*|t", ""):gsub("|A[^|]*|a", ""):gsub("|K[^|]*|k", "?")
    local n
    repeat
        s, n = s:gsub("|c%x%x%x%x%x%x%x%x([^|]-)|r", "%1")
        local m
        s, m = s:gsub("|cn[^:|]*:([^|]-)|r", "%1")
        n = n + m
    until n == 0
    return s:find("|", 1, true) ~= nil
end
WoW.strays = {}

-- Every printed line, in every test, is checked for a stray "|" (done() fails on one).
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    if WoW.StrayPipe(line) then WoW.strays[#WoW.strays + 1] = line end
    table.insert(WoW.chat, line)
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
            f._id = i
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
WoW.nameFilters = {}
-- GetDecoratedSenderName's last step (ChatFrameUtil.lua:1112): each filter
-- gets (event, name, arg1..arg14); a nil return keeps the name
-- (ChatFrameFilters.lua:59-66). guid goes in arg12.
function WoW.decorateName(event, name, guid)
    for _, fn in ipairs(WoW.nameFilters) do
        local new = fn(event, name, "hi", "Sender", "", "", "", "", 0, 0, "", 0, 1, guid)
        if new ~= nil then name = new end
    end
    return name
end
ChatFrameUtil = {
    -- The edit box being typed in, else nil (ChatFrameUtil.lua:496).
    GetActiveWindow = function() return WoW.activeBox end,
    -- The edit box Enter opens (ChatFrameUtil.lua:500, 570).
    GetLastActiveWindow = function() return WoW.lastActive end,
    SetLastActiveWindow = function(editBox) WoW.lastActive = editBox end,
    -- ChatFrameUtil.lua:845: the showTimestamps setting, nil for "none".
    GetTimestampFormat = function()
        local v = WoW.cvars.showTimestamps
        if v ~= nil and v ~= "none" then return v end
    end,
    -- Sender-name filters (ChatFrameFilters.lua:183); WoW.decorateName runs them.
    AddSenderNameFilter = function(fn) table.insert(WoW.nameFilters, fn) end,
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
function FCFDock_GetSelectedWindow(dock) return dock._selected or ChatFrame1 end
function FCFDock_SelectWindow(dock, chatFrame) dock._selected = chatFrame end
-- Window names by index (GetChatWindowInfo's first return).
WoW.windowNames = { "General", "Combat Log", "Whispers" }
-- Chat-window settings as the client keeps them per character
-- (GetChatWindowInfo's 10 returns, messages, channels, saved size and place).
-- WoW.chatWindows[i] overrides the defaults built from WoW.windowNames.
WoW.chatWindows = {}
function WoW.window(i)
    local w = WoW.chatWindows[i]
    if not w then
        w = { name = WoW.windowNames[i] or "", size = 14, r = 0, g = 0, b = 0, a = 0.25,
              shown = i <= 3, locked = false, docked = i <= 3 and i or nil, uninteractable = false,
              messages = {}, channels = {} }
        WoW.chatWindows[i] = w
    end
    return w
end
function GetChatWindowInfo(i)
    local w = WoW.window(i)
    return w.name, w.size, w.r, w.g, w.b, w.a, w.shown, w.locked, w.docked, w.uninteractable
end
function GetChatWindowMessages(i) return unpack(WoW.window(i).messages) end
function GetChatWindowChannels(i)
    local out = {}
    for n, c in ipairs(WoW.window(i).channels) do out[#out + 1] = c; out[#out + 1] = n end
    return unpack(out)
end
function GetChatWindowSavedDimensions(i) local w = WoW.window(i); return w.width, w.height end
function GetChatWindowSavedPosition(i) local w = WoW.window(i); return w.point, w.x, w.y end
WoW.layoutCalls = {}
local function setter(field) return function(i, v) WoW.window(i)[field] = v; table.insert(WoW.layoutCalls, field .. i) end end
SetChatWindowName, SetChatWindowAlpha = setter("name"), setter("a")
SetChatWindowDocked, SetChatWindowLocked = setter("docked"), setter("locked")
SetChatWindowUninteractable, SetChatWindowShown = setter("uninteractable"), setter("shown")
function SetChatWindowColor(i, r, g, b) local w = WoW.window(i); w.r, w.g, w.b = r, g, b end
function SetChatWindowSavedDimensions(i, w, h) local c = WoW.window(i); c.width, c.height = w, h; table.insert(WoW.layoutCalls, "dims" .. i) end
function SetChatWindowSavedPosition(i, p, x, y) local c = WoW.window(i); c.point, c.x, c.y = p, x, y; table.insert(WoW.layoutCalls, "pos" .. i) end
WoW.windowUpdates = {}
function FloatingChatFrame_Update(i) table.insert(WoW.windowUpdates, i) end
function FCF_DockUpdate() WoW.dockUpdates = (WoW.dockUpdates or 0) + 1 end
function FCF_SaveDock() WoW.dockSaves = (WoW.dockSaves or 0) + 1 end
-- The per-window display helpers (FloatingChatFrame.lua:1088-1158), recorded.
WoW.shownNames = {}
function FCF_SetWindowName(frame, name) WoW.shownNames[frame:GetID()] = name end
function FCF_SetWindowColor(frame, r, g, b) WoW.shownColor = { frame:GetID(), r, g, b } end
function FCF_SetWindowAlpha(frame, a) WoW.shownAlpha = { frame:GetID(), a } end
-- The window's own methods (ChatFrameMixin, ChatFrame.lua:69-233); a channel
-- adds only if the character is in it (WoW.joined).
WoW.joined = {}
function Methods.RemoveAllMessageGroups(f) WoW.window(f._id).messages = {} end
function Methods.AddMessageGroup(f, g) table.insert(WoW.window(f._id).messages, g) end
function Methods.RemoveAllChannels(f) WoW.window(f._id).channels = {} end
-- Like the client (ChatFrame.lua:149-167): the channel is added whether or
-- not the character is in it, and the return is GetChannelName's id, 0 (a
-- truthy value) for one it isn't in.
function GetChannelName(c) return WoW.joined[c] and 1 or 0 end
function Methods.AddChannel(f, c)
    table.insert(WoW.window(f._id).channels, c)
    return GetChannelName(c)
end
-- WoW's date() is Lua's os.date.
date = os.date
time = os.time
TimeUtil = { BetterDate = function(fmt, t) return os.date(fmt, t) end }
function Methods.ReceiveAllPrivateMessages(f) end
-- ScrollingMessageFrame:AddMessage into the stub's _lines buffer.
function Methods.AddMessage(f, msg, ...)
    f._lines = f._lines or {}
    table.insert(f._lines, { m = msg, extra = { n = select("#", ...), ... } })
end
-- ScrollingMessageFrame:TransformMessages over the stub's _lines buffer
-- (entries { m = text }), as the mixin does (ScrollingMessageFrame.lua:95).
-- ScrollingMessageFrame:RemoveMessagesByPredicate: RemoveIf walks oldest to
-- newest (CircularBuffer.lua:89) and keeps that order.
function Methods.RemoveMessagesByPredicate(f, pred)
    local keep = {}
    for _, e in ipairs(f._lines or {}) do
        if not pred(e.m, unpack(e.extra or {}, 1, e.extra and e.extra.n or 0)) then keep[#keep + 1] = e end
    end
    f._lines = keep
end
-- Storage order: chronological, rotated by f._rot once "wrapped" (as
-- CircularBuffer stores it: the newest lines first, then the older ones).
function Methods.TransformMessages(f, pred, transform)
    local lines = f._lines or {}
    local n, rot = #lines, f._rot or 0
    for k = 1, n do
        local e = lines[(k - 1 + n - rot) % n + 1]
        if pred(e.m, unpack(e.extra or {}, 1, e.extra and e.extra.n or 0)) then e.m = (transform(e.m)) end
    end
end
-- The player, by GUID; their name and realm.
WoW.playerGUID = "Player-1-AAA"
function UnitGUID(unit)
    if unit == "player" then return WoW.playerGUID end
    return WoW.unitGUIDs and WoW.unitGUIDs[unit] or nil
end
-- The Spam & Ignore plugin's lookups: friends, guild, Battle.net, group,
-- the target, the addon's version, atlases.
WoW.friends, WoW.guild, WoW.bnet, WoW.group = {}, {}, {}, {}
C_FriendList = {
    IsFriend = function(guid) return WoW.friends[guid] == true end,
    GetNumFriends = function() return #WoW.friendList end,
    GetFriendInfoByIndex = function(i) return WoW.friendList[i] end,
    GetNumIgnores = function() return WoW.ignores and #WoW.ignores or nil end,
    GetIgnoreName = function(i) return WoW.ignores and WoW.ignores[i] end,
}
function IsGuildMember(guid) return WoW.guild[guid] == true end
-- Names unique across the region (measured true on Forever, FOREVER-PROBE 11).
function RegionalUniqueNamesEnabled() return WoW.uniqueNames ~= false end
C_BattleNet = { GetGameAccountInfoByGUID = function(guid) if WoW.bnet[guid] then return {} end end }
function GetNumGroupMembers() return #WoW.group end
function IsInRaid() return WoW.inRaid == true end
-- Other players' units: WoW.unitGUIDs[unit] and WoW.unitLevels[unit]; a unit
-- with a level is a player.
WoW.unitLevels = {}
function UnitIsPlayer(unit)
    return unit == "player" or (unit == "target" and WoW.targetName ~= nil) or WoW.unitLevels[unit] ~= nil
end
function UnitLevel(unit)
    if unit == "player" then return WoW.playerLevel or 60 end
    return WoW.unitLevels[unit] or 0
end
-- The friends list (FriendInfo, a table) and the guild roster (Retail's
-- GetGuildRosterInfo returns, level 4th and GUID 17th; unmeasured here).
WoW.friendList, WoW.guildRoster = {}, {}
function IsInGuild() return #WoW.guildRoster > 0 end
function GetNumGuildMembers() return #WoW.guildRoster end
function GetGuildRosterInfo(i)
    local m = WoW.guildRoster[i]
    if m then return m.name, "Rank", 1, m.level, "Class", "Zone", "", "", true, 0, "WARRIOR",
        0, 0, false, false, 0, m.guid end
end
C_GuildInfo = { GuildRoster = function() WoW.guildRosterRequested = true end }
-- DifficultyUtil.lua:68: a colour table.
function GetQuestDifficultyColor(level) return { r = 1, g = 0.82, b = 0 } end
function GetUnitName(unit) if unit == "target" then return WoW.targetName end end
WoW.addonVersion = "dev"
-- Installed addons by folder name (GetAddOnInfo's first return is the folder as spelled).
WoW.addons = { "GlassChat", "AltStable", "RestedXP", "ChatProbe" }
C_AddOns = {
    GetAddOnMetadata = function(name, field) if field == "Version" then return WoW.addonVersion end end,
    GetAddOnInfo = function(name)
        for _, a in ipairs(WoW.addons) do if a:lower() == tostring(name):lower() then return a, a end end
        return nil
    end,
}
C_Texture = { GetAtlasInfo = function(name) return name == "socialqueuing-icon-eye" and {} or nil end }
date = os.date
time = os.time
function GetTime() return WoW.now or 0 end
-- Modifier keys held (WoW.mods.shift / ctrl / alt).
WoW.mods = {}
function IsShiftKeyDown() return WoW.mods.shift == true end
function IsControlKeyDown() return WoW.mods.ctrl == true end
function IsAltKeyDown() return WoW.mods.alt == true end
function UnitName(unit) if unit == "player" then return WoW.playerName or "Karuzo", "Morphisto" end end
function GetRealmName() return "Doomhowl" end
-- EventRegistry callbacks: several per event, each called with its owner
-- first (CallbackRegistry.lua:112). WoW.callbacks[event](_, ...) fires them all.
WoW.callbacks, WoW.callbackList = {}, {}
EventRegistry = { RegisterCallback = function(self, event, fn, owner)
    local list = WoW.callbackList[event] or {}
    WoW.callbackList[event] = list
    list[#list + 1] = { fn = fn, owner = owner }
    WoW.callbacks[event] = function(_, ...)
        for _, c in ipairs(list) do c.fn(c.owner, ...) end
    end
end }
-- MenuUtil.CreateContextMenu (Blizzard_Menu): the generator fills a root
-- description; WoW.menu holds its title and buttons ({ text, fn }).
MenuUtil = { CreateContextMenu = function(owner, gen)
    local root = { buttons = {} }
    function root:CreateTitle(t) self.title = t end
    function root:CreateButton(t, fn) table.insert(self.buttons, { text = t, fn = fn }) end
    gen(owner, root)
    WoW.menu = root
end }
-- debugstack: the stack a test sets (WoW.stack), else one with no addon in it.
function debugstack() return WoW.stack or "[C]: ?" end
-- FrameXML's per-window wrapper; temporary windows (id > 10) answer from their tab.
function FCF_GetChatWindowInfo(i)
    if i > 10 then
        local tab = rawget(_G, "ChatFrame" .. i .. "Tab")
        return tab and tab._tabText or "", 14, 1, 1, 1, 1, true, false, false, false
    end
    -- The client's "default size" 0 becomes the real default (line 557).
    local name, size, r, g, b, a, shown, locked, docked, unint = GetChatWindowInfo(i)
    if size == 0 then size = 14 end
    return name, size, r, g, b, a, shown, locked, docked, unint
end
function ScrollingEdit_OnCursorChanged() end
function ScrollingEdit_OnUpdate() end
function Methods.SetVerticalScroll(w, v) w._vscroll = v end
-- A voice-style button beside the chat (VoiceToggleButtonTemplate): its
-- frame is the normal and pushed art, its symbol a separate Icon.
function Methods.GetNormalTexture(b) return b._normal end
function Methods.GetPushedTexture(b) return b._pushed end
function Methods.GetHighlightTexture(b) return b._highlight end
ChatFrameChannelButton = newWidget("Button", UIParent, "ChatFrameChannelButton")
ChatFrameChannelButton._level = 6
for _, k in ipairs({ "_normal", "_pushed", "_highlight" }) do ChatFrameChannelButton[k] = newWidget("Texture", ChatFrameChannelButton) end
-- The TTS button: the same template, plus an opaque black Background square
-- (TextToSpeech.xml:17-24), and Blizzard's UpdateHighlight, which re-sets
-- the highlight on every state change (PropertyButton.lua:60-67).
TextToSpeechButton = newWidget("Button", UIParent, "TextToSpeechButton")
TextToSpeechButton._level = 6
for _, k in ipairs({ "_normal", "_pushed", "_highlight" }) do TextToSpeechButton[k] = newWidget("Texture", TextToSpeechButton) end
TextToSpeechButton.Background = newWidget("Texture", TextToSpeechButton)
rawset(TextToSpeechButton, "UpdateHighlight", function(self) self._highlight._alpha = 1 end)
-- The chat-menu button (FloatingChatFrame.xml:723): file art for normal,
-- pushed and disabled, the frame baked in.
function Methods.GetDisabledTexture(b) return b._disabled end
function Methods.IsEnabled(b) return b._enabled ~= false end
function Methods.SetAtlas(t, name) t._atlas = name end
ChatFrameMenuButton = newWidget("Button", UIParent, "ChatFrameMenuButton")
ChatFrameMenuButton._level = 6
for _, k in ipairs({ "_normal", "_pushed", "_disabled", "_highlight" }) do ChatFrameMenuButton[k] = newWidget("Texture", ChatFrameMenuButton) end
-- The friends button (QuickJoinToast.xml:31): its FriendsButton texture, and
-- Blizzard's press handlers swapping the framed -down/-up art (QuickJoinToast.lua:344-351).
QuickJoinToastButton = newWidget("Button", UIParent, "QuickJoinToastButton")
QuickJoinToastButton._level = 4
for _, k in ipairs({ "_highlight" }) do QuickJoinToastButton[k] = newWidget("Texture", QuickJoinToastButton) end
QuickJoinToastButton.FriendsButton = newWidget("Texture", QuickJoinToastButton)
QuickJoinToastButton.FriendsButton._atlas = "quickjoin-button-friendslist-up"
QuickJoinToastButton._scripts.OnMouseDown = function(self) self.FriendsButton:SetAtlas("quickjoin-button-friendslist-down") end
QuickJoinToastButton._scripts.OnMouseUp = function(self) self.FriendsButton:SetAtlas("quickjoin-button-friendslist-up") end
-- The shared tooltip (records its owner and text).
GameTooltip = newWidget("GameTooltip", UIParent, "GameTooltip")
GameTooltip._shown = false
function Methods.SetOwner(tt, owner) tt._owner = owner end
-- FrameXML's list of frames Escape closes.
UISpecialFrames = {}
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

function GetBuildInfo() return "1.60.1", "70291", "Oct 8 2026", 16001 end
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

--------------------------------------------------------------------------------
-- Battle.net, for the embedded LibAccountSync-1.0 (ported from its own
-- tests/wow_stubs.lua: game account ids are local handles, an unknown id is
-- TargetRequired (6), an offline one TargetOffline (12), BN_CHAT_MSG_ADDON
-- delivers (prefix, text, "WHISPER", senderID)). Every function is in the
-- 70205 and 70291 dumps.
-- WoW.bn.accounts[id] = { characterName, playerGuid, isOnline, clientProgram,
--   wowProjectID, regionID, isInCurrentRegion, factionName, realmName,
--   bnetAccountID } declares an account this client can see.
--------------------------------------------------------------------------------

WoW.bn = { me = 1, myId = 2, project = 18, region = 90, tag = "Owner#1", connected = true,
           accounts = {}, friends = {} }
WoW.prefixes, WoW.bnSent, WoW.sendResults = {}, {}, {}
WoW.player = { faction = "Alliance" }

local function bnSelf()
    return { gameAccountID = WoW.bn.myId, characterName = (UnitName("player")), playerGuid = UnitGUID("player"),
             isOnline = true, clientProgram = "WoW", wowProjectID = WoW.bn.project, regionID = WoW.bn.region,
             isInCurrentRegion = true, factionName = WoW.player.faction, realmName = GetRealmName() }
end
local function bnCopy(t, id)
    if not t then return nil end
    local c = {}
    for k, v in pairs(t) do if k ~= "bnetAccountID" and k ~= "battleTag" then c[k] = v end end
    c.gameAccountID = id
    return c
end
function C_BattleNet.GetGameAccountInfoByID(id)
    if id == WoW.bn.myId then return bnSelf() end
    return bnCopy(WoW.bn.accounts[id], id)
end
-- Spam & Ignore's Battle.net-friend check (WoW.bnet[guid]) first, then the accounts.
function C_BattleNet.GetGameAccountInfoByGUID(guid)
    if WoW.bnet[guid] then return {} end
    if guid == UnitGUID("player") then return bnSelf() end
    for id, a in pairs(WoW.bn.accounts) do
        if a.playerGuid == guid then return bnCopy(a, id) end
    end
end
function C_BattleNet.GetAccountInfoByGUID(guid)
    if guid == UnitGUID("player") then
        return { bnetAccountID = WoW.bn.me, battleTag = WoW.bn.tag, gameAccountInfo = bnSelf() }
    end
    for id, a in pairs(WoW.bn.accounts) do
        if a.playerGuid == guid then
            local tag = (a.bnetAccountID == WoW.bn.me) and WoW.bn.tag or ("Other#" .. tostring(a.bnetAccountID))
            return { bnetAccountID = a.bnetAccountID, battleTag = tag, gameAccountInfo = bnCopy(a, id) }
        end
    end
end
function C_BattleNet.SendGameData(id, prefix, text)
    local result = table.remove(WoW.sendResults, 1)
    if result == nil then
        local a = (id == WoW.bn.myId) and bnSelf() or WoW.bn.accounts[id]
        result = (a == nil) and 6 or (a.isOnline and 0 or 12)
    end
    if result ~= 0 then return result end
    table.insert(WoW.bnSent, { prefix = prefix, text = text, target = id })
    return 0
end
function C_BattleNet.GetFriendNumGameAccounts(i) return #(WoW.bn.friends[i] or {}) end
function C_BattleNet.GetFriendGameAccountInfo(i, j)
    local id = (WoW.bn.friends[i] or {})[j]
    if not id then return nil end
    return C_BattleNet.GetGameAccountInfoByID(id) or { gameAccountID = id }
end
function BNFeaturesEnabledAndConnected() return WoW.bn.connected ~= false end
function BNGetNumFriends() return #WoW.bn.friends, #WoW.bn.friends end
function BNGetInfo() return WoW.bn.me, WoW.bn.tag end

function C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    WoW.prefixes[prefix] = true
    return 0
end
function UnitFactionGroup(unit) if unit == "player" then return WoW.player.faction, WoW.player.faction end end
function IsLoggedIn() return WoW.loggedIn == true end
function GetServerTime() return time() end
function debugprofilestop() return (GetTime() or 0) * 1000 end
function fastrandom(a, b) return math.random(a, b) end
function geterrorhandler() return function(err) table.insert(WoW.errors, err) end end
WoW.errors = {}
function securecallfunction(fn, ...)
    local r = { pcall(fn, ...) }
    if not r[1] then geterrorhandler()(r[2]); return end
    return unpack(r, 2, table.maxn(r))
end
function C_Timer.NewTicker(seconds, fn)
    local t = { s = seconds, fn = fn, every = seconds }
    table.insert(WoW.timers, t)
    return { Cancel = function() t.cancelled = true end }
end

-- ChatThrottleLib as a stub (version 10000, so the library's vendored v32
-- steps aside), with v32's checks: a known priority, WHISPER, at most 255
-- bytes, and the callback (arg, didSend, result).
local CTL_PRIORITIES = { BULK = true, NORMAL = true, ALERT = true }
ChatThrottleLib = {
    version = 10000,
    BNSendGameData = function(self, prio, prefix, text, chattype, gameAccountID, q, callbackFn, callbackArg)
        if not CTL_PRIORITIES[prio] or not gameAccountID or chattype ~= "WHISPER" then
            error("ChatThrottleLib:BNSendGameData(): bad arguments", 2)
        end
        if #text > 255 then error("ChatThrottleLib:BNSendGameData(): message length cannot exceed 255 bytes", 2) end
        local ok, r = pcall(C_BattleNet.SendGameData, gameAccountID, prefix, text)
        if not ok then geterrorhandler()(r); r = 9 end
        if callbackFn then securecallfunction(callbackFn, callbackArg, r == 0, r) end
    end,
}

-- LibStub: the embedded library's own loader reads _G.LibStub before creating it.
local allowNil = { GlassChat = true, GlassChatDB = true, GlassChatCharDB = true, ChatProbeDB = true,
    GlassChatSpamIgnoreDB = true, GlassChatSpamIgnoreCharDB = true, LibStub = true, AltStable = true,
    GlassChatSyncDB = true, GlassChatSpamIgnoreSyncDB = true }
-- Client string alias (in the dump's _G walk); LibStub's version check uses it.
strmatch = string.match
setmetatable(_G, { __index = function(_, k)
    if allowNil[k] then return nil end
    error("read of undefined global '" .. tostring(k) .. "' (not stubbed: is it in the API dump?)", 2)
end })
