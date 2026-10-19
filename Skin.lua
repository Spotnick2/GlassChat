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

-- Pearl, tuned for text: charcoal reading surface, a quieter tab strip,
-- thin pale rims and no wash over the words. Consumer tuning stays on the
-- regions Glass.Apply returns; the embedded material is not edited here.
Skin.TINT = { 0.05, 0.05, 0.06 }
-- The wash is a gradient, which ignores SetAlpha on Forever (porting guide
-- §3, LibGlass#47): it goes through Glass.SetWash, on the window and edit
-- box panels only (#95). Until r7 it was set with SetAlpha and never left.
Skin.GRAIN, Skin.WASH = 0, 0
Skin.RIM_IDLE, Skin.RIM_FOCUS = 0.38, 0.70
Skin.PEARL = { 0.86, 0.90, 0.94 }

-- The window panel's surface, live-tunable (/gchat tune <key> <value>) and
-- saved account-wide in GlassChatDB.look; these are the shipped values.
-- The header's sheen stays short and subdued. Existing saved /gchat tune
-- values take precedence; reset them only when comparing the Pearl defaults.
Skin.LOOK = {
    shadow = 0,     -- the material's drop shadow
    rim = 0.38,     -- Pearl's thin rim, quiet around the reading surface
    dark = 0.20,    -- restrained lower definition
    grain = 0,      -- frost over the body
    top = 0.32,     -- the fine bright line along the top edge
    glow = 0.06,    -- the sheen under it, at its brightest
    glowh = 3,      -- confined to the header (px)
    bottom = 0.18,  -- the dark line along the bottom edge
}
Skin.LOOK_MAX = { glowh = 20 }   -- the others are opacities, 0..1

function Skin.Look(key)
    local saved = GC.db.look
    local v = type(saved) == "table" and saved[key]
    if type(v) == "number" then return v end
    return Skin.LOOK[key]
end
-- px the panel reaches past Blizzard's background (owner: "a little more
-- padding" than the 2 px first shipped).
Skin.PAD_X, Skin.PAD_Y = 8, 5
-- The panel reaches up over the tab strip, so tabs and text share one glass
-- container (owner's mockup). Tabs sit on Background's TOPLEFT
-- (FCF_SetTabPosition, FloatingChatFrame.lua:1835), their name ~11 px up.
Skin.TAB_STRIP = 26
-- Space between the tabs and the first chat line (owner, after the mockup).
-- The lines are clipped to the chat frame (FontStringContainer,
-- ScrollingMessageFrame.xml:10), which Edit Mode owns, so the TABS move up:
-- the dock is re-anchored GAP px higher (Blizzard anchors it in
-- FCFDock_SetPrimary, FloatingChatFrame.lua:2265), and so is a floating
-- window's own tab (FCF_SetTabPosition, line 1835).
Skin.TAB_GAP = 8
Skin.SEPARATOR = { 1, 1, 1, 0.14 }   -- the line between the tabs and the text
Skin.EDIT_INSET = 4       -- the edit box art is 32 px tall; the box reads smaller

local panels = setmetatable({}, { __mode = "k" })   -- Blizzard frame -> { panel, g }

-- The window panel's surface from Skin.Look (after tune(), which sets the
-- grain for every panel).
function Skin.WindowLook(p)
    local L, g = Skin.Look, p.g
    g.rim:SetVertexColor(Skin.PEARL[1], Skin.PEARL[2], Skin.PEARL[3])
    g.shadow:SetAlpha(L("shadow"))
    g.rim:SetAlpha(L("rim"))
    g.dark:SetAlpha(L("dark"))
    g.grain:SetAlpha(L("grain"))
    Glass.SetEdge(g, L("top"), L("glow"), L("bottom"), L("glowh"))
    p.header:SetColorTexture(Skin.TINT[1], Skin.TINT[2], Skin.TINT[3], GC.db.shellAlpha)
end

local function tune(g)
    g.tint:SetColorTexture(Skin.TINT[1], Skin.TINT[2], Skin.TINT[3], GC.db.alpha)
    g.grain:SetAlpha(Skin.GRAIN)
end

-- A shell surface keeps its own opacity: making chat easier to read must
-- not turn all five side pills opaque. Called on every scan, including the
-- alert/plugin pills, so settings changes reach already-created buttons.
function Skin.PillLook(g)
    g.tint:SetColorTexture(Skin.TINT[1], Skin.TINT[2], Skin.TINT[3], GC.db.shellAlpha)
    g.grain:SetAlpha(0)
    g.shadow:SetAlpha(0)
    g.dark:SetAlpha(0.20)
    g.rim:SetVertexColor(Skin.PEARL[1], Skin.PEARL[2], Skin.PEARL[3])
    g.rim:SetAlpha(Skin.RIM_IDLE)
    Glass.SetWash(g, Glass.STYLE.wash)
end

-- The chat window's panel reaches up behind the tabs, so it must sit under
-- them. As a child of the chat frame it drew OVER the MEDIUM-strata tabs,
-- even after its own SetFrameStrata("BACKGROUND") (measured: names washed
-- out, the tab itself at alpha 1). A strata set on a parent is applied to
-- its children, and something sets the chat frame's. So the window panel
-- is a child of UIParent, pinned to BACKGROUND, and follows the chat
-- frame's OnShow/OnHide. The edit box panel stays a child of its box.
local function newPanel(parent, size, strata)
    local panel = CreateFrame("Frame", nil, strata and UIParent or parent)
    if strata then
        panel:SetFrameStrata(strata)
        panel:SetFrameLevel(1)
    else
        panel:SetFrameLevel(math.max(0, parent:GetFrameLevel() - 1))
    end
    local g = Glass.Apply(panel, size)
    g.rim:SetVertexColor(Skin.PEARL[1], Skin.PEARL[2], Skin.PEARL[3])
    g.rim:SetAlpha(Skin.RIM_IDLE)
    g.dark:SetAlpha(0.20)
    g.shadow:SetAlpha(0)
    Glass.SetWash(g, Skin.WASH)
    tune(g)
    return panel, g
end

-- Idle (owner, #108): with nothing to read, the window goes clear. Blizzard
-- fades each line GetTimeVisible() + GetFadeDuration() s after it was added
-- or the window was scrolled (ResetAllFadeTimes, ScrollingMessageFrame.lua:
-- 131-161), and the tabs and buttons once the mouse leaves
-- (FCF_FadeInChatFrame / FCF_FadeOutChatFrame, FloatingChatFrame.lua:
-- 1237-1301), but the dark panel stayed over nothing (owner's screenshot).
-- Idle, the reading, tab strip and edit box fills fade to db.idleAlpha; the
-- rim and edge stay, so the glass is still there. Driven by Skin.StartIdle.
Skin.WAKE_TIME, Skin.SLEEP_TIME = 0.25, 2.0   -- s; Blizzard's tabs take 0.15 and 2.0
Skin.IDLE_EVERY = 0.2                         -- s between checks

local wake = setmetatable({}, { __mode = "k" })      -- chat frame -> 0 (idle) .. 1 (awake)
local target = setmetatable({}, { __mode = "k" })    -- chat frame -> 0 or 1, from the last check
local active = setmetatable({}, { __mode = "k" })    -- chat frame -> GetTime() of its last line or scroll
local counted = setmetatable({}, { __mode = "k" })   -- chat frame -> Chat.LineCount at the last check
local hovered = setmetatable({}, { __mode = "k" })   -- between Blizzard's fade in and fade out
local sinceCheck = 0
local function poke() sinceCheck = Skin.IDLE_EVERY end   -- check on the next frame

local function editOf(f) return rawget(_G, f:GetName() .. "EditBox") end

-- The fills at wake[f], between the idle opacity (0) and the reading ones
-- (1). An idle opacity above a reading one never darkens it.
local function paintIdle(f)
    local k, T = wake[f] or 1, Skin.TINT
    local function mix(full)
        if k >= 1 then return full end   -- awake: exactly the saved opacity
        local idle = math.min(GC.db.idleAlpha, full)
        return idle + (full - idle) * k
    end
    local p = panels[f]
    if p then
        p.g.tint:SetColorTexture(T[1], T[2], T[3], mix(GC.db.alpha))
        p.header:SetColorTexture(T[1], T[2], T[3], mix(GC.db.shellAlpha))
    end
    local edit = editOf(f)
    local e = edit and panels[edit]
    if e then e.g.tint:SetColorTexture(T[1], T[2], T[3], mix(GC.db.alpha)) end
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
        local panel, g = newPanel(f, "large", "BACKGROUND")
        panel:SetPoint("TOPLEFT", bg, "TOPLEFT", -Skin.PAD_X, Skin.PAD_Y + Skin.TAB_STRIP + Skin.TAB_GAP)
        panel:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", Skin.PAD_X, -Skin.PAD_Y)
        local sep = panel:CreateTexture(nil, "ARTWORK")
        sep:SetColorTexture(Skin.SEPARATOR[1], Skin.SEPARATOR[2], Skin.SEPARATOR[3], Skin.SEPARATOR[4])
        -- At the tabs' bottom edge (the strip is TAB_GAP up, LiftDock /
        -- liftTab), under the selected tab's accent underline: PAD_Y higher, it
        -- crossed the tab names and the strip's icons (owner's screenshot).
        sep:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, Skin.TAB_GAP)
        sep:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 0, Skin.TAB_GAP)
        sep:SetHeight(1)
        -- Two adjacent masked fills, never stacked: /gchat alpha stays the
        -- actual reading opacity even when shellalpha is higher or lower.
        -- The seam is exactly under the existing separator. Both textures
        -- belong to panel, the owner of g.mask, and follow its resize.
        local headerHeight = Skin.PAD_Y + Skin.TAB_STRIP
        g.tint:ClearAllPoints()
        g.tint:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -headerHeight)
        g.tint:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
        local header = panel:CreateTexture(nil, "BACKGROUND", nil, -6)
        header:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        header:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, -headerHeight)
        header:AddMaskTexture(g.mask)
        -- The directional edge is the material's own (g.edge, GlassUnitFrames
        -- #60), set to this window's values in Skin.WindowLook.
        p = { panel = panel, g = g, header = header, separator = sep, edge = g.edge }
        panels[f] = p
        -- The panel follows the chat frame's size: refit the lines then.
        panel:SetScript("OnSizeChanged", function() Skin.FitLines(f) end)
        -- Shown again (its tab selected): refit too, since a hidden window
        -- may have been resized while its panel was hidden.
        f:HookScript("OnShow", function()
            if GC.db.glass then panel:Show() end
            Skin.FitLines(f)
        end)
        f:HookScript("OnHide", function() panel:Hide() end)
    end
    if p then p.panel:SetShown(on and f:IsShown()); tune(p.g); Skin.WindowLook(p) end
    setTextures(name, FRAME_TEXTURES, not on)
    Skin.FitLines(f)

    local edit = editOf(f)
    if not edit then paintIdle(f); return end
    local e = panels[edit]
    if on and not e then
        local panel, g = newPanel(edit, "small")
        panel:SetPoint("TOPLEFT", edit, "TOPLEFT", 0, -Skin.EDIT_INSET)
        panel:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", 0, Skin.EDIT_INSET)
        e = { panel = panel, g = g }
        panels[edit] = e
        -- Focus shows on the rim, since the focus art is hidden.
        edit:HookScript("OnEditFocusGained", function() e.g.rim:SetAlpha(Skin.RIM_FOCUS); poke() end)
        edit:HookScript("OnEditFocusLost", function() e.g.rim:SetAlpha(Skin.RIM_IDLE); poke() end)
    end
    if e then e.panel:SetShown(on); tune(e.g) end
    setEditArt(edit:GetName(), on and 0 or 1)
    paintIdle(f)   -- after tune and WindowLook, which paint the reading opacities
