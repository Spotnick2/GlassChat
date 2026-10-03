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
--   7. which addons write to chat, through print or AddMessage       /cprobe sources
--   8. routing one addon's print output to its own tab              /cprobe route
--   9. moving one addon's direct AddMessage lines to that tab        /cprobe move
--
-- Every client call that may be missing or throw goes through try(), so one
-- refusal cannot stop the rest of the probe.

local ADDON, NS = ...
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
-- RegisterEvent throws on an unknown name and returns false on a refusal:
-- both are reported, or an item would read "never fired" instead.
local function register(frame, event)
    local ok, registered = pcall(frame.RegisterEvent, frame, event)
    if not ok then say("|cffff6060FAIL|r RegisterEvent " .. event .. ": " .. tostring(registered))
    elseif registered == false then say("|cffff6060FAIL|r RegisterEvent " .. event .. ": refused") end
end
register(watcher, "ADDON_ACTION_BLOCKED")
register(watcher, "ADDON_ACTION_FORBIDDEN")

-- The filters can't be removed once added, so they count only while watching,
-- the same window the event counts cover.
local function messageFilter()
    if P.watching then P.filterCalls = P.filterCalls + 1 end
    return false
end
local function nameFilter(name)
    if P.watching then P.nameFilterCalls = P.nameFilterCalls + 1 end
    return name
end

local function watch()
    P.watching = not P.watching
    for _, e in ipairs(WATCH) do
        if P.watching then register(watcher, e)
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
-- 7. Where addon output comes from (smart tabs)
--------------------------------------------------------------------------------

-- The addon folder that called print (or AddMessage): the first stack FRAME
-- whose file is neither the print plumbing nor, as the handler, us. Per line,
-- the first path only: a frame line names its file twice (where it is, and
-- "in function <file:line>"), so matching every path skipped us once and
-- then found us again (measured, 70205: everything came out as ChatProbe).
local PLUMBING = { Blizzard_PrintHandler = true, Blizzard_SharedXML = true, Blizzard_ChatFrameBase = true }
P.stackSamples = {}
local function sourceOf()
    if not debugstack then return "no debugstack" end
    local ok, stack = pcall(debugstack, 2, 20, 0)
    if not ok or type(stack) ~= "string" then return "unknown" end
    -- The stack starts with OUR frames (sourceOf itself, then the handler or
    -- hook: measured, debugstack(2) still lists sourceOf). Skip that whole
    -- leading run, then the plumbing and C frames; the next addon is the
    -- caller (ChatProbe again when the probe printed).
    local leading, found, blizzard = true, "unknown", false
    for line in stack:gmatch("[^\n]+") do
        local name = line:match("AddOns[/\\]([^/\\]+)[/\\]")
        if leading then
            if name ~= ADDON then leading = false end
        end
        if not leading and name then
            if not PLUMBING[name] then found = name; break end
            blizzard = true
        end
    end
    -- Only chat plumbing above us: one of Blizzard's own 5-argument
    -- AddMessage lines (system, notices: ChatFrameOverrides.lua:211-405).
    if found == "unknown" and blizzard then found = "Blizzard" end
    -- One raw sample per source, so the log shows the real stack format.
    if P.tracing and not P.stackSamples[found] then P.stackSamples[found] = stack:sub(1, 600) end
    return found
end

local function bump(t, k) t[k] = (t[k] or 0) + 1 end

-- inPrint: inside the original print handler. selfEmit: the probe itself
-- re-adding a line (routing, moving). The AddMessage hook ignores both.
local origPrint, inPrint, selfEmit
P.printSources, P.directSources = {}, {}
P.tracing, P.routeFrame = false, nil

-- One wrapper for items 7 and 8. It never prints (that would recurse); it
-- only counts, and routes our own lines when item 8 is on.
local function printHandler(...)
    if not (P.tracing or P.routeFrame) then return origPrint(...) end   -- no stack walk when idle
    local src = sourceOf()
    if P.tracing then bump(P.printSources, src) end
    if P.routeFrame and src == ADDON then
        selfEmit = true
        local ok, err = pcall(function(...) P.routeFrame:AddMessage(strjoin(" ", tostringall(...))) end, ...)
        selfEmit = false
        if not ok then P.routeError = tostring(err) end
        return
    end
    inPrint = true
    local ok, err = pcall(origPrint, ...)
    inPrint = false
    if not ok then error(err, 0) end
