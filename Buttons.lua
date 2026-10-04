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
-- a small tail at the bottom left, on the button, over the pill.
local bubbles = setmetatable({}, { __mode = "k" })
local function bubble(b)
    local parts = bubbles[b]
    if parts then return parts end
    parts = {}
    local gold = GC.Skin.TAB_GOLD
    local function fill(w, h, point, rel, relPoint, x, y)
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetSize(w, h)
        t:SetPoint(point, rel, relPoint, x, y)
        t:SetColorTexture(gold[1], gold[2], gold[3], 1)
        parts[#parts + 1] = t
        return t
    end
    fill(14, 7, "CENTER", b, "CENTER", 0, 1)
    local body = fill(12, 9, "CENTER", b, "CENTER", 0, 1)
    local tail = fill(3, 2, "TOPLEFT", body, "BOTTOMLEFT", 2, 0)
    fill(2, 1, "TOPLEFT", tail, "BOTTOMLEFT", 0, 0)
    bubbles[b] = parts
    return parts
end

-- The friends button's symbol: ours with glass, Blizzard's without.
local function friendsArt(b, on)
    local t = rawget(b, "FriendsButton")   -- a parentKey: a plain field
    if not t then return end
    t:ClearAllPoints()
    if on then
        t:SetAtlas(Buttons.FRIENDS_ICON)
        t:SetSize(22, 20)
        t:SetPoint("CENTER", b, "CENTER", 0, 3)
    else
        t:SetAtlas(Buttons.FRIENDS_STOCK)
        t:SetAllPoints(b)
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
    if b == rawget(_G, Buttons.FRIENDS) then
        friendsArt(b, on)
        -- Blizzard swaps in its framed -down/-up art on each press: ours again after.
        if not hooked[b] then
            hooked[b] = true
            local function again(self) if pills[self] and GC.db.glass then friendsArt(self, true) end end
            b:HookScript("OnMouseDown", again)
            b:HookScript("OnMouseUp", again)
        end
        return
    end
    art(b, on)
    if b == rawget(_G, Buttons.MENU) then
        for _, t in ipairs(bubble(b)) do t:SetShown(on) end
    end
    -- Blizzard re-sets the highlight on every state change (PropertyButton
    -- UpdateHighlight, PropertyButton.lua:60-67): soften it again after.
    if not hooked[b] and rawget(b, "UpdateHighlight") then   -- a mixin method: a plain field too
        hooked[b] = true
        hooksecurefunc(b, "UpdateHighlight", function(self)
            if pills[self] then art(self, GC.db.glass) end
        end)
    end
end

function Buttons.Refresh()
    local names = { Buttons.MENU, Buttons.FRIENDS }
    for _, name in ipairs(Buttons.VOICE) do names[#names + 1] = name end
    for _, name in ipairs(names) do
        local b = rawget(_G, name)
        if b and b.GetNormalTexture then
            local ok, err = pcall(Buttons.Style, b)
            if not ok then GC.API.Fail("button " .. name, err) end
        end
    end
end

GC.Chat.AfterScan("buttons", Buttons.Refresh)

Buttons._test = { pills = pills, bubbles = bubbles }
