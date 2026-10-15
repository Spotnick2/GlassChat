-- ChatProbe: the throwaway measurement addon for GlassChat, milestone 0.
-- It answers the questions docs/PLAN.md leaves open before any real chat
-- code is written. It is a ForeverProbe module (..\ForeverProbe, its
-- docs/GUIDE.md): its lines go to the ForeverProbe console (/fp), never to
-- chat, and to ChatProbeDB.log (SavedVariables), so a full client exit leaves
-- the session on disk for review. It never logs what other players said: only
-- lengths, types and whether a value was secret.
--
-- Chat is what it measures, so a few commands still write to chat ON PURPOSE:
-- those lines are the test stimuli (item 4's link, item 8's routed line), not
-- its diagnostics.
--
-- What it measures (the numbers match the plan's probe items):
--   1. the stock chat state: class colours, line limit, filter API  /fp chat state
--   2. CopyToClipboard from addon code                              /fp chat clip
--   3. drag-select copy on a chat frame (SetTextCopyable)           /fp chat copyable
--   4. a clickable addon link (|Haddon:...|h + EventRegistry)        /fp chat link
--   5. secrecy of chat event payloads, in and out of combat and
--      instances, and whether addon filters still run               /fp chat watch
--   6. reading the scrollback (GetMessageInfo), secret lines         /fp chat history
--   7. which addons write to chat, through print or AddMessage       /fp chat sources
--   8. routing one addon's print output to its own tab              /fp chat route
--   9. moving one addon's direct AddMessage lines to that tab        /fp chat move
--  10. line identity per chat type (lineID, GUID, collisions)       /fp chat lines
--  11. sender name shapes; server ignore with surnames              /fp chat ignoretest
--  12. ignore-list readiness at login; what the server ignore blocks (automatic)
--
-- Every client call that may be missing or throw goes through Probe:Try, so
-- one refusal cannot stop the rest of the probe.

local ADDON, NS = ...
local MAX_LOG = 3000
local function maxWindows()
    local c = Constants and Constants.ChatFrameConstants
    return (c and c.MaxChatWindows) or NUM_CHAT_WINDOWS or 10
end

local P = { watching = false, counts = {}, samples = {}, filterCalls = 0, nameFilterCalls = 0 }

--------------------------------------------------------------------------------
-- Log: the ForeverProbe module. Lines go to the console and, from this
-- addon's ADDON_LOADED, to ChatProbeDB.log (bound with UseLog).
--------------------------------------------------------------------------------

local Probe = ForeverProbe:Module("ChatProbe", { api = 1, cmd = "chat" })

local function say(msg) Probe:Say(msg) end

-- A value as text, never operating on a secret one (strings unquoted, as the
-- log always had them).
local function show(v) return Probe.Show(v, true) end

-- A string by type and length only (never its content).
local shape = Probe.Shape

local function try(label, fn, ...) return Probe:Try(label, fn, ...) end

-- A chat test stimulus: a line this probe writes to chat ON PURPOSE.
local function stimulus(msg) print("|cff7fd4ffChatProbe|r " .. msg) end

-- The one shared fact (ForeverProbe docs/GUIDE.md "Facts"): whether names
-- carry surnames here. The setting is the region's and an account is in one
-- region, so it holds for every character on the account: no inputs.
ForeverProbe:DefineFact("client.RegionalUniqueNamesEnabled", { owner = "ChatProbe", rev = 1, inputs = {},
    run = function() return RegionalUniqueNamesEnabled() end })

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

local present = Probe.Present

local function state()
    say("client " .. table.concat({ GetBuildInfo() }, " ", 1, 2) .. ", " .. where())
    Probe:Fact("client.RegionalUniqueNamesEnabled")
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
    stimulus("4 click this: |cff40c0ff|Haddon:chatprobe:hello|h[ChatProbe link]|h|r"
        .. " (left, right and shift-click; expect a line for each in /fp, no error, no tooltip)")
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

-- ADDON_ACTION_BLOCKED / FORBIDDEN are ForeverProbe's: its baseline logs them.
watcher:SetScript("OnEvent", function(_, event, text, sender, _, _, _, _, _, _, _, _, lineID, guid)
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
local function register(frame, event) Probe:RegisterEvents(frame, { event }) end

-- The filters can't be removed once added, so they count only while watching,
-- the same window the event counts cover.
local function messageFilter()
    if P.watching then P.filterCalls = P.filterCalls + 1 end
    return false
end
-- Called as (event, decoratedPlayerName, ...) (ChatFrameFilters.lua:36):
-- the NAME is the second argument, and must come back unchanged.
local function nameFilter(_, name)
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
        .. (P.watching and ". Chat in say/party/guild, out of combat, in combat and in a dungeon; then /fp chat report." or ""))
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
        say("7 tracing addon output: use your addons (run ASProbe etc.), then /fp chat sources again for the counts")
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
    stimulus("8 this line should be in the 'Probe' tab, not in General. Watch /fp for a blocked-action line;"
        .. " /fp chat route again to stop.")
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
        .. " of them and Probe has them all, then /fp chat move again for the counts.")
