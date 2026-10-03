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
-- Known: the channel button's tutorial Flash (chatframe-button-highlightalert)
-- still pulses a frame-shaped glow; UIFrameFlash drives its alpha, so it
-- isn't fought.

GlassChat = GlassChat or {}
local GC = GlassChat
local Buttons = {}
GC.Buttons = Buttons

Buttons.VOICE = { "ChatFrameChannelButton", "TextToSpeechButton",
    "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }
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
    -- rawget: a parentKey child is a plain field on the frame table.
    local bg = rawget(b, "Background")
    if bg then bg:SetAlpha(frameAlpha) end
    if h then h:SetAlpha(on and Buttons.HIGHLIGHT or 1) end
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
    -- puts its rims on g.top at +10 (Glass.lua:117), which would draw them
    -- over the gold Icon; down with the pill instead.
    p.pill:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
    p.g.top:SetFrameLevel(p.pill:GetFrameLevel())
    GC.Skin.Tune(p.g)
    p.g.grain:SetAlpha(0)
    p.g.shadow:SetAlpha(0)
    p.pill:SetShown(on)
    art(b, on)
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
