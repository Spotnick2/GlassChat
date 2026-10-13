-- #83 alerts: your name (first, or First Surname) and your words in public
-- and group chat, a sound and a taskbar flash, at most once per line and per
-- EVERY seconds; the log behind the button beside the chat.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.playerGUID = "Player-1-ME"
WoW.playerName = "Karuzo Elegia"
WoW.now = 100
local GC = loadAddon()
local Alerts = GC.Alerts
local spamDB = GlassChatSpamIgnoreDB

-- Installed after the spam and address filters, on public and group chat only.
local at = {}
for i, fn in ipairs(WoW.messageFilters.CHAT_MSG_CHANNEL) do
    if fn == GC.Spam.Filter then at.spam = i end
    if fn == GC.Url.Filter then at.url = i end
    if fn == Alerts.Filter then at.alerts = i end
end
check(at.alerts and at.spam < at.alerts and at.url < at.alerts, "after Spam & Ignore's filter and the address filter")
check(WoW.messageFilters.CHAT_MSG_WHISPER == nil or not (function()
    for _, fn in ipairs(WoW.messageFilters.CHAT_MSG_WHISPER) do if fn == Alerts.Filter then return true end end
end)(), "never on whispers")
for _, e in ipairs(Alerts.EVENTS) do check(WoW.KNOWN_EVENTS[e], "a real event: " .. e) end

-- Every filter on the event, in order, as ProcessFilters runs them: a true
-- first return hides the line and stops the loop.
local nextLine = 5000
local function post(event, text, sender, guid, lineID, channel)
    nextLine = nextLine + 1
    for _, fn in ipairs(WoW.messageFilters[event] or {}) do
        local hide = fn(ChatFrame1, event, text, sender or "Someone Else", "", channel or "", "", "", 0, 0, "", 0,
            lineID or nextLine, guid or ("Player-1-OTHER" .. nextLine))   -- a new sender each time: never a spam repeat
        if hide then return "hidden" end
    end
end
local SAY, CH, GUILD = "CHAT_MSG_SAY", "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD"
local function sounds() return #WoW.sounds end
local function fresh() Alerts._test.reset(); WoW.now = WoW.now + 60 end

-- The first name, whole word, any case.
for _, t in ipairs({ "karuzo, can you help?", "@Karuzo hi", "KARUZO!", "hey Karuzo Elegia", "is that karuzo's?",
    "“Karuzo”", "Karuzo—please", "ok…karuzo" }) do
    eq(Alerts.Matches(t), true, "your first name: " .. t)
end
for _, t in ipairs({ "Karuzos are cool", "akaruzo", "karuzo2", "Karuzoé", "nothing here" }) do
    eq(Alerts.Matches(t), false, "not your name: " .. t)
end
-- Player links: another "Karuzo" isn't you; a link to you is.
local function plink(name) return "|cffc79c6e|Hplayer:" .. name .. ":1234:GUILD|h[" .. name .. "]|h|r" end
eq(Alerts.Matches("ask " .. plink("Karuzo Othername") .. " about it"), false, "another Karuzo's link isn't you")
eq(Alerts.Matches("ask " .. plink("Karuzo Elegia") .. " about it"), true, "a link to you is")
eq(Alerts.Matches("ask " .. plink("Karuzo Elegia-Doomhowl") .. " now"), true, "with your own realm too")
eq(Alerts.Matches("ask " .. plink("Karuzo Elegia-Otherrealm") .. " now"), false, "your name on another realm isn't you")
eq(Alerts.Matches("kar" .. plink("Bob Smith") .. "uzo"), false, "a dropped link leaves a space: nothing joins")
eq(Alerts.Matches("||Hplayer:Bob Smith|h[karuzo]|h"), true, "an escaped pipe isn't a link: the text is read as typed")

-- Full name mode.
GC.Settings.SetAlertName("full")
eq(Alerts.Matches("karuzo, help"), false, "full: the first name alone isn't enough")
eq(Alerts.Matches("hey  karuzo   elegia!"), true, "full: First Surname, any spacing")
GC.Settings.SetAlertName("off")
eq(Alerts.Matches("karuzo elegia"), false, "off: no name")
GC.Settings.SetAlertName("bogus")
eq(GC.db.alertName, "off", "a bad choice is refused by the setter")
GC.Settings.SetAlertName("first")

