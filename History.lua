-- History.lua: what you sent, on plain Up/Down, kept across sessions.
--
-- Measured (70205): the edit box's own history does NOT answer plain arrows,
-- even with SetAltArrowKeyMode(false). The template has ignoreArrows="true"
-- (ChatFrameEditBox.xml:3). Prat's Editbox module turns Alt mode off so
-- OnArrowPressed fires, then cycles its OWN list with SetText
-- (Editbox.lua:291-323). We do the same with GlassChatCharDB.sent.
--
-- Lines are recorded from a hooksecurefunc on each edit box's AddHistoryLine
-- (Blizzard calls it on send, ChatFrameEditBox.lua:248-276). They are also
-- replayed into the native history, so Alt+Up/Down (arrows option off)
-- knows them too.

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local History = {}
GC.History = History

History.MIN, History.MAX = 10, 500

-- Per edit box: { index = 0 (not browsing) .. #sent, draft = text before browsing }.
local state = setmetatable({}, { __mode = "k" })

local function sent()
    local c = GC.charDB
    if type(c.sent) ~= "table" then c.sent = {} end
    return c.sent
end

local function trim(list, max)
    while #list > max do table.remove(list, 1) end
end

-- After a send, every box starts again from the newest line.
local function resetAll()
    for _, s in pairs(state) do s.index, s.draft = 0, nil end
end

local function record(_, text)
    if type(text) ~= "string" or API.IsSecret(text) or text == "" then return end
    resetAll()
    local list = sent()
    if list[#list] == text then return end   -- Blizzard may add the same line twice in one send
    list[#list + 1] = text
    trim(list, GC.db.history)
end

-- Chat messaging lockdown blocks SetText on the edit box (Prat's guard).
local function locked()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() == true
end

-- Name suggestions (/w Exa...) use Up/Down too: leave the keys to them
-- while the list is open for this box (Blizzard's own test,
-- AutoComplete.lua:360).
local function suggesting(edit)
    local ac = rawget(_G, "AutoCompleteBox")
    return ac ~= nil and ac:IsShown() and ac.parent == edit
end

-- The draft is its text AND its destination. SetText re-parses the box
-- (OnTextChanged -> ParseText, ChatFrameEditBox.lua:473-474), so recalling
-- "/s ..." switches it to SAY; restoring only the text would then send an
-- unfinished whisper publicly (Codex review of #4). The destination lives in
-- these attributes (ChatFrameEditBox.lua:14-50).
local DESTINATION = { "chatType", "tellTarget", "channelTarget", "stickyType" }

local function saveDraft(edit)
    local d = { text = edit:GetText() }
    for _, k in ipairs(DESTINATION) do d[k] = edit:GetAttribute(k) end
    return d
end

-- Text first (it re-parses), then the saved destination over whatever the
-- parse chose, then the header ("Say:", "Tell Bob:") redrawn to match.
local function restoreDraft(edit, d)
    edit:SetText(d and d.text or "")
    if not d then return end
    for _, k in ipairs(DESTINATION) do edit:SetAttribute(k, d[k]) end
    if edit.UpdateHeader then
        local ok, err = pcall(edit.UpdateHeader, edit)
        if not ok then API.Fail("history header", err) end
    end
end

-- Up: one line older. Down: one line newer; past the newest, back to the
-- draft, destination included. The list is newest last.
local function onArrow(edit, key)
    if not GC.db.plainArrows or (key ~= "UP" and key ~= "DOWN") or locked() or suggesting(edit) then return end
    local list, s = sent(), state[edit]
    local n = #list
    if n == 0 or not s then return end
    if key == "UP" then
        if s.index == 0 then s.draft = saveDraft(edit) end
        if s.index < n then s.index = s.index + 1 end
    else
        if s.index == 0 then return end
        s.index = s.index - 1
    end
    if s.index == 0 then restoreDraft(edit, s.draft) else edit:SetText(list[n - s.index + 1]) end
end

-- A new history size: the saved list and every native history follow.
function History.Trim()
    trim(sent(), GC.db.history)
end

function History.EditBox(edit)
    edit:SetAltArrowKeyMode(not GC.db.plainArrows)
    edit:SetHistoryLines(GC.db.history)
    if state[edit] then return end
    state[edit] = { index = 0 }
    local ok, err = pcall(function()
        for _, line in ipairs(sent()) do edit:AddHistoryLine(line) end
    end)
    if not ok then API.Fail("history replay " .. tostring(edit:GetName()), err) end
    -- Hooked only AFTER the replay, so replayed lines aren't recorded again.
    hooksecurefunc(edit, "AddHistoryLine", record)
    edit:HookScript("OnArrowPressed", onArrow)
    edit:HookScript("OnEditFocusLost", function(self) state[self].index, state[self].draft = 0, nil end)
end

GC.Chat.OnEachFrame("history", function(f)
    local edit = rawget(_G, f:GetName() .. "EditBox")
    if edit then History.EditBox(edit) end
end)

History._test = { record = record, sent = sent, onArrow = onArrow, state = state }
