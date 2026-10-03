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

-- Up: one line older. Down: one line newer; past the newest, back to what
-- was being typed. The list is newest last.
local function onArrow(edit, key)
    if not GC.db.plainArrows or (key ~= "UP" and key ~= "DOWN") or locked() then return end
    local list, s = sent(), state[edit]
    local n = #list
    if n == 0 or not s then return end
    if key == "UP" then
        if s.index == 0 then s.draft = edit:GetText() end
        if s.index < n then s.index = s.index + 1 end
    else
        if s.index == 0 then return end
        s.index = s.index - 1
    end
    if s.index == 0 then edit:SetText(s.draft or "") else edit:SetText(list[n - s.index + 1]) end
end

function History.EditBox(edit)
    edit:SetAltArrowKeyMode(not GC.db.plainArrows)
    if state[edit] then return end
    state[edit] = { index = 0 }
    edit:SetHistoryLines(GC.db.history)
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