end

-- Whole lines only under the header (critique: "the first visible line is
-- cut through"). Blizzard stacks the lines up from the frame's bottom and
-- clips them to FontStringContainer, which covers the frame
-- (ScrollingMessageFrame.lua:578-610, .xml:10), so the top line is cut
-- wherever the height runs out. Lowering the container's top edge to a whole
-- number of lines leaves only full lines (exact when message spacing is 0,
-- as in chat). Refit on resize (the panel's OnSizeChanged: Blizzard sets the
-- chat frame's own OnSizeChanged with SetScript) and on font size changes.
Skin.TEXT_GAP = 2
-- A line's descenders can reach a pixel or two below its box, so a boundary
-- exactly on a line edge still showed a sliver of the line above (measured:
-- a fragment over the first full line). Cut that far into the first full
-- line's empty top instead.
Skin.FIT_TRIM = 2
local measure
local function lineHeight(f)
    local file, size, flags = f:GetFont()
    if not (file and size) then return nil end
    if not measure then
        measure = UIParent:CreateFontString(nil, "BACKGROUND")
        measure:Hide()
    end
    measure:SetFont(file, size, flags)
    measure:SetText("Ag")
    local lh = measure:GetLineHeight()
    if type(lh) == "number" and lh > 0 then return lh + (f:GetSpacing() or 0) end
end

function Skin.FitLines(f)
    local box = f.FontStringContainer
    if not box then return end
    local lh, h = lineHeight(f), f:GetHeight()
    if not (GC.db.glass and lh and h and h > lh) then
        box:ClearAllPoints()
        box:SetAllPoints(f)
        return
    end
    local n = math.floor((h - Skin.TEXT_GAP) / lh)
    if n < 1 then   -- shorter than one line plus the gap: never an empty box
        box:ClearAllPoints()
        box:SetAllPoints(f)
        return
    end
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(h - n * lh + Skin.FIT_TRIM))
    box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
end

-- Tabs (owner: "really small and hard to read", then the mockup: tabs
-- inside the glass, the selected one lit with a gold underline, the others
-- plain). All on widgets, or through Blizzard's own setter; no field or
-- global is written:
-- - a bigger font with a shadow. It's set at ADDON_LOADED, before Blizzard
--   names the tabs (FloatingChatFrame_Update -> FCF_SetWindowName, line 585),
--   and the name sizes the tab, so the tab fits the bigger text. A live size
--   change fits fully after a /reload;
-- - the stock tab art (background, selected and highlight pieces) at alpha 0:
--   FCFTab_UpdateColors toggles the selected pieces with Show/Hide, which
--   doesn't touch alpha;
-- - for the selected tab, a faint fill and a gold underline (textures under
--   the name); other names light grey. Re-applied after FCFTab_UpdateColors;
-- - higher resting opacity (stock: selected 0.4, others 0.2), set with
--   ChatFrameUtil.SetTabAlphas after Blizzard's FCFTab_UpdateAlpha. That
--   table is read through securecallfunction precisely so an addon's write
--   doesn't spread (ChatFrameUtil.lua:89-91).
Skin.TAB_REST = { selected = 1, other = 0.9 }
Skin.TAB_HOVER = 1
Skin.TAB_PAD_X, Skin.TAB_PAD_Y = 10, 5
Skin.TAB_GOLD = { 1, 0.82, 0 }
-- Gold remains the alert resting colour; navigation uses Pearl's ice blue.
Skin.ACCENT = { 0.65, 0.835, 0.905 }
Skin.TAB_GREY = { 0.8, 0.8, 0.8 }
Skin.TAB_FILL = 0.08
local TAB_ART = { "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight" }   -- parentKeys (FloatingChatFrame.xml:245-320)
local tabFont = setmetatable({}, { __mode = "k" })   -- tab -> its stock font, for glass off
local tabLit = setmetatable({}, { __mode = "k" })    -- tab -> { fill, line }

local function tabOf(f) return rawget(_G, f:GetName() .. "Tab") end

-- Selected (or alerting) tabs rest at mouse-over 1 in stock; the others
-- lower. Blizzard's own pair is remembered when it sets one (the hook), so a
-- later scan never mistakes our raised values for a selected tab.
local blizzAlphas = setmetatable({}, { __mode = "k" })   -- tab -> { over, rest } as Blizzard set them

local function raiseTab(tab, over, rest)
    local floor = (over >= 1) and Skin.TAB_REST.selected or Skin.TAB_REST.other
    local newRest, newOver = math.max(rest, floor), math.max(over, Skin.TAB_HOVER)
    -- Faded in now? Blizzard has just set the tab to its own over or rest.
    local fadedIn = over ~= rest and math.abs(tab:GetAlpha() - over) < 0.001
    ChatFrameUtil.SetTabAlphas(tab, newOver, newRest)
    tab:SetAlpha(fadedIn and newOver or newRest)
end

-- After Blizzard's FCFTab_UpdateAlpha: its values are fresh.
local function onTabAlpha(f)
    local tab = tabOf(f)
    if not (tab and ChatFrameUtil and ChatFrameUtil.GetTabAlphas) then return end
    local over, rest = ChatFrameUtil.GetTabAlphas(tab)
    if type(over) ~= "number" or type(rest) ~= "number" then return end
    blizzAlphas[tab] = { over, rest }
    if GC.db.glass then raiseTab(tab, over, rest) end
end

-- From a scan: only from Blizzard's remembered pair.
local function applyTabAlpha(f)
    local tab = tabOf(f)
    local b = tab and blizzAlphas[tab]
    if not (b and ChatFrameUtil and ChatFrameUtil.SetTabAlphas) then return end
    if GC.db.glass then
        raiseTab(tab, b[1], b[2])
    else
        ChatFrameUtil.SetTabAlphas(tab, b[1], b[2])
    end
end

-- The selected look, or the plain one; nothing with glass off.
local function paintTab(tab, selected)
    local lit = tabLit[tab]
    if not lit then return end
    local on = GC.db.glass
    lit.fill:SetShown(on and selected)
    lit.line:SetShown(on and selected)
    if on then
        local c = selected and Skin.ACCENT or Skin.TAB_GREY
        tab:GetFontString():SetTextColor(c[1], c[2], c[3])
    end
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

    if not tabLit[tab] then
        local fill = tab:CreateTexture(nil, "BACKGROUND")
        fill:SetColorTexture(Skin.ACCENT[1], Skin.ACCENT[2], Skin.ACCENT[3], Skin.TAB_FILL)
        fill:SetPoint("TOPLEFT", text, "TOPLEFT", -Skin.TAB_PAD_X, Skin.TAB_PAD_Y)
        fill:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", Skin.TAB_PAD_X, -Skin.TAB_PAD_Y)
        local line = tab:CreateTexture(nil, "BORDER")
        line:SetColorTexture(Skin.ACCENT[1], Skin.ACCENT[2], Skin.ACCENT[3], 1)
        line:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, 0)
        line:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
        line:SetHeight(2)
        tabLit[tab] = { fill = fill, line = line }
    end
    for _, k in ipairs(TAB_ART) do
        local tex = tab[k]
        if tex then tex:SetAlpha(on and 0 or 1) end
    end
    -- Blizzard shows the selected pieces on the selected tab: read that.
    paintTab(tab, tab.ActiveMiddle ~= nil and tab.ActiveMiddle:IsShown())
    applyTabAlpha(f)
