-- The options page (#127): registered at PLAYER_LOGIN with its sub-pages in
-- order, each hidden at creation and built on its first show, every value
-- re-read on each show, every control through GC.Settings.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Blizzard's Settings framework (Settings.Register*, OpenToCategory: in the dump).
local reg = { subs = {} }
rawset(_G, "Settings", {
    RegisterCanvasLayoutCategory = function(frame, name)
        reg.main = { frame = frame, name = name, GetID = function() return 7 end }
        return reg.main
    end,
    RegisterAddOnCategory = function(c) reg.addon = c end,
    RegisterCanvasLayoutSubcategory = function(c, frame, name) reg.subs[#reg.subs + 1] = name end,
    OpenToCategory = function(id) reg.opened = id end,
})

local GC = loadAddon()
local O = GC.Options
local function slash(s) SlashCmdList.GLASSCHAT(s) end

-- Widgets by their label, on one page.
local function inside(w, frame)
    while w do
        if w == frame then return true end
        w = w._parent
    end
end
local function find(page, kind, text)
    for _, w in ipairs(WoW.frames) do
        if inside(w, page.frame) then
            local l = (kind == "CheckButton" and w.label) or (kind == "Radio" and w.text) or (kind == "Slider" and w.label)
            local t = kind == "Radio" and w._template == "UIRadioButtonTemplate" or w._type == kind
            if kind == "Button" then l, t = w, w._type == "Button" and w._template == "UIPanelButtonTemplate" end
            if t and l and l:GetText() == text then return w end
        end
    end
    error("no " .. kind .. " " .. text, 2)
end
local function click(b, checked)
    if checked ~= nil then b:SetChecked(checked) end
    b._scripts.OnClick(b)
end
local function show(page) page.frame:Hide(); page.frame:Show() end

-- Registered once, in order: the core's pages, the plugin's, then About.
eq(reg.main.name, "Glass Chat", "the main page registered")
eq(reg.addon, reg.main, "  as an AddOns category")
eq(table.concat(reg.subs, ","), "Look,Alerts,Spam & Ignore,About", "sub-pages in order, About last")
check(not O._test.main.frame:IsShown(), "hidden at creation (a page created shown is blank the first time)")

-- The main page.
local main = O._test.main
show(main)
check(main.built, "built on its first show")
local keep = find(main, "CheckButton", "Keep player chat across reloads and logins (never addon lines)")
check(not keep:GetChecked(), "a checkbox shows the setting")
click(keep, true)
check(GC.db.keep, "  and sets it through GC.Settings")
slash("keep off")
show(main)
check(not keep:GetChecked(), "a /gchat change shows on the next show")
local lines = find(main, "Slider", "Lines kept per chat window")
eq(lines:GetValue(), GC.db.lines, "a slider shows the setting")
lines._scripts.OnValueChanged(lines, 2050)
eq(GC.db.lines, 2100, "  and sets it, on its step")
eq(lines.valueText:GetText(), "2100", "  with its value beside")

-- Look: a refresh never saves a value back (an unset alpha stays unset:
-- over Glass UI's bodies, set and unset differ).
local look = O.lookPage
show(look)
eq(rawget(GC.db, "alpha"), nil, "showing the page saves nothing")
local alpha = find(look, "Slider", "Reading area and input")
alpha:SetValue(0.5)   -- the client fires OnValueChanged
eq(rawget(GC.db, "alpha"), 0.5, "the darkness slider sets it")
click(find(look, "Button", "Reset"))
eq(rawget(GC.db, "alpha"), nil, "  Reset unsets it")
eq(alpha:GetValue(), GC.db.alpha, "  and the slider follows")
local smoked = find(look, "Radio", "Smoked")
click(smoked)
eq(GC.db.body, "smoked", "a body radio sets the body")
check(smoked:GetChecked() and not find(look, "Radio", "Clear"):GetChecked(), "  one checked")
slash("body chat")
show(look)
check(find(look, "Radio", "Charcoal"):GetChecked(), "  a /gchat body shows")
local rim = find(look, "Slider", "Rim")
rim._scripts.OnValueChanged(rim, 0.5)
eq(GC.Skin.Look("rim"), 0.5, "a fine-tuning slider")
click(find(look, "Button", "Reset fine tuning"))
eq(GC.Skin.Look("rim"), GC.Skin.LOOK.rim, "  and its reset")

-- Alerts.
local alerts = O.alertsPage
show(alerts)
click(find(alerts, "Radio", "Ready check"))
eq(GC.db.alertSound, "ready", "a sound radio sets the sound")
eq(WoW.sounds[#WoW.sounds].kit, GC.Alerts.SOUNDS.ready, "  and plays a sample")
local W = O._test.words
W.box:SetText("raid tonight")
W.box._scripts.OnEnterPressed(W.box)
eq(GC.Alerts.Words()[1], "raid tonight", "a word added from the box")
check(W.rows[1].remove:IsShown() and not W.rows[2].remove:IsShown(), "  its row shown, the others not")
eq(W.status:GetText(), "alert on: raid tonight", "  and said")
click(W.rows[1].remove)
eq(#GC.Alerts.Words(), 0, "Remove takes it out")

-- Spam & Ignore, the plugin's page.
local spam = O._test.pages[3]
show(spam)
local cjk = find(spam, "CheckButton", "Hide Chinese, Japanese and Korean posts")
click(cjk, false)
eq(GC.Spam.db.cjk, false, "the plugin's page sets its settings")
local rep = find(spam, "Slider", "Hide a repeated post for (minutes)")
rep._scripts.OnValueChanged(rep, 10)
eq(GC.Spam.db.repeatWindow, 600, "  the repeat window in minutes")

-- About: the commands /gchat help prints.
show(O._test.about)
local about = O._test.aboutLines
eq(#about, #GC.HelpLines(), "About lists every command /gchat help prints")
check(about[1]:GetText():find("^/gchat options") ~= nil, "  /gchat options first")

slash("options")
eq(reg.opened, 7, "/gchat options opens it")

eq(next(GC.failures), nil, "no failures")
done("test_options")