end

local function installPrint()
    if origPrint then return true end
    if not (getprinthandler and setprinthandler) then say("7 print handler API absent"); return false end
    origPrint = getprinthandler()
    local ok = try("setprinthandler", setprinthandler, printHandler)
    if not ok then origPrint = nil end
    return ok
end

local hookedFrames = {}
-- Item 9 moves one addon's direct AddMessage lines: the post-hook copies the
-- line to the tab, then removes it from the frame it landed in through the
-- public RemoveMessagesByPredicate (ScrollingMessageFrame.lua:45).
local function moveLine(frame, msg, r, g, b)
    local target = P.moveTarget
    if frame == target or type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
    selfEmit = true
    local okA, errA = pcall(target.AddMessage, target, msg, r, g, b)
    selfEmit = false
    if not okA then P.moveError = tostring(errA); return end
    -- RemoveIf walks OLDEST to newest (CircularBuffer.lua:89), and an older
    -- identical line may exist: count the matches, then remove only the last
    -- one, which is the line just added. Secret lines are never compared.
    local function same(m) return not (issecretvalue and issecretvalue(m)) and m == msg end
    local matches, seen, removed = 0, 0, false
    local okC, errC = pcall(frame.RemoveMessagesByPredicate, frame, function(m)
        if same(m) then matches = matches + 1 end
        return false
    end)
    local okR, errR = true, nil
    if okC and matches > 0 then
        okR, errR = pcall(frame.RemoveMessagesByPredicate, frame, function(m)
            if not same(m) then return false end
            seen = seen + 1
            if seen == matches then removed = true; return true end
            return false
        end)
    end
    if not okC then P.moveError = tostring(errC) elseif not okR then P.moveError = tostring(errR) end
    P.moved = P.moved + 1
    if not removed then P.notRemoved = P.notRemoved + 1 end
end

local function hookDirect()
    for i = 1, maxWindows() do
        local f = _G["ChatFrame" .. i]
        if f and not hookedFrames[f] then
            hookedFrames[f] = true
            try("hook AddMessage " .. i, hooksecurefunc, f, "AddMessage", function(frame, msg, r, g, b, _, _, _, event)
                if inPrint or selfEmit or not (P.tracing or P.moveSource) then return end
                if issecretvalue and issecretvalue(event) then
                    if P.tracing then bump(P.directSources, "<secret event>") end
                    return
                end
                if event ~= nil then return end
                local src = sourceOf()
                if P.tracing then bump(P.directSources, src) end
                if P.moveSource and src == P.moveSource then moveLine(frame, msg, r, g, b) end
            end)
        end
    end
end

local function sources()
    if not P.tracing then
        if not installPrint() then return end
        hookDirect()
        P.tracing = true
        say("7 tracing addon output: use your addons (run ASProbe etc.), then /cprobe sources again for the counts")
        return
    end
    P.tracing = false
    for src, n in pairs(P.printSources) do say("7 print from " .. src .. " = " .. n) end
    for src, n in pairs(P.directSources) do say("7 AddMessage (no chat event) from " .. src .. " = " .. n) end
    for src, stack in pairs(P.stackSamples) do
        say("7 sample stack for " .. src .. ": " .. stack:gsub("\n", " || "))
    end
    P.printSources, P.directSources, P.stackSamples = {}, {}, {}
    say("7 tracing off. 'print' lines go through the print handler; 'AddMessage' ones need item 9.")
end

--------------------------------------------------------------------------------
-- 8. Route one addon's output to its own tab
--------------------------------------------------------------------------------