end

-- The window panel of a chat frame (nil before it's built or with glass off
-- from the start): other modules put their controls on it.
function Skin.Panel(f)
    return panels[f]
end

-- Re-apply after a setting change (glass on/off, opacity, tab size).
function Skin.Refresh()
    GC.Chat.Scan()
end

GC.Chat.OnEachFrame("skin", Skin.Frame)
GC.Chat.OnEachFrame("tabs", Skin.Tab)

-- The tab strip, GAP px up with glass on, where Blizzard put it with glass off.
local function gap() return GC.db.glass and Skin.TAB_GAP or 0 end

-- The dock's primary window comes from the FCFDock_SetPrimary hook's own
-- argument, else DEFAULT_CHAT_FRAME, not from the dock's fields.
local primary
function Skin.LiftDock(_, chatFrame)
    if chatFrame then primary = chatFrame end
    local dock = rawget(_G, "GeneralDockManager")
    local p = primary or rawget(_G, "DEFAULT_CHAT_FRAME")
    local bg = dock and p and rawget(_G, p:GetName() .. "Background")
    if not bg then return end
    dock:ClearAllPoints()
    dock:SetPoint("BOTTOMLEFT", bg, "TOPLEFT", 0, gap())
    -- Its right end stops short of the Copy button, so the tabs and the
    -- dock's overflow arrow (bottom right of the dock) never sit under it.
    dock:SetPoint("BOTTOMRIGHT", bg, "TOPRIGHT", GC.db.glass and -Skin.DOCK_RESERVE or 0, gap())