end

--------------------------------------------------------------------------------
-- 10. Line identity (Spam & Ignore S0)
--------------------------------------------------------------------------------

-- Every event the plugin would filter. A filter runs once per chat frame
-- that shows the line, so the same lineID arriving N times is expected; a
-- lineID arriving with DIFFERENT text (a collision) is what must never happen.
local IDENTITY_EVENTS = { "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE",
    "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_DND", "CHAT_MSG_AFK",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }

-- The trace lives in ChatProbeDB.ids (SavedVariables), so a /reload between
-- starting and reporting never loses it: it keeps counting after a reload
-- (measured: the first in-game run was lost that way). The per-line
-- fingerprints stay session-only (they'd grow the file); a collision check
-- therefore spans one session at a time.
P.ids = { on = false, stats = {}, seen = {}, collisions = 0, shapes = {} }
local function savedIds()
    if type(ChatProbeDB) ~= "table" then return nil end
    if type(ChatProbeDB.ids) ~= "table" then
        ChatProbeDB.ids = { on = false, stats = {}, collisions = 0, shapes = {} }
    end
    return ChatProbeDB.ids
end

-- A short, content-free fingerprint of a line: its length and a checksum.
-- Enough to tell "same line" from "different line"; never logged.
local function fingerprint(text)
    if type(text) ~= "string" then return "?" end
    local sum = 0
    for i = 1, #text do sum = (sum * 31 + text:byte(i)) % 1000003 end
    return #text .. ":" .. sum
end

-- The sender's SHAPE, never the name: words, a realm dash, a space.
local function senderShape(sender)
    if issecretvalue and issecretvalue(sender) then return "<secret>" end
    if type(sender) ~= "string" then return type(sender) end
    local words = select(2, sender:gsub("%S+", ""))
    return string.format("words=%d dash=%s", words, tostring(sender:find("-", 1, true) ~= nil))
end

local function identityFilter(_, event, text, sender, ...)
    local I = P.ids
    if not I.on then return false end
    local S = savedIds()
    local lineID, guid = select(9, ...)   -- arg11, arg12 (text, sender are arg1, arg2)
    local st = S.stats[event] or { lines = 0, calls = 0, badID = 0, badGUID = 0, secret = 0 }
    S.stats[event] = st
    st.calls = st.calls + 1
    if (issecretvalue and (issecretvalue(lineID) or issecretvalue(guid) or issecretvalue(text))) then
        st.secret = st.secret + 1
        return false
    end
    if type(lineID) ~= "number" or lineID <= 0 then st.badID = st.badID + 1; return false end
    if type(guid) ~= "string" or guid:sub(1, 7) ~= "Player-" then st.badGUID = st.badGUID + 1 end
    local key = event .. "#" .. lineID
    local fp = fingerprint(text)
    local prev = I.seen[key]
    if prev == nil then
        st.lines = st.lines + 1
        I.seen[key] = fp
        S.shapes[event .. " " .. senderShape(sender)] = true
    elseif prev ~= fp then
        S.collisions = S.collisions + 1
    end
    return false
end

local identityAdded = false
local function addIdentityFilters()
    if identityAdded or not (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) then return end
    for _, e in ipairs(IDENTITY_EVENTS) do
        try("filter " .. e, ChatFrameUtil.AddMessageEventFilter, e, identityFilter)
    end
    identityAdded = true
end

local function identityReport(S)
    for event, st in pairs(S.stats) do
        say(string.format("10 %s: %d lines, %d filter calls (%.1f per line), badID=%d badGUID=%d secret=%d",
            event, st.lines, st.calls, st.lines > 0 and st.calls / st.lines or 0, st.badID, st.badGUID, st.secret))
    end
    say("10 lineID collisions (same id, different text) = " .. S.collisions)
    for shape in pairs(S.shapes) do say("11 sender shape: " .. shape) end
end

local function identity()
    local S = savedIds()
    if not S then return end
    if not S.on then
        addIdentityFilters()
        S.on, S.stats, S.collisions, S.shapes = true, {}, 0, {}
        P.ids.on, P.ids.seen = true, {}
        say("10 tracing line identity: chat in as many channels as you can (say, trade, guild, party,"
            .. " a whisper, /e, an emote like /wave, /afk), with chat shown in two tabs, then /fp chat lines again"
            .. " (a /reload in between is fine)")
        return
    end
    S.on, P.ids.on = false, false
    identityReport(S)
    say("10 tracing off.")
end

-- After a reload: a trace that was on keeps going.
local function resumeIdentity()
    local S = savedIds()
    if S and S.on then
        addIdentityFilters()
        P.ids.on, P.ids.seen = true, {}
        say("10 line-identity trace resumed after the reload (/fp chat lines to report)")
    end
end

--------------------------------------------------------------------------------
-- 11. Server ignore with surnames (uses YOUR TARGET; cleans up after itself)
--------------------------------------------------------------------------------

local function ignoreNames()
    local out = {}
    local ok, n = pcall(C_FriendList.GetNumIgnores)
    if not ok or type(n) ~= "number" then return out, nil end
    for i = 1, n do
        local okN, name = pcall(C_FriendList.GetIgnoreName, i)
        out[#out + 1] = okN and show(name) or "error"
    end
    return out, n
end

P.ignoreTest = nil
local function ignoreTest()
    -- One test at a time: a second one before the list update would leave
    -- the first target ignored (Codex, #16).
    if P.ignoreTest then
        say("11 an ignore test is still waiting for the list update; try again in a moment")
        return
    end
    if not UnitIsPlayer("target") or UnitIsUnit("target", "player") then
        say("11 target another player first (an alt or a friend who agrees: they're ignored for a moment, then removed)")
        return
    end
    local first, surname = UnitName("target")
    local full = GetUnitName("target", true)
    local guid = UnitGUID("target")
    local names = { show(first), show(surname), show(full) }
    say("11 target: UnitName = " .. names[1] .. " / " .. names[2] .. ", GetUnitName(target, true) = " .. names[3]
        .. ", RegionalUniqueNamesEnabled = " .. show(RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled()))
    local _, before = ignoreNames()
    say("11 ignores before: " .. show(before))
    -- The form Blizzard's unit menu uses (GetFullPlayerName with regional
    -- unique names): "First Surname".
    local candidate = full
    if type(first) == "string" and type(surname) == "string" and surname ~= "" and not (type(full) == "string" and full:find(" ", 1, true)) then
        candidate = first .. " " .. surname
    end
    -- Never touch an ignore the player already has: only an entry this test
    -- added is removed again (Codex, #16).
    local already = false
    if guid and C_FriendList.IsIgnoredByGuid then
        local okG, byGuid = pcall(C_FriendList.IsIgnoredByGuid, guid)
        already = okG and byGuid == true
    end
    if not already then
        for _, name in ipairs((ignoreNames())) do
            if name == candidate then already = true end
        end
    end
    if already then
        say("11 your target is already on your ignore list; the test leaves it alone (pick someone else)")
        return
    end
    local ok, added = try("AddIgnore", C_FriendList.AddIgnore, candidate)
    say("11 AddIgnore(" .. show(candidate) .. ") ok=" .. tostring(ok) .. " returned=" .. show(added))
    if ok and added == true then
        P.ignoreTest = { name = candidate, guid = guid }
        say("11 waiting for IGNORELIST_UPDATE (it reads the list back, then removes the entry)")
    else
        say("11 not added, so nothing to clean up")
    end
end

local function ignoreReadBack()
    local t = P.ignoreTest
    if not t then return end
    -- Only whether the TARGET's exact entry is there: no other name from the
    -- list is ever logged, not even a similar one (Codex, #16).
    local names, n = ignoreNames()
    local exact = false
    for _, name in ipairs(names) do
        if name == t.name then exact = true end
    end
    say("11 ignores now: " .. show(n) .. "; exact entry " .. show(t.name) .. " present = " .. tostring(exact))
    local okG, byGuid = false, nil
    if t.guid and C_FriendList.IsIgnoredByGuid then okG, byGuid = pcall(C_FriendList.IsIgnoredByGuid, t.guid) end
    say("11 IsIgnoredByGuid(target) = " .. (okG and show(byGuid) or "error"))
    local okD, removed = try("DelIgnore", C_FriendList.DelIgnore, t.name)
    say("11 DelIgnore(" .. show(t.name) .. ") ok=" .. tostring(okD) .. " returned=" .. show(removed) .. " (cleaned up)")
    P.ignoreTest = nil
end

--------------------------------------------------------------------------------
-- 12. What the server ignore blocks (needs an alt on another account)
--------------------------------------------------------------------------------

local blockWatch = CreateFrame("Frame")
P.blocks = {}
blockWatch:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "IGNORELIST_UPDATE" then
        local _, n = ignoreNames()
        say(string.format("12 IGNORELIST_UPDATE at %.1f s, %s ignores", GetTime(), show(n)))
        if P.ignoreTest then ignoreReadBack() end
        return
    end
    P.blocks[event] = (P.blocks[event] or 0) + 1
    -- CHAT_MSG_IGNORED is (text, playerName, ...); invites and duels put the
    -- name first (70205 dump :6946, :7713, :7180). Codex, #16. A plain branch
    -- on the event name, never `x and a2 or a1`: that truth-tests a2, which
    -- can be secret in chat lockdown (ChatInfoDocumentation.lua:1733), before
    -- senderShape's guard could see it.
    local sender = a1
    if event == "CHAT_MSG_IGNORED" then sender = a2 end
    say("12 " .. event .. " (from " .. senderShape(sender) .. ")")
end)
for _, e in ipairs({ "IGNORELIST_UPDATE", "CHAT_MSG_IGNORED", "PARTY_INVITE_REQUEST", "DUEL_REQUESTED" }) do
    register(blockWatch, e)
end

-- The list's readiness through login (12): how many ignores each step sees.
local function countAt(label)
    local _, n = ignoreNames()
    say(string.format("12 ignores at %s: %s", label, show(n)))
end

--------------------------------------------------------------------------------
-- 13. Atlases for the chat-menu bubble and the friends button (GlassChat #7)
--------------------------------------------------------------------------------

-- The voice buttons' gold symbols are frameless atlases named
-- chatframe-button-icon-<x> (FrameXML uses voicechat, headset, mic-on/off,
-- speaker-on/off, TTS). The chat-menu bubble and the friends button have
-- their frame baked in; a frameless symbol for each would let GlassChat put
-- them on a glass pill like the others. FrameXML names none, so the client
-- is asked which of these exist; each one found is shown, numbered, in a row
-- on screen to choose from by eye. Logged with its size and file.
P.ATLAS_CANDIDATES = {
    -- chat menu (a speech bubble)
    "chatframe-button-icon-chat", "chatframe-button-icon-bubble", "chatframe-button-icon-menu",
    "chatframe-button-icon-speech", "chatframe-button-icon-chatbubble", "chatframe-button-icon-text",
    "chatframe-button-icon-emote", "chatframe-button-icon-language", "chat-bubble", "chatbubble",
    "communities-icon-chat", "groupfinder-icon-chat", "socialqueuing-icon-chat",
    -- friends / social
    "chatframe-button-icon-friends", "chatframe-button-icon-social", "chatframe-button-icon-friend",
    "socialqueuing-icon-group", "groupfinder-icon-friend", "friends-icon-friendsInGroup",
    "friends-icon-addFriend", "housefinder_bnet-friend-icon-circle", "quickjoin-button-friendslist-up",
    "communities-icon-addgroupplus",
    -- known good, for comparison
    "chatframe-button-icon-voicechat", "chatframe-button-icon-TTS",
}

local atlasRow
local function atlases()
    if atlasRow and atlasRow:IsShown() then atlasRow:Hide(); say("13 atlas row hidden"); return end
    local get = C_Texture and C_Texture.GetAtlasInfo
    if not get then say("13 C_Texture.GetAtlasInfo absent"); return end
    atlasRow = atlasRow or CreateFrame("Frame", nil, UIParent)
    atlasRow:SetFrameStrata("DIALOG")
    atlasRow:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    atlasRow:SetSize(10, 64)
    atlasRow.items = atlasRow.items or {}
    for _, t in ipairs(atlasRow.items) do t.tex:Hide(); t.num:Hide() end
    local found, x = 0, 0
    for i, name in ipairs(P.ATLAS_CANDIDATES) do
        local ok, info = pcall(get, name)
        if ok and type(info) == "table" then
            found = found + 1
            say(string.format("13 #%d FOUND %s  %dx%d  file %s", found, name, info.width or 0, info.height or 0,
                tostring(info.file or info.filename)))
            local item = atlasRow.items[found]
            if not item then
                item = { tex = atlasRow:CreateTexture(nil, "ARTWORK"), num = atlasRow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge") }
                atlasRow.items[found] = item
            end
            item.tex:SetAtlas(name)
            item.tex:SetSize(32, 32)
            item.tex:SetPoint("LEFT", atlasRow, "LEFT", x, 8)
            item.tex:SetVertexColor(1, 0.82, 0)   -- gold, as GlassChat would draw it
            item.tex:Show()
            item.num:SetText(found)
            item.num:SetPoint("TOP", item.tex, "BOTTOM", 0, -2)
            item.num:Show()
            x = x + 44
        else
            say("13 missing " .. name)
        end
    end
    atlasRow:SetWidth(math.max(10, x))
    atlasRow:Show()
    say("13 " .. found .. " of " .. #P.ATLAS_CANDIDATES .. " exist; they're shown numbered, in gold, above the middle of the screen. "
        .. "Tell Claude which number fits the chat menu and which the friends button. /fp chat atlases again hides the row.")
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

for _, c in ipairs({
    { "state", state, "1 stock chat settings and APIs" },
    { "clip", clip, "2 copy a test string to the clipboard" },
    { "copyable", copyable, "3 toggle drag-select copy on the main chat" },
    { "link", link, "4 print a clickable addon link (a chat stimulus)" },
    { "watch", watch, "5 toggle logging chat payload secrecy (then report)" },
    { "report", report, "5 the payload counts" },
    { "history", history, "6 read the scrollback of every chat frame" },
    { "sources", sources, "7 toggle tracing which addons print to chat, and how" },
    { "route", route, "8 toggle sending ChatProbe's chat stimuli to a new 'Probe' tab" },
    { "move", move, "9 [addon] toggle moving an addon's direct AddMessage lines (default AltStableProbe) to 'Probe'" },
    { "lines", identity, "10/11 toggle tracing line identity and sender shapes" },
    { "ignoretest", ignoreTest, "11 server ignore on your TARGET (added, read back, removed)" },
    { "atlases", atlases, "13 which chat-menu / friends symbols exist (shown on screen, numbered)" },
}) do
    local fn = c[2]
    Probe:Command(c[1], function(arg) fn(arg) end, c[3])
end
-- Empties ChatProbeDB.log IN PLACE: the host holds that same table.
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")

local boot = CreateFrame("Frame")
register(boot, "ADDON_LOADED")
register(boot, "PLAYER_LOGIN")
register(boot, "PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then countAt("PLAYER_LOGIN"); return end
    if event == "PLAYER_ENTERING_WORLD" then
        countAt("PLAYER_ENTERING_WORLD")
        C_Timer.After(5, function() countAt("PLAYER_ENTERING_WORLD +5 s") end)
        return
    end
    if name ~= ADDON then return end
    -- ForeverProbe is a dependency, so it is ready by now; Ready() logs it if
    -- not (the load order the pilot checks in game).
    Probe:Ready()
    if type(ChatProbeDB) ~= "table" then ChatProbeDB = {} end
    if type(ChatProbeDB.log) ~= "table" then ChatProbeDB.log = {} end
    Probe:UseLog(ChatProbeDB.log, MAX_LOG)
    ChatProbeDB.loads = (ChatProbeDB.loads or 0) + 1
    say("loaded (" .. ChatProbeDB.loads .. " loads). /fp chat for the commands")
    countAt("ADDON_LOADED")
    resumeIdentity()
end)

-- The test seam lives on the addon namespace, not in _G.
NS._test = { Probe = Probe, identity = identity, identityFilter = identityFilter, ignoreTest = ignoreTest,
    ignoreReadBack = ignoreReadBack, blockWatch = blockWatch, P = P, state = state, clip = clip, copyable = copyable, link = link, watch = watch,
    report = report, history = history, watcher = watcher, sources = sources, route = route,
    sourceOf = sourceOf, printHandler = printHandler, move = move }
