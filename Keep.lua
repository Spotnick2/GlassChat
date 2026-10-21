-- Keep.lua (#125): the chat kept across sessions and reloads, player chat
-- only (owner: "and I don't mean the addon spam"). Off by default.
--
-- Prat's Scrollback copies the frame's private historyBuffer and pushes into
-- it; here only public calls:
-- - saved at PLAYER_LOGOUT, which fires on /reload and on logout before
--   SavedVariables are written: each window's lines through Copy.Entry;
-- - put back at the next PLAYER_LOGIN with BackFillMessage, which adds at
--   the oldest end (ScrollingMessageFrame.lua:20), so the history sits above
--   whatever printed at login, under a grey divider. It never goes through
--   AddMessage, so the shared hook never sees it: no second stamp, no
--   routing, no line count.
--
-- Only lines Blizzard printed for a player-chat event (Focus.KindOf: say,
-- party, guild, whispers, channels...): never addon output, system lines or
-- the combat log. Each line passes its event back, so focus mode still sorts
-- it, and its saved time as the 11th value (Copy.Read's kept), so it keeps
-- its age across several sessions. Saved per character
-- (GlassChatCharDB.kept), never in GlassChat.lua, which holds focus mode's
-- export and is meant to be shared.

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local Keep = {}
GC.Keep = Keep

Keep.MAX = 200             -- lines kept per window
Keep.MAX_AGE = 24 * 3600   -- s: an older line is dropped
Keep.GREY = { 0.5, 0.5, 0.5 }

local function plainNumber(v)
    if API.IsSecret(v) or type(v) ~= "number" or v ~= v then return nil end
    return v
end

local function plainString(v)
    if API.IsSecret(v) or type(v) ~= "string" then return nil end
    return v
end

-- A window's name, to tell it's still the same window at the restore.
local function windowName(i)
    local ok, name = pcall(GetChatWindowInfo, i)
    return ok and plainString(name) or nil
end

-- The numbered windows, never the combat log. Temporary whisper windows
-- (11 and up) aren't brought back by Blizzard, so they're never kept.
local function windows()
    local out, log = {}, rawget(_G, "COMBATLOG")
    for i = 1, GC.Chat.MaxWindows() do
        local f = rawget(_G, "ChatFrame" .. i)
        if f and f ~= log then out[i] = f end
    end
    return out
end

local function wanted(event, id)
    if not plainString(event) then return false end
    local kind = GC.Focus.KindOf(event, id)
    return kind ~= "System" and kind ~= "Addons"
end

--------------------------------------------------------------------------------
-- Battle.net names
--------------------------------------------------------------------------------

-- A Battle.net name is a |K token, valid for one session only. At the save,
-- each BNplayer link (LinkUtil.lua:163: name, bnetIDAccount, lineID,
-- chatType, chatTarget) becomes "\2<chatType>\3<BattleTag>\2": the
-- BattleTag is a plain string. At the restore, the friend is found by it and
-- the link rebuilt with this session's name and id (Prat's updateBnet), else
-- the BattleTag's name, never the stale token. Any other token becomes "?".
local function battleTag(id)
    local bn = rawget(_G, "C_BattleNet")
    id = tonumber(id)
    if not (id and bn and bn.GetAccountInfoByID) then return nil end
    local ok, info = pcall(bn.GetAccountInfoByID, id)
    if not ok or type(info) ~= "table" then return nil end
    local tag = plainString(info.battleTag)
    if not tag or tag == "" or tag:find("[%c|]") then return nil end
    return tag
end

local function saveText(raw)
    local s = raw:gsub("|HBNplayer:(.-)|h.-|h", function(data)
        local id, chatType = data:match("^[^:]*:([^:]*):[^:]*:([^:]*)")
        local tag = battleTag(id)
        if not tag or not chatType or chatType:find("[%c|]") then return "[?]" end
        return "\2" .. chatType .. "\3" .. tag .. "\2"
    end)
    return (s:gsub("|K.-|k", "?"))
end

-- This session's friends by BattleTag. Battle.net may not have filled in yet:
-- then the names stay plain.
local function friends()
    local out, bn = {}, rawget(_G, "C_BattleNet")
    if not (bn and bn.GetFriendAccountInfo and rawget(_G, "BNGetNumFriends")) then return out end
    local ok, n = pcall(BNGetNumFriends)
    n = ok and plainNumber(n) or 0
    for i = 1, n do
        local okI, info = pcall(bn.GetFriendAccountInfo, i)
        if okI and type(info) == "table" then
            local tag, name, id = plainString(info.battleTag), plainString(info.accountName), plainNumber(info.bnetAccountID)
            if tag and name and id then out[tag] = { name = name, id = id } end
        end
    end
    return out
end

local function restoreText(s, known)
    return (s:gsub("\2([^\3]*)\3([^\2]*)\2", function(chatType, tag)
        local f = known[tag]
        local link = rawget(_G, "GetBNPlayerLink")
        if f and link then return link(f.name, "[" .. f.name .. "]", f.id, 0, chatType, f.name) end
        return "[" .. (tag:match("^[^#]+") or tag) .. "]"
    end))
end

--------------------------------------------------------------------------------
-- Saving and restoring
--------------------------------------------------------------------------------

local function colour(v)
    v = plainNumber(v)
    if not v or v < 0 or v > 1 then return 1 end
    return v
end

-- Newest first, over the whole window, until Keep.MAX lines are found:
-- Copy.Read's Copy.MAX would miss older chat under a run of addon lines,
-- with /gchat lines up to 5000 (Codex on #126). Returned oldest first.
local function saveWindow(f, now)
    local found = {}
    for i = GC.Copy.Count(f), 1, -1 do
        if #found >= Keep.MAX then break end
        local e = GC.Copy.Entry(f, i, "keep read")
        if e and not e.hidden and plainString(e.raw) and wanted(e.event, e.id) then
            local t = plainNumber(e.kept) or now
            if now - t <= Keep.MAX_AGE then
                found[#found + 1] = { text = saveText(e.raw), r = colour(e.r), g = colour(e.g), b = colour(e.b),
                    id = plainNumber(e.id), event = e.event, t = t }
            end
        end
    end
    local lines = {}
    for k = #found, 1, -1 do lines[#lines + 1] = found[k] end
    return lines
end

-- Off: nothing is kept, and what was saved goes.
function Keep.Save()
    local c = GC.charDB
    if not c then return end
    if not GC.db.keep then c.kept = nil; return end
    local now, saved = time(), {}
    for i, f in pairs(windows()) do
        local name = windowName(i)
        local ok, lines = pcall(saveWindow, f, now)
        if not ok then
            API.Fail("keep save " .. i, lines)
        elseif name and #lines > 0 then
            saved[i] = { name = name, lines = lines }
        end
    end
    c.kept = next(saved) and { saved = now, windows = saved } or nil
end

local function ago(s)
    if s < 60 then return "moments ago" end
    if s < 3600 then return math.floor(s / 60) .. " min ago" end
    return math.floor(s / 3600) .. " h ago"
end

-- A saved line, checked: the file can be edited by hand.
local function valid(l, now)
    return type(l) == "table" and type(l.text) == "string" and type(l.t) == "number" and now - l.t <= Keep.MAX_AGE
        and (l.id == nil or type(l.id) == "number") and wanted(l.event, l.id)
end

local function restoreWindow(f, lines, now, saved, known)
    local keep = {}
    for _, l in ipairs(lines) do
        if valid(l, now) then keep[#keep + 1] = l end
    end
    if #keep == 0 then return end
    -- Each backfilled line goes above the ones before it: the divider first,
    -- right above this session's lines, then the history newest first.
    f:BackFillMessage("--- previous session, " .. ago(math.max(0, now - saved)) .. " ---", unpack(Keep.GREY))
    for k = #keep, 1, -1 do
        local l = keep[k]
        f:BackFillMessage(restoreText(l.text, known), colour(l.r), colour(l.g), colour(l.b), l.id, nil, nil,
            l.event, nil, nil, l.t)
    end
    f:ResetAllFadeTimes()   -- shown like new lines, and the window awake (Skin's idle)
end

-- Once a session. A window renamed or gone since is skipped.
local restored = false
function Keep.Restore()
    if restored then return end
    restored = true
    local kept = GC.charDB and GC.charDB.kept
    if not GC.db.keep or type(kept) ~= "table" or type(kept.windows) ~= "table" then return end
    local now = time()
    local saved = type(kept.saved) == "number" and kept.saved or now
    local known = friends()
    local frames = windows()
    for i, w in pairs(kept.windows) do
        local f = frames[i]
        if f and type(w) == "table" and type(w.lines) == "table" and w.name == windowName(i) then
            local ok, err = pcall(restoreWindow, f, w.lines, now, saved, known)
            if not ok then API.Fail("keep restore " .. i, err) end
        end
    end
end

function Keep.Start()
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then Keep.Restore() else Keep.Save() end
    end)
    API.RegisterEvents(f, { "PLAYER_LOGIN", "PLAYER_LOGOUT" })
end

Keep._test = { saveText = saveText, restoreText = restoreText, reset = function() restored = false end }