end

-- A floating (undocked) window's tab: the same point FCF_SetTabPosition
-- sets, raised.
local function liftTab(chatFrame, x)
    -- Docked tabs are laid out by the dock (FCFDock_UpdateTabs); Blizzard
    -- also calls this on docked frames (FloatingChatFrame_Update, line 609).
    if GC.Chat.IsDocked(chatFrame) then return end
    local tab = tabOf(chatFrame)
    local bg = rawget(_G, chatFrame:GetName() .. "Background")
    if not (tab and bg) then return end
    tab:ClearAllPoints()
    tab:SetPoint("BOTTOMLEFT", bg, "TOPLEFT", (x or 0) + 2, gap())
end

Skin.LiftTab = liftTab
-- px kept free at the dock's right end for the tab-strip icons (copy, and a
-- plugin's, such as Spam & Ignore's eye): Copy.BUTTON_W + its margin each.
Skin.STRIP_ICON_STEP = 26   -- px between icons, right to left
Skin.CORE_ICONS = 2         -- copy, then focus; a plugin's icon comes after them
Skin.DOCK_RESERVE = 30 + Skin.CORE_ICONS * Skin.STRIP_ICON_STEP
-- n icons at the strip's right end (1 = the copy icon alone, the default).
function Skin.ReserveIcons(n)
    Skin.DOCK_RESERVE = 30 + n * Skin.STRIP_ICON_STEP
