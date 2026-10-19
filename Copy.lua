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
Copy.MAX = 1000   -- lines shown at most: a 5000-line window would freeze the client in one EditBox

-- Colour codes, links, textures, atlases and protected names out; the
-- client's own C_StringUtil.StripHyperlinks first when it answers, then our
-- patterns for anything it leaves (or on a client without it).
-- An escaped pipe ("||", a literal | on screen) is set aside first, so the
-- code patterns never match its second half (a||rb must stay a|rb), and
-- protected Battle.net names (|K...|k) go before the client's stripper, as
-- Prat's CleanText does. StripHyperlinks keeps the brackets
-- (maintainBrackets), so [Thunderfury] stays [Thunderfury] as on screen.
local PIPE = "\1"
function Copy.Plain(text)
    if API.IsSecret(text) or type(text) ~= "string" then return nil end
    local s = text:gsub("||", PIPE)
    s = s:gsub("|Haddon:GlassChat:url:[^|]*|h%[(.-)%]|h", "%1")
    s = s:gsub("|K.-|k", "?")
    local util = rawget(_G, "C_StringUtil")
    if util and util.StripHyperlinks then
        local ok, stripped = pcall(util.StripHyperlinks, s, false, true)
        if ok and not API.IsSecret(stripped) and type(stripped) == "string" then s = stripped end
    end
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
    s = s:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    s = s:gsub(PIPE, "|")
    return s
end

-- A window's lines, oldest first: the newest Copy.MAX of them, as
-- { text, raw, hidden, id, event } (GetMessageInfo's 1st, 5th and 8th
-- returns: ScrollingMessageFrame's UnpackageEntry of AddMessage's
-- arguments). Returns the entries, how many were hidden (secret), and the
-- window's total. A line that fails to read for another reason is a
-- failure, not a secret. Copy and focus mode both read through this.
function Copy.Read(f, key)
    local out, hidden = {}, 0
    local ok, n = pcall(f.GetNumMessages, f)
    if not ok or API.IsSecret(n) or type(n) ~= "number" then return out, 0, 0 end
    for i = math.max(1, n - Copy.MAX + 1), n do
        local okM, text, _, _, _, id, _, _, event = pcall(f.GetMessageInfo, f, i)
        if not okM then
            API.Fail(key or "copy read", text)
        elseif API.IsSecret(text) then
            hidden = hidden + 1
            out[#out + 1] = { text = Copy.HIDDEN, hidden = true }
        else
            local plain = Copy.Plain(text)
            if plain then out[#out + 1] = { text = plain, raw = text, id = id, event = event } end
        end
    end
    return out, hidden, n
end

-- Just the text of Copy.Read's lines.
function Copy.Lines(f)
    local entries, hidden, n = Copy.Read(f)
    local out = {}
    for i, e in ipairs(entries) do out[i] = e.text end
    return out, hidden, n
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
    -- The view follows the cursor (Ctrl+End, arrows): FrameXML's handler.
    if rawget(_G, "ScrollingEdit_OnCursorChanged") then
        edit:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        edit:SetScript("OnUpdate", ScrollingEdit_OnUpdate)
    end
    scroll:SetScrollChild(edit)
    win.scroll = scroll
    API.AutoHideScrollBar(scroll)
    API.ReadOnly(edit, win, "text", true)   -- typing puts the text back, selected
    win.edit = edit
    win.status = Glass.Font(win, 11, "LEFT")
    win.status:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 14, 16)
    win.status:SetTextColor(0.75, 0.75, 0.75)
    win.close = API.Button(win, "Close", 90, function() win:Hide() end)
    win.close:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 10)
end

-- A window's name for the title. FCF_GetChatWindowInfo covers the
-- temporary whisper windows too (FloatingChatFrame.lua:543); a whisper tab's
-- text can be secret, so that is checked before anything else.
function Copy.WindowName(f)
    local get = rawget(_G, "FCF_GetChatWindowInfo") or rawget(_G, "GetChatWindowInfo")
    if get then
        local ok, name = pcall(get, f:GetID())
        if ok and not API.IsSecret(name) and type(name) == "string" and name ~= "" then return name end
    end
    return f:GetName()
end

-- The window itself, for any plain text (the spam plugin's hidden-lines log
-- uses it too): title, text selected for Ctrl+C, a status line.
function Copy.Show(title, text, status)
    if not win then build() end
    win.text = text
    win.title:SetText(title)
    win.hint:SetText("Selected. Press Ctrl+C to copy, then Esc to close.")
    win.status:SetText(status or "")
    win.scroll:SetVerticalScroll(0)
    API.ShowWindow(win)
    win.edit:SetText(win.text)
    win.edit:SetFocus()
    win.edit:HighlightText()
