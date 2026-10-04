-- Buttons.lua: the buttons beside the chat as compact glass buttons with
-- Blizzard's own gold symbols, instead of chunky metal frames (outside
-- critique of the M1 look).
--
-- Voice-style buttons (VoiceToggleButtonTemplate, VoiceToggleButton.xml:3):
-- the frame is the button's normal and pushed art (atlases
-- chatframe-button-up / -down) and the symbol a separate Icon texture. So
-- the frame art goes to alpha 0 (state changes swap the atlas on the same
-- texture, which keeps its alpha) and a small glass pill sits behind the
-- symbol. The highlight is softened, not removed, so hovering still shows.
--
-- The chat-menu bubble (ChatFrameMenuButton) and the friends button
-- (QuickJoinToastButton) have their frame baked into one texture
-- (UI-ChatIcon-Chat-Up, quickjoin-button-friendslist-up). Probe item 13
-- found which frameless symbols the client has (owner's picks, #7):
-- - friends: socialqueuing-icon-group, set on the button's own FriendsButton
--   texture and set again after Blizzard's OnMouseDown/Up (QuickJoinToast
--   .lua:344-351 swap it to the framed -down/-up art); its friend count stays;
-- - chat menu: no frameless bubble exists (communities-icon-chat sits on a
--   black square), so a small gold bubble is drawn from fills, like the copy
--   icon, and the button's file art goes to alpha 0.
-- The queue toast (QueueButton, shown only while a group is advertised) is
-- left as it is.
-- Known: the channel button's tutorial Flash (chatframe-button-highlightalert)
-- still pulses a frame-shaped glow; UIFrameFlash drives its alpha, so it
-- isn't fought.

GlassChat = GlassChat or {}
local GC = GlassChat
local Buttons = {}
GC.Buttons = Buttons

