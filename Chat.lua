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

-- The chat windows that exist, by index. A tab the player never opened still
-- has its frame; the setup is cheap and idempotent, so all of them get it.
function Chat.Frames()
    local out = {}
    for i = 1, Chat.MaxWindows() do
        local f = rawget(_G, "ChatFrame" .. i)   -- rawget: absent windows read nil, never an error
        if f then out[#out + 1] = f end
    end
    return out
end

-- Per-window setup functions, run on every window at each scan. Each one
-- must be idempotent; one failing never stops the others.
local perFrame = {}
function Chat.OnEachFrame(key, fn)
    perFrame[#perFrame + 1] = { key = key, fn = fn }
end

function Chat.Scan()
    for _, f in ipairs(Chat.Frames()) do
        for _, step in ipairs(perFrame) do
            local ok, err = pcall(step.fn, f)
            if not ok then API.Fail(step.key .. " " .. tostring(f:GetName()), err) end
        end
    end
end

-- Scrollback. SetMaxLines keeps the lines already there (CircularBuffer.lua:29).
Chat.MIN_LINES, Chat.MAX_LINES = 128, 5000
Chat.OnEachFrame("lines", function(f)
    local want = GC.db.lines
    if f:GetMaxLines() ~= want then f:SetMaxLines(want) end
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

local started = false
function Chat.Start()
    if started then return end
    started = true
    Chat.Scan()
    GC.Skin.HookTabs()
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_CHANNEL", Chat.ShortChannel)
    end
    -- New tabs, and the temporary whisper windows, get the same setup.
    for _, name in ipairs({ "FCF_OpenNewWindow", "FCF_OpenTemporaryWindow" }) do
        if rawget(_G, name) then hooksecurefunc(name, function() Chat.Scan() end) end
    end
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then Chat.ApplyClassColors() end
        Chat.Scan()
    end)
    API.RegisterEvents(f, { "PLAYER_LOGIN", "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" })
end