end
GC.Chat.OnEachFrame("lift", function(f) liftTab(f, 0) end)   -- every FCF_SetTabPosition call site passes 0
GC.Chat.AfterScan("dock", function() Skin.LiftDock() end)

-- After Blizzard's own tab updates (selection, docking, alerts).
function Skin.HookTabs()
    if rawget(_G, "FCFDock_SetPrimary") then hooksecurefunc("FCFDock_SetPrimary", Skin.LiftDock) end
    if rawget(_G, "FCF_SetChatWindowFontSize") then
        hooksecurefunc("FCF_SetChatWindowFontSize", function()
            for _, f in ipairs(GC.Chat.Frames()) do Skin.FitLines(f) end
        end)
    end
    if rawget(_G, "FCF_SetTabPosition") then hooksecurefunc("FCF_SetTabPosition", liftTab) end
    Skin.LiftDock()
    if rawget(_G, "FCFTab_UpdateAlpha") then hooksecurefunc("FCFTab_UpdateAlpha", onTabAlpha) end
    if rawget(_G, "FCFTab_UpdateColors") then
        hooksecurefunc("FCFTab_UpdateColors", paintTab)
    end
end

-- Idle: awake while a line is still readable (its own fade timer, restarted
-- by a scroll), the mouse is over the window, it's scrolled up, its edit
-- box has focus, or its lines never fade.
local function awake(f, now)
    local n = GC.Chat.LineCount(f)
    if counted[f] ~= n then counted[f], active[f] = n, now end   -- a new line, or the first check
    if hovered[f] then return true end
    local edit = editOf(f)
    if edit and edit:HasFocus() then return true end
    if not f:GetFading() or not f:AtBottom() then return true end
    return now - active[f] < (f:GetTimeVisible() or 0) + (f:GetFadeDuration() or 0)
