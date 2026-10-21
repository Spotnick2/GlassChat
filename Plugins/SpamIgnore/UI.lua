-- UI.lua (Spam & Ignore): the icon, the hidden-lines window, and the /gchat
-- subcommands.
--
-- The icon is OPT-IN (owner: "make it a setting ... disabled by default"):
-- /gchat spam icon on. It's a side button beside the chat (GC.Buttons.Side,
-- #86), just above the alerts button, with a count of lines hidden since you
-- last looked: gold at rest, green and pulsing while they wait. In a dev or test build it's
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

local function hasAtlas(name)
    local get = C_Texture and C_Texture.GetAtlasInfo
    if not get then return false end
    local ok, info = pcall(get, name)
    return ok and info ~= nil and not API.IsSecret(info)
end

-- A line was just hidden, or the count was cleared: repaint (green and
-- pulsing while lines wait).
function UI.PaintAll() GC.Buttons.PaintSide("spam") end
UI.Blocked = UI.PaintAll

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

-- The symbol is chosen once, when the button is first built: a bug in a dev
-- or debug build, else the eye (a plain square on a client without it).
local function symbol()
    if Spam.IsDebug() then return { texture = UI.BUG } end
    if hasAtlas(UI.EYE) then return { atlas = UI.EYE } end
    return { texture = "Interface\\Buttons\\WHITE8X8" }
end

function UI.RegisterIcon()
    local opts = symbol()
    opts.order = 2   -- above the alerts button
    opts.tooltip = function() return Spam.IsDebug() and "Blocked lines (debug)" or "Hidden lines" end
    opts.count = function() return Spam.unseen end
    opts.shown = function() return Spam.db.icon end
    opts.onClick = function() UI.Open() end
    GC.Buttons.Side("spam", opts)
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
    Spam.Edited("added")
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
            Spam.Edited("removed")
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
        if mirror == "on" or mirror == "off" then UI.Set.mirror(mirror == "on") else GC.SpamMirror.Check("setting") end
        say("Blizzard's ignore list kept in step on each character: " .. (Spam.db.mirror and "on" or
            "off (lists are left as they are)") .. " (/gchat ignore mirror on/off)")
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

-- The settings' setters, shared by the slash commands and settings sync
-- (GC.SettingsSync: a received value goes through the same steps).
UI.Set = {
    cjk = function(on) Spam.db.cjk = on and true or false end,
    repeatWindow = function(seconds) Spam.db.repeatWindow = math.floor(seconds) end,
    icon = function(on)
        Spam.db.icon = on and true or false
        GC.Chat.Scan()
    end,
    mirror = function(on)
        Spam.db.mirror = on and true or false
        GC.SpamMirror.Check("setting")
    end,
    score = function(mode)
        Spam.db.score = mode
        Spam.ResetMemo()   -- earlier decisions were made under the old mode
    end,
}

-- The plugin's section of settings sync (docs/PLAN-SETTINGS.md).
local function registerSettings()
    local SS = GC.SettingsSync
    if not SS then return end
    local function key(k, typ, extra)
        local spec = {
            key = k, type = typ,
            default = function() return Spam.DEFAULTS[k] end,
            get = function() return rawget(Spam.db, k) end,
            set = UI.Set[k],
            clear = function() Spam.db[k] = nil end,
        }
        for f, v in pairs(extra or {}) do spec[f] = v end
        return spec
    end
    SS.Register("spam", {
        key("cjk", "b", { label = "CJK posts hidden" }),
        key("repeatWindow", "i", { lo = 0, hi = Spam.REPEAT_MAX, label = "repeat window (s)" }),
        key("icon", "b", { label = "spam icon" }),
        key("mirror", "b", { label = "Blizzard ignore list kept in step" }),
        key("score", "e", { values = { "off", "watch", "hide" }, label = "spam score" }),
    })
end

