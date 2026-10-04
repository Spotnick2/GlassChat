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
-- - the main window's position and size are Edit Mode's: Blizzard's own
--   restore skips DEFAULT_CHAT_FRAME (line 1476), and so do we;
-- - chat types and channels through the window's own methods. A channel is
--   added only if this character is already in it: nothing is joined
--   (Prat's channel-renumbering dance is out of scope).

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local say = API.Print
local Layout = {}
GC.Layout = Layout

Layout.LINK = "addon:GlassChat:layout:"

-- A saved value: plain strings, numbers and booleans only (never a secret).
local function plain(v)
    if API.IsSecret(v) then return nil end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
    return nil
end

-- Every other value of a list (GetChatWindowChannels: name, zone ID, ...).
local function odd(...)
    local out = {}
    for i = 1, select("#", ...), 2 do
        local v = plain((select(i, ...)))
        if type(v) == "string" then out[#out + 1] = v end
    end
    return out
end

local function strings(...)
    local out = {}
    for i = 1, select("#", ...) do
        local v = plain((select(i, ...)))
        if type(v) == "string" then out[#out + 1] = v end
    end
    return out
end

function Layout.CaptureWindow(i)
    local name, size, r, g, b, a, shown, locked, docked, uninteractable = GetChatWindowInfo(i)
    local w = {
        name = plain(name), fontSize = plain(size), r = plain(r), g = plain(g), b = plain(b), a = plain(a),
        shown = plain(shown) and true or false, locked = plain(locked) and true or false,
        docked = plain(docked), uninteractable = plain(uninteractable) and true or false,
        messages = strings(GetChatWindowMessages(i)),
        channels = odd(GetChatWindowChannels(i)),
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

-- Whether this character's windows already look like the saved layout:
-- the same windows shown, named, docked, with the same chat types.
local function sameList(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

function Layout.Matches(saved)
    for i, w in pairs(saved.windows) do
        local now = Layout.CaptureWindow(i)
        if now.shown ~= w.shown or now.name ~= w.name or (now.docked ~= nil) ~= (w.docked ~= nil)
            or not sameList(now.messages, w.messages) then
            return false
        end
    end
    return true
end

local function who()
    local name = UnitName("player")
    return (plain(name) or "?") .. " (" .. (plain(GetRealmName()) or "?") .. ")"
end

function Layout.Save()
    GC.db.layout = { windows = Layout.Capture(), from = who(), guid = plain(UnitGUID("player")) }
    GC.charDB.layoutAnswered = "saved"
    local n = 0
    for _, w in pairs(GC.db.layout.windows) do if w.shown or w.docked then n = n + 1 end end
    say("chat layout saved from " .. GC.db.layout.from .. ": " .. n .. " windows. Other characters will be offered it.")
end

-- One window, inside its own pcall: one failing never stops the others.
local function applyWindow(i, w)
    local f = rawget(_G, "ChatFrame" .. i)
    if not f then return 0 end
    if w.name then SetChatWindowName(i, w.name) end
    if w.r then SetChatWindowColor(i, w.r, w.g, w.b) end
    if w.a then SetChatWindowAlpha(i, w.a) end
    SetChatWindowDocked(i, w.docked)
    SetChatWindowLocked(i, w.locked)
    SetChatWindowUninteractable(i, w.uninteractable)
    if i ~= 1 then
        if w.width and w.height then SetChatWindowSavedDimensions(i, w.width, w.height) end
        if w.point then SetChatWindowSavedPosition(i, w.point, w.x, w.y) end
    end
    SetChatWindowShown(i, w.shown)
    if w.fontSize and rawget(_G, "FCF_SetChatWindowFontSize") then FCF_SetChatWindowFontSize(nil, f, w.fontSize) end
    FloatingChatFrame_Update(i, 1)
    local missing = 0
    if w.shown or w.docked then
        f:RemoveAllMessageGroups()
        for _, group in ipairs(w.messages) do f:AddMessageGroup(group) end
        f:RemoveAllChannels()
        for _, channel in ipairs(w.channels) do
            if not f:AddChannel(channel) then missing = missing + 1 end
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
    if rawget(_G, "FCF_DockUpdate") then pcall(FCF_DockUpdate) end
    GC.charDB.layoutAnswered = "applied"
    GC.Chat.Scan()
    local msg = "chat layout from " .. tostring(saved.from) .. " applied"
    if missing > 0 then msg = msg .. "; " .. missing .. " channel(s) skipped (join them, then apply again)" end
    if failed > 0 then msg = msg .. "; " .. failed .. " window(s) failed (/gchat failures)" end
    say(msg .. ".")
    return true
end

function Layout.Forget()
    GC.db.layout = nil
    say("saved chat layout forgotten")
end

-- The offer: once per character, a clickable line, only when there is a
-- layout from ANOTHER character and this one doesn't already match it.
function Layout.Offer()
    local saved = GC.db.layout
    if type(saved) ~= "table" or GC.charDB.layoutAnswered then return false end
    if saved.guid and saved.guid == plain(UnitGUID("player")) then return false end
    local ok, same = pcall(Layout.Matches, saved)
    if ok and same then return false end
    print("|cff7fd4ffGlassChat|r your chat layout from " .. tostring(saved.from) .. " isn't on this character: "
        .. "|cff7fd4ff|H" .. Layout.LINK .. "apply|h[Apply it]|h|r  "
        .. "|cffaaaaaa|H" .. Layout.LINK .. "no|h[Not here]|h|r")
    return true
end

-- Clicks on our links arrive here, with no hook (probe item 4).
function Layout.OnLink(_, link)
    if type(link) ~= "string" or API.IsSecret(link) then return end
    if link == Layout.LINK .. "apply" then
        Layout.Apply()
    elseif link == Layout.LINK .. "no" then
        GC.charDB.layoutAnswered = "no"
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
    -- After the first login's chat setup has settled.
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, _, isInitialLogin)
        if isInitialLogin then C_Timer.After(3, function() pcall(Layout.Offer) end) end
    end)
    API.RegisterEvents(f, { "PLAYER_ENTERING_WORLD" })
end

Layout._test = { applyWindow = applyWindow }
