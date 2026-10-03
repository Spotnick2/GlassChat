-- History.lua: what you sent, on plain Up/Down, kept across sessions.
--
-- The edit box keeps its own history (historyLines="32" in
-- ChatFrameEditBox.xml); stock Forever cycles it with Alt+Up/Down.
-- SetAltArrowKeyMode(false) puts it on the plain arrows, as Prat's Editbox
-- module does. Lines are recorded from a hooksecurefunc on each edit box's
-- AddHistoryLine (Blizzard calls it on send, ChatFrameEditBox.lua:248-276)
-- into GlassChatCharDB.sent, and replayed into every edit box at login
-- (Prat History's recipe).

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local History = {}
GC.History = History

History.MIN, History.MAX = 10, 500

local seen = setmetatable({}, { __mode = "k" })   -- edit boxes already set up

local function sent()
    local c = GC.charDB
    if type(c.sent) ~= "table" then c.sent = {} end
    return c.sent
end

local function trim(list, max)
    while #list > max do table.remove(list, 1) end
end

local function record(_, text)
    if type(text) ~= "string" or API.IsSecret(text) or text == "" then return end
    local list = sent()
    if list[#list] == text then return end   -- Blizzard may add the same line twice in one send
    list[#list + 1] = text
    trim(list, GC.db.history)
end

function History.EditBox(edit)
    edit:SetAltArrowKeyMode(not GC.db.plainArrows)
    if seen[edit] then return end
    seen[edit] = true
    edit:SetHistoryLines(GC.db.history)
    local ok, err = pcall(function()
        for _, line in ipairs(sent()) do edit:AddHistoryLine(line) end
    end)
    if not ok then API.Fail("history replay " .. tostring(edit:GetName()), err) end
    -- Hooked only AFTER the replay, so replayed lines aren't recorded again.
    hooksecurefunc(edit, "AddHistoryLine", record)
end

GC.Chat.OnEachFrame("history", function(f)
    local edit = rawget(_G, f:GetName() .. "EditBox")
    if edit then History.EditBox(edit) end
end)

History._test = { record = record, sent = sent }
