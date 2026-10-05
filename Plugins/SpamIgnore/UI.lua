-- UI.lua (Spam & Ignore): the tab-strip icon, the hidden-lines window, and
-- the /gchat subcommands.
--
-- The icon is OPT-IN (owner: "make it a setting ... disabled by default"):
-- /gchat spam icon on. It sits left of the copy icon on each window's glass
-- panel, with a count of lines hidden since you last looked. In a dev or test build it's
-- a bug (owner: a window "with blocked messages only, activated via a bug
-- icon", until the official release); in a release it's an eye. Either
-- opens the same copy-style window, the debug one with more detail. No line
-- is ever printed into chat: a filter runs before Blizzard picks the window
-- (ChatFrameOverrides.lua:312-363), so it could land in the wrong tab.

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local Spam = GC.Spam
local UI = {}
GC.SpamUI = UI

UI.BUG = "Interface\\HelpFrame\\HelpIcon-Bug"     -- Blizzard's help frame
UI.EYE = "socialqueuing-icon-eye"                -- Blizzard's Quick Join
UI.SIZE = 18
-- The look (owner: "we'll adjust later"): gold on hover, like the copy icon;
-- highlighted (gold, full strength, a soft glow) while unseen lines wait;
-- a BLINK of BLINK_TIME seconds each time a line is blocked.
UI.BLINK_TIME, UI.BLINK_PERIOD, UI.BLINK_LOW = 3, 0.25, 0.25
UI.GLOW = 0.35

local buttons = setmetatable({}, { __mode = "k" })   -- chat frame -> button

local function hasAtlas(name)
    local get = C_Texture and C_Texture.GetAtlasInfo
    if not get then return false end
    local ok, info = pcall(get, name)
    return ok and info ~= nil and not API.IsSecret(info)
end

local function paint(b)
    local n = Spam.unseen
    b.count:SetText(n > 0 and tostring(math.min(n, 99)) or "")
    local lit = n > 0 or b.hovered
    local c = lit and GC.Skin.TAB_GOLD or GC.Skin.TAB_GREY
    b.icon:SetVertexColor(c[1], c[2], c[3])
    b.icon:SetAlpha(lit and 1 or 0.7)
    b.glow:SetShown(n > 0)
end

function UI.PaintAll()
    for _, b in pairs(buttons) do paint(b) end
end

-- A line was just blocked: repaint, and blink every icon for BLINK_TIME s
-- (a new block restarts it).
local blinkToken
function UI.Blocked()
    UI.PaintAll()
    for _, b in pairs(buttons) do
        b.blink:Stop()
        b.blink:Play()
    end
    local token = {}
    blinkToken = token
    C_Timer.After(UI.BLINK_TIME, function()
        if blinkToken ~= token then return end
        for _, b in pairs(buttons) do b.blink:Stop(); b.icon:SetAlpha(1) end
        UI.PaintAll()
    end)
end

function UI.Open()
    local debug = Spam.IsDebug()
    local log = Spam.Log()
    local title = debug and "Spam & Ignore: blocked lines (debug)" or "Spam & Ignore: hidden lines"
    local status = #log .. " hidden this session, newest first"
    if #log == 0 then status = "nothing hidden this session" end
    GC.Copy.Show(title, Spam.LogText(debug), status)
    Spam.unseen = 0
    UI.PaintAll()
end

function UI.Button(f)
    if buttons[f] then buttons[f]:SetShown(Spam.db.icon and true or false); return end
    if not Spam.db.icon then return end
    local p = GC.Skin.Panel(f)
    if not p then return end
    local b = CreateFrame("Button", nil, p.panel)
    b:SetFrameStrata("MEDIUM")
    b:SetSize(UI.SIZE + 4, UI.SIZE + 2)
    b:SetPoint("TOPRIGHT", p.panel, "TOPRIGHT", -14 - GC.Skin.CORE_ICONS * GC.Skin.STRIP_ICON_STEP, -9)
    local icon = b:CreateTexture(nil, "OVERLAY")
    icon:SetSize(UI.SIZE, UI.SIZE)
    icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    if Spam.IsDebug() then
        icon:SetTexture(UI.BUG)
        icon:SetDesaturated(true)
    elseif hasAtlas(UI.EYE) then
        icon:SetAtlas(UI.EYE)
        icon:SetDesaturated(true)
    else
        icon:SetColorTexture(1, 1, 1, 0.5)   -- no eye art on this client: a plain square
    end
    b.icon = icon
    -- The highlight: a soft additive glow behind the icon while lines wait.
    local glow = b:CreateTexture(nil, "ARTWORK")
    glow:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    glow:SetColorTexture(GC.Skin.TAB_GOLD[1], GC.Skin.TAB_GOLD[2], GC.Skin.TAB_GOLD[3], UI.GLOW)
    glow:SetBlendMode("ADD")
    glow:Hide()
    b.glow = glow
    -- The blink: the icon's alpha bouncing down and back.
    local blink = icon:CreateAnimationGroup()
    blink:SetLooping("BOUNCE")
    local fade = blink:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(UI.BLINK_LOW)
    fade:SetDuration(UI.BLINK_PERIOD)
    b.blink = blink
    local count = GC.Glass.Font(b, 11, "CENTER")
    count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b.count = count
    b:SetScript("OnEnter", function(self)
        self.hovered = true
        paint(self)
        local tip = rawget(_G, "GameTooltip")
        if tip then
            tip:SetOwner(self, "ANCHOR_TOP")
            tip:SetText(Spam.IsDebug() and "Blocked lines (debug)" or "Hidden lines")
            tip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.hovered = false
        paint(self)
        local tip = rawget(_G, "GameTooltip")
        if tip then tip:Hide() end
    end)
    b:SetScript("OnClick", function() UI.Open() end)
    buttons[f] = b
    paint(b)
end

--------------------------------------------------------------------------------
-- /gchat subcommands
--------------------------------------------------------------------------------

local say = API.Print

local function mute(arg)
    if arg == "" then say("/gchat mute <phrase>  (~phrase also catches tricks like p r 0 f e s s i o n)"); return end
    local aggressive = arg:sub(1, 1) == "~"
    local phrase = aggressive and arg:sub(2):match("^%s*(.-)%s*$") or arg
    local form = aggressive and GC.SpamText.Aggressive(phrase) or GC.SpamText.Visible(phrase)
    if form == "" then say("that phrase has nothing to match on"); return end
    if #phrase > Spam.MUTE_MAX then say("that phrase is too long (at most " .. Spam.MUTE_MAX .. " bytes)"); return end
    for _, m in ipairs(Spam.db.mutes) do
        if m.phrase:lower() == phrase:lower() and (m.aggressive or false) == aggressive then
            say("already muted: " .. phrase); return
        end
    end
    table.insert(Spam.db.mutes, { phrase = phrase, aggressive = aggressive or nil })
    Spam.RebuildMutes()
    say("muted" .. (aggressive and " (tricks too)" or "") .. ": " .. phrase)
end

-- "~phrase" unmutes the aggressive rule, "phrase" the literal one: they're
-- separate rules, as in mute's duplicate check (Codex review of #20).
local function unmute(arg)
    local aggressive = arg:sub(1, 1) == "~"
    local phrase = aggressive and arg:sub(2):match("^%s*(.-)%s*$") or arg
    for i, m in ipairs(Spam.db.mutes) do
        if m.phrase:lower() == phrase:lower() and (m.aggressive or false) == aggressive then
            table.remove(Spam.db.mutes, i)
            Spam.RebuildMutes()
            say("unmuted: " .. (aggressive and "~" or "") .. m.phrase)
            return
        end
    end
    say((aggressive and "~" or "") .. phrase .. " isn't muted")
end

local function mutes()
    if #Spam.db.mutes == 0 then say("no muted phrases (/gchat mute <phrase>)"); return end
    for _, m in ipairs(Spam.db.mutes) do say("muted: " .. (m.aggressive and "~" or "") .. m.phrase) end
end

local function ignores()
    local any = false
    for guid, e in pairs(Spam.db.ignore) do
        any = true
        local own = Spam.IsOwn(guid) and " |cffff6060(one of your own characters: skipped, /gchat unignore it)|r" or ""
        say("ignored: " .. e.name .. own)
    end
    for l, e in pairs(Spam.db.pending) do
        any = true
        local own = Spam.OwnByName(l) and " |cffff6060(one of your own characters: skipped, /gchat unignore it)|r" or ""
        say("ignored (pending): " .. e.name .. own)
    end
    for key, name in pairs(GC.SpamMirror.Failed()) do
        local what = key:sub(1, 4) == "add:" and "added to" or "removed from"
        say("|cffffd100" .. name .. ": couldn't be " .. what .. " Blizzard's ignore list on this character" ..
            (what == "added to" and " (full, or not found); still ignored in chat|r" or "|r"))
    end
    if not any then say("no one ignored (/gchat ignore <First Surname>)") end
end

local function ignore(arg)
    local mirror = (arg == "mirror" and "") or arg:match("^mirror (on)$") or arg:match("^mirror (off)$")
    if mirror then
        if mirror == "on" or mirror == "off" then Spam.db.mirror = mirror == "on" end
        say("Blizzard's ignore list kept in step on each character: " .. (Spam.db.mirror and "on" or
            "off (lists are left as they are)") .. " (/gchat ignore mirror on|off)")
        GC.SpamMirror.Check("setting")
        return
    end
    if arg == "import" then say(Spam.Import()); GC.SpamMirror.Check("import"); return end
    -- S3: the lists to your other accounts (GC.SpamSync).
    if arg == "send" then GC.SpamSync.Send(); return end
    if arg == "send empty" then GC.SpamSync.Send(true); return end
    local sync = (arg == "sync" and "") or arg:match("^sync (%a+)$")
    if sync then GC.SpamSync.Command(sync); return end
    if arg == "" then ignores(); return end
    say(Spam.Ignore(arg))
    GC.SpamMirror.Check("ignore")
end

local function allow(arg)
    if arg == "" then say("/gchat allow <First Surname>: never hide their lines (heuristics only)"); return end
    local guid, shown = Spam.Resolve(arg)
    if not guid then say("I haven't seen " .. arg .. " in chat yet; target them, or wait for a line"); return end
    Spam.db.allow[guid] = { name = shown }
    say("allowed: " .. shown)
end

local function spam(arg)
    local cmd, rest = arg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "log" then
        UI.Open()
    elseif cmd == "cjk" then
        if rest == "on" or rest == "off" then Spam.db.cjk = rest == "on" end
        say("CJK posts in public chat: " .. (Spam.db.cjk and "hidden" or "shown"))
    elseif cmd == "repeat" then
        local m = tonumber(rest)
        if m and m == m and m >= 0 and m <= 60 then Spam.db.repeatWindow = math.floor(m * 60) end
        say(string.format("repeats hidden for %g minute(s) after a post", Spam.db.repeatWindow / 60))
    elseif cmd == "debug" then
        if rest == "on" or rest == "off" then Spam.db.debug = rest == "on" end
        say("debug log: " .. (Spam.IsDebug() and "on" or "off") .. " (the icon changes after /reload)")
    elseif cmd == "icon" then
        if rest == "on" or rest == "off" then
            Spam.db.icon = rest == "on"
            GC.Skin.ReserveIcons(GC.Skin.CORE_ICONS + (Spam.db.icon and 1 or 0))
            GC.Chat.Scan()
        end
        say("tab-strip icon: " .. (Spam.db.icon and "shown" or "hidden") .. " (/gchat spam icon on|off)")
    elseif cmd == "test" then
        local reason = Spam.Judge("CHAT_MSG_CHANNEL", rest, "Test Sender", "Player-0-TEST", true)
        say("test: " .. (reason and ("hidden (" .. reason .. ")") or "shown"))
    else
        say("/gchat spam log - what was hidden")
        say("/gchat spam icon on|off - a tab-strip icon that opens it (" .. (Spam.db.icon and "shown" or "hidden") .. ")")
        say("/gchat spam cjk on|off - CJK posts in public chat (" .. (Spam.db.cjk and "hidden" or "shown") .. ")")
        say(string.format("/gchat spam repeat <minutes> - repeat window (%g)", Spam.db.repeatWindow / 60))
        say("/gchat spam test <text> - would a public line be hidden?")
        say("/gchat spam debug on|off - the debug log and bug icon (on until the release)")
    end
end

function UI.Start()
    GC.Skin.ReserveIcons(GC.Skin.CORE_ICONS + (Spam.db.icon and 1 or 0))
    GC.Chat.OnEachFrame("spam icon", UI.Button)
    Spam.onHidden = UI.Blocked
    GC.RegisterSlash("mute", mute)
    GC.RegisterSlash("unmute", unmute)
    GC.RegisterSlash("mutes", mutes)
    GC.RegisterSlash("ignore", ignore)
    GC.RegisterSlash("unignore", function(arg) say(Spam.Unignore(arg)); GC.SpamMirror.UnignoreHere(arg) end)
    GC.RegisterSlash("ignores", ignores)
    GC.RegisterSlash("allow", allow)
    GC.RegisterSlash("spam", spam, {
        "/gchat mute|unmute <phrase>, /gchat mutes - muted phrases in public chat",
        "/gchat ignore|unignore <First Surname>, /gchat ignores, /gchat ignore import - on all your characters",
        "/gchat ignore mirror on|off - keep Blizzard's ignore list in step (blocks invites and duels too)",
        "/gchat ignore send - copy these lists to your other WoW accounts online; /gchat ignore sync - its status",
        "/gchat allow <First Surname> - never hide their lines",
        "/gchat spam - repeats, CJK, the log, a test",
    })
    GC.Chat.Scan()
end

UI._test = { buttons = buttons }
