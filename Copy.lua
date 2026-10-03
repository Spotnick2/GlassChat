-- Copy.lua: a chat window's lines as plain text, ready for Ctrl+C.
--
-- Addons can't write the clipboard on Forever: CopyToClipboard is forbidden,
-- even through Blizzard's own drag-select (probe items 2-3). So, as Prat's
-- CopyChat and GlassPanel's Share do, the text goes into a read-only glass
-- window, already selected; the player presses Ctrl+C.
--
-- Lines come from the public GetMessageInfo, 1 = oldest
-- (ScrollingMessageFrame.lua:30-31). A secret line is never read, matched
-- or copied: it shows as "(hidden line)". Focus mode (M4) builds on this.

GlassChat = GlassChat or {}
local GC = GlassChat
local API, Glass = GC.API, GC.Glass
local Copy = {}
GC.Copy = Copy

Copy.HIDDEN = "(hidden line)"

-- Colour codes, links, textures, atlases and protected names out; the
-- client's own C_StringUtil.StripHyperlinks first when it answers, then our
-- patterns for anything it leaves (or on a client without it).
function Copy.Plain(text)
    if type(text) ~= "string" or API.IsSecret(text) then return nil end
    local s = text
    local util = rawget(_G, "C_StringUtil")
    if util and util.StripHyperlinks then
        local ok, stripped = pcall(util.StripHyperlinks, s)
        if ok and type(stripped) == "string" and not API.IsSecret(stripped) then s = stripped end
    end
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
    s = s:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    s = s:gsub("|K.-|k", "?")   -- Battle.net names are protected strings
    s = s:gsub("||", "|")
    return s
end

-- Every line of a chat window, oldest first, plus how many were hidden.
function Copy.Lines(f)
    local out, hidden = {}, 0
    local ok, n = pcall(f.GetNumMessages, f)
    if not ok or type(n) ~= "number" then return out, 0 end
    for i = 1, n do
        local okM, text = pcall(f.GetMessageInfo, f, i)
        local plain = okM and Copy.Plain(text)
        if plain then
            out[#out + 1] = plain
        else
            hidden = hidden + 1
            out[#out + 1] = Copy.HIDDEN
        end
    end
    return out, hidden
end

-- The window the player is looking at: the dock's selected one, else the
-- default.
function Copy.CurrentFrame()
    local dock = rawget(_G, "GENERAL_CHAT_DOCK")
    if dock and rawget(_G, "FCFDock_GetSelectedWindow") then
        local ok, f = pcall(FCFDock_GetSelectedWindow, dock)
        if ok and f then return f end
    end
    return rawget(_G, "DEFAULT_CHAT_FRAME")
end

local win

local function build()
    win = API.Window("GlassChatCopyWindow", 640, 420)
    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", win.hint, "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -34, 44)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(580)
    edit:SetMaxLetters(0)   -- no cap on what we show
    scroll:SetScrollChild(edit)
    API.AutoHideScrollBar(scroll)
    edit:SetScript("OnEscapePressed", function() win:Hide() end)
    -- Read-only: typing puts the text back, selected.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and win.text then
            self:SetText(win.text)
            self:HighlightText()
        end
    end)
    win.edit = edit
    win.status = Glass.Font(win, 11, "LEFT")
    win.status:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 14, 16)
    win.status:SetTextColor(0.75, 0.75, 0.75)
    win.close = API.Button(win, "Close", 90, function() win:Hide() end)
    win.close:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 10)
end

-- Open the copy window on a chat window's lines, selected.
function Copy.Open(f)
    f = f or Copy.CurrentFrame()
    if not f then return end
    if not win then build() end
    local lines, hidden = Copy.Lines(f)
    win.text = table.concat(lines, "\n")
    local okN, name = false, nil
    if rawget(_G, "GetChatWindowInfo") then okN, name = pcall(GetChatWindowInfo, f:GetID()) end
    if not (okN and type(name) == "string" and name ~= "") then name = f:GetName() end
    win.title:SetText("Copy: " .. name)
    win.hint:SetText("Selected. Press Ctrl+C to copy, then Esc to close.")
    local status = #lines .. " lines"
    if hidden > 0 then status = status .. ", " .. hidden .. " hidden (can't be read)" end
    win.status:SetText(status)
    win:Show()
    win.edit:SetText(win.text)
    win.edit:SetFocus()
    win.edit:HighlightText()
end

-- The Copy button: a grey label at the right end of each window's tab strip,
-- on its glass panel (so it shows and hides with it). Its own frame is
-- raised to MEDIUM, the tabs' strata, so nothing under it takes the click.
Copy.BUTTON_W, Copy.BUTTON_H = 44, 18
local buttons = setmetatable({}, { __mode = "k" })   -- chat frame -> button

function Copy.Button(f)
    if buttons[f] then return end
    local p = GC.Skin.Panel(f)
    if not p then return end
    local b = CreateFrame("Button", nil, p.panel)
    b:SetFrameStrata("MEDIUM")
    b:SetSize(Copy.BUTTON_W, Copy.BUTTON_H)
    b:SetPoint("TOPRIGHT", p.panel, "TOPRIGHT", -12, -10)
    local label = Glass.Font(b, 13, "CENTER")
    label:SetPoint("CENTER", b, "CENTER", 0, 0)
    label:SetText("Copy")
    label:SetTextColor(0.8, 0.8, 0.8)
    b:SetScript("OnEnter", function() label:SetTextColor(1, 0.82, 0) end)
    b:SetScript("OnLeave", function() label:SetTextColor(0.8, 0.8, 0.8) end)
    b:SetScript("OnClick", function() Copy.Open(f) end)
    buttons[f] = b
end

GC.Chat.OnEachFrame("copy", Copy.Button)

Copy._test = { window = function() return win end, buttons = buttons }
