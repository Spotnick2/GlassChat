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
--   black square), so an ice-blue bubble is drawn from fills, like the copy
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

-- The chat menu's bubble: two overlapping accent fills (a rounded body) and
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
    local accent = GC.Skin.ACCENT
    local function fill(w, hh, point, rel, relPoint, x, y)
        local t = h:CreateTexture(nil, "OVERLAY")
        t:SetSize(w, hh)
        t:SetPoint(point, rel, relPoint, x, y)
        t:SetColorTexture(accent[1], accent[2], accent[3], 1)
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
-- With glass, symbol and count move onto the column's line with the pill
-- (Buttons.ColumnOffset); without, the count goes back to its own place
-- (BOTTOM, y 4: QuickJoinToast.xml:45-48).
local function friendsArt(b, on)
    local t = rawget(b, "FriendsButton")   -- a parentKey: a plain field
    if not t then return end
    local dx = on and Buttons.ColumnOffset(b) or 0
    t:ClearAllPoints()
    if on then
        t:SetAtlas(Buttons.FRIENDS_ICON)
        t:SetSize(18, 16)
        t:SetPoint("CENTER", b, "CENTER", dx, 6)
    else
        t:SetAtlas(Buttons.FRIENDS_STOCK)
        t:SetAllPoints(b)
    end
    local count = rawget(b, "FriendCount")
    if count then
        count:ClearAllPoints()
        count:SetPoint("BOTTOM", b, "BOTTOM", dx, 4)
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
    -- Its pill on the column's line, not on the button's own centre.
    local p = pills[b]
    if p and on then
        p.pill:ClearAllPoints()
        p.pill:SetPoint("CENTER", b, "CENTER", Buttons.ColumnOffset(b), 0)
    end
    -- Once per change: with glass off, a scan must not re-set the stock art
    -- over Blizzard's pressed state (review of #38).
    -- With glass, every scan: the stack's justification may have moved
    -- (ChatAlertFrameMixin:SetChatButtonSide), and the symbol is ours anyway.
    if on or applied[b] ~= on then
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
        -- LibGlass's pill (r5, lifted from this recipe, #80): one level under
        -- the button, its rims too, no grain or shadow. Then the panel's rim.
        local pill, g = GC.Glass.Pill(b, { side = Buttons.SIZE, highlight = Buttons.HIGHLIGHT })
        g.rim:SetAlpha(GC.Skin.RIM_IDLE)
        p = { pill = pill, g = g }
        pills[b] = p
    end
    -- Re-synced every time: the button's level may have moved, and the
    -- rims would then draw over the gold Icon.
    GC.Glass.RelevelPill(p.pill)
    GC.Skin.PillLook(p.g)
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