-- The "Probe" tab: the one this character already has, else a new empty one.
local function probeTab()
    for i = 1, maxWindows() do
        -- A closed tab keeps its name (FCF_Close only hides and undocks), so
        -- reuse only one that is shown or docked.
        local ok, name, _, _, _, _, _, shown, _, docked = pcall(GetChatWindowInfo, i)
        if ok and name == "Probe" and (shown or docked) and _G["ChatFrame" .. i] then
            return _G["ChatFrame" .. i], false
        end
    end
    if not FCF_OpenNewWindow then say("FCF_OpenNewWindow absent"); return nil end
    local ok, frame = try("FCF_OpenNewWindow", FCF_OpenNewWindow, "Probe", true)
    if not (ok and frame) then say("no new tab (all chat windows in use?)"); return nil end
    return frame, true
end

local function route()
    if P.routeFrame then
        P.routeFrame = nil
        say("8 routing off: ChatProbe lines are back in the main chat."
            .. (P.routeError and (" Routing error: " .. P.routeError) or ""))
        return
    end
    if not installPrint() then return end
    local frame, new = probeTab()
    if not frame then return end
    local groups = frame.messageTypeList and #frame.messageTypeList or "?"
    say("8 " .. (new and "opened" or "reusing") .. " tab " .. show(frame:GetName()) .. " with " .. show(groups)
        .. " message groups. Routing ChatProbe's lines there.")
    P.routeFrame = frame
    say("8 this line should be in the 'Probe' tab, not in General. Watch for a blocked-action line; /cprobe route again to stop.")
end

--------------------------------------------------------------------------------
-- 9. Move one addon's direct AddMessage output to its own tab
--------------------------------------------------------------------------------

P.moved, P.notRemoved = 0, 0
local function move(arg)
    if P.moveSource then
        say("9 moving off: " .. P.moved .. " lines moved from " .. P.moveSource .. ", " .. P.notRemoved
            .. " copied but not removed" .. (P.moveError and (", error: " .. P.moveError) or ""))
        P.moveSource, P.moveTarget, P.moved, P.notRemoved, P.moveError = nil, nil, 0, 0, nil
        return
    end
    local frame = probeTab()
    if not frame then return end
    hookDirect()
    P.moveTarget, P.moveSource = frame, (arg and arg ~= "") and arg or "AltStableProbe"
    say("9 moving " .. P.moveSource .. "'s AddMessage lines to the 'Probe' tab. Use it, check General has none"
        .. " of them and Probe has them all, then /cprobe move again for the counts.")
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
    say("/cprobe sources  - 7 toggle tracing which addons print to chat, and how")
    say("/cprobe route    - 8 toggle sending ChatProbe's own lines to a new 'Probe' tab")
    say("/cprobe move [addon] - 9 toggle moving an addon's direct AddMessage lines (default AltStableProbe) to 'Probe'")
    say("/cprobe clear    - empty the saved log")
end

SLASH_CHATPROBE1 = "/cprobe"
SlashCmdList.CHATPROBE = function(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "state" then state()
    elseif cmd == "clip" then clip()
    elseif cmd == "copyable" then copyable()
    elseif cmd == "link" then link()
    elseif cmd == "watch" then watch()
    elseif cmd == "report" then report()
    elseif cmd == "history" then history()
    elseif cmd == "sources" then sources()
    elseif cmd == "route" then route()
    elseif cmd == "move" then move(arg)
    elseif cmd == "clear" then ChatProbeDB.log = {}; say("log cleared")
    else help() end
end

local boot = CreateFrame("Frame")
register(boot, "ADDON_LOADED")
boot:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON then return end
    if type(ChatProbeDB) ~= "table" then ChatProbeDB = {} end
    if type(ChatProbeDB.log) ~= "table" then ChatProbeDB.log = {} end
    ChatProbeDB.loads = (ChatProbeDB.loads or 0) + 1
    say("loaded (" .. ChatProbeDB.loads .. " loads). /cprobe help")
end)

-- The test seam lives on the addon namespace, not in _G.
NS._test = { P = P, state = state, clip = clip, copyable = copyable, link = link, watch = watch,
    report = report, history = history, watcher = watcher, sources = sources, route = route,
    sourceOf = sourceOf, printHandler = printHandler, move = move }
