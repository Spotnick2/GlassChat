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
Tabs.SRC_LINK = "addon:GlassChat:src:"   -- an addon line's prefix: right-click for a tab (#35)
-- Our own probes (owner): routed at once in developer mode (GC.IsDev).
Tabs.PROBE = "Probe$"
Tabs.CHATTY, Tabs.WINDOW = 20, 60   -- lines within seconds that make an addon "chatty"
-- The game loading (owner: "ignore the initial loading of the addons"):
-- from GlassChat's start until LOAD_QUIET s after the loading screen of a
-- login or /reload, every addon prints its "loaded" line. Those lines open no
-- tab, route no probe by its name and count toward no offer; a tab already
-- open still gets its addon's lines, and who wrote each line is still noted.
Tabs.LOAD_QUIET = 15
Tabs.LOAD_BACKSTOP = 60   -- the quiet ends by then even if no loading screen is ever seen (review of #42)

local function say(msg) API.Print(msg) end

-- A notice printed WHILE a line is being handled would land in the chat
-- before that line is moved or rewritten (it goes through the same hook), so
-- "remove the newest" would find the notice and leave the line in both
-- places (Codex review of #36). Inside the hook, notices wait in `held` and
-- Chat.lua prints them once the line is done (Tabs.LineDone).
local handling, held = false, {}
local moving = false   -- copying a line into its tab (Route)
local function notice(msg)
    if handling then held[#held + 1] = msg else say(msg) end
end
function Tabs.LineDone()
    -- The copy into a tab runs that tab's hook first: wait for the outer line.
    if moving then return end
    handling = false
    if #held == 0 then return end
    local out = held
    held = {}
    for _, m in ipairs(out) do say(m) end
end

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
local devDone = {}      -- addon -> true: developer mode already routed or released it
local loading = true    -- the game is still loading (see LOAD_QUIET)
local quietGen = 0      -- the latest quiet; an older timer never ends a newer one
local function quietFor(seconds)
    quietGen = quietGen + 1
    local gen = quietGen
    loading = true
    C_Timer.After(seconds, function() if gen == quietGen then loading = false end end)
end
function Tabs.Loading() return loading end
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

-- Is its cached tab still open? Closed: forgotten here, and marked closed
-- when it was routed. Never opens a window, never prints.
function Tabs.CheckTab(src)
    local f = tabs[src]
    if not f then return end
    local ok, wname, _, _, _, _, _, shown, _, docked = pcall(GetChatWindowInfo, f:GetID())
    if ok and not API.IsSecret(wname) and wname == src and (shown or docked) then return end
    tabs[src] = nil
    if session[src] or rules()[src] then closed[src] = true end
end

local function tabFor(src)
    local f = tabs[src]
    if f then
        local ok, wname, _, _, _, _, _, shown, _, docked = pcall(GetChatWindowInfo, f:GetID())
        if ok and not API.IsSecret(wname) and wname == src and (shown or docked) then return f end
        -- Closed by the player: back to the main chat for this session.
        tabs[src], closed[src] = nil, true
        notice(src .. "'s tab was closed: its lines go back to the main chat for this session (/gchat tabs)")
        return nil
    end
    f = openWindow(src)
    if not f and loading then return nil end   -- no new tab while the game loads: the line stays
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
            notice("no room for another chat tab for " .. src .. " (the game allows " .. GC.Chat.MaxWindows() ..
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


-- Which addon wrote each recent line, by its text (focus mode's "From"
-- filter). Two generations of SOURCE_CAP texts each: a full current one
-- becomes the previous one, so a write is O(1) in this hot hook, and a text
-- written again moves to the current one (review of #28). Identical text
-- from two addons is credited to the last writer.
Tabs.SOURCE_CAP = 2000
local current, previous, size = {}, {}, 0
local function remember(msg, src)
    if current[msg] == nil then
        size = size + 1
        if size > Tabs.SOURCE_CAP then previous, current, size = current, {}, 1 end
    end
    current[msg] = src
end
function Tabs.SourceFor(msg)
    if API.IsSecret(msg) or type(msg) ~= "string" then return nil end
    return current[msg] or previous[msg]
end
-- A line stamped after it was added (Chat.lua): its writer follows the new text.
function Tabs.Restamped(old, new)
    local src = Tabs.SourceFor(old)
    if src and not API.IsSecret(new) and type(new) == "string" then remember(new, src) end
end

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

local function offer(src, why)
    offered[src] = true
    local function link(kind, text)
        return "|H" .. Tabs.LINK .. kind .. ":" .. src .. "|h|cff7fd4ff[" .. text .. "]|r|h"
    end
    notice((why or (src .. " printed " .. Tabs.CHATTY .. " lines in a minute.")) .. " " .. link("session", "Own tab for this session")
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

-- The last line Route saw, and its writer: Chat.lua's rewrite of that same
-- line asks Linkify for its prefix link next.
local lastMsg, lastSrc

-- The line with its leading coloured prefix ("|cff..[AltStable]|r") made our
-- link, its colour kept; nil when it has none, or for any other line.
function Tabs.Linkify(msg)
    if msg ~= lastMsg or not lastSrc or not lastSrc:find("^[%w_%-]+$") then return nil end
    local color, inner, rest = msg:match("^(|c%x%x%x%x%x%x%x%x)(.-)|r(.*)$")
    if not color or inner == "" or inner:find("|", 1, true) then return nil end
    -- A name, not a sentence: "[AltStable]" or the addon's own name ("ChatProbe").
    -- A line coloured end to end isn't turned into one big link (review of #36).
    if not (inner:find("^%[[^%]]+%]:?$") or inner:lower() == lastSrc:lower()) then return nil end
    return color .. "|H" .. Tabs.SRC_LINK .. lastSrc .. "|h" .. inner .. "|h|r" .. rest
end

-- From Chat.lua's AddMessage post-hook, for a line with no chat event.
-- Returns true when the line was moved to its addon's tab.
function Tabs.Route(f, msg, r, g, b)
    if moving then return false end   -- (a copy into its tab: lastMsg/lastSrc still describe it)
    lastMsg, lastSrc = nil, nil
    handling = true
    -- The combat log writes every entry this way (Blizzard_CombatLog.lua:1699):
    -- never walk the stack for it.
    if f == rawget(_G, "COMBATLOG") then return false end
    if API.IsSecret(msg) or type(msg) ~= "string" or msg == "" then return false end
    local src = Tabs.SourceOf()
    if not src or src == "Blizzard" or ours(src) then return false end
    remember(msg, src)
    -- lastMsg/lastSrc are set right before the line's rewrite needs them (the
    -- returns below, the copy into its tab): a notice printed meanwhile goes
    -- through Route itself and resets them (review of #36).
    -- Developer mode: our own probes get their tab at once, once a session.
    if not loading and not Tabs.IsRouted(src) and not devDone[src] and src:find(Tabs.PROBE) and GC.IsDev() then
        local _, never = rules()
        devDone[src] = true
        if not never[src] and not closed[src] then
            session[src] = true
            notice("developer mode: " .. src .. " gets its own tab (right-click its name, or /gchat tabs forget " .. src .. ")")
        end
    end
    if not Tabs.IsRouted(src) then
        if not loading then noteChatty(src) end
        lastMsg, lastSrc = msg, src
        return false
    end
    local tab = tabFor(src)
    lastMsg, lastSrc = msg, src
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

-- The one place a rule changes: the offer's links, the right-click menu and
-- /gchat tabs route all come here. kind: session, always, never, main
-- (back to the main chat; may be offered again).
function Tabs.SetRule(src, kind)
    local always, never = rules()
    devDone[src] = true   -- a choice made: developer mode leaves it alone
    if kind == "session" or kind == "always" then Tabs.CheckTab(src) end   -- no stale closed frame kept
    if kind == "session" then
        -- This session only: a saved Always goes (Codex review of #36).
        session[src], closed[src], never[src], always[src] = true, nil, nil, nil
        say(src .. " gets its own tab for this session (/gchat tabs)")
    elseif kind == "always" then
        always[src], closed[src], never[src] = true, nil, nil
        say(src .. " gets its own tab on all your characters (/gchat tabs forget " .. src .. " to stop)")
    elseif kind == "never" then
        never[src], always[src], session[src] = true, nil, nil
        say("ok, " .. src .. " stays in the main chat; GlassChat won't ask again (/gchat tabs forget " .. src .. ")")
    elseif kind == "main" then
        always[src], session[src] = nil, nil
        say(src .. "'s lines go back to the main chat (its tab stays until you close it)")
    end
end

-- An addon asking for its own tab (owner: "the probes could send a
-- message"): GlassChat.RequestTab("MyProbe"). In developer mode it's routed
-- at once; otherwise the player gets the one-time offer, so no addon takes a
-- tab on its own. A player's No always wins.
function Tabs.Request(src)
    if API.IsSecret(src) or type(src) ~= "string" or not src:find("^[%w_%-]+$") or ours(src) then return false end
    local always, never = rules()
    if never[src] or always[src] or session[src] or devDone[src] then return Tabs.IsRouted(src) and true or false end
    if GC.IsDev() then
        devDone[src] = true
        session[src], closed[src] = true, nil
        say("developer mode: " .. src .. " asked for its own tab (right-click its name, or /gchat tabs forget " .. src .. ")")
        return true
    end
    if not offered[src] then offer(src, src .. " asks for its own chat tab.") end
    return false
end

-- Right-click on an addon's name: a menu of the rules for it, and its lines
-- in focus mode. frame: the window clicked, resolved now, not when an item is
-- picked (Codex, #78).
function Tabs.Menu(src, frame)
    local always = rules()
    Tabs.CheckTab(src)                  -- closed since its last line? (Codex review of #36)
    local routed = Tabs.IsRouted(src)   -- a closed tab isn't routed (review of #36)
    if API.ContextMenu(function(root)
        root:CreateTitle(src)
        root:CreateButton("Show its lines", function() GC.Focus.Open(frame, "", src) end)
        if not routed then root:CreateButton("Own tab for this session", function() Tabs.SetRule(src, "session") end) end
        if not always[src] then root:CreateButton("Own tab, always", function() Tabs.SetRule(src, "always") end) end
        if routed then root:CreateButton("Back to the main chat", function() Tabs.SetRule(src, "main") end) end
    end) then return end
    -- No menu: the same choices as links.
    local function link(kind, text) return "|H" .. Tabs.LINK .. kind .. ":" .. src .. "|h|cff7fd4ff[" .. text .. "]|r|h" end
    say(src .. ": " .. link("session", "Own tab for this session") .. " " .. link("always", "Always"))
end

-- The chat window a link was clicked in: SetItemRef's 4th argument
-- (ChatFrame.lua:19 passes the clicked frame). Anything else (nil, a secret,
-- a widget that isn't a chat window): the window in view (Codex, #78).
local function clickedWindow(frame)
    if not API.IsSecret(frame) and type(frame) == "table" and frame.GetMessageInfo and frame.GetNumMessages then
        return frame
    end
    return GC.Copy.CurrentFrame()
end

local function modified()
    return IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()
end

-- An addon's name: a plain left-click shows its lines in focus mode (#78;
-- modified clicks do nothing, as before); a right-click opens its menu.
function Tabs.OnLink(_, link, _, button, frame)
    if API.IsSecret(link) or type(link) ~= "string" then return end
    local src = link:match("^addon:GlassChat:src:(.+)$")
    if src then
        if API.IsSecret(button) then return end
        if button == "RightButton" then
            Tabs.Menu(src, clickedWindow(frame))
        elseif button == "LeftButton" and not modified() then
            GC.Focus.Open(clickedWindow(frame), "", src)
        end
        return
    end
    local kind
    kind, src = link:match("^addon:GlassChat:tabs:(%a+):(.+)$")
    if kind then Tabs.SetRule(src, kind) end
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
    -- /gchat tabs route <Addon> [always]: a tab without the mouse (#35).
    local route = arg:match("^[Rr][Oo][Uu][Tt][Ee]%s+(.+)$")
    if route then
        local name = route:match("^(%S+)%s+[Aa][Ll][Ww][Aa][Yy][Ss]$")
        local typed = name or route
        -- The folder name as the client spells it (rules match it exactly; review of #36).
        local real = API.AddOnName(typed) or known(typed)
        if not real:find("^[%w_%-]+$") or ours(real) then
            say("no tab for " .. typed .. " (an addon's folder name, not GlassChat's own)")
            return
        end
        Tabs.SetRule(real, name and "always" or "session")
        return
    end
    local forget = arg:match("^[Ff][Oo][Rr][Gg][Ee][Tt]%s+(.+)$")
    if forget then
        forget = known(forget)
        devDone[forget] = true   -- a saved rule forgotten stays forgotten (Codex review of #36)
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
    say("/gchat tabs route <Addon> [always] - its own tab (or right-click its name in chat)")
    say("/gchat tabs forget <Addon> - drop its rule")
end

local started = false
function Tabs.Start()
    if started then return end
    started = true
    -- First, so it holds even if anything below fails: the quiet can't outlive this.
    quietFor(Tabs.LOAD_BACKSTOP)
    GC.Chat.Route = Tabs.Route
    GC.Chat.Restamped = Tabs.Restamped
    GC.Chat.Linkify = Tabs.Linkify
    GC.Chat.LineDone = Tabs.LineDone
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", Tabs.OnLink, Tabs)
    end
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, _, isLogin, isReload)
        -- A secret argument can't be read: taken as a login, so the quiet still ends on time.
        local unknown = API.IsSecret(isLogin) or API.IsSecret(isReload)
        if not unknown and not (isLogin or isReload) then return end   -- zoning: addons aren't loading
        quietFor(Tabs.LOAD_QUIET)
    end)
    API.RegisterEvents(f, { "PLAYER_ENTERING_WORLD" })
end

Tabs._test = {
    reset = function() session, closed, tabs, offered, recent, moving, devDone = {}, {}, {}, {}, {}, false, {} end,
    loaded = function() loading = false end,
    sources = function() return current, previous end,
}
