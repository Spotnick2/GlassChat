-- ChatProbe: the throwaway measurement addon for GlassChat, milestone 0.
-- It answers the questions docs/PLAN.md leaves open before any real chat
-- code is written. Every line it prints also goes to ChatProbeDB.log
-- (SavedVariables), so a full client exit leaves the session on disk for
-- review. It never logs what other players said: only lengths, types and
-- whether a value was secret.
--
-- What it measures (the numbers match the plan's probe items):
--   1. the stock chat state: class colours, line limit, filter API  /cprobe state
--   2. CopyToClipboard from addon code                              /cprobe clip
--   3. drag-select copy on a chat frame (SetTextCopyable)           /cprobe copyable
--   4. a clickable addon link (|Haddon:...|h + EventRegistry)        /cprobe link
--   5. secrecy of chat event payloads, in and out of combat and
--      instances, and whether addon filters still run               /cprobe watch
--   6. reading the scrollback (GetMessageInfo), secret lines         /cprobe history
--
-- Every client call that may be missing or throw goes through try(), so one
-- refusal cannot stop the rest of the probe.

local ADDON = ...
local MAX_LOG = 3000
local function maxWindows()
    local c = Constants and Constants.ChatFrameConstants
    return (c and c.MaxChatWindows) or NUM_CHAT_WINDOWS or 10
end

local P = { watching = false, counts = {}, samples = {}, filterCalls = 0, nameFilterCalls = 0 }

--------------------------------------------------------------------------------
-- Log
--------------------------------------------------------------------------------

local function stamp()
    local t = GetTime and GetTime() or 0
    return string.format("%.1f%s", t, InCombatLockdown() and " C" or "")
end

local function say(msg)
    msg = tostring(msg)
    print("|cff7fd4ffChatProbe|r " .. msg)
    if type(ChatProbeDB) == "table" and type(ChatProbeDB.log) == "table" then
        local log = ChatProbeDB.log
        log[#log + 1] = stamp() .. " " .. msg
        if #log > MAX_LOG then table.remove(log, 1) end
    end
end

-- Describe a value without ever operating on a secret one.
local function show(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    if v == nil then return "nil" end
    return tostring(v)
end

-- Describe a string by type and length only (never its content).
local function shape(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    if type(v) == "string" then return "str" .. #v end
    return type(v)
end

local function try(label, fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then say("|cffff6060FAIL|r " .. label .. ": " .. tostring(a)) end
    return ok, a, b, c, d
end

local function lockdown()
    if not (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown) then return "n/a" end
    local ok, v = pcall(C_ChatInfo.InChatMessagingLockdown)
    return ok and show(v) or "error"
end

local function where()
    local _, kind = GetInstanceInfo()
    return "instance=" .. show(kind) .. " lockdown=" .. lockdown()
end

--------------------------------------------------------------------------------
-- 1. Stock chat state
--------------------------------------------------------------------------------

local function present(path)
    local t = _G
    for part in path:gmatch("[^.]+") do
        if type(t) ~= "table" then return false end
        t = rawget(t, part)   -- rawget: asking must not trip a strict _G
    end
    return t ~= nil
end

local function state()
    say("client " .. table.concat({ GetBuildInfo() }, " ", 1, 2) .. ", " .. where())
    local okC, override = try("GetCVar", C_CVar.GetCVar, "chatClassColorOverride")
    say("1 CVar chatClassColorOverride = " .. show(okC and override or nil)
        .. " (0 = always colour, 1 = never, else per chat type)")
    for _, kind in ipairs({ "SAY", "YELL", "PARTY", "RAID", "GUILD", "OFFICER", "WHISPER", "CHANNEL", "EMOTE" }) do
        local info = ChatTypeInfo and ChatTypeInfo[kind]
        say("1 ChatTypeInfo." .. kind .. ".colorNameByClass = " .. show(info and info.colorNameByClass))
    end
    if ChatFrameUtil and ChatFrameUtil.ShouldColorChatByClass and ChatTypeInfo then
        local ok, v = try("ShouldColorChatByClass", ChatFrameUtil.ShouldColorChatByClass, ChatTypeInfo.SAY)
        if ok then say("1 ShouldColorChatByClass(SAY) = " .. show(v)) end
    end
    for _, name in ipairs({ "ChatFrameUtil.AddMessageEventFilter", "ChatFrameUtil.AddSenderNameFilter",
        "ChatFrame_AddMessageEventFilter", "ChatFrameUtil.GetDecoratedSenderName", "CopyToClipboard",
        "C_StringUtil.StripHyperlinks", "EventRegistry", "GetPlayerInfoByGUID", "NUM_CHAT_WINDOWS",
        "ChatFrame_MessageEventHandler", "ChatFrame_OnHyperlinkShow" }) do
        say("1 present " .. name .. " = " .. tostring(present(name)))
    end
    local n = maxWindows()
    for i = 1, n do
        local f = _G["ChatFrame" .. i]
        if f then
            local okL, lines = try("GetMaxLines", f.GetMaxLines, f)
            local okN, num = try("GetNumMessages", f.GetNumMessages, f)
            say(string.format("1 ChatFrame%d shown=%s maxLines=%s messages=%s copyable=%s", i,
                tostring(f:IsShown()), show(okL and lines), show(okN and num), show(f.IsTextCopyable and f:IsTextCopyable())))
        end
    end
end

--------------------------------------------------------------------------------
-- 2. Clipboard
--------------------------------------------------------------------------------

local function clip()
    if not CopyToClipboard then say("2 CopyToClipboard is absent"); return end
    local text = "GlassChat probe " .. tostring(time())
    local ok, n = try("CopyToClipboard", CopyToClipboard, text, true)
    say("2 CopyToClipboard ok=" .. tostring(ok) .. " returned=" .. show(n)
        .. ". Now paste (Ctrl+V) in Notepad: expect '" .. text .. "'. Watch for a blocked-action line.")
end

--------------------------------------------------------------------------------
-- 3. Drag-select copy on ChatFrame1
--------------------------------------------------------------------------------

local function copyable()
    local f = ChatFrame1
    if not (f and f.SetTextCopyable) then say("3 ChatFrame1:SetTextCopyable is absent"); return end
    local on = not f:IsTextCopyable()
    try("SetTextCopyable", f.SetTextCopyable, f, on)
    say("3 ChatFrame1 copyable = " .. show(f:IsTextCopyable())
        .. (on and ". Drag-select some text in the main chat, release, then paste in Notepad."
            .. " Also check clicking links and dragging the frame still work." or ""))
end

--------------------------------------------------------------------------------
-- 4. A clickable addon link
--------------------------------------------------------------------------------

local linkHooked = false
local function link()
    if not linkHooked then
        if EventRegistry and EventRegistry.RegisterCallback then
            try("EventRegistry SetItemRef", EventRegistry.RegisterCallback, EventRegistry, "SetItemRef",
                function(_, l, text, button)
                    if type(l) == "string" and l:find("^addon:chatprobe") then
                        say("4 SetItemRef callback: link=" .. l .. " button=" .. show(button)
                            .. " shift=" .. tostring(IsShiftKeyDown()))
                    end
                end, P)
        end
        if hooksecurefunc then
            try("hook SetItemRef", hooksecurefunc, "SetItemRef", function(l)
                if type(l) == "string" and l:find("^addon:chatprobe") then say("4 SetItemRef hook saw " .. l) end
            end)
        end
        linkHooked = true
    end
    print("|cff7fd4ffChatProbe|r 4 click this: |cff40c0ff|Haddon:chatprobe:hello|h[ChatProbe link]|h|r"
        .. " (left, right and shift-click; expect a log line for each, no error, no tooltip)")
end

--------------------------------------------------------------------------------
-- 5. Chat payload secrecy and filters
--------------------------------------------------------------------------------

local WATCH = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE", "CHAT_MSG_SYSTEM", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_LOOT",
    "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL" }

local watcher = CreateFrame("Frame")
local filtersAdded = false

local function bucket(event)
    return event .. (InCombatLockdown() and " C" or "") .. " lockdown=" .. lockdown()
end

watcher:SetScript("OnEvent", function(_, event, text, sender, _, _, _, _, _, _, _, _, lineID, guid)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        say("|cffff6060" .. event .. "|r " .. show(text) .. " " .. show(sender))
        return
    end
    local key = bucket(event)
    P.counts[key] = (P.counts[key] or 0) + 1
    if (P.samples[key] or 0) >= 3 then return end   -- three samples per bucket
    P.samples[key] = (P.samples[key] or 0) + 1
    local class = "?"
    if GetPlayerInfoByGUID and type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) and guid ~= "" then
        local ok, _, englishClass = pcall(GetPlayerInfoByGUID, guid)
        class = ok and show(englishClass) or "error"
    end
    say("5 " .. key .. " text=" .. shape(text) .. " sender=" .. shape(sender) .. " lineID=" .. shape(lineID)
        .. " guid=" .. shape(guid) .. " class=" .. class .. " " .. where())
end)
watcher:RegisterEvent("ADDON_ACTION_BLOCKED")
watcher:RegisterEvent("ADDON_ACTION_FORBIDDEN")

local function messageFilter() P.filterCalls = P.filterCalls + 1; return false end
local function nameFilter(name) P.nameFilterCalls = P.nameFilterCalls + 1; return name end

local function watch()
    P.watching = not P.watching
    for _, e in ipairs(WATCH) do
        if P.watching then try("RegisterEvent " .. e, watcher.RegisterEvent, watcher, e)
        else watcher:UnregisterEvent(e) end
    end
    if P.watching and not filtersAdded and ChatFrameUtil then
        for _, e in ipairs(WATCH) do
            try("AddMessageEventFilter " .. e, ChatFrameUtil.AddMessageEventFilter, e, messageFilter)
        end
        if ChatFrameUtil.AddSenderNameFilter then
            try("AddSenderNameFilter", ChatFrameUtil.AddSenderNameFilter, nameFilter)
        end
        filtersAdded = true
    end
    say("5 watching chat payloads = " .. tostring(P.watching)
        .. (P.watching and ". Chat in say/party/guild, out of combat, in combat and in a dungeon; then /cprobe report." or ""))
end

local function report()
    local events = 0
    for key, n in pairs(P.counts) do
        events = events + n
        say("5 count " .. key .. " = " .. n)
    end
    -- Each event is filtered once per chat frame that shows it, so calls >=
    -- events is normal; calls well under events means filters were skipped.
    say("5 events=" .. events .. " messageFilter calls=" .. P.filterCalls .. " senderNameFilter calls=" .. P.nameFilterCalls)
end

--------------------------------------------------------------------------------
-- 6. Scrollback
--------------------------------------------------------------------------------

local function history()
    for i = 1, maxWindows() do
        local f = _G["ChatFrame" .. i]
        if f and f.GetNumMessages then
            local ok, n = try("GetNumMessages", f.GetNumMessages, f)
            if ok and type(n) == "number" then
                local secret, plain, longest = 0, 0, 0
                for m = 1, n do
                    local okM, text, r, g, b, lineID = pcall(f.GetMessageInfo, f, m)
                    if not okM then secret = secret + 1
                    elseif issecretvalue and issecretvalue(text) then secret = secret + 1
                    elseif type(text) == "string" then
                        plain = plain + 1
                        if #text > longest then longest = #text end
                    end
                end
                local okH, has = false, nil
                if f.HasSecretValues then okH, has = pcall(f.HasSecretValues, f) end
                say(string.format("6 ChatFrame%d messages=%d plain=%d secret=%d longest=%d HasSecretValues=%s",
                    i, n, plain, secret, longest, okH and show(has) or "n/a"))
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

local function help()
    say("/cprobe state    - 1 stock chat settings and APIs")
    say("/cprobe clip     - 2 copy a test string to the clipboard")
    say("/cprobe copyable - 3 toggle drag-select copy on the main chat")
    say("/cprobe link     - 4 print a clickable addon link")
    say("/cprobe watch    - 5 toggle logging chat payload secrecy (then /cprobe report)")
    say("/cprobe history  - 6 read the scrollback of every chat frame")
    say("/cprobe clear    - empty the saved log")
end

SLASH_CHATPROBE1 = "/cprobe"
SlashCmdList.CHATPROBE = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "state" then state()
    elseif cmd == "clip" then clip()
    elseif cmd == "copyable" then copyable()
    elseif cmd == "link" then link()
    elseif cmd == "watch" then watch()
    elseif cmd == "report" then report()
    elseif cmd == "history" then history()
    elseif cmd == "clear" then ChatProbeDB.log = {}; say("log cleared")
    else help() end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON then return end
    if type(ChatProbeDB) ~= "table" then ChatProbeDB = {} end
    if type(ChatProbeDB.log) ~= "table" then ChatProbeDB.log = {} end
    ChatProbeDB.loads = (ChatProbeDB.loads or 0) + 1
    say("loaded (" .. ChatProbeDB.loads .. " loads). /cprobe help")
end)

ChatProbe_test = { P = P, state = state, clip = clip, copyable = copyable, link = link, watch = watch,
    report = report, history = history, watcher = watcher }
