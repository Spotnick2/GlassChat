-- Focus.lua (M4): freeze a chat window into a large glass window, with
-- search, filters and copy.
--
-- The chat behind it is never touched: a snapshot of the window's lines
-- (GetMessageInfo, 1 = oldest) is read once, so nothing scrolls away while
-- you read; "N new lines" refreshes it. Each line keeps its kind (from the
-- chat event Blizzard passed to AddMessage: ChatFrameOverrides.lua) and, for
-- addon output, the addon that wrote it (Tabs.SourceFor, from M3's
-- attribution). Secret lines show as Copy.HIDDEN and are never matched,
-- copied or exported.
--
-- The view is a read-only EditBox like the copy window's, so whatever is
-- shown is already copyable (Ctrl+A, Ctrl+C); addons can't write the
-- clipboard here (probe items 2-3). Export writes the view to
-- GlassChatDB.export, readable from SavedVariables after a /reload.

GlassChat = GlassChat or {}
local GC = GlassChat
local API, Glass = GC.API, GC.Glass
local Focus = {}
GC.Focus = Focus

Focus.CONTEXT = 2          -- lines kept around each match "with context"
Focus.TYPING_DELAY = 0.15  -- s after the last keystroke before the view is rebuilt

-- Kinds by chat event (API values, not display text). A line with no event
-- is Blizzard's own when it carries a chat-type id (system, loot, money,
-- XP, channel notices: ChatFrameOverrides.lua:211-537 pass info.id and no
-- event), else addon output (review of #28).
Focus.KINDS = { "Say", "Yell", "Emote", "Party", "Raid", "Guild", "Whisper", "Channel", "System", "Addons" }
local KIND_OF = {
    CHAT_MSG_SAY = "Say", CHAT_MSG_YELL = "Yell", CHAT_MSG_EMOTE = "Emote", CHAT_MSG_TEXT_EMOTE = "Emote",
    CHAT_MSG_PARTY = "Party", CHAT_MSG_PARTY_LEADER = "Party",
    CHAT_MSG_RAID = "Raid", CHAT_MSG_RAID_LEADER = "Raid", CHAT_MSG_RAID_WARNING = "Raid",
    CHAT_MSG_INSTANCE_CHAT = "Raid", CHAT_MSG_INSTANCE_CHAT_LEADER = "Raid",
    CHAT_MSG_GUILD = "Guild", CHAT_MSG_OFFICER = "Guild", CHAT_MSG_GUILD_ACHIEVEMENT = "Guild",
    CHAT_MSG_WHISPER = "Whisper", CHAT_MSG_WHISPER_INFORM = "Whisper", CHAT_MSG_BN_WHISPER = "Whisper",
    CHAT_MSG_BN_WHISPER_INFORM = "Whisper", CHAT_MSG_AFK = "Whisper", CHAT_MSG_DND = "Whisper",
    CHAT_MSG_CHANNEL = "Channel",
}
function Focus.KindOf(event, id)
    if API.IsSecret(event) then return "System" end   -- before any other use
    if event == nil then
        if API.IsSecret(id) or id ~= nil then return "System" end
        return "Addons"
    end
    if type(event) ~= "string" then return "System" end
    return KIND_OF[event] or "System"
end

--------------------------------------------------------------------------------
-- The snapshot and the view
--------------------------------------------------------------------------------

-- The window's lines, oldest first, the newest Copy.MAX of them (Copy.Read):
-- { text, kind, source, hidden }. A line with no chat event gets its writer:
-- - first from our own link on its prefix (Tabs.LinkedSource), which outlives
--   the text -> source map (#78);
-- - then from the map, but only for a line with no chat-type id. Blizzard's
--   system, loot and money lines carry one, and an addon that wraps
--   AddMessage would be on the stack for all of them (review of #79). An
--   addon line with an id is still credited through its link (Codex, #78).
function Focus.Snapshot(f)
    local entries = GC.Copy.Read(f, "focus read")
    for _, e in ipairs(entries) do
        if e.hidden then
            e.kind = "System"
        else
            e.kind = Focus.KindOf(e.event, e.id)
            if not API.IsSecret(e.event) and e.event == nil then
                local src = GC.Tabs.LinkedSource(e.raw)
                if not src and e.kind == "Addons" then src = GC.Tabs.SourceFor(e.raw) end
                if src then e.kind, e.source = "Addons", src end
            end
        end
        e.raw, e.id, e.event = nil, nil, nil
    end
    return entries
end

-- The lines the filters let through: kinds (a set; empty = all), source
-- (nil = any), search (plain, case-insensitive), with ±CONTEXT lines around
-- each match when context is on.
function Focus.Filter(lines, kinds, source, search, context)
    local passed = {}
    for _, e in ipairs(lines) do
        if (not next(kinds) or kinds[e.kind]) and (not source or e.source == source) then passed[#passed + 1] = e end
    end
    if not search or search == "" then return passed end
    local needle = search:lower()
    local keep = {}
    for i, e in ipairs(passed) do
        if not e.hidden and e.text:lower():find(needle, 1, true) then
            local lo, hi = i, i
            if context then lo, hi = math.max(1, i - Focus.CONTEXT), math.min(#passed, i + Focus.CONTEXT) end
            for j = lo, hi do keep[j] = true end
        end
    end
    local out = {}
    for i, e in ipairs(passed) do if keep[i] then out[#out + 1] = e end end
    return out
end

-- The sources present in a snapshot, sorted, for the "From" button.
local function sources(lines)
    local seen, out = {}, {}
    for _, e in ipairs(lines) do
        if e.source and not seen[e.source] then seen[e.source] = true; out[#out + 1] = e.source end
    end
    table.sort(out)
    return out
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local win
local state = { frame = nil, lines = {}, kinds = {}, source = nil, context = false, count = 0, shown = {} }

local HINT = "Frozen. Search and filter below; Select all then Ctrl+C copies what's shown."

local function render()
    win.hint:SetText(HINT)   -- a new view clears any selection (review of #28)
    local shown = Focus.Filter(state.lines, state.kinds, state.source, win.search:GetText(), state.context)
    state.shown = shown
    local texts = {}
    for i, e in ipairs(shown) do texts[i] = e.text end
    win.text = table.concat(texts, "\n")
    win.edit:SetText(win.text)
    -- Only when the source itself has no lines: a search or a kind that empties
    -- the view isn't "no lines" (review of #79).
    if state.source and #shown == 0 and #Focus.Filter(state.lines, {}, state.source, "", false) == 0 then
        -- "attributed": a line whose writer is unknown can't be counted (#78).
        win.status:SetText("No attributed " .. state.source .. " lines in this window's newest "
            .. #state.lines .. " messages")
    else
        win.status:SetText(#shown .. " of " .. #state.lines .. " lines")
    end
    for _, kind in ipairs(Focus.KINDS) do
        win.chips[kind]:SetAlpha((not next(state.kinds) or state.kinds[kind]) and 1 or 0.4)
    end
    win.from:SetText("From: " .. (state.source or "any"))
    win.context:SetText(state.context and "With context" or "Matches only")
end

-- A chosen source stays chosen with no lines in the snapshot: falling back to
-- "any" would show, copy and export everything (Codex, #78).
local function snapshot()
    state.lines = Focus.Snapshot(state.frame)
    state.count = GC.Chat.LineCount(state.frame)
    win.newer:Hide()
    render()
end

local function build()
    local pw, ph = 1000, 700
    local okW, w = pcall(UIParent.GetWidth, UIParent)
    local okH, h = pcall(UIParent.GetHeight, UIParent)
    if okW and type(w) == "number" and w > 0 then pw = math.floor(w * 0.85) end
    if okH and type(h) == "number" and h > 0 then ph = math.floor(h * 0.8) end
    win = API.Window("GlassChatFocusWindow", pw, ph)
    win:ClearAllPoints()
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    -- Row 1: search, the source, matches/context.
    local search = CreateFrame("EditBox", nil, win, "SearchBoxTemplate")
    search:SetSize(260, 20)
    search:SetAutoFocus(false)
    search:SetPoint("TOPLEFT", win.hint, "BOTTOMLEFT", 6, -10)
    -- Rebuilt once typing pauses, not per keystroke: the view can be Copy.MAX lines.
    search:HookScript("OnTextChanged", function()
        if win.quiet then return end
        local token = {}
        win.typing = token
        C_Timer.After(Focus.TYPING_DELAY, function()
            if win.typing == token then win.typing = nil; render() end
        end)
    end)
    win.search = search
    win.from = API.Button(win, "From: any", 160, function()
        local list = sources(state.lines)
        local at
        for i, s in ipairs(list) do if s == state.source then at = i end end
        -- The next one present; from "any", or from a source with no lines here, the
        -- first (review of #79). After the last: any.
        state.source = list[at and at + 1 or 1]
        render()
    end)
    win.from:SetPoint("LEFT", search, "RIGHT", 12, 0)
    win.context = API.Button(win, "Matches only", 120, function()
        state.context = not state.context
        render()
    end)
    win.context:SetPoint("LEFT", win.from, "RIGHT", 8, 0)

    -- Row 2: the kinds. A click selects or deselects one; none selected = all.
    win.chips = {}
    local prev
    for _, kind in ipairs(Focus.KINDS) do
        local b = API.Button(win, kind, 70, function()
            state.kinds[kind] = not state.kinds[kind] or nil
            render()
        end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else b:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -10) end
        win.chips[kind] = b
        prev = b
    end

    -- The view: read-only, copyable.
    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", win.chips[Focus.KINDS[1]], "BOTTOMLEFT", 0, -10)
    scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -34, 44)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(pw - 70)
    edit:SetMaxLetters(0)
    if rawget(_G, "ScrollingEdit_OnCursorChanged") then
        edit:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        edit:SetScript("OnUpdate", ScrollingEdit_OnUpdate)
    end
    API.ReadOnly(edit, win, "text", false)
    scroll:SetScrollChild(edit)
    API.AutoHideScrollBar(scroll)
    win.scroll, win.edit = scroll, edit

    -- Bottom: the count; new lines, export, select, close.
    win.status = Glass.Font(win, 11, "LEFT")
    win.status:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 14, 16)
    win.status:SetTextColor(0.75, 0.75, 0.75)
    win.close = API.Button(win, "Close", 90, function() win:Hide() end)
    win.close:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 10)
    win.select = API.Button(win, "Select all", 100, function()
        Focus.Settle()
        win.edit:SetFocus()
        win.edit:HighlightText()
        win.hint:SetText("Selected. Press Ctrl+C to copy.")
    end)
    win.select:SetPoint("RIGHT", win.close, "LEFT", -8, 0)
    win.export = API.Button(win, "Export", 90, function() Focus.Export() end)
    win.export:SetPoint("RIGHT", win.select, "LEFT", -8, 0)
    win.newer = API.Button(win, "New lines", 130, function() snapshot() end)
    win.newer:SetPoint("RIGHT", win.export, "LEFT", -8, 0)
    win.newer:Hide()

    -- New lines arrive behind the frozen view: say how many, twice a second.
    local acc = 0
    win:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + (elapsed or 0)
        if acc < 0.5 then return end
        acc = 0
        local n = GC.Chat.LineCount(state.frame) - state.count
        if n > 0 then
            win.newer:SetText(n .. " new line" .. (n == 1 and "" or "s"))
            win.newer:Show()
        end
    end)
end

-- Open focus mode on a chat window (the one in view by default), with an
-- optional search and an optional source (an addon's folder name: only its
-- lines, #78).
function Focus.Open(f, search, source)
    f = f or GC.Copy.CurrentFrame()
    if not f then return end
    if not win then build() end
    state.frame, state.kinds, state.source, state.context = f, {}, source, false
    win.title:SetText("Focus: " .. GC.Copy.WindowName(f))
    API.ShowWindow(win)
    win.quiet = true   -- set the search without a render; snapshot renders once
    win.search:SetText(search or "")
    win.quiet = false
    snapshot()
    win.scroll:SetVerticalScroll(0)
end

-- A search still waiting for its pause is applied now, so what's copied or
-- exported is the view for the search shown (Codex review of #28).
function Focus.Settle()
    if win and win.typing then
        win.typing = nil
        render()
    end
end

-- The view, as plain lines, into SavedVariables for after a /reload.
function Focus.Export()
    if not win then return end
    Focus.Settle()
    local out = {}   -- at most Copy.MAX lines: the snapshot's size
    for _, e in ipairs(state.shown) do
        if not e.hidden then out[#out + 1] = e.text end
    end
    local kinds = {}
    for k in pairs(state.kinds) do kinds[#kinds + 1] = k end
    table.sort(kinds)
    GC.db.export = {
        at = date("%Y-%m-%d %H:%M:%S"),
        window = GC.Copy.WindowName(state.frame),
        search = win.search:GetText(),
        kinds = #kinds > 0 and table.concat(kinds, ",") or "all",
        source = state.source or "any",
        lines = out,
    }
    API.Print("exported " .. #out .. " lines to GlassChatDB.export: after a /reload or logout it's in " ..
        "WTF\\Account\\<account>\\SavedVariables\\GlassChat.lua")
end

--------------------------------------------------------------------------------
-- The magnifier on the tab strip, left of the copy icon
--------------------------------------------------------------------------------

Focus.ICON = "common-search-magnifyingglass"
local buttons = setmetatable({}, { __mode = "k" })

function Focus.Button(f)
    if buttons[f] then return end
    local p = GC.Skin.Panel(f)
    if not p then return end
    local b = CreateFrame("Button", nil, p.panel)
    b:SetFrameStrata("MEDIUM")
    b:SetSize(GC.Copy.BUTTON_W, GC.Copy.BUTTON_H)
    b:SetPoint("TOPRIGHT", p.panel, "TOPRIGHT", -14 - GC.Skin.STRIP_ICON_STEP, -9)
    local icon = b:CreateTexture(nil, "OVERLAY")
    icon:SetSize(14, 14)
    icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    local get = C_Texture and C_Texture.GetAtlasInfo
    local okA, info = false, nil
    if get then okA, info = pcall(get, Focus.ICON) end
    if okA and info and not API.IsSecret(info) then icon:SetAtlas(Focus.ICON) else icon:SetColorTexture(1, 1, 1, 0.5) end
    icon:SetDesaturated(true)
    local grey, accent = GC.Skin.TAB_GREY, GC.Skin.ACCENT
    icon:SetVertexColor(grey[1], grey[2], grey[3])
    b:SetScript("OnEnter", function(self)
        icon:SetVertexColor(accent[1], accent[2], accent[3])
        local tip = rawget(_G, "GameTooltip")
        if tip then
            tip:SetOwner(self, "ANCHOR_TOP")
            tip:SetText("Focus: freeze, search and filter this window")
            tip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        icon:SetVertexColor(grey[1], grey[2], grey[3])
        local tip = rawget(_G, "GameTooltip")
        if tip then tip:Hide() end
    end)
    b:SetScript("OnClick", function() Focus.Open(f) end)
    b.icon = icon
    buttons[f] = b
end

GC.Chat.OnEachFrame("focus", Focus.Button)

Focus._test = { window = function() return win end, state = state, buttons = buttons }