--------------------------------------------------------------------------------
-- Side buttons (#83, #86): GlassChat's own buttons beside the chat, in
-- Blizzard's own stack above the button column, ChatAlertFrame, where the
-- text-to-speech button (TextToSpeech.lua:14-15) and the friends button
-- (BNet.lua:33-34, 334-335) live. Blizzard lays the shown ones out upward
-- (AlertFrames.lua:417-427), so they never overlap the voice buttons, which
-- grow down from the column's top and covered a stack inside a short column
-- (Codex, #85; owner's pick). Each is a plain Button given
-- ContainedAlertFrameMixin, the four methods the container calls on it, and
-- added with AddAutoAnchoredSubSystem at SIDE_PRIORITY + order / 100: right
-- above text-to-speech (0) and below the toasts that come and go (Battle.net
-- 1, session time 2, voice prompts 10-11, voice activity 19+), so a toast
-- pops above them. Showing or hiding one re-stacks the container. A
-- client without the container stacks them above the chat-menu bubble.
-- Unmeasured: the container's layout now runs over our frames (taint): watch
-- for ADDON_ACTION_BLOCKED naming GlassChat.
-- Their neighbours' colours (owner): gold at rest, green while something
-- waits, as the channel button turns into the green headset
-- (ChannelFrameButtonMixin.lua:20-21). While green, the symbol pulses until
-- the button is clicked (owner: "flashing ... when the icons are green").
--
-- Buttons.Side(key, opts): order (1 lowest, 2 above it...),
-- text or texture or atlas (the symbol), tooltip, count() (what waits),
-- shown() and onClick(). Built at the next scan; Buttons.PaintSide(key)
-- repaints one after its count changed.
--------------------------------------------------------------------------------

Buttons.SIDE_SIZE, Buttons.SIDE_GAP = 24, 2
Buttons.SIDE_PRIORITY = 0.5   -- between text-to-speech (0) and Blizzard's toasts (1 and up)

-- Blizzard's chat alert stack, when this client has it; nil otherwise.
local function container()
    local c = rawget(_G, "ChatAlertFrame")
    if c and c.AddAutoAnchoredSubSystem and c.SetSubSystemAnchorPriority and c.UpdateAnchors
        and rawget(_G, "ContainedAlertFrameMixin") and rawget(_G, "Mixin") then
        return c
    end
end

-- Every pill on one vertical line, the button column's centre (owner: they
-- were "not horizontally aligned at all"). The voice buttons and the chat
-- menu are centred in ChatFrame1ButtonFrame (FloatingChatFrameVoiceChat.xml:6,
-- FloatingChatFrame.xml:726). ChatAlertFrame is as wide as that column and
-- sits on it (ChatAlertFrameMixin.lua:5-7), but lines its frames up by one
-- edge (AlertFrames.lua:447-452): the 32-wide friends button was 1.5 off the
-- line, and 24-wide side buttons 2.5 the other way. So a side button takes
-- the container's width, and the friends pill, symbol and count move by this:
-- how far b's centre is from the container's. 0 without the container, or
-- with a centred stack.
function Buttons.ColumnOffset(b)
    local c = container()
    if not (c and rawget(c, "GetJustification")) then return 0 end   -- a mixin method: a plain field
    local d = (c:GetWidth() - b:GetWidth()) / 2
    local j = c:GetJustification()
    if j == "LEFT" then return d elseif j == "RIGHT" then return -d end
    return 0
end

-- Glass off (owner, #118): Blizzard's chat-button frame, the one the voice
-- buttons and the chat menu wear (VoiceToggleButton.xml, set as PropertyButton.lua:
-- 22-27 and 86 does, 27 x 26), so the symbol isn't left bare in the stock column.
-- With glass on, at alpha 0.
Buttons.STOCK_FRAME = { "chatframe-button-up", "chatframe-button-down", "chatframe-button-highlight" }
Buttons.STOCK_W, Buttons.STOCK_H = 27, 26
Buttons.GREEN = { 0.3, 0.9, 0.3 }
Buttons.GLOW = 0.35
Buttons.PULSE_PERIOD, Buttons.PULSE_LOW = 0.6, 0.35
local sides = {}   -- key -> { opts, button }

local function sideColor(b, c)
    if b.isText then b.symbol:SetTextColor(c[1], c[2], c[3])
    else b.symbol:SetVertexColor(c[1], c[2], c[3]) end
end

local function paintSide(s)
    local b = s.button
    if not b then return end
    local n = s.opts.count() or 0
    b.count:SetText(n > 0 and tostring(math.min(n, 99)) or "")
    sideColor(b, n > 0 and Buttons.GREEN or GC.Skin.TAB_GOLD)
    b.glow:SetShown(n > 0)
    if n > 0 then
        if not b.pulse:IsPlaying() then b.pulse:Play() end
    else
        if b.pulse:IsPlaying() then b.pulse:Stop() end
        b.symbol:SetAlpha(b.hovered and 1 or 0.8)
    end
end

function Buttons.PaintSide(key)
    local s = sides[key]
    if s then paintSide(s) end
end

local function buildSide(s, menu)
    local o = s.opts
    local c = container()
    local b = CreateFrame("Button", nil, c and UIParent or (menu:GetParent() or UIParent))
    b:SetFrameStrata("MEDIUM")
    -- In the container, as wide as it: centred on the column whichever edge it
    -- lines up by (Buttons.ColumnOffset). The pill keeps SIDE_SIZE.
    b:SetSize(c and c:GetWidth() or Buttons.SIDE_SIZE, Buttons.SIDE_SIZE)
    if c then
        -- The methods the container calls on a contained frame (AlertFrameIntrinsic.lua),
        -- on our own button; then into Blizzard's stack.
        Mixin(b, ContainedAlertFrameMixin)
        local system = c:AddAutoAnchoredSubSystem(b)
        c:SetSubSystemAnchorPriority(system, Buttons.SIDE_PRIORITY + o.order / 100)
        s.contained = true
    end
    -- The stock frame, for glass off (Buttons.STOCK_FRAME), centred like the pill.
    b:SetNormalAtlas(Buttons.STOCK_FRAME[1])
    b:SetPushedAtlas(Buttons.STOCK_FRAME[2])
    b:SetHighlightAtlas(Buttons.STOCK_FRAME[3], "ADD")
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
        local t = b[get](b)
        if t then
            t:ClearAllPoints()
            t:SetPoint("CENTER", b, "CENTER", 0, 0)
            t:SetSize(Buttons.STOCK_W, Buttons.STOCK_H)
        end
    end
    -- With glass, no highlight texture to soften: hover is paintSide's.
    local pill, g = GC.Glass.Pill(b, { side = Buttons.SIDE_SIZE, highlight = false })
    g.rim:SetAlpha(GC.Skin.RIM_IDLE)
    GC.Skin.PillLook(g)
    b.pill = pill
    local glow = b:CreateTexture(nil, "ARTWORK")
    glow:SetAllPoints(pill)
    glow:SetColorTexture(Buttons.GREEN[1], Buttons.GREEN[2], Buttons.GREEN[3], Buttons.GLOW)
    glow:SetBlendMode("ADD")
    glow:Hide()
    b.glow = glow
    if o.text then
        b.symbol, b.isText = GC.Glass.Font(b, 16, "CENTER"), true
        b.symbol:SetText(o.text)
    else
        b.symbol = b:CreateTexture(nil, "OVERLAY")
        b.symbol:SetSize(Buttons.SIDE_SIZE - 6, Buttons.SIDE_SIZE - 6)
        if o.atlas then b.symbol:SetAtlas(o.atlas) else b.symbol:SetTexture(o.texture) end
        b.symbol:SetDesaturated(true)   -- tinted gold or green by paintSide
    end
    b.symbol:SetPoint("CENTER", b, "CENTER", 0, 0)
    local pulse = b.symbol:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(Buttons.PULSE_LOW)
    fade:SetDuration(Buttons.PULSE_PERIOD)
    b.pulse = pulse
    b.count = GC.Glass.Font(b, 11, "CENTER")
    b.count:SetPoint("BOTTOMRIGHT", pill, "BOTTOMRIGHT", 3, -3)
    b:SetScript("OnEnter", function(self)
        self.hovered = true
        paintSide(s)
        local tip = rawget(_G, "GameTooltip")
        if tip then
            tip:SetOwner(self, "ANCHOR_RIGHT")
            tip:SetText(type(o.tooltip) == "function" and o.tooltip() or o.tooltip)
            tip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.hovered = false
        paintSide(s)
        local tip = rawget(_G, "GameTooltip")
        if tip then tip:Hide() end
    end)
    b:SetScript("OnClick", function() o.onClick() end)
    s.button = b
end

function Buttons.Side(key, opts)
    sides[key] = { opts = opts }
end

-- The side buttons built so far, shown or not (Area.lua's footprint).
function Buttons.SideFrames()
    local out = {}
    for _, s in pairs(sides) do
        if s.button then out[#out + 1] = s.button end
    end
    return out
end

-- Build, show and stack every side button: each shown one sits on the one
-- below it, the first on the chat-menu bubble.
function Buttons.RefreshSides()
    local menu = rawget(_G, Buttons.MENU)
    if not menu then return end
    local list = {}
    for _, s in pairs(sides) do list[#list + 1] = s end
    table.sort(list, function(a, z) return a.opts.order < z.opts.order end)
    local below = menu   -- the fallback stack, without the container
    for _, s in ipairs(list) do
        local shown = s.opts.shown() and true or false
        if shown and not s.button then buildSide(s, menu) end
        local b = s.button
        if b then
            GC.Glass.RelevelPill(b.pill)
            GC.Skin.PillLook(b.pill.glassPill)
            b:SetShown(shown)
            b.pill:SetShown(GC.db.glass and true or false)
            for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
                local t = b[get](b)
                if t then t:SetAlpha(GC.db.glass and 0 or 1) end
            end
            if shown and not s.contained then
                b:ClearAllPoints()
                b:SetPoint("BOTTOM", below, "TOP", 0, Buttons.SIDE_GAP)
                below = b
            end
            paintSide(s)
        end
    end
    -- The container re-stacks on its frames' own show and hide; once more for
    -- a change made while one was already in place.
    local c = container()
    if c then c:UpdateAnchors() end
end

GC.Chat.AfterScan("side buttons", function()
    local ok, err = pcall(Buttons.RefreshSides)
    if not ok then GC.API.Fail("side buttons", err) end
end)

Buttons._test = { pills = pills, bubbles = bubbles, side = function(key) return sides[key] and sides[key].button end }