end

local function idleStep(elapsed)
    if not GC.db.glass then return end
    sinceCheck = sinceCheck + elapsed
    local check = sinceCheck >= Skin.IDLE_EVERY
    if check then sinceCheck = 0 end
    local now = GetTime()
    for _, f in ipairs(GC.Chat.Frames()) do
        if panels[f] and f:IsShown() then   -- a hidden window is checked once shown
            if check then target[f] = awake(f, now) and 1 or 0 end
            local k, t = wake[f] or 1, target[f] or 1
            if k ~= t then
                local d = elapsed / (t > k and Skin.WAKE_TIME or Skin.SLEEP_TIME)
                wake[f] = t > k and math.min(t, k + d) or math.max(t, k - d)
                paintIdle(f)
            end
        end
    end
end

local fadeHooked = setmetatable({}, { __mode = "k" })
GC.Chat.OnEachFrame("idle", function(f)
    if fadeHooked[f] or not f.ResetAllFadeTimes then return end
    fadeHooked[f] = true
    hooksecurefunc(f, "ResetAllFadeTimes", function() active[f] = GetTime(); poke() end)
end)

local idleDriver
function Skin.StartIdle()
    if idleDriver then return end
    idleDriver = CreateFrame("Frame")
    idleDriver:SetScript("OnUpdate", function(self, elapsed)
        local ok, err = pcall(idleStep, elapsed)
        if ok then return end
        -- Readability first: a failure leaves every window awake, for good.
        GC.API.Fail("idle", err)
        self:SetScript("OnUpdate", nil)
        for f in pairs(wake) do wake[f] = 1; pcall(paintIdle, f) end
    end)
    for name, over in pairs({ FCF_FadeInChatFrame = true, FCF_FadeOutChatFrame = false }) do
        if rawget(_G, name) then
            hooksecurefunc(name, function(f) if f then hovered[f] = over or nil; poke() end end)
        end
    end
end

-- The panel's tint and grain, for other modules' glass (Buttons.lua's pills).
Skin.Tune = tune

Skin._test = { panels = panels, tabFont = tabFont, tabLit = tabLit, applyTabAlpha = applyTabAlpha, liftTab = liftTab,
    wake = wake, hovered = hovered }
