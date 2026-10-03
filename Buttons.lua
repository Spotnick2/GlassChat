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
-- The chat-menu bubble (ChatFrameMenuButton: one texture, frame baked in)
-- and the friends button (QuickJoinToastButton: animated atlases) are left
-- as they are until an in-game atlas check says what can replace them.

GlassChat = GlassChat or {}
local GC = GlassChat
local Glass = GC.Glass
local Buttons = {}
GC.Buttons = Buttons

Buttons.VOICE = { "ChatFrameChannelButton", "TextToSpeechButton",
    "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }
Buttons.SIZE = 24
Buttons.HIGHLIGHT = 0.4

local pills = setmetatable({}, { __mode = "k" })   -- button -> { pill, g }

local function art(b, alpha)
    for _, t in ipairs({ b:GetNormalTexture(), b:GetPushedTexture() }) do
        if t then t:SetAlpha(alpha) end
    end
    local h = b:GetHighlightTexture()
    if h then h:SetAlpha(alpha == 0 and Buttons.HIGHLIGHT or 1) end
end

function Buttons.Style(b)
    local on = GC.db.glass
    local p = pills[b]
    if on and not p then
        local pill = CreateFrame("Frame", nil, b)
        pill:SetSize(Buttons.SIZE, Buttons.SIZE)
        pill:SetPoint("CENTER", b, "CENTER", 0, 0)
        pill:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
        local g = Glass.Apply(pill, "small")
        g.tint:SetColorTexture(GC.Skin.TINT[1], GC.Skin.TINT[2], GC.Skin.TINT[3], GC.db.alpha)
        g.grain:SetAlpha(0)
        g.wash:SetAlpha(0)
        g.shadow:SetAlpha(0)
        g.rim:SetAlpha(GC.Skin.RIM_IDLE)
        p = { pill = pill, g = g }
        pills[b] = p
    end
    if p then
        p.pill:SetShown(on)
        p.g.tint:SetColorTexture(GC.Skin.TINT[1], GC.Skin.TINT[2], GC.Skin.TINT[3], GC.db.alpha)
    end
    art(b, on and 0 or 1)
end

function Buttons.Refresh()
    for _, name in ipairs(Buttons.VOICE) do
        local b = rawget(_G, name)
        if b and b.GetNormalTexture then
            local ok, err = pcall(Buttons.Style, b)
            if not ok then GC.API.Fail("button " .. name, err) end
        end
    end
end

GC.Chat.AfterScan("buttons", Buttons.Refresh)

Buttons._test = { pills = pills }
