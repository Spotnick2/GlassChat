-- Tabs.lua (M3): smart tabs. An addon that floods chat (the owner's probes)
-- is offered its own tab, for the session or always.
--
-- Measured (docs/FOREVER-PROBE.md 7-9):
-- - The writer of a line is found from the stack (debugstack): the first
--   frame below our own that isn't Blizzard's plumbing names its addon
--   folder. A frame line names its file twice, so only its first path counts.
-- - ASProbe and the AltStable family write with DEFAULT_CHAT_FRAME:AddMessage,
--   not print, so a print handler alone misses the owner's main case. One
--   AddMessage post-hook (Chat.lua, shared with the timestamps) sees both:
--   print reaches AddMessage through Blizzard_PrintHandler.
-- - Moving a line works: copy it to the tab, then remove the copy where it
--   landed with the public RemoveMessagesByPredicate (ScrollingMessageFrame
--   .lua:45). RemoveIf walks oldest to newest (CircularBuffer.lua:89), so
--   the last match is the line just added, even with older identical lines.
-- - FCF_OpenNewWindow(name, true) opens an empty tab; chat tabs are per
--   character, so rules are account-wide and each character opens its own.
-- Only lines with no chat event are considered: those are addon output
-- (Blizzard's chat lines carry their event). Secret lines are never moved.

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local Tabs = {}
GC.Tabs = Tabs

Tabs.LINK = "addon:GlassChat:tabs:"
Tabs.CHATTY, Tabs.WINDOW = 20, 60   -- lines within seconds that make an addon "chatty"

local function say(msg) API.Print(msg) end

--------------------------------------------------------------------------------
-- Who wrote this line
--------------------------------------------------------------------------------

-- Not the writer: Blizzard's plumbing, and standalone libraries (Ace3,
-- LibStub-style folders) an addon calls to print (review of #26).
local function plumbing(name)
    return name:find("^Blizzard_") ~= nil or name:find("^Ace") ~= nil or name:find("^Lib") ~= nil
end
local function ours(name)
    return name == "GlassChat" or name:find("^GlassChat") ~= nil
end

-- The addon folder behind the current AddMessage call, "Blizzard" when only
-- Blizzard's code is above us, or nil. Our own frames come first (the hook,
-- debugstack still lists its caller): that leading run is skipped, with the
-- frames between them that name no addon, "[C]: in function `pcall'" and
-- "(tail call)" (review of #26: stopping at those credited GlassChat).
function Tabs.SourceOf()
    if not debugstack then return nil end
    local ok, stack = pcall(debugstack, 2, 20, 0)
    if not ok or API.IsSecret(stack) or type(stack) ~= "string" then return nil end
    local leading, blizzard = true, false
    for line in stack:gmatch("[^\n]+") do
        local name = line:match("AddOns[/\\]([^/\\]+)[/\\]")
        if leading and name and name ~= "GlassChat" then leading = false end
        if not leading and name then
            if not plumbing(name) then return name end
            blizzard = true
        end
    end
    return blizzard and "Blizzard" or nil
end

--------------------------------------------------------------------------------
-- Rules: always (account-wide, saved), this session, never ask
--------------------------------------------------------------------------------

local session = {}      -- addon -> true: routed this session
local closed = {}       -- addon -> true: its tab was closed this session
local tabs = {}         -- addon -> chat frame
local offered = {}      -- addon -> true: asked this session
local recent = {}       -- addon -> { times }

local function rules()
    local db = GC.db
    if type(rawget(db, "routes")) ~= "table" then db.routes = {} end
    if type(rawget(db, "routeNever")) ~= "table" then db.routeNever = {} end
    return db.routes, db.routeNever
end

function Tabs.IsRouted(src)
    local always = rules()
    return (session[src] or always[src]) and not closed[src]
end

--------------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------------

-- A window of this name that's open (shown or docked), else nil. A closed
-- window keeps its name (FCF_Close only hides and undocks): not reused.
local function openWindow(name)
    for i = 1, GC.Chat.MaxWindows() do
        local ok, wname, _, _, _, _, _, shown, _, docked = pcall(GetChatWindowInfo, i)
        if ok and not API.IsSecret(wname) and wname == name and (shown or docked) then
            local f = rawget(_G, "ChatFrame" .. i)
            if f then return f end
        end
    end
end

local function tabFor(src)
    local f = tabs[src]
    if f then
        local ok, wname, _, _, _, _, _, shown, _, docked = pcall(GetChatWindowInfo, f:GetID())
        if ok and not API.IsSecret(wname) and wname == src and (shown or docked) then return f end
        -- Closed by the player: back to the main chat for this session.
        tabs[src], closed[src] = nil, true
        say(src .. "'s tab was closed: its lines go back to the main chat for this session (/gchat tabs)")
        return nil
    end
    f = openWindow(src)
    -- Never a new tab while the player is typing: FCF_OpenNewWindow makes the
    -- new tab's edit box the last active one, and in the IM chat style that
    -- hides the box being typed in, whose OnHide clears the unfinished text
    -- and its destination (ChatFrameUtil.lua:570-580; Codex review of #26).
    -- The line stays where it is; the tab opens on the next line after.
    if not f and ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow() then
        return nil
    end
    if not f and FCF_OpenNewWindow then
        -- FCF_OpenNewWindow selects the new tab and makes its edit box the
        -- active one (FloatingChatFrame.lua:847-849): put back what the player
        -- had, so routing never switches their chat (review of #26).
        local dock = rawget(_G, "GENERAL_CHAT_DOCK")
        local selected = dock and FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(dock)
        local active = ChatFrameUtil and ChatFrameUtil.GetLastActiveWindow and ChatFrameUtil.GetLastActiveWindow()
        local ok, made = pcall(FCF_OpenNewWindow, src, true)
        if ok then f = made else API.Fail("tab open", made) end
        if f and selected and selected ~= f and FCFDock_SelectWindow then
            local okS, err = pcall(FCFDock_SelectWindow, dock, selected)
            if not okS then API.Fail("tab reselect", err) end
        end
        if f and active and ChatFrameUtil.SetLastActiveWindow then
            local okA, err = pcall(ChatFrameUtil.SetLastActiveWindow, active)
            if not okA then API.Fail("tab active box", err) end
        end
        if not f and ok then
            closed[src] = true
            say("no room for another chat tab for " .. src .. " (the game allows " .. GC.Chat.MaxWindows() ..
                "); its lines stay in the main chat")
            return nil
        end
        if not f then closed[src] = true; return nil end
    end
    tabs[src] = f
    return f
end

--------------------------------------------------------------------------------
-- Moving a line
--------------------------------------------------------------------------------

local moving = false

-- One pass: RemoveIf walks oldest to newest, so the line just added is the
-- last entry (each pass rebuilds the buffer, so not two; review of #26).
local function removeNewest(f, msg)
    local n = f:GetNumMessages()
    if API.IsSecret(n) or type(n) ~= "number" or n < 1 then return false end
    local i, removed = 0, false
    f:RemoveMessagesByPredicate(function(m)
        i = i + 1
        if i == n and not API.IsSecret(m) and m == msg then removed = true; return true end
        return false
    end)
    return removed
end

local function offer(src)
    offered[src] = true
    local function link(kind, text)
        return "|H" .. Tabs.LINK .. kind .. ":" .. src .. "|h|cff7fd4ff[" .. text .. "]|r|h"
    end
    say(src .. " printed " .. Tabs.CHATTY .. " lines in a minute. " .. link("session", "Own tab for this session")
        .. " " .. link("always", "Always") .. " " .. link("never", "No"))
end

local function noteChatty(src)
    local _, never = rules()
    if offered[src] or never[src] then return end
    local t, list = GetTime(), recent[src] or {}
    recent[src] = list
    list[#list + 1] = t
    while list[1] and t - list[1] > Tabs.WINDOW do table.remove(list, 1) end
    if #list >= Tabs.CHATTY then
        recent[src] = nil
        offer(src)
    end
end

-- From Chat.lua's AddMessage post-hook, for a line with no chat event.
-- Returns true when the line was moved to its addon's tab.
function Tabs.Route(f, msg, r, g, b)
    if moving then return false end
    -- The combat log writes every entry this way (Blizzard_CombatLog.lua:1699):
    -- never walk the stack for it.
    if f == rawget(_G, "COMBATLOG") then return false end
    if API.IsSecret(msg) or type(msg) ~= "string" or msg == "" then return false end
    local src = Tabs.SourceOf()
    if not src or src == "Blizzard" or ours(src) then return false end
    if not Tabs.IsRouted(src) then
        noteChatty(src)
        return false
    end
    local tab = tabFor(src)
    if not tab or tab == f then return false end
    moving = true
    local ok, err = pcall(tab.AddMessage, tab, msg, r, g, b)
    moving = false
    if not ok then API.Fail("tab copy", err); return false end
    local okR, removed = pcall(removeNewest, f, msg)
    if not okR then API.Fail("tab remove", removed) end
    return true
end

--------------------------------------------------------------------------------
-- The offer's links, and /gchat tabs
--------------------------------------------------------------------------------

function Tabs.OnLink(_, link)
    if API.IsSecret(link) or type(link) ~= "string" then return end
    local kind, src = link:match("^addon:GlassChat:tabs:(%a+):(.+)$")
    if not kind then return end
    local always, never = rules()
    if kind == "session" then
        session[src], closed[src] = true, nil
        say(src .. " gets its own tab for this session (/gchat tabs)")
    elseif kind == "always" then
        always[src], closed[src] = true, nil
        say(src .. " gets its own tab on all your characters (/gchat tabs forget " .. src .. " to stop)")
    elseif kind == "never" then
        never[src], always[src], session[src] = true, nil, nil
        say("ok, " .. src .. " stays in the main chat; GlassChat won't ask again (/gchat tabs forget " .. src .. ")")
    end
end

-- An addon's name as its rule spells it (case-insensitive), else as typed.
local function known(name)
    local always, never = rules()
    local l = name:lower()
    for _, t in ipairs({ always, never, session }) do
        for k in pairs(t) do if k:lower() == l then return k end end
    end
    return name
end

function Tabs.Command(arg)
    local always, never = rules()
    local forget = arg:match("^[Ff][Oo][Rr][Gg][Ee][Tt]%s+(.+)$")
    if forget then
        forget = known(forget)
        local was = always[forget] or never[forget] or session[forget]
        always[forget], never[forget], session[forget], offered[forget] = nil, nil, nil, nil
        say(was and ("forgot " .. forget .. ": its lines stay in the main chat, and it may be offered a tab again")
            or ("no rule for " .. forget))
        return
    end
    local any = false
    for src in pairs(always) do any = true; say("own tab, always: " .. src .. (closed[src] and " (closed this session)" or "")) end
    for src in pairs(session) do any = true; say("own tab, this session: " .. src) end
    for src in pairs(never) do any = true; say("never asked: " .. src) end
    if not any then say("no tab rules yet: a chatty addon is offered its own tab") end
    say("/gchat tabs forget <Addon> - drop its rule")
end

local started = false
function Tabs.Start()
    if started then return end
    started = true
    GC.Chat.Route = Tabs.Route
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", Tabs.OnLink, Tabs)
    end
end

Tabs._test = {
    reset = function() session, closed, tabs, offered, recent, moving = {}, {}, {}, {}, {}, false end,
}