Buttons.VOICE = { "ChatFrameChannelButton", "TextToSpeechButton",
    "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }
Buttons.MENU, Buttons.FRIENDS = "ChatFrameMenuButton", "QuickJoinToastButton"
Buttons.FRIENDS_ICON = "socialqueuing-icon-group"   -- probe 13: #2, 29x26
Buttons.FRIENDS_STOCK = "quickjoin-button-friendslist-up"
Buttons.SIZE = 24
Buttons.HIGHLIGHT = 0.4

local pills = setmetatable({}, { __mode = "k" })   -- button -> { pill, g }
local hooked = setmetatable({}, { __mode = "k" })

-- The metal frame (normal and pushed art, read one by one: a nil normal
-- texture must not hide a pushed one), TTS's own black Background square
-- (TextToSpeech.xml:17-24, a parentKey), and the highlight, softened.
local function art(b, on)
    local frameAlpha = on and 0 or 1
    local n, pushed, h = b:GetNormalTexture(), b:GetPushedTexture(), b:GetHighlightTexture()
    if n then n:SetAlpha(frameAlpha) end
    if pushed then pushed:SetAlpha(frameAlpha) end
    local disabled = b.GetDisabledTexture and b:GetDisabledTexture()
    if disabled then disabled:SetAlpha(frameAlpha) end
    -- rawget: a parentKey child is a plain field on the frame table.
    local bg = rawget(b, "Background")
    if bg then bg:SetAlpha(frameAlpha) end
    if h then h:SetAlpha(on and Buttons.HIGHLIGHT or 1) end
end

-- The chat menu's bubble: two overlapping gold fills (a rounded body) and
-- a small tail at the bottom left, on a holder over the pill. Pressed, the
-- holder moves 1 px down; disabled, the bubble dims, as PropertyButton does
-- for the voice symbols (review of #38).
local bubbles = setmetatable({}, { __mode = "k" })
local function bubble(b)
    local parts = bubbles[b]
    if parts then return parts end
    parts = { holder = CreateFrame("Frame", nil, b) }
    local h = parts.holder
    h:SetSize(16, 14)
    h:SetPoint("CENTER", b, "CENTER", 0, 1)
    local gold = GC.Skin.TAB_GOLD
    local function fill(w, hh, point, rel, relPoint, x, y)
        local t = h:CreateTexture(nil, "OVERLAY")
        t:SetSize(w, hh)
        t:SetPoint(point, rel, relPoint, x, y)
        t:SetColorTexture(gold[1], gold[2], gold[3], 1)
        parts[#parts + 1] = t
        return t
    end
    fill(14, 7, "CENTER", h, "CENTER", 0, 0)
    local body = fill(12, 9, "CENTER", h, "CENTER", 0, 0)
    local tail = fill(3, 2, "TOPLEFT", body, "BOTTOMLEFT", 2, 0)
    fill(2, 1, "TOPLEFT", tail, "BOTTOMLEFT", 0, 0)
    bubbles[b] = parts
    return parts
end
local function bubbleState(b, pressed)
    local parts = bubbles[b]
    if not parts then return end
    parts.holder:ClearAllPoints()
    parts.holder:SetPoint("CENTER", b, "CENTER", pressed and 1 or 0, pressed and 0 or 1)
    local enabled = not b.IsEnabled or b:IsEnabled()
    parts.holder:SetAlpha(enabled and 1 or 0.4)
end

-- The friends button's symbol: ours with glass, Blizzard's without. Raised
-- and a little smaller, so the friend count (BOTTOM, y 4) sits under it,
-- not over it (review of #38).
local function friendsArt(b, on)
    local t = rawget(b, "FriendsButton")   -- a parentKey: a plain field
    if not t then return end
    t:ClearAllPoints()
    if on then
        t:SetAtlas(Buttons.FRIENDS_ICON)
        t:SetSize(18, 16)
        t:SetPoint("CENTER", b, "CENTER", 0, 6)
    else
        t:SetAtlas(Buttons.FRIENDS_STOCK)
        t:SetAllPoints(b)
    end
end

-- What each button does with its own symbol, on top of the shared steps
-- (pill, frame art, highlight), which every button gets (review of #38).
local symbol = {}
local hlHooked = setmetatable({}, { __mode = "k" })
local applied = setmetatable({}, { __mode = "k" })   -- button -> the state last applied
symbol[Buttons.MENU] = function(b, on)
    local parts = bubble(b)
    parts.holder:SetShown(on)
    bubbleState(b, false)
    if not hooked[b] then
        hooked[b] = true
        b:HookScript("OnMouseDown", function(self) if pills[self] then bubbleState(self, true) end end)
        b:HookScript("OnMouseUp", function(self) if pills[self] then bubbleState(self, false) end end)
        b:HookScript("OnEnable", function(self) if pills[self] then bubbleState(self, false) end end)
        b:HookScript("OnDisable", function(self) if pills[self] then bubbleState(self, false) end end)
    end
end
symbol[Buttons.FRIENDS] = function(b, on)
    -- Once per change: with glass off, a scan must not re-set the stock art
    -- over Blizzard's pressed state (review of #38).
    if applied[b] ~= on then
        applied[b] = on
        friendsArt(b, on)
    end
    -- Blizzard swaps in its framed -down/-up art on each press: ours again after.
    if not hooked[b] then
        hooked[b] = true
        local function again(self) if pills[self] and GC.db.glass then friendsArt(self, true) end end
        b:HookScript("OnMouseDown", again)
        b:HookScript("OnMouseUp", again)
    end
end

function Buttons.Style(b)
    local on = GC.db.glass
    local p = pills[b]
    if not (on or p) then return end   -- never styled: the stock button is left alone
    if on and not p then
        -- The panel recipe and tuning from Skin, then only what a 24 px
        -- pill needs differently.
        local pill, g = GC.Skin.NewPanel(b, "small")
        pill:SetSize(Buttons.SIZE, Buttons.SIZE)
        pill:SetPoint("CENTER", b, "CENTER", 0, 0)
        p = { pill = pill, g = g }
        pills[b] = p
    end
    -- Re-synced every time: the button's level may have moved. Glass.Apply
    -- puts its rims on g.top at +10 (LibGlass.lua, lib.impl.Apply), which would draw them
    -- over the gold Icon; down with the pill instead.
    p.pill:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
    p.g.top:SetFrameLevel(p.pill:GetFrameLevel())
    GC.Skin.Tune(p.g)
    p.g.grain:SetAlpha(0)
    p.g.shadow:SetAlpha(0)
    p.pill:SetShown(on)
    art(b, on)
    local own = symbol[b:GetName()]
    if own then own(b, on) end
    -- Blizzard re-sets the highlight on every state change (PropertyButton
    -- UpdateHighlight, PropertyButton.lua:60-67): soften it again after.
    if not hlHooked[b] and rawget(b, "UpdateHighlight") then   -- a mixin method: a plain field too
        hlHooked[b] = true
        hooksecurefunc(b, "UpdateHighlight", function(self)
            if pills[self] then art(self, GC.db.glass) end
        end)
    end
end

-- Every button beside the chat, in one list built once.
Buttons.ALL = { Buttons.MENU, Buttons.FRIENDS }
for _, name in ipairs(Buttons.VOICE) do Buttons.ALL[#Buttons.ALL + 1] = name end

function Buttons.Refresh()
    for _, name in ipairs(Buttons.ALL) do
        local b = rawget(_G, name)
        if b and b.GetNormalTexture then
            local ok, err = pcall(Buttons.Style, b)
            if not ok then GC.API.Fail("button " .. name, err) end
        end
    end
end

GC.Chat.AfterScan("buttons", Buttons.Refresh)

Buttons._test = { pills = pills, bubbles = bubbles }
