-- Options.lua (#127): the page in Esc > Options > AddOns > Glass Chat, with
-- sub-pages, built with the porting guide's measured recipe ("An Options
-- page with sub-pages and an About page"), as the sibling Glass addons do:
-- - each page a plain Frame with .name, hidden at creation (or its first
--   visit is blank), its controls built on the first OnShow, every value
--   re-read on every OnShow, so a /gchat change never shows stale;
-- - registered once at PLAYER_LOGIN, the sub-pages right after the main
--   page, in order: the core's, then the plugins' (Options.AddPage, before
--   PLAYER_LOGIN), then About;
-- - choices are radio groups, never dropdowns; the slider is GlassUnitFrames'
--   hand-built one.
--
-- Every control writes through GC.Settings (or the module's own function,
-- as /gchat does), never a saved table directly: no new state. Each page
-- scrolls (the Settings canvas is a fixed size), GlassActionBars' recipe.

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local Options = {}
GC.Options = Options

Options.WIDTH = 560          -- the scroll content's width
Options.ACROSS = { 200, 100 }   -- a radio row: the first button, then every step (px)
local RADIO_ART = "Interface\\Buttons\\UI-RadioButton"   -- 4 cells: normal, checked, highlight, pushed

local building = {}          -- the refresh list of the page being built
local refreshing = false     -- a refresh sets values: their scripts must not save them back

local function label(parent, text, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    fs:SetText(text or "")
    return fs
end

-- A column of controls, top to bottom: col = { parent, y }.
local function place(col, w, h, gap, x)
    gap = gap or 4
    w:SetPoint("TOPLEFT", col.parent, "TOPLEFT", x or 0, -(col.y + gap))
    col.y = col.y + gap + h
end

--------------------------------------------------------------------------------
-- Controls (used by the plugins' pages too)
--------------------------------------------------------------------------------

function Options.Heading(col, text)
    local fs = label(col.parent, text, "GameFontNormal")
    place(col, fs, 16, col.y == 0 and 4 or 18)
    return fs
end

-- A wrapped text's height as drawn, or nil before the client can tell.
local function textHeight(fs)
    local h = fs:GetStringHeight()
    if API.IsSecret(h) or type(h) ~= "number" or h <= 0 then return nil end
    return h
end

-- A line of small text, wrapped at the page's width. It takes the room its
-- text takes as drawn, at least `lines` lines (for a text set later).
function Options.Note(col, text, lines)
    local fs = label(col.parent, text, "GameFontHighlightSmall")
    fs:SetWidth(Options.WIDTH)
    fs:SetJustifyH("LEFT")
    place(col, fs, math.max(13 * (lines or 1), textHeight(fs) or 0), 4)
    return fs
end

-- An on/off setting: our own label beside the template's box.
function Options.Check(col, text, get, set)
    local cb = CreateFrame("CheckButton", nil, col.parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    place(col, cb, 24, 2)
    cb.label = label(col.parent, text)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    local function sync() cb:SetChecked(get() == true) end
    cb:SetScript("OnClick", function() set(cb:GetChecked() == true); sync() end)
    building[#building + 1] = sync
    return cb
end

-- A labelled radio button: UIRadioButtonTemplate when the client has it (its
-- own label, rb.text, takes the text), else the client's own radio art and a
-- label of ours (GlassActionBars').
local function radioButton(parent, text)
    local rb, templated = API.SafeFrame("CheckButton", parent, "UIRadioButtonTemplate", "text")
    if templated then
        rb.text:SetFontObject("GameFontHighlight")
        rb.text:SetText(text)
        return rb
    end
    rb:SetSize(16, 16)
    rb:SetNormalTexture(RADIO_ART)
    rb:GetNormalTexture():SetTexCoord(0, 0.25, 0, 1)
    rb:SetCheckedTexture(RADIO_ART)
    rb:GetCheckedTexture():SetTexCoord(0.25, 0.5, 0, 1)
    rb:SetHighlightTexture(RADIO_ART)
    rb:GetHighlightTexture():SetTexCoord(0.5, 0.75, 0, 1)
    rb:GetHighlightTexture():SetBlendMode("ADD")
    label(parent, text):SetPoint("LEFT", rb, "RIGHT", 4, 0)
    return rb
end

-- Mutually exclusive choices in a row after `text`: { {value, text}, ... }.
-- The whole group re-syncs after a click, so a refused choice snaps back.
-- Returns the buttons and the row's label.
function Options.Radios(col, text, choices, get, set, across)
    across = across or Options.ACROSS
    local name = label(col.parent, text)
    place(col, name, 20, 6)
    local group = {}
    local function sync()
        local current = get()
        for i, rb in ipairs(group) do rb:SetChecked(choices[i][1] == current) end
    end
    for i, c in ipairs(choices) do
        local rb = radioButton(col.parent, c[2])
        rb:SetPoint("LEFT", name, "LEFT", across[1] + (i - 1) * across[2], 0)
        rb:SetScript("OnClick", function() set(c[1]); sync() end)
        group[i] = rb
    end
    building[#building + 1] = sync
    return group, name
end

-- GlassUnitFrames' slider: the label and the value on one line, the track
-- under it. t = { min, max, step, fmt, get, set }.
local SLIDER_W = 240
function Options.Slider(col, text, t)
    local step = t.step or 0.05
    local fmt = t.fmt or "%.2f"
    local name = label(col.parent, text)
    place(col, name, 16, 8)
    local value = label(col.parent, "")
    value:SetPoint("LEFT", name, "LEFT", SLIDER_W + 12, -22)
    local s = CreateFrame("Slider", nil, col.parent)
    s:SetSize(SLIDER_W, 16)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(t.min, t.max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", s, "LEFT", 0, 0)
    track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    track:SetHeight(6)
    track:SetColorTexture(0.25, 0.25, 0.3, 0.9)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    place(col, s, 16, 4)
    s.label, s.valueText = name, value
    s:SetScript("OnValueChanged", function(_, v)
        if API.IsSecret(v) or type(v) ~= "number" then return end
        v = math.floor(v / step + 0.5) * step
        value:SetText(fmt:format(v))
        if refreshing then return end
        t.set(v)
    end)
    building[#building + 1] = function()
        local v = t.get()
        s:SetValue(v)
        value:SetText(fmt:format(v))
    end
    return s
end

-- A button at the column's left, or beside `beside` when given.
function Options.Button(col, text, width, onClick, beside)
    local b = API.Button(col.parent, text, width, onClick)
    if beside then b:SetPoint("LEFT", beside, "RIGHT", 12, 0) else place(col, b, 22, 8) end
    return b
end

-- A function run on every show of the page being built (a count, a list).
function Options.OnRefresh(fn) building[#building + 1] = fn end

-- Every control on a page re-read (one change moves others: a reset).
function Options.Refresh(page)
    refreshing = true
    for _, fn in ipairs(page.refreshers) do
        local ok, err = pcall(fn)
        if not ok then API.Fail("options refresh " .. page.frame.name, err) end
    end
    refreshing = false
end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

-- A scrolling column under the title (GlassActionBars' scrollArea).
local function scrollArea(frame, anchor)
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(Options.WIDTH, 1)
    scroll:SetScrollChild(content)
    if scroll.ScrollBar then API.AutoHideScrollBar(scroll) end
    return content
end

local function newPage(name, title, build)
    local frame = CreateFrame("Frame")
    frame.name = name
    frame:Hide()
    local page = { frame = frame, refreshers = {}, built = false }
    frame:SetScript("OnShow", function()
        if not page.built then
            page.built = true
            local head = label(frame, title, "GameFontNormalHuge")
            head:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
            local content = scrollArea(frame, head)
            local col = { parent = content, y = 0 }
            building = page.refreshers
            local ok, err = pcall(build, col, page)
            if not ok then API.Fail("options " .. name, err) end
            content:SetHeight(col.y + 16)
            page.col = col
        end
        Options.Refresh(page)
    end)
    return page
end

local main
local pages, about = {}, nil   -- sub-pages in order; About last
local category

-- A plugin's page, under ours (before PLAYER_LOGIN). build(col, page).
function Options.AddPage(name, build)
    local page = newPage(name, name, build)
    pages[#pages + 1] = page
    return page
end

local function sv(key) return function() return GC.db[key] end end
local function set(name) return function(v) GC.Settings[name](v) end end

--------------------------------------------------------------------------------
-- The main page: the chat itself
--------------------------------------------------------------------------------

function Options.VersionText()
    local v = API.AddOnVersion("GlassChat")
    if not v or v == "" or v:find("@project%-version@") then return "dev" end
    return v
end

main = newPage("Glass Chat", "Glass Chat", function(col)
    local version = Options.Note(col, "")
    building[#building + 1] = function()
        version:SetText("Version " .. Options.VersionText() .. " for World of Warcraft: Forever, by Spotnick")
    end
    Options.Heading(col, "Chat")
    Options.Check(col, "Class-coloured names", sv("classColors"), set("SetClassColors"))
    Options.Check(col, "Player levels before their name, once seen: [60:Name]", sv("levels"), set("SetLevels"))
    Options.Check(col, "Short channel names: [1. General] without the zone", sv("shortChannels"), set("SetShortChannels"))
    Options.Check(col, "Click a web address to copy it", sv("urls"), set("SetUrls"))
    Options.Check(col, "A time on every line, addon output too", sv("timestamps"), set("SetTimestamps"))
    Options.Check(col, "Keep player chat across reloads and logins (never addon lines)", sv("keep"), set("SetKeep"))
    Options.Heading(col, "Typing")
    Options.Check(col, "Up/Down recall what you sent, without Alt", sv("plainArrows"), set("SetPlainArrows"))
    Options.Slider(col, "Sent lines kept, per character", { min = GC.History.MIN, max = GC.History.MAX, step = 10,
        fmt = "%d", get = sv("history"), set = set("SetHistory") })
    Options.Heading(col, "Windows and tabs")
    Options.Slider(col, "Lines kept per chat window", { min = GC.Chat.MIN_LINES, max = GC.Chat.MAX_LINES, step = 100,
        fmt = "%d", get = sv("lines"), set = set("SetLines") })
    Options.Slider(col, "Tab name size (fits fully after a /reload)", { min = 10, max = 20, step = 1, fmt = "%d",
        get = sv("tabSize"), set = set("SetTabSize") })
    Options.Check(col, "An open tab named after an addon catches its lines", sv("tabsCatch"), set("SetTabsCatch"))
    Options.Note(col, "Chatty addons are offered their own tab in chat; /gchat tabs lists your choices.")
    Options.Note(col, "Type /gchat help for every command.")
end)

--------------------------------------------------------------------------------
-- Look
--------------------------------------------------------------------------------

Options.BODIES = { { "clear", "Clear" }, { "smoked", "Smoked" }, { "class", "Class" }, { "chat", "Charcoal" } }
Options.ACCENTS = { { "gold", "Gold" }, { "ice", "Ice" } }
Options.TUNE = {
    { "rim", "Rim" }, { "top", "Top edge line" }, { "glow", "Sheen under it" }, { "glowh", "Sheen height (px)" },
    { "bottom", "Bottom edge line" }, { "dark", "Lower shading" }, { "grain", "Frost" }, { "shadow", "Drop shadow" },
}

-- A Glass UI choice first while following: it is selected whenever the
-- player hasn't set their own (by source, not value), as /gchat body suite.
local function lookRadios(col, text, key, choices, setter)
    local S = GC.Suite
    local following = S.Following()
    local list = {}
    if following then list[1] = { "suite", "Glass UI's" } end
    for _, c in ipairs(choices) do list[#list + 1] = c end
    local function current() return key == "tint" and S.Tint() or S.AccentName() end
    return Options.Radios(col, text, list, function()
        if following and S.Own(key) == nil then return "suite" end
        return current()
    end, function(v)
        if following then S.SetOwn(key, v) else setter(v) end
    end, following and { 140, 90 } or nil)
end

Options.lookPage = Options.AddPage("Look", function(col, page)
    local S = GC.Suite
    Options.Heading(col, "The glass")
    Options.Check(col, "Glass panels (off: Blizzard's own chat background)", sv("glass"), set("SetGlass"))
    if S.Following() then
        local note = Options.Note(col, "Following Glass UI's look: its body and accent, live. A choice of your own "
            .. "below is for the chat alone; \"Glass UI's\" follows it again.", 2)
        local suite = rawget(_G, "GlassUI") and rawget(GlassUI, "Suite")
        if type(suite) == "table" and type(rawget(suite, "Open")) == "function" then
            Options._test.openSuite = Options.Button(col, "Open Glass UI", 140, function() pcall(suite.Open) end)
        end
        Options._test.suiteNote = note
    end
    Options._test.body = lookRadios(col, "Body", "tint", Options.BODIES, GC.Settings.SetBody)
    Options._test.accent = lookRadios(col, "Selected tab", "accent", Options.ACCENTS, GC.Settings.SetAccent)
    Options.Heading(col, "Darkness")
    local alpha = Options.Slider(col, "Reading area and input", { min = 0, max = 1, get = sv("alpha"),
        set = set("SetAlpha") })
    Options.Button(col, "Reset", 80, function() GC.Settings.ResetAlpha(); Options.Refresh(page) end, alpha.valueText)
    Options.Slider(col, "Tab strip and buttons", { min = 0, max = 1, get = sv("shellAlpha"), set = set("SetShellAlpha") })
    Options.Slider(col, "With nothing to read (1: never fades)", { min = 0, max = 1, get = sv("idleAlpha"),
        set = set("SetIdleAlpha") })
    Options.Heading(col, "Fine tuning")
    Options.Note(col, "The window's edges and sheen, as /gchat tune sets them.")
    for _, t in ipairs(Options.TUNE) do
        local key = t[1]
        local max = GC.Skin.LOOK_MAX[key] or 1
        Options.Slider(col, t[2], { min = 0, max = max, step = max > 1 and 1 or 0.01, fmt = max > 1 and "%d" or "%.2f",
            get = function() return GC.Skin.Look(key) end, set = function(v) GC.Settings.SetLook(key, v) end })
    end
    Options.Button(col, "Reset fine tuning", 160, function() GC.Settings.ResetLook(); Options.Refresh(page) end)
end)

--------------------------------------------------------------------------------
-- Alerts
--------------------------------------------------------------------------------

Options.NAMES = { { "first", "First name" }, { "full", "First Surname" }, { "off", "Off" } }
Options.SOUNDS = { { "lfg", "LFG" }, { "raid", "Raid warning" }, { "ready", "Ready check" }, { "tell", "Whisper" },
    { "off", "Off" } }

Options.alertsPage = Options.AddPage("Alerts", function(col, page)
    local A = GC.Alerts
    Options.Check(col, "A sound when public, guild or group chat mentions you or your words", sv("alerts"),
        set("SetAlerts"))
    Options.Radios(col, "Your name", Options.NAMES, sv("alertName"), set("SetAlertName"), { 120, 120 })
    local _, row = Options.Radios(col, "Sound", Options.SOUNDS, sv("alertSound"), function(v)
        GC.Settings.SetAlertSound(v)
        A.Play(v)   -- a sample, as /gchat alert sound
    end, { 100, 110 })
    Options._test.soundRow = row
    Options.Check(col, "Blink the game in the taskbar", sv("alertFlash"), set("SetAlertFlash"))
    Options.Check(col, "The whisper sound on every whisper (the game's own waits 5 minutes between two)",
        sv("whisperSound"), set("SetWhisperSound"))

    Options.Heading(col, "Your words, on all your characters")
    local box = CreateFrame("EditBox", nil, col.parent)
    box:SetSize(260, 22)
    box:SetAutoFocus(false)
    box:SetFontObject("ChatFontNormal")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetMaxLetters(A.MAX_WORD)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(box)
    bg:SetColorTexture(0, 0, 0, 0.5)
    place(col, box, 22, 8)
    local status = Options.Note(col, "")
    local rows = {}
    local function sync()
        local list = A.Words()
        for i, r in ipairs(rows) do
            r.word = list[i]
            r.text:SetText(list[i] or "")
            r.text:SetShown(list[i] ~= nil)
            r.remove:SetShown(list[i] ~= nil)
        end
    end
    local function add()
        local _, msg = A.AddWord(box:GetText())
        status:SetText(msg)
        box:SetText("")
        sync()
    end
    box:SetScript("OnEnterPressed", add)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Options.Button(col, "Add", 80, add, box)
    for i = 1, A.MAX_WORDS do
        local r = {}
        r.text = label(col.parent, "")
        place(col, r.text, 20, 2, 4)
        r.remove = API.Button(col.parent, "Remove", 80, function()
            if r.word then
                local _, msg = A.RemoveWord(r.word)
                status:SetText(msg)
            end
            sync()
        end)
        r.remove:SetPoint("LEFT", r.text, "LEFT", 260, 0)
        rows[i] = r
    end
    building[#building + 1] = function() status:SetText(""); sync() end
    Options._test.words = { box = box, rows = rows, status = status }
end)

--------------------------------------------------------------------------------
-- About, and registering
--------------------------------------------------------------------------------

about = newPage("About", "Glass Chat", function(col)
    Options.Note(col, "A small, glass-styled chat for World of Warcraft: Forever.")
    local version = Options.Note(col, "")
    building[#building + 1] = function() version:SetText("Version " .. Options.VersionText() .. ", by Spotnick") end
    Options.Heading(col, "How to use")
    Options.Note(col, "Focus mode (the magnifier on the tab strip, or /gchat focus) freezes a window to search, "
        .. "filter, copy and export. The Copy button copies a window. Click an addon's [Name] in chat for only its "
        .. "lines, right-click it for its own tab. Click a web address to copy it.", 3)
    -- One wrapped block, its height its text's: a long command wraps without
    -- running into the next (owner's screenshot).
    Options.Heading(col, "Commands")
    local commands = Options.Note(col, "")
    commands:SetSpacing(3)
    local top = col.y - 13
    Options._test.aboutCommands = commands
    building[#building + 1] = function()
        local help = GC.HelpLines()
        commands:SetText(table.concat(help, "\n"))
        local h = textHeight(commands) or #help * 16
        commands:SetHeight(h)
        col.parent:SetHeight(top + h + 16)
    end
end)

function Options.Register()
    local S = rawget(_G, "Settings")
    if category or type(S) ~= "table" or not (S.RegisterCanvasLayoutCategory and S.RegisterAddOnCategory) then return end
    local ok, c = pcall(S.RegisterCanvasLayoutCategory, main.frame, main.frame.name)
    if not ok or not c then API.Fail("options", c); return end
    category = c
    local okA, err = pcall(S.RegisterAddOnCategory, category)
    if not okA then API.Fail("options", err) end
    -- Gnomesweeper's measured order: the main page, then its sub-pages.
    if S.RegisterCanvasLayoutSubcategory then
        local list = {}
        for _, p in ipairs(pages) do list[#list + 1] = p end
        list[#list + 1] = about
        for _, p in ipairs(list) do
            local okS, errS = pcall(S.RegisterCanvasLayoutSubcategory, category, p.frame, p.frame.name)
            if not okS then API.Fail("options " .. p.frame.name, errS) end
        end
    end
end

-- Open the page; false when the Settings framework can't.
function Options.Open()
    local S = rawget(_G, "Settings")
    if not (category and type(S) == "table" and S.OpenToCategory) then return false end
    return pcall(S.OpenToCategory, category:GetID()) and true or false
end

function Options.Start()
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function()
        local ok, err = pcall(Options.Register)
        if not ok then API.Fail("options", err) end
    end)
    API.RegisterEvents(f, { "PLAYER_LOGIN" })
end

Options._test = { main = main, about = about, pages = pages }
