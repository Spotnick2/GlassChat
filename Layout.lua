-- Layout.lua (M2): one chat layout for every character.
--
-- Chat windows are saved per character (measured: chat-cache.txt per
-- character folder), so each new character starts with Blizzard's default
-- tabs. "Save" records what the client's chat-window API reports, account
-- wide; "apply" sets the same values on this character. Prat's Memory
-- module is the recipe (Memory.lua:145-240), trimmed:
-- - values go in through Blizzard's own SetChatWindow* setters, then
--   FloatingChatFrame_Update(i, 1) applies them per window
--   (FloatingChatFrame.lua:579): name, colour, opacity, lock, docking,
--   shown or closed;
-- - the main window (DEFAULT_CHAT_FRAME, an Edit Mode system) gets only its
--   font, colour and chat contents: no FloatingChatFrame_Update, lock or
--   dock, and never its place or size. Prat's own note: this recipe "causes
--   taint with DF edit mode" (review of #10);
-- - chat types and channels through the window's own methods. A channel is
--   added only if this character is in it (GetChannelName > 0; AddChannel's
--   own return is 0, which is truthy, for one it isn't): nothing is joined.
--   Channel names are saved as the client gives them and replayed on the
--   same client, never compared to an English name;
-- - tabs already docked keep their order: FCF_DockFrame and
--   FCFDock_AddChatFrame return early for them (FloatingChatFrame.lua:1721,
--   2311), and reordering would mean undocking. FCF_SaveDock then records
--   the real order.

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local say = API.Print
local Layout = {}
GC.Layout = Layout

Layout.LINK = "addon:GlassChat:layout:"
Layout.OFFER_DELAY = 3   -- s after the first login, so the chat setup has settled

-- A saved value: plain strings, numbers and booleans only (never a secret).
local function plain(v)
    if API.IsSecret(v) then return nil end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
    return nil
end

-- The strings of a list, every `step`-th value (GetChatWindowChannels gives
-- name, zone ID, name, zone ID...).
local function strings(step, ...)
    local out = {}
    for i = 1, select("#", ...), step do
        local v = plain((select(i, ...)))
        if type(v) == "string" then out[#out + 1] = v end
    end
    return out
end

-- FCF_GetChatWindowInfo maps the client's "default size" 0 to the real
-- default (FloatingChatFrame.lua:557); a raw 0 would set an invisible font.
local function windowInfo(i)
    local get = rawget(_G, "FCF_GetChatWindowInfo") or GetChatWindowInfo
    return get(i)
end

function Layout.CaptureWindow(i)
    local name, size, r, g, b, a, shown, locked, docked, uninteractable = windowInfo(i)
    size = plain(size)
    local w = {
        name = plain(name), fontSize = (type(size) == "number" and size > 0) and size or nil,
        r = plain(r), g = plain(g), b = plain(b), a = plain(a),
        shown = plain(shown) and true or false, locked = plain(locked) and true or false,
        docked = plain(docked), uninteractable = plain(uninteractable) and true or false,
        messages = strings(1, GetChatWindowMessages(i)),
        channels = strings(2, GetChatWindowChannels(i)),
    }
    if i ~= 1 then   -- the main window's place is Edit Mode's
        w.width, w.height = GetChatWindowSavedDimensions(i)
        w.point, w.x, w.y = GetChatWindowSavedPosition(i)
        w.width, w.height, w.point, w.x, w.y = plain(w.width), plain(w.height), plain(w.point), plain(w.x), plain(w.y)
    end
    return w
end

function Layout.Capture()
    local windows = {}
    for i = 1, GC.Chat.MaxWindows() do windows[i] = Layout.CaptureWindow(i) end
    return windows
end

-- Colours and opacity come back as floats: equal within a hair.
local function near(a, b)
    if a == nil or b == nil then return a == b end
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.001
end

local function sameList(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

-- Whether this character's windows already look like the saved layout.
-- A window hidden and undocked on both sides is the same whatever its name;
-- an open one must match in name, docking, font, chat types and channels.
local function inUse(w) return w.shown or w.docked ~= nil end
function Layout.Matches(saved)
    for i, w in pairs(saved.windows) do
        local now = Layout.CaptureWindow(i)
        if inUse(now) ~= inUse(w) then return false end
        if inUse(w) then
            if now.name ~= w.name or (now.docked ~= nil) ~= (w.docked ~= nil) or now.fontSize ~= w.fontSize
                or not sameList(now.messages, w.messages) or not sameList(now.channels, w.channels) then
                return false
            end
            -- Colour and opacity are applied to every window, the main one too.
            if not (near(now.r, w.r) and near(now.g, w.g) and near(now.b, w.b) and near(now.a, w.a)) then
                return false
            end
            -- Lock and click-through are applied to every window but the main one.
            if i ~= 1 and (now.locked ~= w.locked or now.uninteractable ~= w.uninteractable) then
                return false
            end
            -- A floating window's size and place are part of the layout too (Codex, #10);
            -- the main window's are Edit Mode's and were never saved.
            if i ~= 1 and w.docked == nil and (now.width ~= w.width or now.height ~= w.height
                or now.point ~= w.point or now.x ~= w.x or now.y ~= w.y) then
                return false
            end
        end
    end
    return true
end

local function who()
    local name = API.PlayerFullName()
    return (plain(name) or "?") .. " (" .. (plain(GetRealmName()) or "?") .. ")"
end

-- Each save gets a new id: a character's answer is to ONE save, so a newer
-- one is offered again. The counter lives outside the layout, so forget +
-- save never reuses an id another character already answered (Codex, #10).
function Layout.Save()
    local id = (tonumber(GC.db.layoutRevision) or (type(GC.db.layout) == "table" and tonumber(GC.db.layout.id)) or 0) + 1
    GC.db.layoutRevision = id
    GC.db.layout = { id = id, windows = Layout.Capture(), from = who(), guid = plain(UnitGUID("player")) }
    GC.charDB.layoutAnswered = id
    local n = 0
    for _, w in pairs(GC.db.layout.windows) do if inUse(w) then n = n + 1 end end
    say("chat layout saved from " .. GC.db.layout.from .. ": " .. n .. " windows. Other characters will be offered it.")
end

local function joined(channel)
    local ok, id = pcall(GetChannelName, channel)
    return ok and not API.IsSecret(id) and type(id) == "number" and id > 0
end

-- One window, inside its own pcall: one failing never stops the others.
local function applyWindow(i, w)
    local f = rawget(_G, "ChatFrame" .. i)
    if not f then return 0 end
    local main = i == 1
    if w.name then SetChatWindowName(i, w.name) end
    if w.r then SetChatWindowColor(i, w.r, w.g, w.b) end
    if w.a then SetChatWindowAlpha(i, w.a) end
    if not main then
        SetChatWindowDocked(i, w.docked)
        SetChatWindowLocked(i, w.locked)
        SetChatWindowUninteractable(i, w.uninteractable)
        if w.width and w.height then SetChatWindowSavedDimensions(i, w.width, w.height) end
        if w.point then SetChatWindowSavedPosition(i, w.point, w.x, w.y) end
        SetChatWindowShown(i, w.shown)
    end
    if w.fontSize and rawget(_G, "FCF_SetChatWindowFontSize") then FCF_SetChatWindowFontSize(nil, f, w.fontSize) end
    if not main then
        FloatingChatFrame_Update(i, 1)
    else
        -- The setters above only save the main window's values; these
        -- helpers show them (tab text, background colour and opacity), with
        -- nothing about its place, size or docking (Codex, #10).
        if w.name and rawget(_G, "FCF_SetWindowName") then FCF_SetWindowName(f, w.name, true) end
        if w.r and rawget(_G, "FCF_SetWindowColor") then FCF_SetWindowColor(f, w.r, w.g, w.b, true) end
        if w.a and rawget(_G, "FCF_SetWindowAlpha") then FCF_SetWindowAlpha(f, w.a, true) end
    end
    local missing = 0
    if inUse(w) then
        f:RemoveAllMessageGroups()
        for _, group in ipairs(w.messages) do f:AddMessageGroup(group) end
        f:RemoveAllChannels()
        for _, channel in ipairs(w.channels) do
            if joined(channel) then f:AddChannel(channel) else missing = missing + 1 end
        end
        f:ReceiveAllPrivateMessages()
    end
    return missing
end

function Layout.Apply()
    local saved = GC.db.layout
    if type(saved) ~= "table" or type(saved.windows) ~= "table" then
        say("no chat layout saved yet: /gchat layout save on the character whose chat you like")
        return false
    end
    if InCombatLockdown() then
        say("can't change chat windows in combat; try again after")
        return false
    end
    local missing, failed = 0, 0
    for i = 1, GC.Chat.MaxWindows() do
        local w = saved.windows[i]
        if w then
            local ok, n = pcall(applyWindow, i, w)
            if ok then missing = missing + n
            else failed = failed + 1; API.Fail("layout window " .. i, n) end
        end
    end
    for _, name in ipairs({ "FCF_DockUpdate", "FCF_SaveDock" }) do
        local fn = rawget(_G, name)
        if fn then
            local ok, err = pcall(fn)
            if not ok then API.Fail("layout " .. name, err) end
        end
    end
    -- Answered only when it fully worked, so a failed apply is offered again.
    if failed == 0 then GC.charDB.layoutAnswered = saved.id end
    GC.Chat.Scan()
    local msg = "chat layout from " .. tostring(saved.from) .. " applied"
    if missing > 0 then msg = msg .. "; " .. missing .. " channel(s) skipped (join them, then apply again)" end
    if failed > 0 then msg = msg .. "; " .. failed .. " window(s) failed (/gchat failures)" end
    say(msg .. ".")
    return failed == 0
end

function Layout.Forget()
    GC.db.layout = nil
    say("saved chat layout forgotten")
end

-- The offer: once per save and character, a clickable line, only for a
-- layout from ANOTHER character that this one doesn't already match.
function Layout.Offer()
    local saved = GC.db.layout
    if type(saved) ~= "table" or GC.charDB.layoutAnswered == saved.id then return false end
    if saved.guid and saved.guid == plain(UnitGUID("player")) then return false end
    local ok, same = pcall(Layout.Matches, saved)
    if not ok then API.Fail("layout match", same) end
    if ok and same then return false end
    say("your chat layout from " .. tostring(saved.from) .. " isn't on this character: "
        .. "|cff7fd4ff|H" .. Layout.LINK .. "apply|h[Apply it]|h|r  "
        .. "|cffaaaaaa|H" .. Layout.LINK .. "no|h[Not here]|h|r")
    return true
end

-- From the boot frame's first-login branch (GlassChat.lua).
function Layout.ScheduleOffer()
    C_Timer.After(Layout.OFFER_DELAY, function()
        local ok, err = pcall(Layout.Offer)
        if not ok then API.Fail("layout offer", err) end
    end)
end

-- Clicks on our links arrive here, with no hook (probe item 4).
function Layout.OnLink(_, link)
    if API.IsSecret(link) or type(link) ~= "string" then return end
    if link == Layout.LINK .. "apply" then
        Layout.Apply()
    elseif link == Layout.LINK .. "no" then
        local saved = GC.db.layout
        GC.charDB.layoutAnswered = type(saved) == "table" and saved.id or true
        say("ok, not on this character (/gchat layout apply any time)")
    end
end

function Layout.Command(arg)
    if arg == "save" then
        Layout.Save()
    elseif arg == "apply" then
        Layout.Apply()
    elseif arg == "forget" then
        Layout.Forget()
    else
        local saved = GC.db.layout
        say(type(saved) == "table" and ("saved layout: from " .. tostring(saved.from)) or "no layout saved")
        say("/gchat layout save - keep this character's chat windows for the others")
        say("/gchat layout apply - put the saved layout on this character")
        say("/gchat layout forget - drop the saved layout")
    end
end

local started = false
function Layout.Start()
    if started then return end
    started = true
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", Layout.OnLink, Layout)
    end
end

Layout._test = { applyWindow = applyWindow }