-- Your words.
SlashCmdList.GLASSCHAT("alert add   Onyxia   Hide ")
eq(GC.db.alertWords[1], "onyxia hide", "a phrase, whole, trimmed, lower-cased")
SlashCmdList.GLASSCHAT("alert add onyxia hide")
eq(#GC.db.alertWords, 1, "no duplicates")
SlashCmdList.GLASSCHAT("alert add " .. string.rep("x", Alerts.MAX_WORD + 1))
eq(#GC.db.alertWords, 1, "too long: refused, not cut")
SlashCmdList.GLASSCHAT("alert add    ")
eq(#GC.db.alertWords, 1, "empty: refused")
eq(Alerts.Matches("wts Onyxia  Hide backpack"), true, "a word of yours")
eq(Alerts.Matches("wts |cffa335ee|Hitem:1:2|h[Onyxia Hide Backpack]|h|r"), true, "inside an item link's text")
eq(Alerts.Matches("ask " .. plink("Onyxia Hide") .. " now"), true, "your words still match inside another player's link")
SlashCmdList.GLASSCHAT("alert remove ONYXIA hide")
eq(#GC.db.alertWords, 0, "removed, however typed")
-- A word with a dash or curly quotes is kept as messages read (Codex, #85).
SlashCmdList.GLASSCHAT("alert add onyxia\226\128\148hide")
eq(GC.db.alertWords[1], "onyxia hide", "the dash is kept as a space, as in a message")
eq(Alerts.Matches("wts onyxia\226\128\148hide now"), true, "so the same text matches")
SlashCmdList.GLASSCHAT("alert remove onyxia\226\128\148hide")
eq(#GC.db.alertWords, 0, "and remove finds it the same way")
SlashCmdList.GLASSCHAT("alert add \226\128\156quoted\226\128\157")
eq(GC.db.alertWords[1], "quoted", "curly quotes around a word go")
GC.db.alertWords = {}
for i = 1, Alerts.MAX_WORDS + 1 do SlashCmdList.GLASSCHAT("alert add word" .. i) end
eq(#GC.db.alertWords, Alerts.MAX_WORDS, "at most MAX_WORDS")
GC.db.alertWords = {}

-- The alert: through the filters, once per line, throttled.
fresh()
local s0, f0 = sounds(), WoW.flashes
post(SAY, "karuzo come here")
eq(sounds(), s0 + 1, "a mention plays the sound")
eq(WoW.sounds[#WoW.sounds].kit, 1210, "LFG Bulletin Board's sound by default (owner's pick)")
eq(WoW.sounds[#WoW.sounds].channel, "Master", "on Master")
eq(WoW.flashes, f0 + 1, "and flashes the taskbar")
eq(Alerts.unseen, 1, "and waits behind the button")
check(Alerts.Log()[1]:find("%[say%] Someone Else: karuzo come here$"), "logged with where and who")
fresh()
s0 = sounds()
for _ = 1, 3 do post(GUILD, "karuzo, guild bank?", "Guild Mate", nil, 777) end
eq(sounds(), s0 + 1, "a line seen in three windows alerts once")
eq(#Alerts.Log(), 1, "and is logged once")
post(GUILD, "karuzo again", "Guild Mate", nil, 778)
eq(sounds(), s0 + 1, "a second mention inside EVERY s plays nothing")
eq(#Alerts.Log(), 2, "but is still logged")
WoW.now = WoW.now + Alerts.EVERY
post(GUILD, "karuzo, later", "Guild Mate", nil, 779)
eq(sounds(), s0 + 2, "after EVERY s it plays again")
fresh()
s0 = sounds()
post(SAY, "karuzo here", "Karuzo Elegia", "Player-1-ME")
eq(sounds(), s0, "never your own line")
post(SAY, "no mention at all")
eq(sounds(), s0, "a line without you: nothing")
eq(Alerts.unseen, 0, "and nothing logged")
post("CHAT_MSG_CHANNEL", "karuzo in trade", "Trader Joe", nil, nil, "2. Trade - City")
check(Alerts.Log()[1]:find("%[2%. Trade %- City%]"), "a channel line is logged with the channel's own label")

-- A line Spam & Ignore hides never alerts: its filter stops the loop first.
fresh()
s0 = sounds()
spamDB.mutes = { { phrase = "gold" } }
GC.Spam.RebuildMutes()
eq(post(CH, "karuzo buy gold cheap", "Gold Seller", "Player-1-SPAM"), "hidden", "the spam filter hides it")
eq(sounds(), s0, "and no alert")
spamDB.mutes = {}
GC.Spam.RebuildMutes()

-- Secrets: nothing, and nothing fails.
fresh()
s0 = sounds()
Alerts.Filter(nil, SAY, WoW.Secret("msg"), "x", "", "", "", "", 0, 0, "", 0, 1, "Player-1-X")
Alerts.Filter(nil, SAY, WoW.MarkSecret("karuzo marked"), "x", "", "", "", "", 0, 0, "", 0, 2, "Player-1-X")
Alerts.Filter(nil, SAY, "karuzo", "x", "", "", "", "", 0, 0, "", 0, 3, WoW.Secret("guid"))
eq(sounds(), s0, "a secret message or sender: no alert")
Alerts.Filter(nil, SAY, "karuzo", "x", "", "", "", "", 0, 0, "", 0, WoW.Secret("lineID"), "Player-1-X")
eq(sounds(), s0 + 1, "a secret lineID only turns the memo off")

-- Settings: off, the sound choice, no flash, a refused sound.
fresh()
s0, f0 = sounds(), WoW.flashes
SlashCmdList.GLASSCHAT("alert off")
post(SAY, "karuzo")
eq(sounds(), s0, "alerts off: nothing")
SlashCmdList.GLASSCHAT("alert on")
SlashCmdList.GLASSCHAT("alert sound ready")
eq(GC.db.alertSound, "ready", "/gchat alert sound ready")
eq(WoW.sounds[#WoW.sounds].kit, 8960, "plays a sample")
SlashCmdList.GLASSCHAT("alert sound lfg")
eq(WoW.sounds[#WoW.sounds].kit, 1210, "lfg: LFG Bulletin Board's sound")
SlashCmdList.GLASSCHAT("alert sound ready")
SlashCmdList.GLASSCHAT("alert flash off")
fresh()
s0, f0 = sounds(), WoW.flashes
post(SAY, "karuzo")
eq(WoW.sounds[#WoW.sounds].kit, 8960, "the chosen sound")
eq(WoW.flashes, f0, "no flash when it's off")
SlashCmdList.GLASSCHAT("alert sound off")
SlashCmdList.GLASSCHAT("alert flash on")
fresh()
s0, f0 = sounds(), WoW.flashes
post(SAY, "karuzo")
eq(sounds(), s0, "sound off: silent")
eq(WoW.flashes, f0 + 1, "the flash doesn't need the sound")
SlashCmdList.GLASSCHAT("alert sound raid")
eq(next(GC.failures), nil, "nothing failed so far")
WoW.willPlay = false
fresh()
post(SAY, "karuzo")
check(GC.failures["alert sound"] and GC.failures["alert sound"]:find("did not play %(kit 8959%)"),
    "a sound that didn't play is reported, as just that")
WoW.willPlay = nil
GC.failures["alert sound"] = nil

-- Whispers (#92): the tell sound on every one, as with Prat (Blizzard's waits 300 s).
local W, BNW = "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER"
local function filterAt(event, fn)
    for i, f in ipairs(WoW.messageFilters[event] or {}) do if f == fn then return i end end
end
check(filterAt(W, Alerts.Whisper) and filterAt(BNW, Alerts.Whisper), "on whispers and Battle.net whispers")
check(filterAt(W, GC.Spam.Filter) < filterAt(W, Alerts.Whisper), "after Spam & Ignore's filter")
check(not filterAt("CHAT_MSG_WHISPER_INFORM", Alerts.Whisper), "never on the ones you send")
for _, e in ipairs(Alerts.WHISPERS) do check(WoW.KNOWN_EVENTS[e], "a real event: " .. e) end
fresh()
s0, f0 = sounds(), WoW.flashes
local unseen0 = Alerts.unseen
for i = 1, 3 do post(W, "hi " .. i, "Some Friend", "Player-1-FRIEND") end
eq(sounds(), s0 + 3, "every whisper plays, three in a row too: no throttle")
eq(WoW.sounds[#WoW.sounds].kit, 3081, "Blizzard's tell sound")
eq(WoW.sounds[#WoW.sounds].channel, nil, "on the stock call's channel (sound effects)")
eq(WoW.flashes, f0, "no flash of ours: Blizzard flashes for a whisper itself")
eq(Alerts.unseen, unseen0, "and nothing behind the alerts button")
post(BNW, "bnet hi", "Some Account", nil)
eq(sounds(), s0 + 4, "a Battle.net whisper too")
s0 = sounds()
for _ = 1, 2 do post(W, "seen in two windows", "Some Friend", "Player-1-FRIEND", 9001) end
eq(sounds(), s0 + 1, "a whisper shown in two windows plays once")
Alerts.Whisper(nil, W, "x", "y", "", "", "", "", 0, 0, "", 0, WoW.Secret("lineID"), "Player-1-X")
eq(sounds(), s0 + 2, "a secret lineID only turns the memo off")
post(W, "karuzo, a whisper", "Some Friend", "Player-1-FRIEND")
eq(WoW.sounds[#WoW.sounds].kit, 3081, "your name in a whisper: the whisper sound, not a mention alert")
-- An ignored player's whisper is hidden first: silent.
post(W, "hello", "Pest Person", "Player-1-PEST")
SlashCmdList.GLASSCHAT("ignore Pest Person")
s0 = sounds()
eq(post(W, "psst", "Pest Person", "Player-1-PEST"), "hidden", "Spam & Ignore hides an ignored player's whisper")
eq(sounds(), s0, "and no sound")
SlashCmdList.GLASSCHAT("unignore Pest Person")
-- Its own switch: alerts off leaves it, whisper off stops it.
SlashCmdList.GLASSCHAT("alert off")
post(W, "still", "Some Friend", "Player-1-FRIEND")
eq(sounds(), s0 + 1, "mention alerts off: whispers still sound")
SlashCmdList.GLASSCHAT("alert on")
SlashCmdList.GLASSCHAT("alert whisper off")
eq(GC.db.whisperSound, false, "/gchat alert whisper off")
post(W, "quiet", "Some Friend", "Player-1-FRIEND")
eq(sounds(), s0 + 1, "off: only Blizzard's own")
SlashCmdList.GLASSCHAT("alert whisper on")
eq(rawget(GC.db, "whisperSound"), true, "/gchat alert whisper on")
-- Sound effects off: PlaySound says it won't play. The player's choice, not a failure.
WoW.willPlay = false
post(W, "muted", "Some Friend", "Player-1-FRIEND")
WoW.willPlay = nil
eq(GC.failures["whisper sound"], nil, "willPlay false isn't reported")

-- The button: above the chat-menu bubble, lit while alerts wait, a click lists them.
local b = Alerts._test.button()
check(b, "a button beside the chat")
-- In Blizzard's chat alert stack above the column (owner's pick after Codex, #85):
-- right above text-to-speech, never inside the column where the voice buttons grow.
local point, rel, relPoint = b:GetPoint(1)
check(point == "BOTTOMLEFT" and rel == TextToSpeechButtonFrame and relPoint == "TOPLEFT",
    "in Blizzard's stack above the column, right above text-to-speech")
eq(b:GetAlertContainer(), ChatAlertFrame, "contained by ChatAlertFrame")
fresh()
post(SAY, "karuzo one")
post(SAY, "karuzo two")
eq(b.count:GetText(), "2", "it counts what waits")
check(b.glow:IsShown(), "and is lit")
eq(b.symbol._textColor[2], GC.Buttons.GREEN[2], "green while alerts wait, as the channel button's headset")
eq(b.glow._color[1], GC.Buttons.GREEN[1], "with a green glow")
check(b.pulse:IsPlaying(), "pulsing while green (owner)")
b._scripts.OnClick(b)
eq(Alerts.unseen, 0, "a click marks them seen")
check(not b.glow:IsShown() and b.count:GetText() == "", "and puts the light out")
eq(b.symbol._textColor[2], GC.Skin.TAB_GOLD[2], "gold at rest, like its neighbours")
check(not b.pulse:IsPlaying(), "and still")
SlashCmdList.GLASSCHAT("alert off")
check(not b:IsShown(), "no button while alerts are off")
SlashCmdList.GLASSCHAT("alert on")
check(b:IsShown(), "back with them")

-- A client without the container: a side button stacks above the chat-menu bubble.
local realContainer = ChatAlertFrame
rawset(_G, "ChatAlertFrame", nil)
GC.Buttons.Side("fallback", { order = 9, text = "?", tooltip = "t", count = function() return 0 end,
    shown = function() return true end, onClick = function() end })
GC.Chat.Scan()
local fb = GC.Buttons._test.side("fallback")
point, rel, relPoint = fb:GetPoint(1)
check(point == "BOTTOM" and rel == ChatFrameMenuButton and relPoint == "TOP", "without the container: above the chat-menu bubble")
GC.Buttons.Side("fallback2", { order = 10, text = "?", tooltip = "t", count = function() return 0 end,
    shown = function() return true end, onClick = function() end })
GC.Chat.Scan()
point, rel = GC.Buttons._test.side("fallback2"):GetPoint(1)
eq(rel, fb, "and the next one on top of it")
rawset(_G, "ChatAlertFrame", realContainer)

eq(next(GC.failures), nil, "nothing failed")
done("test_alerts")
