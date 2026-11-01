-- Audit.lua (ChatProbe, #132 PR 4): the release audit's in-game checks as
-- one procedure, /fp steps chat audit (docs/FOREVER-PROBE.md, "Release audit").
-- Loads after ChatProbe.lua, whose helpers it takes from the namespace.
--
-- What it measures (the numbers are section 15's items):
--   15.9  Blizzard's buffer at exactly its maximum: does the next line land
--         where an index reaches it? On the probe's own hidden frame, so no
--         chat is touched (GlassChat avoids the state, #132 F3b).
--   15.1  what GlassChat's AddMessage hook costs per line: plain, stamped,
--         one buffer walk, the combat log's walk, and debugstack (F1, F8).
--   15.3  the side buttons in Blizzard's alert stack while a toast shows (F8).
--   15.5  GetGuildRosterInfo's return order (Levels.lua): types only.
--   15.10 history browsing in combat: lockdown, the draft's destination.
--   15.2  chat payload secrecy inside an instance (the watcher's shapes).
--   15.4, 15.6  after a logout: Keep's Battle.net link, the friend list at
--         login, and a probe tab caught again by its name.
--   15.7  settings and layout from another account, applied (optional).
--   15.8  GlassChat's failures and blocked actions over the session.
-- It never logs what anyone said: counts, types, times and its own lines only.
-- The owner's settings it changes are saved first and put back at the end
-- (/fp chat auditrestore after a stopped run).

local _, NS = ...
local S = NS.shared
local Probe, say, show = S.Probe, S.say, S.show

local function glassChat() return S.glassChat() end
local function need()
    local G = glassChat()
    if not G then error("GlassChat isn't loaded", 0) end
    return G
end

local function store()
    if type(ChatProbeDB.audit) ~= "table" then ChatProbeDB.audit = {} end
    return ChatProbeDB.audit
end

--------------------------------------------------------------------------------
-- The owner's values: kept once, put back at the end
--------------------------------------------------------------------------------

local function keepOwn()
    local G, a = glassChat(), store()
    if not G or type(a.saved) == "table" then return end
    a.saved = { lines = rawget(G.db, "lines"), timestamps = rawget(G.db, "timestamps"), keep = rawget(G.db, "keep"),
        icon = G.Spam and G.Spam.db and G.Spam.db.icon, failures = #S.failureKeys() }
end

local function restoreOwn()
    local G, a = glassChat(), store()
    local s = a.saved
    if not (G and type(s) == "table") then say("15 nothing to put back"); return false end
    G.Settings.SetLines(s.lines or G.DEFAULTS.lines)
    G.db.lines = s.lines
    G.Settings.SetTimestamps(s.timestamps or false)
    G.db.timestamps = s.timestamps
    if (s.keep or false) ~= (G.db.keep or false) then G.Settings.SetKeep(s.keep or false) end
    G.db.keep = s.keep
    if s.icon ~= nil and G.SpamUI and G.SpamUI.Set then G.SpamUI.Set.icon(s.icon) end
    a.saved = nil
    say("15 your values are back (a window grown to more lines keeps that size until your next login)")
    return true
end

-- GlassChat's failures beyond those there at the start, and its blocked or
-- forbidden actions (#132 F2's keys).
local function failureLine()
    local G = glassChat()
    local keys, counts = S.failureKeys(), G and G.failureCounts or {}
    local out, blocked = {}, 0
    for _, k in ipairs(keys) do
        if k:find("^blocked ") or k:find("^forbidden ") then blocked = blocked + 1 end
        out[#out + 1] = k .. " x" .. tostring(counts[k] or 1)
    end
    return keys, blocked, table.concat(out, ", ")
end

local function noBlocked()
    local keys, blocked, line = failureLine()
    return blocked == 0, #keys .. " failures, " .. blocked .. " blocked: " .. line
end

--------------------------------------------------------------------------------
-- 15.9 Blizzard's buffer at exactly its maximum
--------------------------------------------------------------------------------

-- A hidden message frame of the probe's own: the same buffer as a chat
-- window (ScrollingMessageFrameMixin, CircularBuffer), no GlassChat hook.
-- Filled past 150, put in the state under test, then five new lines: are
-- they the five newest, and is the count the maximum?
local function bufferCase(label, into)
    local f = CreateFrame("ScrollingMessageFrame", nil, UIParent)
    f:Hide()
    f:SetMaxLines(150)
    for i = 1, 200 do f:AddMessage("old " .. i) end
    into(f)
    for i = 1, 5 do f:AddMessage("new " .. i) end
    local n, max = f:GetNumMessages(), f:GetMaxLines()
    local newest, inPlace = {}, true
    for k = 0, 4 do
        local text = f:GetMessageInfo(n - k)
        newest[#newest + 1] = show(text)
        if text ~= "new " .. (5 - k) then inPlace = false end
    end
    say(string.format("15.9 %s: %s lines (max %s), newest five %s: %s", label, show(n), show(max),
        inPlace and "in place" or "NOT in place", table.concat(newest, ", ")))
    return { n = n, max = max, inPlace = inPlace }
end

local function buffer()
    local a = store()
    a.buffer = {
        control = bufferCase("control, nothing done", function() end),
        shrunk = bufferCase("shrunk to 128 while full", function(f) f:SetMaxLines(128) end),
        noop = bufferCase("a removal that removes nothing, while full", function(f)
            f:RemoveMessagesByPredicate(function() return false end)
        end),
    }
    local b = a.buffer
    return string.format("control %s/%s %s; shrunk %s/%s %s; no-op removal %s/%s %s", show(b.control.n), show(b.control.max),
        tostring(b.control.inPlace), show(b.shrunk.n), show(b.shrunk.max), tostring(b.shrunk.inPlace), show(b.noop.n),
        show(b.noop.max), tostring(b.noop.inPlace))
end

--------------------------------------------------------------------------------
-- 15.1 The hook's cost per line
--------------------------------------------------------------------------------

local function timeLines(f, n, label)
    local t0 = debugprofilestop()
    for i = 1, n do f:AddMessage("|cff7fd4ffChatProbe|r audit timing, " .. label .. " " .. i) end
    return (debugprofilestop() - t0) / n
end

local function timeWalks(f, n)
    local t0 = debugprofilestop()
    for _ = 1, n do f:TransformMessages(function() return false end, function(...) return ... end) end
    return (debugprofilestop() - t0) / n
end

-- General filled to its maximum with plain lines, then 200 plain and 200
-- stamped lines timed. GlassChat's routing is off for the run (Chat.Route),
-- so the cost measured is the rewrite's, never a move to the probe's tab.
-- Writes up to Chat.MAX_LINES + 400 lines of the probe's own to General.
local function hotPath(label)
    local G = need()
    local f, log = rawget(_G, "ChatFrame1"), rawget(_G, "COMBATLOG")
    local route, wasStamps = G.Chat.Route, G.db.timestamps
    G.Chat.Route = nil
    local ok, r = pcall(function()
        G.Settings.SetTimestamps(false)
        local max, n0 = f:GetMaxLines(), f:GetNumMessages()
        local fill = math.min(math.max(0, max - n0), G.Chat.MAX_LINES)
        for i = 1, fill do f:AddMessage("|cff7fd4ffChatProbe|r audit fill " .. i) end
        local out = { max = max, n = f:GetNumMessages(), filled = fill }
        out.plain = timeLines(f, 200, "plain")
        G.Settings.SetTimestamps(true)
        out.stamped = timeLines(f, 200, "stamped")
        out.walk = timeWalks(f, 20)
        if log then out.logN, out.logWalk = log:GetNumMessages(), timeWalks(log, 20) end
        local t0 = debugprofilestop()
        for _ = 1, 200 do G.Tabs.SourceOf() end
        out.source = (debugprofilestop() - t0) / 200
        return out
    end)
    G.Chat.Route = route
    G.Settings.SetTimestamps(wasStamps and true or false)
    if not ok then error(r, 0) end
    local a = store()
    a.hot = a.hot or {}
    a.hot[label] = r
    local line = string.format("15.1 %s: General %d of %d lines (%d filled): %.3f ms a plain line, %.3f ms a stamped one,"
        .. " %.3f ms one walk; combat log %s lines, %s ms one walk; debugstack attribution %.3f ms", label, r.n, r.max,
        r.filled, r.plain, r.stamped, r.walk, show(r.logN), r.logWalk and string.format("%.3f", r.logWalk) or "n/a", r.source)
    say(line)
    return line
end

--------------------------------------------------------------------------------
-- 15.5 GetGuildRosterInfo's order (Levels.lua reads the 4th and the 17th)
--------------------------------------------------------------------------------

local function roster()
    if not (IsInGuild and IsInGuild()) then return "not in a guild" end
    local p = Probe.Pack(Probe:Try("GetGuildRosterInfo", GetGuildRosterInfo, 1))
    if not p[1] then return "GetGuildRosterInfo failed" end
    local shapes = {}
    for i = 2, p.n do shapes[#shapes + 1] = (i - 1) .. "=" .. Probe.Shape(p[i]) end
    local level, guid = p[5], p[18]
    local levelOk = not (issecretvalue and issecretvalue(level)) and type(level) == "number" and level >= 1 and level <= 200
    local guidOk = not (issecretvalue and issecretvalue(guid)) and type(guid) == "string" and guid:find("^Player%-") ~= nil
    local line = string.format("15.5 %d returns; 4th a level: %s; 17th a player GUID: %s; shapes %s", p.n - 1,
        tostring(levelOk), tostring(guidOk), table.concat(shapes, " "))
    say(line)
    return levelOk and guidOk, line
end

--------------------------------------------------------------------------------
-- 15.10 History browsing in combat
--------------------------------------------------------------------------------

local function editBox()
    local util = rawget(_G, "ChatFrameUtil")
    local ok, e = false, nil
    if util and util.GetActiveWindow then ok, e = pcall(util.GetActiveWindow) end
    return (ok and type(e) == "table" and e) or rawget(_G, "ChatFrame1EditBox")
end

local function destination()
    local e = editBox()
    if not e then return nil end
    local ok, v = pcall(e.GetAttribute, e, "chatType")
    return ok and show(v) or "?"
end

local fought = {}

local function combatWait(key, onPoll)
    return function()
        if InCombatLockdown() then
            fought[key] = true
            if onPoll then onPoll() end
            return false, "in combat"
        end
        if fought[key] then return true, "the fight is over" end
        return false, "waiting for a fight"
    end
end

local function noteLockdown()
    local a = store()
    a.history = a.history or { polls = 0, locked = 0, kinds = {} }
    local h = a.history
    h.polls = h.polls + 1
    local ok, v = pcall(C_ChatInfo.InChatMessagingLockdown)
    if ok and v == true then h.locked = h.locked + 1 end
    h.kinds[destination() or "none"] = true
end

--------------------------------------------------------------------------------
-- 15.4, 15.6 After a logout
--------------------------------------------------------------------------------

local TAB = "ChatProbe"

local function probeWindow()
    for i = 1, (S.maxWindows and S.maxWindows() or 10) do
        local ok, name, _, _, _, _, _, shown, _, docked = pcall(GetChatWindowInfo, i)
        if ok and name == TAB and (shown or docked) then return rawget(_G, "ChatFrame" .. i) end
    end
end

-- The stimulus goes straight to the main window, as most addons write (probe
-- item 7): GlassChat's hook routes it to the probe's tab, print or not.
local function landsInTab(text)
    local main = rawget(_G, "DEFAULT_CHAT_FRAME")
    if main then main:AddMessage("|cff7fd4ffChatProbe|r " .. text) end
    local f = probeWindow()
    if not f then return false, "no " .. TAB .. " window" end
    local n = f:GetNumMessages()
    local last = n > 0 and f:GetMessageInfo(n)
    local hit = type(last) == "string" and not (issecretvalue and issecretvalue(last)) and last:find(text, 1, true) ~= nil
    return hit, TAB .. " window " .. f:GetName() .. ", the line " .. (hit and "landed in it" or "did NOT land in it")
end

-- The friend list at login, for Keep's restore (it runs at PLAYER_LOGIN).
local function friendCount()
    local fn = rawget(_G, "BNGetNumFriends")
    if not fn then return "n/a" end
    local ok, n = pcall(fn)
    return ok and show(n) or "error"
end

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "PLAYER_LOGIN" })
boot:SetScript("OnEvent", function()
    if type(ChatProbeDB) ~= "table" then return end
    local a = store()
    a.friendsAtLogin = friendCount()
    say("15.4 Battle.net friends at PLAYER_LOGIN: " .. a.friendsAtLogin)
    C_Timer.After(5, function()
        a.friendsAt5 = friendCount()
        say("15.4 Battle.net friends 5 s after login: " .. a.friendsAt5)
    end)
end)

--------------------------------------------------------------------------------
-- 15.7 Settings from another account
--------------------------------------------------------------------------------

local function newestCopy()
    local G = glassChat()
    local best = 0
    for _, n in pairs(G and type(rawget(G.db, "settingsApplied")) == "table" and G.db.settingsApplied or {}) do
        if type(n) == "number" and n > best then best = n end
    end
    return best
end

--------------------------------------------------------------------------------
-- The procedure
--------------------------------------------------------------------------------

Probe:Steps("audit", {
    title = "GlassChat: the release audit's in-game checks (#132)",
    rev = 1,
    { text = "Reading GlassChat, and saving the settings this run changes, to put back at the end.", auto = true,
      run = function()
          fought = {}
          keepOwn()
          local G = need()
          return "lines " .. show(G.db.lines) .. ", stamps " .. show(G.db.timestamps) .. ", keep " .. show(G.db.keep)
      end },
    -- 15.9
    { text = "Blizzard's chat buffer at its maximum, on a hidden frame of the probe's own (no chat is touched).",
      button = "Measure", run = buffer,
      check = function()
          local b = store().buffer
          return b and b.control.inPlace and b.control.n == b.control.max, "the control keeps its newest lines"
      end },
    -- 15.1
    { text = "The cost of GlassChat's chat hook. This writes up to 1400 test lines to General (only you see them) and takes a few seconds.",
      button = "Time it", run = function() return hotPath("lines " .. tostring(need().db.lines)) end },
    { text = "The same with 5000 lines of scrollback (put back at the end). Writes up to 4400 more test lines.",
      button = "Time it", run = function()
          need().Settings.SetLines(5000)
          return hotPath("lines 5000")
      end },
    -- 15.3
    { text = "The ! and the spam icon as if lines were waiting.", button = "Light them",
      run = function()
          local G = need()
          S.spamIcon(true)
          return S.lightPills(2)
      end },
    { text = "Now make Blizzard show a toast above the chat buttons: a Battle.net friend logging in or out, or a voice-chat prompt. Then Next.",
      screenshot = "toast" },
    { text = "Did the toast sit above the ! and the spam icon (or they above it), with nothing overlapping, and did the stack close up again after?",
      ask = true, check = noBlocked },
    { text = "Clearing the ! and the spam icon.", auto = true,
      run = function()
          local G = need()
          if G.Alerts then G.Alerts.unseen = 0; G.Alerts.Lit() end
          if G.Spam and G.SpamUI then G.Spam.unseen = 0; G.SpamUI.PaintAll() end
          return "cleared"
      end },
    -- 15.5
    { text = "Your guild's roster (skip if you have no guild).", button = "Ask for it",
      run = function()
          if not (IsInGuild and IsInGuild()) then return "not in a guild" end
          C_GuildInfo.GuildRoster()
          return "asked"
      end },
    { text = "Waiting for the roster.", event = "GUILD_ROSTER_UPDATE", shapeOnly = true },
    { text = "Reading its first entry's shape (types only, never a name).", auto = true, run = roster },
    -- 15.10
    { text = "Open the chat box and type an unfinished whisper to a friend (/w Name hello), without sending it. This step ends by itself.",
      wait = function()
          local e = editBox()
          local kind = destination()
          if e and e:HasFocus() and kind == "WHISPER" then return true, "a whisper draft" end
          return false, "the box says " .. tostring(kind)
      end, timeout = 600 },
    { text = "Keep the box open and start a fight. In combat, press Up twice, then Down twice, back to your draft. The step ends when the fight does.",
      wait = combatWait("history", noteLockdown), timeout = 900,
      check = function()
          local h = store().history or { polls = 0, locked = 0, kinds = {} }
          local kinds = {}
          for k in pairs(h.kinds) do kinds[#kinds + 1] = k end
          table.sort(kinds)
          return true, string.format("%d polls in combat, lockdown on %d; destinations seen: %s", h.polls, h.locked,
              table.concat(kinds, " "))
      end },
    { text = "Is your draft back, still a whisper to the same friend (the box shows Tell Name:)?", ask = true },
    { text = "Send it. Did your friend get it as a whisper, not in say?", ask = true, check = noBlocked },
    { text = "In a fight again, press Up to bring back a slash command you sent before (or send /dance first, then bring it back) and send it. Then Next.",
      check = noBlocked },
    { text = "Did the command you brought back run?", ask = true },
    -- 15.2
    { text = "Watching chat payloads (types and lengths only).", auto = true,
      run = function()
          if not S.P.watching then S.watch() end
          return "watching"
      end },
    { text = "Go into a dungeon, say a line or two in party chat, then pull a pack. The step ends after a fight inside the instance.",
      wait = function()
          local _, kind = GetInstanceInfo()
          local inside = kind ~= nil and kind ~= "none"
          if InCombatLockdown() then
              if inside then
                  fought.dungeon = true
                  local fps = GetFramerate()
                  local a = store()
                  if type(fps) == "number" and (not a.fpsMin or fps < a.fpsMin) then a.fpsMin = fps end
              end
              return false, "in combat"
          end
          if fought.dungeon then return true, "a fight in the instance is over" end
          return false, inside and "inside: waiting for a fight" or "waiting for the instance"
      end, timeout = 3600 },
    { text = "The payload counts, by event, combat and lockdown.", auto = true,
      run = function()
          S.report()
          if S.P.watching then S.watch() end
          return "lowest fps in the fight: " .. show(store().fpsMin)
      end },
    -- 15.4, 15.6
    { text = "Kept chat on, and a tab of the probe's own.", button = "Set up",
      run = function()
          local G = need()
          if not G.db.keep then G.Settings.SetKeep(true) end
          G.Tabs.SetRule(TAB, "session")
          return landsInTab("audit: a line for my own tab")
      end,
      check = function() return probeWindow() ~= nil, "the " .. TAB .. " tab is open" end },
    { text = "Have a Battle.net friend whisper you (or whisper them and get a reply), so General shows a Battle.net line. Then Next." },
    { text = "Log out to the character screen and back in on this character (or exit the game and relaunch). The procedure goes on at login.",
      reload = "exit" },
    { text = "Welcome back. Checking the tab.", button = "Check",
      run = function()
          local a = store()
          local hit, why = landsInTab("audit: a line after the logout")
          return why .. "; friends at login " .. tostring(a.friendsAtLogin) .. ", 5 s later " .. tostring(a.friendsAt5)
      end,
      check = function() return probeWindow() ~= nil, "the " .. TAB .. " tab came back" end },
    { text = "Did the line the probe just wrote land in the ChatProbe tab (not in General)?", ask = true },
    { text = "In General, above the 'previous session' line, click your friend's Battle.net name. Does it open a whisper to them?",
      ask = true, screenshot = "kept Battle.net line" },
    -- 15.7
    { text = "Optional (Skip without a second account online): noting the last settings copy received.", auto = true,
      run = function() store().copyBase = newestCopy(); return "last copy " .. show(store().copyBase) end },
    { text = "On your other account, with GlassChat and Spam & Ignore, type /gchat layout save, then /gchat settings send layout. This step ends when the copy arrives here.",
      wait = function()
          if newestCopy() > (store().copyBase or 0) then return true, "a copy arrived" end
          return false, "waiting for the copy"
      end, timeout = 900 },
    { text = "Click [Apply it] in chat (the received layout), then Next. /gchat settings undo puts your own back later.",
      check = function()
          local G = need()
          local ok = type(G.db.layout) == "table" and G.charDB.layoutAnswered == G.db.layout.id
          local fine, detail = noBlocked()
          return ok and fine, (ok and "applied" or "not applied") .. "; " .. detail
      end, screenshot = "layout applied" },
    -- 15.8
    { text = "GlassChat's failures over the session (/gchat failures).", auto = true,
      run = function()
          local keys, blocked, line = failureLine()
          say("15.8 " .. #keys .. " failures, " .. blocked .. " blocked or forbidden: " .. line)
          return line
      end, check = noBlocked },
    { text = "Putting your own settings back.", auto = true, run = function() restoreOwn(); return "done" end,
      check = function() return type(store().saved) ~= "table", "put back" end },
    { text = "That's all. Press Reload now (or type /reload) so the results are saved.", reload = true },
})

Probe:Command("auditrestore", function() restoreOwn() end, "15 put back the settings a stopped audit run changed")

NS._test.audit = { buffer = buffer, hotPath = hotPath, roster = roster, restoreOwn = restoreOwn }