local function spam(arg)
    local cmd, rest = arg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "log" then
        UI.Open()
    elseif cmd == "cjk" then
        if rest == "on" or rest == "off" then UI.Set.cjk(rest == "on") end
        say("CJK posts in public chat: " .. (Spam.db.cjk and "hidden" or "shown"))
    elseif cmd == "repeat" then
        local m = tonumber(rest)
        if m and m == m and m >= 0 and m <= Spam.REPEAT_MAX / 60 then UI.Set.repeatWindow(m * 60) end
        say(string.format("repeats hidden for %g minute(s) after a post", Spam.db.repeatWindow / 60))
    elseif cmd == "debug" then
        if rest == "on" or rest == "off" then Spam.db.debug = rest == "on" end
        say("debug log: " .. (Spam.IsDebug() and "on" or "off") .. " (the icon changes after /reload)")
    elseif cmd == "icon" then
        if rest == "on" or rest == "off" then UI.Set.icon(rest == "on") end
        say("icon beside the chat: " .. (Spam.db.icon and "shown" or "hidden") .. " (/gchat spam icon on/off)")
    elseif cmd == "score" then
        local mode = rest:lower()
        if mode == "off" or mode == "watch" or mode == "hide" then
            UI.Set.score(mode)
            say("spam score: " .. mode .. (mode == "watch" and " (logged, still shown: /gchat spam score)" or ""))
            return
        elseif mode ~= "" then   -- never a typo taken for the log (review of #47)
            say("spam score: unknown mode '" .. rest .. "'; use off, watch or hide (now " .. Spam.db.score .. ")")
            return
        end
        local Score = GC.SpamScore
        local text = Score.LogText()
        GC.Copy.Show("Spam score (" .. Spam.db.score .. ")", text ~= "" and text or "nothing scored yet",
            string.format("%d spam, %d near misses; /gchat spam score off/watch/hide", #Score.Log(), #Score.Near()))
    elseif cmd == "collect" then
        local mode = rest:lower()
        if mode == "on" or mode == "off" then
            Spam.db.collect = mode == "on"
        elseif mode == "default" then
            Spam.db.collect = nil   -- the build's default again (review of #59)
        elseif mode == "clear" then
            Spam.db.collected = nil
        elseif mode ~= "" then
            say("spam collect: on, off, default or clear"); return
        end
        local n = type(Spam.db.collected) == "table" and #Spam.db.collected or 0
        local why = rawget(Spam.db, "collect") == nil and "this build's default" or "your setting; /gchat spam collect default undoes it"
        say(string.format("collecting spam lines: %s (%s; %d saved, at most %d; on disk after a full exit, "
            .. "in SavedVariables\\GlassChatSpamIgnore.lua)", Spam.Collecting() and "on" or "off", why, n, Spam.COLLECT_MAX))
    elseif cmd == "test" then
        local reason, scored = Spam.Judge("CHAT_MSG_CHANNEL", rest, "Test Sender", "Player-0-TEST", true)
        local kinds = scored and (" - kinds: " .. GC.SpamScore.Label(scored) .. (scored.spam and ", spam" or "")) or ""
        say("test: " .. (reason and ("hidden (" .. reason .. ")") or "shown") .. kinds)
    else
        say("/gchat spam log - what was hidden")
        say("/gchat spam icon on/off - an icon beside the chat that opens it (" .. (Spam.db.icon and "shown" or "hidden") .. ")")
        say("/gchat spam cjk on/off - CJK posts in public chat (" .. (Spam.db.cjk and "hidden" or "shown") .. ")")
        say(string.format("/gchat spam repeat <minutes> - repeat window (%g)", Spam.db.repeatWindow / 60))
        say("/gchat spam score [off/watch/hide] - the spam score's log, or its mode (" .. Spam.db.score .. ")")
        say("/gchat spam collect on/off/default/clear - keep scored and hidden lines on disk, to tune the score ("
            .. (Spam.Collecting() and "on" or "off") .. ")")
        say("/gchat spam test <text> - would a public line be hidden?")
        say("/gchat spam debug on/off - the debug log and bug icon (on until the release)")
    end
end

-- Its page under Glass Chat's options (#127), added before PLAYER_LOGIN so it
-- registers in order. The lists stay commands.
UI.SCORES = { { "off", "Off" }, { "watch", "Watch" }, { "hide", "Hide" } }
local function optionsPage()
    local O = GC.Options
    if not O then return end
    UI.page = O.AddPage("Spam & Ignore", function(col)
        local function get(k) return function() return Spam.db[k] end end
        O.Heading(col, "Public chat")
        O.Check(col, "Hide Chinese, Japanese and Korean posts", get("cjk"), UI.Set.cjk)
        O.Slider(col, "Hide a repeated post for (minutes)", { min = 0, max = Spam.REPEAT_MAX / 60, step = 1, fmt = "%d",
            get = function() return Spam.db.repeatWindow / 60 end, set = function(m) UI.Set.repeatWindow(m * 60) end })
        O.Radios(col, "Spam score", UI.SCORES, get("score"), UI.Set.score, { 120, 100 })
        O.Note(col, "Watch hides nothing: /gchat spam score lists what it would hide, and why.")
        O.Heading(col, "Ignores")
        O.Check(col, "Keep Blizzard's ignore list in step (blocks invites and duels too)", get("mirror"), UI.Set.mirror)
        O.Check(col, "Copy the lists between your WoW accounts (/gchat ignore send)", GC.AccountSync.IsEnabled,
            GC.AccountSync.SetEnabled)
        local counts = O.Note(col, "")
        O.OnRefresh(function()
            local n = 0
            for _ in pairs(Spam.db.ignore) do n = n + 1 end
            for _ in pairs(Spam.db.pending) do n = n + 1 end
            counts:SetText(n .. " ignored, " .. #Spam.db.mutes .. " muted phrases: /gchat ignores, /gchat mutes")
        end)
        O.Heading(col, "What was hidden")
        O.Check(col, "An icon beside the chat while hidden lines wait", get("icon"), UI.Set.icon)
        O.Button(col, "Show hidden lines", 160, UI.Open)
        O.Note(col, "The lists are commands: /gchat ignore, /gchat mute, /gchat allow. /gchat help lists them all.")
    end)
end

function UI.Start()
    registerSettings()
    optionsPage()
    UI.RegisterIcon()
    Spam.onHidden = UI.Blocked
    GC.RegisterSlash("mute", mute)
    GC.RegisterSlash("unmute", unmute)
    GC.RegisterSlash("mutes", mutes)
    GC.RegisterSlash("ignore", ignore)
    GC.RegisterSlash("unignore", function(arg) say(Spam.Unignore(arg)); GC.SpamMirror.UnignoreHere(arg) end)
    GC.RegisterSlash("ignores", ignores)
    GC.RegisterSlash("allow", allow)
    GC.RegisterSlash("spam", spam, {
        "/gchat mute <phrase>, /gchat unmute <phrase>, /gchat mutes - muted phrases in public chat",
        "/gchat ignore <First Surname>, /gchat unignore <First Surname>, /gchat ignores, /gchat ignore import - on all your characters",
        "/gchat ignore mirror on/off - keep Blizzard's ignore list in step (blocks invites and duels too)",
        "/gchat ignore send - copy these lists to your other WoW accounts online; /gchat ignore sync - its status",
        "/gchat allow <First Surname> - never hide their lines",
        "/gchat spam - repeats, CJK, the spam score, the log, a test",
    })
    GC.Chat.Scan()
end

UI._test = { button = function() return GC.Buttons._test.side("spam") end }