end

-- Open the copy window on a chat window's lines, selected.
function Copy.Open(f)
    f = f or Copy.CurrentFrame()
    if not f then return end
    local lines, hidden, total = Copy.Lines(f)
    local status = #lines .. " lines"
    if total > Copy.MAX then status = status .. " (the newest " .. Copy.MAX .. " of " .. total .. ")" end
    if hidden > 0 then status = status .. ", " .. hidden .. " hidden (can't be read)" end
    Copy.Show("Copy: " .. Copy.WindowName(f), table.concat(lines, "\n"), status)
end

-- The Copy button: a grey copy icon at the right end of each window's tab strip,
-- on its glass panel (so it shows and hides with it: glass off is the stock
-- look, and /gchat copy still works). Its own frame is raised to MEDIUM, the
-- tabs' strata, and the dock stops Skin.DOCK_RESERVE px short of it, so no
-- tab or overflow arrow sits under it.
Copy.BUTTON_W, Copy.BUTTON_H = 22, 20
Copy.PAGE_W, Copy.PAGE_H, Copy.PAGE_OFFSET = 9, 11, 4
local buttons = setmetatable({}, { __mode = "k" })   -- chat frame -> button

-- The copy icon (owner: "a cut and paste icon"): two overlapping page
-- outlines drawn from 1 px lines, no art file, so it's crisp at any UI
-- scale and recolours with the tab palette. The front page is filled with
-- the panel's charcoal so the back one passes behind it.
-- One draw layer, increasing sublevels: back outline (1), front fill (2),
-- front outline (3), so the front sheet covers the back one's lines (Codex,
-- #12: an ARTWORK fill drew under both OVERLAY outlines).
local function page(b, x, y, lines, sublevel)
    local W, H = Copy.PAGE_W, Copy.PAGE_H
    local function line(px, py, w, h)
        local t = b:CreateTexture(nil, "OVERLAY", nil, sublevel)
        t:SetPoint("TOPLEFT", b, "CENTER", x + px, y - py)
        t:SetSize(w, h)
        lines[#lines + 1] = t
        return t
    end
    line(0, 0, W, 1)        -- top
    line(0, H - 1, W, 1)    -- bottom
    line(0, 0, 1, H)        -- left
    line(W - 1, 0, 1, H)    -- right
end

local function paintIcon(icon, c)
    for _, t in ipairs(icon.lines) do t:SetColorTexture(c[1], c[2], c[3], 1) end
end

function Copy.Button(f)
    if buttons[f] then return end
    local p = GC.Skin.Panel(f)
    if not p then return end
    local b = CreateFrame("Button", nil, p.panel)
    b:SetFrameStrata("MEDIUM")
    b:SetSize(Copy.BUTTON_W, Copy.BUTTON_H)
    b:SetPoint("TOPRIGHT", p.panel, "TOPRIGHT", -14, -9)
    local o, W, H = Copy.PAGE_OFFSET, Copy.PAGE_W, Copy.PAGE_H
    local icon = { lines = {} }
    -- Back page up-left, front page down-right over it.
    local left, top = -(W + o) / 2, (H + o) / 2
    page(b, left, top, icon.lines, 1)
    local fill = b:CreateTexture(nil, "OVERLAY", nil, 2)
    fill:SetPoint("TOPLEFT", b, "CENTER", left + o, top - o)
    fill:SetSize(W, H)
    fill:SetColorTexture(GC.Skin.TINT[1], GC.Skin.TINT[2], GC.Skin.TINT[3], 1)
    icon.fill = fill
    page(b, left + o, top - o, icon.lines, 3)
    local grey, accent = GC.Skin.TAB_GREY, GC.Skin.ACCENT
    paintIcon(icon, grey)
    b:SetScript("OnEnter", function(self)
        paintIcon(icon, accent)
        local tip = rawget(_G, "GameTooltip")
        if tip then
            tip:SetOwner(self, "ANCHOR_TOP")
            tip:SetText("Copy this window")
            tip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        paintIcon(icon, grey)
        local tip = rawget(_G, "GameTooltip")
        if tip then tip:Hide() end
    end)
    b:SetScript("OnClick", function() Copy.Open(f) end)
    b.icon = icon   -- our own frame: a field on it is fine
    buttons[f] = b
end

GC.Chat.OnEachFrame("copy", Copy.Button)

Copy._test = { window = function() return win end, buttons = buttons }
