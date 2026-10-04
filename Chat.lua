-- Chat.lua: the stock chat windows, extended, never replaced. It finds every
-- ChatFrameN (new and temporary tabs included), runs each module's per-window
-- setup on it, raises the scrollback, and keeps class-coloured names on.
--
-- Measured (docs/FOREVER-PROBE.md): every window holds 128 lines; class
-- colours come from the chatClassColorOverride CVar ("0" = always), not from
-- the per-type ChatTypeInfo flags, which all read false.

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local Chat = {}
GC.Chat = Chat

-- Constants.ChatFrameConstants.MaxChatWindows is the documented one;
-- NUM_CHAT_WINDOWS is its deprecated alias (Deprecated_ChatFrame.lua:18).
function Chat.MaxWindows()
    local c = Constants and Constants.ChatFrameConstants
    return (c and c.MaxChatWindows) or 10
end

-- The chat windows that exist. A tab the player never opened still has its
-- frame; the setup is cheap and idempotent, so all of them get it.
-- Temporary whisper windows are ChatFrame11 and up (FloatingChatFrame.lua:975,
-- MaxChatWindows + 1), so Blizzard's own list, CHAT_FRAMES (lines 93, 445),
-- is walked too; 1..MaxChatWindows covers a client without it.
function Chat.Frames()
    local out, seen = {}, {}
    local function add(f)
        if f and not seen[f] then seen[f] = true; out[#out + 1] = f end
    end
    for i = 1, Chat.MaxWindows() do
        add(rawget(_G, "ChatFrame" .. i))   -- rawget: absent windows read nil, never an error
    end
    local names = rawget(_G, "CHAT_FRAMES")
    if type(names) == "table" then
        for _, name in ipairs(names) do
            if type(name) == "string" then add(rawget(_G, name)) end
        end
    end
    return out
end

-- Whether a window is in the main dock, from Blizzard's accessor rather
-- than the frame's own fields.
function Chat.IsDocked(f)
    local dock = rawget(_G, "GENERAL_CHAT_DOCK")
    if not (dock and rawget(_G, "FCFDock_GetChatFrames")) then return false end
    for _, d in ipairs(FCFDock_GetChatFrames(dock) or {}) do
        if d == f then return true end
    end
    return false
end

-- Per-window setup functions, run on every window at each scan. Each one
-- must be idempotent; one failing never stops the others.
local perFrame = {}
function Chat.OnEachFrame(key, fn)
    perFrame[#perFrame + 1] = { key = key, fn = fn }
end

-- And setups that aren't per window (the dock, the buttons beside the
-- chat), run once after every scan.
local afterScan = {}
function Chat.AfterScan(key, fn)
    afterScan[#afterScan + 1] = { key = key, fn = fn }
end

-- Every setting change re-runs this too (GC.Settings), so a module never
-- needs its own refresh wiring.
function Chat.Scan()
    for _, f in ipairs(Chat.Frames()) do
        for _, step in ipairs(perFrame) do
            local ok, err = pcall(step.fn, f)
            if not ok then API.Fail(step.key .. " " .. tostring(f:GetName()), err) end
        end
    end
    for _, step in ipairs(afterScan) do
        local ok, err = pcall(step.fn)
        if not ok then API.Fail(step.key, err) end
    end
end

-- Scrollback. SetMaxLines keeps the lines already there (CircularBuffer.lua:29).
Chat.MIN_LINES, Chat.MAX_LINES = 128, 5000
Chat.OnEachFrame("lines", function(f)
    local want = GC.db.lines
    if f:GetMaxLines() ~= want then f:SetMaxLines(want) end
end)

-- Timestamps (owner: "off by default, but I want it"). Blizzard stamps chat
-- lines itself from the showTimestamps setting (ChatFrameUtil.lua:845,
-- ChatFrameOverrides.lua:424, 661), a plain BetterDate(format, time())
-- prefix; GlassChat turns that on, and remembers what was there to give it
-- back. Lines with no chat event (addon output, like probe logs, and
-- Blizzard's system lines) get no stamp from Blizzard: GlassChat adds the
-- same plain prefix to them right after they're added, through the window's
-- public TransformMessages (ScrollingMessageFrame.lua:95). A line that
-- already starts with a time is left alone, so nothing is stamped twice.
Chat.STAMP_FORMAT = "%H:%M:%S "
local STAMP_CVAR = "showTimestamps"

function Chat.ApplyTimestamps()
    if not (C_CVar and C_CVar.GetCVar and C_CVar.SetCVar) then return end
    local now = C_CVar.GetCVar(STAMP_CVAR)
    if GC.db.timestamps then
        if now ~= Chat.STAMP_FORMAT then
            if GC.db.stampsBefore == nil and type(now) == "string" then GC.db.stampsBefore = now end
            C_CVar.SetCVar(STAMP_CVAR, Chat.STAMP_FORMAT)
        end
    elseif GC.db.stampsBefore ~= nil then
        C_CVar.SetCVar(STAMP_CVAR, GC.db.stampsBefore)
        GC.db.stampsBefore = nil
    end
end

local function stamped(msg)
    return msg:find("^%d%d?:%d%d") ~= nil
end

-- Right after a line with no chat event lands: prefix it, once.
local function stampLine(f, msg, r, g, b, id, accessID, typeID, event)
    if not GC.db.timestamps then return end
    if API.IsSecret(event) or event ~= nil then return end   -- Blizzard stamps chat-event lines itself
    if API.IsSecret(msg) or type(msg) ~= "string" or msg == "" or stamped(msg) then return end
    local stamp = date(Chat.STAMP_FORMAT)
    local done = false
    f:TransformMessages(function(m)
        if done or API.IsSecret(m) or m ~= msg then return false end
        done = true
        return true
    end, function(m, ...) return stamp .. m, ... end)
end

local stampHooked = setmetatable({}, { __mode = "k" })
Chat.OnEachFrame("timestamps", function(f)
    if stampHooked[f] or not f.TransformMessages then return end
    stampHooked[f] = true
    hooksecurefunc(f, "AddMessage", function(...)
        local ok, err = pcall(stampLine, ...)
        if not ok then API.Fail("timestamp", err) end
    end)
end)

-- Class colours: the client does the colouring; keep its switch on. "Off"
-- leaves the CVar alone rather than guessing what the player had before.
local CVAR = "chatClassColorOverride"
function Chat.ApplyClassColors()
    if not GC.db.classColors then return end
    if not (C_CVar and C_CVar.GetCVar and C_CVar.SetCVar) then return end
    if C_CVar.GetCVar(CVAR) ~= "0" then C_CVar.SetCVar(CVAR, "0") end
end

-- "[1. General - The Barrens]" -> "[1. General]" (owner: Prat did this;
-- on by default). Blizzard builds the prefix from arg4 through
-- ResolvePrefixedChannelName (ChatFrameOverrides.lua:657), and the click link
-- from arg8, so rewriting arg4 in a message filter changes the label only.
-- A filter replaces the arguments by returning false followed by the new
-- ones (ChatFrameFilters.lua:145-160); Blizzard only calls it when the
-- arguments are accessible (canaccessvalue). Zone channels only (arg7, the
-- zone channel ID, > 0): a custom channel's name is left alone, even with
-- " - " in it. The join/leave notices keep the zone, which says where you are.
function Chat.ShortChannel(_, _, ...)
    if not GC.db.shortChannels then return false end
    local arg4, arg7 = select(4, ...), select(7, ...)
    if type(arg4) ~= "string" or API.IsSecret(arg4) or API.IsSecret(arg7) then return false end
    if type(arg7) ~= "number" or arg7 <= 0 then return false end
    local short = arg4:match("^(.-) %- .+$")
    if not short then return false end
    local args, n = { ... }, select("#", ...)
    args[4] = short
    return false, unpack(args, 1, n)
end

-- Each step on its own, so one failing (a hooked global changed on a new
-- build) never costs the others: the events and the filter come first,
-- since they are what keeps re-applying everything later.
local started = false
local function step(key, fn)
    local ok, err = pcall(fn)
    if not ok then API.Fail("start " .. key, err) end
end

function Chat.Start()
    if started then return end
    started = true
    step("events", function()
        local f = CreateFrame("Frame")
        f:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_LOGIN" then Chat.ApplyClassColors(); Chat.ApplyTimestamps() end
            Chat.Scan()
        end)
        API.RegisterEvents(f, { "PLAYER_LOGIN", "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" })
    end)
    step("channel filter", function()
        if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
            ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_CHANNEL", Chat.ShortChannel)
        end
    end)
    -- New tabs, and the temporary whisper windows, get the same setup.
    step("window hooks", function()
        for _, name in ipairs({ "FCF_OpenNewWindow", "FCF_OpenTemporaryWindow" }) do
            if rawget(_G, name) then hooksecurefunc(name, function() Chat.Scan() end) end
        end
    end)
    step("tab hooks", GC.Skin.HookTabs)
    step("scan", Chat.Scan)
end
