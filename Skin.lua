-- Skin.lua: a dark, translucent glass panel behind every chat window and its
-- edit box. Readability first (owner): the chat always stays visible, the
-- panel is darker than the other Glass addons' material, and nothing glossy
-- sits over the text.
--
-- Blizzard's own background (CHAT_FRAME_TEXTURES) is HIDDEN, not faded: its
-- hover fade only touches textures that are shown (FCF_FadeInChatFrame,
-- FloatingChatFrame.lua:1336-1340) and nothing re-shows them, so a hidden
-- one stays hidden. The edit box border is set to alpha 0 instead, because
-- its focus textures are toggled with SetShown (ChatFrameEditBoxOverrides.lua:27).
-- Every visual is our own frame, a child of the Blizzard one; no field is
-- written on a Blizzard frame.

GlassChat = GlassChat or {}
local GC = GlassChat
local Glass = GC.Glass
local Skin = {}
GC.Skin = Skin

-- FrameXML's list (FloatingChatFrame.lua:43), with a copy for safety.
local FRAME_TEXTURES = CHAT_FRAME_TEXTURES or {
    "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
    "LeftTexture", "RightTexture", "BottomTexture", "TopTexture",
    "ButtonFrameBackground", "ButtonFrameTopLeftTexture", "ButtonFrameBottomLeftTexture",
    "ButtonFrameTopRightTexture", "ButtonFrameBottomRightTexture", "ButtonFrameLeftTexture",
    "ButtonFrameRightTexture", "ButtonFrameBottomTexture", "ButtonFrameTopTexture",
}
local EDIT_TEXTURES = { "Left", "Right", "Mid", "FocusLeft", "FocusRight", "FocusMid" }

-- The look: the material, made darker and flatter for text.
Skin.GRAIN, Skin.WASH = 0.2, 0.05
Skin.RIM_IDLE, Skin.RIM_FOCUS = 0.45, 0.9
-- px the panel reaches past Blizzard's background (owner: "a little more
-- padding" than the 2 px first shipped).
Skin.PAD_X, Skin.PAD_Y = 8, 5
Skin.EDIT_INSET = 4       -- the edit box art is 32 px tall; the box reads smaller

local panels = setmetatable({}, { __mode = "k" })   -- Blizzard frame -> { panel, g }

local function tune(g)
    g.tint:SetColorTexture(0, 0, 0, GC.db.alpha)
    g.grain:SetAlpha(Skin.GRAIN)
    g.wash:SetAlpha(Skin.WASH)
end

local function newPanel(parent, size)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetFrameLevel(math.max(0, parent:GetFrameLevel() - 1))
    local g = Glass.Apply(panel, size)
    g.rim:SetAlpha(Skin.RIM_IDLE)
    tune(g)
    return panel, g
end

local function setTextures(prefix, names, shown)
    for _, n in ipairs(names) do
        local t = rawget(_G, prefix .. n)
        if t then t:SetShown(shown) end
    end
end

local function setEditArt(prefix, alpha)
    for _, n in ipairs(EDIT_TEXTURES) do
        local t = rawget(_G, prefix .. n)
        if t then t:SetAlpha(alpha) end
    end
end

function Skin.Frame(f)
    local name = f:GetName()
    local on = GC.db.glass
    local p = panels[f]
    if on and not p then
        -- Exactly over Blizzard's background rectangle (FloatingChatFrame.xml:6-12).
        local bg = rawget(_G, name .. "Background") or f
        local panel, g = newPanel(f, "large")
        panel:SetPoint("TOPLEFT", bg, "TOPLEFT", -Skin.PAD_X, Skin.PAD_Y)
        panel:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", Skin.PAD_X, -Skin.PAD_Y)
        p = { panel = panel, g = g }
        panels[f] = p
    end
    if p then p.panel:SetShown(on); tune(p.g) end
    setTextures(name, FRAME_TEXTURES, not on)

    local edit = rawget(_G, name .. "EditBox")
    if not edit then return end
    local e = panels[edit]
    if on and not e then
        local panel, g = newPanel(edit, "small")
        panel:SetPoint("TOPLEFT", edit, "TOPLEFT", 0, -Skin.EDIT_INSET)
        panel:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", 0, Skin.EDIT_INSET)
        e = { panel = panel, g = g }
        panels[edit] = e
        -- Focus shows on the rim, since the focus art is hidden.
        edit:HookScript("OnEditFocusGained", function() e.g.rim:SetAlpha(Skin.RIM_FOCUS) end)
        edit:HookScript("OnEditFocusLost", function() e.g.rim:SetAlpha(Skin.RIM_IDLE) end)
    end
    if e then e.panel:SetShown(on); tune(e.g) end
    setEditArt(edit:GetName(), on and 0 or 1)
end

-- Tabs (owner: "really small and hard to read"). Three changes, all on
-- widgets or through Blizzard's own setter; no field or global is written:
-- - a bigger font with a shadow. It's set at ADDON_LOADED, before Blizzard
--   names the tabs (FloatingChatFrame_Update -> FCF_SetWindowName, line 585),
--   and the name sizes the tab, so the tab fits the bigger text. A live size
--   change fits fully after a /reload;
-- - a small glass pill behind the name instead of the stock tab art, with a
--   brighter rim on the selected tab;
-- - higher resting opacity (stock: selected 0.4, others 0.2), set with
--   ChatFrameUtil.SetTabAlphas after Blizzard's FCFTab_UpdateAlpha. That
--   table is read through securecallfunction precisely so an addon's write
--   doesn't spread (ChatFrameUtil.lua:89-91).
Skin.TAB_REST = { selected = 0.9, other = 0.6 }
Skin.TAB_HOVER = 1
Skin.TAB_PAD_X, Skin.TAB_PAD_Y = 8, 4
local TAB_ART = { "Left", "Middle", "Right" }   -- the stock tab background (parentKeys)
local tabFont = setmetatable({}, { __mode = "k" })   -- tab -> its stock font, for glass off

local function tabOf(f) return rawget(_G, f:GetName() .. "Tab") end

-- Selected (or alerting) tabs rest at mouse-over 1 in stock; the others lower.
local function applyTabAlpha(f)
    local tab = tabOf(f)
    if not (tab and GC.db.glass and ChatFrameUtil and ChatFrameUtil.GetTabAlphas) then return end
    local over, rest = ChatFrameUtil.GetTabAlphas(tab)
    if type(over) ~= "number" or type(rest) ~= "number" then return end   -- not set up by Blizzard yet
    local floor = (over >= 1) and Skin.TAB_REST.selected or Skin.TAB_REST.other
    rest = math.max(rest, floor)
    over = math.max(over, Skin.TAB_HOVER)
    ChatFrameUtil.SetTabAlphas(tab, over, rest)
    tab:SetAlpha(f.hasBeenFaded and over or rest)
end

function Skin.Tab(f)
    local tab = tabOf(f)
    local text = tab and tab:GetFontString()
    if not text then return end
    local on = GC.db.glass
    if not tabFont[tab] then
        local file, size, flags = text:GetFont()
        tabFont[tab] = { file = file, size = size, flags = flags, height = text:GetHeight() }
    end
    local o = tabFont[tab]
    if on then
        text:SetFont(o.file, GC.db.tabSize, "")
        text:SetHeight(GC.db.tabSize + 4)   -- the template's 8 px would clip it
        text:SetShadowOffset(1, -1)
        text:SetShadowColor(0, 0, 0, 1)
    else
        text:SetFont(o.file, o.size, o.flags)
        text:SetHeight(o.height)
    end

    local t = panels[tab]
    if on and not t then
        local panel, g = newPanel(tab, "small")
        panel:SetPoint("TOPLEFT", text, "TOPLEFT", -Skin.TAB_PAD_X, Skin.TAB_PAD_Y)
        panel:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", Skin.TAB_PAD_X, -Skin.TAB_PAD_Y)
        t = { panel = panel, g = g }
        panels[tab] = t
    end
    if t then t.panel:SetShown(on); tune(t.g) end
    for _, k in ipairs(TAB_ART) do
        local tex = tab[k]
        if tex then tex:SetAlpha(on and 0 or 1) end
    end
    applyTabAlpha(f)
end

-- Re-apply after a setting change (glass on/off, opacity, tab size).
function Skin.Refresh()
    for _, f in ipairs(GC.Chat.Frames()) do Skin.Frame(f); Skin.Tab(f) end
end

GC.Chat.OnEachFrame("skin", Skin.Frame)
GC.Chat.OnEachFrame("tabs", Skin.Tab)

-- After Blizzard's own tab updates (selection, docking, alerts).
function Skin.HookTabs()
    if rawget(_G, "FCFTab_UpdateAlpha") then hooksecurefunc("FCFTab_UpdateAlpha", applyTabAlpha) end
    if rawget(_G, "FCFTab_UpdateColors") then
        hooksecurefunc("FCFTab_UpdateColors", function(tab, selected)
            local t = panels[tab]
            if t then t.g.rim:SetAlpha(selected and Skin.RIM_FOCUS or Skin.RIM_IDLE) end
        end)
    end
end

Skin._test = { panels = panels, tabFont = tabFont, applyTabAlpha = applyTabAlpha }
