-- Spam & Ignore (S1): the two policies, mutes, CJK, repeats, the memo, the
-- ignore list (never your own characters), the log and the opt-in icon.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.playerGUID = "Player-1-ME"
WoW.playerName = "Karuzo Elegia"
local GC = loadAddon()
local Spam, UI, Text = GC.Spam, GC.SpamUI, GC.SpamText
local db = GlassChatSpamIgnoreDB

-- The filter is installed for every player-chat event.
-- The plugin's filter is on CHAT_MSG_CHANNEL, before the address filter
-- (added at PLAYER_LOGIN), so it judges the text as typed.
local spamAt, urlAt
for i, fn in ipairs(WoW.messageFilters.CHAT_MSG_CHANNEL) do
    if fn == Spam.Filter then spamAt = i end
    if fn == GC.Url.Filter then urlAt = i end
end
check(spamAt, "the plugin's filter is on CHAT_MSG_CHANNEL")
check(urlAt and spamAt < urlAt, "and runs before the address filter")
check(WoW.messageFilters.CHAT_MSG_GUILD ~= nil, "and on guild chat (for explicit ignores)")

local nextLine = 1000
local function say(event, text, sender, guid, lineID)
    nextLine = nextLine + 1
    return Spam.Filter(nil, event, text, sender, "", "", "", "", 0, 0, "", 0, lineID or nextLine, guid)
end
local CH, SAY, GUILD, WHISPER = "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_GUILD", "CHAT_MSG_WHISPER"

-- Your own character is recorded at login.
check(db.own["Player-1-ME"] ~= nil, "this character is recorded as yours")
eq(db.own["Player-1-ME"].name, "Karuzo Elegia", "by its full name, whole in UnitName's first return")
-- The split shape (AltStable #56): first name and surname in two returns.
local realName = UnitName
rawset(_G, "UnitName", function(unit) if unit == "player" then return "Karuzo", "Test" end end)
eq(GC.API.PlayerFullName(), "Karuzo Test", "the split shape gives the full name back")
Spam.RecordSelf()
eq(db.own["Player-1-ME"].name, "Karuzo Test", "and that's what's recorded")
check(Spam.OwnByName("karuzo test"), "so a name check finds this character")
rawset(_G, "UnitName", function(unit) if unit == "player" then return "Karuzo Elegia", "Morphisto" end end)
eq(GC.API.PlayerFullName(), "Karuzo Elegia", "a whole first return keeps its own name, the second slot not glued on")
rawset(_G, "UnitName", realName)
Spam.RecordSelf()

-- Mutes: literal phrases at word edges, plurals ok, never inside a word.
db.mutes = { { phrase = "profession kit" }, { phrase = "kit" } }
Spam.RebuildMutes()
check(say(CH, "WTS Profession Kits cheap!", "Seller One", "Player-1-S1"), "a muted phrase hides the line (plural too)")
check(not say(CH, "I'm kiting the boss to the wall", "Tank Two", "Player-1-T2"), "'kit' never hides 'kiting'")
check(not say(CH, "nice kitten", "Cat Lover", "Player-1-C3"), "nor 'kitten'")
check(say(CH, "free kit here", "Kit Giver", "Player-1-K4"), "but a lone 'kit' is hidden")
-- Aggressive matching is opt-in.
db.mutes = { { phrase = "profession", aggressive = true } }
Spam.RebuildMutes()
check(say(CH, "p r 0 f e s s i o n kits", "Sneaky Seller", "Player-1-S5") == false, "digits stay digits: 0 isn't o")
check(say(CH, "p.r.o.f.e.s.s.i.o.n kits", "Sneaky Seller", "Player-1-S5"), "aggressive: separators dropped")
check(say(CH, "\208\160rofession kits", "Cyrillic Seller", "Player-1-S6"), "aggressive: a Cyrillic look-alike maps to ASCII")
db.mutes = {}
Spam.RebuildMutes()

-- CJK (on by default): public chat only, 3+ characters and a third of the line.
local cjk = "\228\189\160\229\165\189\228\184\150\231\149\140"   -- 4 ideographs
check(say(CH, cjk .. " gold", "Cjk Poster", "Player-1-Z1"), "a CJK post is hidden by default")
check(not say(CH, "hello my friend " .. "\228\189\160" .. " ok", "Mostly English", "Player-1-Z2"), "one CJK character in English isn't")
check(not say(GUILD, cjk, "Guild Mate", "Player-1-Z3"), "never in guild chat")
check(not say(WHISPER, cjk, "Whisperer", "Player-1-Z4"), "nor in whispers")
db.cjk = false
check(not say(CH, cjk, "Cjk Poster", "Player-1-Z1"), "/gchat spam cjk off shows them")
db.cjk = nil

-- Repeats: the first post shown, repeats in the window hidden, timed from
-- the last SHOWN post; another item link is another post.
WoW.now = 1000
check(not say(CH, "LFM Deadmines need healer", "Group Leader", "Player-1-R1"), "a first post is shown")
WoW.now = 1060
check(say(CH, "LFM  deadmines NEED healer", "Group Leader", "Player-1-R1"), "the same post a minute later is hidden")
WoW.now = 1200
check(say(CH, "LFM Deadmines need healer", "Group Leader", "Player-1-R1"), "and still within 5 minutes of the shown one")
WoW.now = 1301
check(not say(CH, "LFM Deadmines need healer", "Group Leader", "Player-1-R1"), "after the window one gets through")
check(not say(CH, "WTS |cffa335ee|Hitem:19019|h[Thunderfury]|h|r", "Item Seller", "Player-1-R2"), "an item post is shown")
check(not say(CH, "WTS |cffa335ee|Hitem:17182|h[Thunderfury]|h|r", "Item Seller", "Player-1-R2"), "another item with the same name is another post")
check(not say(WHISPER, "hi", "Friendly", "Player-1-R3") and not say(WHISPER, "hi", "Friendly", "Player-1-R3"),
    "repeats are never judged in whispers")
-- The spacing changed to get past the repeat rule (owner's collected Trade
-- chat, #63): still the same post.
check(not say(CH, "<Dream> Immediate Openings Hunters Rdruids and Spriests. Apply!", "Guild Ad", "Player-1-R4"),
    "an advert is shown")
check(say(CH, "<Dream> Immediate Openings Hunters R Druids and S Priests. Apply!", "Guild Ad", "Player-1-R4"),
    "re-posted with spaces inside its words: a repeat")
check(say(CH, "<Dream> Immediate Openings Hunters RDruids and SPriests - Apply", "Guild Ad", "Player-1-R4"),
    "with its punctuation changed: a repeat")
check(not say(CH, "<Dream> Immediate Openings Mages and Priests. Apply!", "Guild Ad", "Player-1-R4"),
    "other words are another post")
check(not say(CH, "!!!", "Punct Only", "Player-1-R5") and not say(CH, "???", "Punct Only", "Player-1-R5"),
    "a line of only punctuation keeps it: !!! and ??? aren't one post")
local RK = GC.SpamText.RepeatKey
check(RK("WTS |Hitem:1|h[Sword]|h") ~= RK("WTS |Hitem:2|h[Sword]|h"), "link data still tells posts apart (same link text)")
-- Review of #64: meaning kept, Unicode tricks caught, no locale.
check(RK("WTS [Lotus] 1.5g") ~= RK("WTS [Lotus] 15g"), "a decimal point between digits counts: 1.5g isn't 15g")
check(RK("10,000g") ~= RK("100,00g") and RK("raid 7:30") ~= RK("raid 73:0"), "so do a comma and a colon between digits")
eq(RK("Hunters R Druids - Apply"), RK("Hunters R Druids \226\128\147 Apply"), "an en dash is punctuation")
eq(RK("Apply..."), RK("Apply\226\128\166"), "an ellipsis too")
eq(RK("R Druids"), RK("R\194\160Druids"), "and a no-break space")
eq(RK("Apply now"), RK("\208\144pply now"), "a look-alike letter is its Latin twin")
eq(RK("Apply now"), RK("\239\188\161pply now"), "and a full-width one")
-- Full-width digits and separators (Codex review of #64): the same price in
-- any width is one post, a different price another.
local FW1, FW5, FWDOT, FWBANG = "\239\188\145", "\239\188\149", "\239\188\142", "\239\188\129"
eq(RK("WTS " .. FW1 .. "." .. FW5 .. "g"), RK("WTS 1.5g"), "full-width digits around a dot: still 1.5g")
eq(RK("WTS 1" .. FWDOT .. "5g"), RK("WTS 1.5g"), "a full-width dot between digits: still 1.5g")
eq(RK("WTS " .. FW1 .. FWDOT .. FW5 .. "g"), RK("WTS 1.5g"), "all full-width: still 1.5g")
check(RK("WTS " .. FW1 .. "." .. FW5 .. "g") ~= RK("WTS 15g"), "and never 15g")
check(RK("WTS 1" .. FWDOT .. "5g") ~= RK("WTS 15g"), "in any width")
eq(RK("Apply" .. FWBANG), RK("Apply!"), "full-width punctuation elsewhere is still ignored")
check(RK("caf\195\169 ok") ~= RK("caf\195\160 ok"), "accented letters stay whole letters (no byte classes)")
eq(RK("caf\195\169"), RK("cafe"), "and an accent alone doesn't make a new post (Aggressive's letter map)")
check(RK("\208\191\209\128\208\184\208\178\208\181\209\130") ~= RK("\208\191\209\128\208\184\208\178\208\190"), "two Russian words stay apart")
eq(RK("!!!"), RK("! ! !"), "a punctuation-only line ignores its spacing")
check(RK("!!!") ~= RK("???"), "but keeps its marks")

-- Heuristics never touch you, friends, guild, group or the allow list.
WoW.friends["Player-1-F1"] = true
WoW.guild["Player-1-G1"] = true
db.mutes = { { phrase = "spam" } }
Spam.RebuildMutes()
check(not say(CH, "spam", "Karuzo Elegia", "Player-1-ME"), "your own lines are never hidden")
check(not say(CH, "spam", "Best Friend", "Player-1-F1"), "nor a friend's")
check(not say(CH, "spam", "Guild Mate", "Player-1-G1"), "nor a guild member's")
check(say(CH, "spam", "Stranger Danger", "Player-1-X1"), "a stranger's is")
db.mutes = {}
Spam.RebuildMutes()

-- The memo: a line shown in two windows is judged once (one log entry).
Spam._test.reset()
db.mutes = { { phrase = "twice" } }
Spam.RebuildMutes()
check(say(CH, "say twice", "Two Windows", "Player-1-W1", 5000), "first window: hidden")
check(say(CH, "say twice", "Two Windows", "Player-1-W1", 5000), "second window: hidden by the same decision")
eq(#Spam.Log(), 1, "logged once, not once per window")
eq(Spam.unseen, 1, "counted once")
db.mutes = {}
Spam.RebuildMutes()

-- Explicit ignores: by GUID, in every chat type, guild and group included.
say(CH, "hello", "Annoying Person", "Player-1-A1")   -- seen, so the name resolves
SlashCmdList.GLASSCHAT("ignore Annoying Person")
check(db.ignore["Player-1-A1"] and db.ignore["Player-1-A1"].name == "Annoying Person", "/gchat ignore resolves the GUID from chat")
check(say(GUILD, "hi guild", "Annoying Person", "Player-1-A1"), "an ignored player is hidden in guild chat too")
WoW.friends["Player-1-A1"] = true
check(say(WHISPER, "psst", "Annoying Person", "Player-1-A1"), "even as a friend (the ignore wins)")
SlashCmdList.GLASSCHAT("unignore Annoying Person")
check(not say(WHISPER, "psst again", "Annoying Person", "Player-1-A1"), "/gchat unignore lets them through")
-- Pending: a name not seen yet, confirmed by their first line.
SlashCmdList.GLASSCHAT("ignore Future Pest")
check(db.pending["future pest"] ~= nil, "a name not seen yet is pending")
check(say(SAY, "hello", "Future Pest", "Player-1-P1"), "their first line is hidden")
check(db.ignore["Player-1-P1"] and not db.pending["future pest"], "and turns the pending entry into a GUID one")

-- Never your own characters (owner).
db.own["Player-1-ALT"] = { name = "Zoruka Mortalis" }
newChat()
SlashCmdList.GLASSCHAT("ignore Zoruka Mortalis")
check(chatHas("one of your own characters"), "ignoring one of your own characters is refused")
check(db.ignore["Player-1-ALT"] == nil and db.pending["zoruka mortalis"] == nil, "and nothing is added")
db.ignore["Player-1-ALT"] = { name = "Zoruka Mortalis" }   -- an old entry, from before it was known
check(not say(WHISPER, "it's me", "Zoruka Mortalis", "Player-1-ALT"), "an old entry for your own character is skipped")
db.ignore["Player-1-ME"] = { name = "Karuzo Elegia" }
check(not say(SAY, "me", "Karuzo Elegia", "Player-1-ME"), "the current character is never ignored")
db.ignore["Player-1-ALT"], db.ignore["Player-1-ME"] = nil, nil

-- Import: Blizzard's list, by name; a known name gets its GUID, an unknown
-- one is pending, your own are skipped.
WoW.ignores = nil
newChat()
SlashCmdList.GLASSCHAT("ignore import")
check(chatHas("isn't ready yet"), "import before the list is readable says so")
say(CH, "hi", "Known Grudge", "Player-1-KG")
WoW.ignores = { "Known Grudge", "Unknown Grudge", "Zoruka Mortalis" }
newChat()
SlashCmdList.GLASSCHAT("ignore import")
check(db.ignore["Player-1-KG"] ~= nil, "an imported name seen in chat gets its GUID")
check(db.pending["unknown grudge"] ~= nil, "one not seen yet is pending")
check(chatHas("skipped 1 of your own characters"), "your own character on the list is skipped")

-- Secrets pass through, untouched.
check(not Spam.Filter(nil, CH, WoW.Secret("text"), "Someone", "", "", "", "", 0, 0, "", 0, 9999, "Player-1-Q"),
    "a secret text passes")
check(not Spam.Filter(nil, CH, "x", "Someone", "", "", "", "", 0, 0, "", 0, WoW.Secret("id"), WoW.Secret("guid")),
    "a secret GUID passes")
db.mutes = { { phrase = "spam" } }
Spam.RebuildMutes()
check(not say(CH, "spam", "Npc Thing", "Creature-0-1"), "a non-player GUID passes, muted phrase or not")
check(say(CH, "spam", "Real Player", "Player-1-RP"), "(while a player's is hidden)")
db.mutes = {}
Spam.RebuildMutes()

-- The log, the icon (opt-in, off by default) and the debug wording.
check(UI._test.buttons[ChatFrame1] == nil, "no tab-strip icon by default")
eq(GC.Skin.DOCK_RESERVE, 82, "and the tabs keep their room")
SlashCmdList.GLASSCHAT("spam icon on")
local b = UI._test.buttons[ChatFrame1]
check(b and b:IsShown(), "/gchat spam icon on adds it")
eq(GC.Skin.DOCK_RESERVE, 108, "with room for a third icon")
eq(b.icon._file, UI.BUG, "a bug in a dev build")
check(b.count:GetText() ~= "", "showing how many lines were hidden")
-- Highlighted while lines wait; gold on hover; a blink for 3 s per block.
check(b.glow:IsShown(), "highlighted (a glow) while unseen lines wait")
eq(b.icon._vertex and b.icon._vertex[2] or nil, GC.Skin.TAB_GOLD[2], "in gold")
WoW.timers = {}
db.mutes = { { phrase = "blinky" } }
Spam.RebuildMutes()
say(CH, "blinky", "Spammy Sam", "Player-1-BL")
check(b.blink:IsPlaying(), "a new block makes it blink")
WoW.flushTimers(2)
check(b.blink:IsPlaying(), "still blinking within 3 s")
WoW.flushTimers(3)
check(not b.blink:IsPlaying(), "and stops after 3 s")
db.mutes = {}
Spam.RebuildMutes()
b._scripts.OnClick(b)
local win = GC.Copy._test.window()
check(win:IsShown() and win.title:GetText():find("debug", 1, true), "it opens the blocked-lines window (debug)")
check(win.edit:GetText():find("[ignored] Future Pest (SAY)", 1, true), "listing each line with its reason, sender and event")
eq(b.count:GetText(), "", "and the count clears once seen")
check(not b.glow:IsShown(), "and the highlight goes")
eq(b.icon._vertex[1], GC.Skin.TAB_GREY[1], "grey at rest")
b._scripts.OnEnter(b)
eq(b.icon._vertex[2], GC.Skin.TAB_GOLD[2], "gold on hover, like the copy icon")
b._scripts.OnLeave(b)
eq(b.icon._vertex[1], GC.Skin.TAB_GREY[1], "grey again after")
SlashCmdList.GLASSCHAT("spam icon off")
check(not b:IsShown(), "/gchat spam icon off hides it")
eq(GC.Skin.DOCK_RESERVE, 82, "and gives the tabs their room back")
WoW.addonVersion = "1.2.0"
check(not Spam.IsDebug(), "a release isn't a debug build")
db.debug = true
check(Spam.IsDebug(), "/gchat spam debug on overrides it")
db.debug = nil

-- /gchat spam test.
db.mutes = { { phrase = "boost" } }
Spam.RebuildMutes()
newChat()
SlashCmdList.GLASSCHAT("spam test cheap boost here")
check(chatHas("hidden %(muted: boost%)"), "/gchat spam test says why a line would be hidden")
SlashCmdList.GLASSCHAT("mute boost")
check(chatHas("already muted"), "a duplicate mute is refused")
SlashCmdList.GLASSCHAT("mute ~ . . . ")
check(chatHas("nothing to match on"), "an empty mute is refused")

-- Unmute picks the rule by mode too (Codex review of #20).
db.mutes = {}
Spam.RebuildMutes()
SlashCmdList.GLASSCHAT("mute kit")
SlashCmdList.GLASSCHAT("mute ~kit")
eq(#db.mutes, 2, "a literal and an aggressive rule are separate")
SlashCmdList.GLASSCHAT("unmute ~kit")
eq(#db.mutes, 1, "unmute ~kit removes one")
check(not db.mutes[1].aggressive and db.mutes[1].phrase == "kit", "the aggressive one, keeping the literal")
check(not say(CH, "k.i.t here", "Trick Seller", "Player-1-TK"), "and the aggressive match is gone")
SlashCmdList.GLASSCHAT("unmute kit")
eq(#db.mutes, 0, "unmute kit removes the literal one")

-- A phrase the command accepts survives a load; a too-long one is refused.
newChat()
SlashCmdList.GLASSCHAT("mute " .. string.rep("a", Spam.MUTE_MAX + 1))
check(chatHas("too long"), "a phrase over the limit is refused")
eq(#db.mutes, 0, "and not added")
SlashCmdList.GLASSCHAT("mute " .. string.rep("b", Spam.MUTE_MAX))
Spam.Load()
eq(#Spam.db.mutes, 1, "one at the limit is kept across a load")
db = Spam.db
db.mutes = {}
Spam.RebuildMutes()

-- No usable lineID: only stateless checks, nothing logged (Codex review of #20).
Spam._test.reset()
WoW.now = 5000
for _, id in ipairs({ 0, false }) do
    local lid = id or nil
    local a = Spam.Filter(nil, CH, "LFM no id", "No Id", "", "", "", "", 0, 0, "", 0, lid, "Player-1-NI")
    local b = Spam.Filter(nil, CH, "LFM no id", "No Id", "", "", "", "", 0, 0, "", 0, lid, "Player-1-NI")
    check(not a and not b, "lineID " .. tostring(lid) .. ": the same line in two windows is shown in both (no repeat state)")
end
db.mutes = { { phrase = "noid" } }
Spam.RebuildMutes()
check(Spam.Filter(nil, CH, "noid", "No Id", "", "", "", "", 0, 0, "", 0, nil, "Player-1-NI"), "a muted line with no lineID is still hidden")
eq(#Spam.Log(), 0, "but not logged")
eq(Spam.unseen, 0, "nor counted")
db.mutes = {}
Spam.RebuildMutes()

-- S3: your characters on other WoW accounts, from AltStable's public API.
local altList = { { guid = "Player-9-OTHERACC", name = "Karuzo Memphisto", realm = "R", account = "2" },
                  { guid = "Creature-0-NOPE", name = "Not A Player" } }
local altCallback
rawset(_G, "AltStable", {
    PUBLIC_API_VERSION = 1,
    GetCharacters = function() return altList end,
    RegisterCallback = function(event, fn) if event == "CharactersChanged" then altCallback = fn end end,
})
WoW.fire("PLAYER_LOGIN")
newChat()
SlashCmdList.GLASSCHAT("ignore Karuzo Memphisto")
check(chatHas("one of your own characters"), "a character on another account (AltStable) can't be ignored")
db.ignore["Player-9-OTHERACC"] = { name = "Karuzo Memphisto" }   -- ignored before AltStable knew it
check(not say(WHISPER, "it's me", "Karuzo Memphisto", "Player-9-OTHERACC"), "and an old ignore of it is skipped")
newChat()
SlashCmdList.GLASSCHAT("ignores")
check(chatHas("Karuzo Memphisto.*one of your own characters"), "/gchat ignores flags it")
db.ignore["Player-9-OTHERACC"] = nil
db.mutes = { { phrase = "gold" } }
Spam.RebuildMutes()
check(not say(CH, "gold", "Karuzo Memphisto", "Player-9-OTHERACC"), "never caught by mutes either")
db.mutes = {}
Spam.RebuildMutes()
check(not Spam.IsOwn("Creature-0-NOPE"), "only player GUIDs count")
-- A character AltStable learns later counts once it says so.
table.insert(altList, { guid = "Player-9-NEWALT", name = "Fresh Alt" })
check(not Spam.IsOwn("Player-9-NEWALT"), "not before AltStable's callback")
altCallback("CharactersChanged")
check(Spam.IsOwn("Player-9-NEWALT") and Spam.OwnByName("fresh alt"), "after it, by GUID and by name")
-- Names: only with a surname, only while names are unique; a known GUID decides.
table.insert(altList, { guid = "Player-9-OLDPEER", name = "Karuzo" })   -- an older peer's record
altCallback("CharactersChanged")
check(Spam.IsOwn("Player-9-OLDPEER"), "a record without a surname is still yours by GUID")
check(not Spam.OwnByName("karuzo"), "but its bare first name is never a name match")
newChat()
say(SAY, "hi", "Karuzo Memphisto", "Player-1-STRANGER")   -- a stranger with that name, seen in chat
SlashCmdList.GLASSCHAT("ignore Karuzo Memphisto")
check(db.ignore["Player-1-STRANGER"], "a player whose GUID is known isn't refused for sharing a name with your alt")
db.ignore["Player-1-STRANGER"] = nil
WoW.uniqueNames = false
altCallback("CharactersChanged")
check(not Spam.OwnByName("fresh alt"), "names count only while the client says they're unique")
WoW.uniqueNames = nil
altCallback("CharactersChanged")
-- A pending entry naming one of yours is flagged.
db.pending["fresh alt"] = { name = "Fresh Alt" }
newChat()
SlashCmdList.GLASSCHAT("ignores")
check(chatHas("Fresh Alt.*one of your own characters"), "a pending entry for one of yours is flagged")
db.pending["fresh alt"] = nil
-- The callback brings Blizzard's list in step too.
local checks, realCheck = 0, GC.SpamMirror.Check
GC.SpamMirror.Check = function(...) checks = checks + 1; return realCheck(...) end
altCallback("CharactersChanged")
eq(checks, 1, "AltStable's update re-runs the ignore-list sync")
GC.SpamMirror.Check = realCheck
-- A broken list or callback is recorded, never thrown; this character still recorded.
rawset(_G, "AltStable", { PUBLIC_API_VERSION = 1, GetCharacters = function() return { "not a table", 5, { guid = "Player-9-GOOD", name = "Good Alt" } } end,
    RegisterCallback = function() error("renamed") end })
Spam._test.reset()
db.own["Player-1-ME"] = nil
WoW.fire("PLAYER_LOGIN")
check(db.own["Player-1-ME"], "this character is still recorded")
check(Spam.IsOwn("Player-9-GOOD"), "a good entry beside malformed ones still counts")
check(GC.failures["spam altstable hook"], "a failing RegisterCallback is recorded")
GC.failures["spam altstable hook"] = nil
rawset(_G, "AltStable", { PUBLIC_API_VERSION = 1, GetCharacters = function() error("boom") end })
Spam.RefreshAltStable()
check(GC.failures["spam altstable read"], "a failing GetCharacters is recorded")
GC.failures["spam altstable read"] = nil
rawset(_G, "AltStable", { PUBLIC_API_VERSION = 1, GetCharacters = function() return altList end })
Spam.RefreshAltStable()
check(not Spam.OwnByName("not a player"), "a non-player entry's name is never yours")

-- Another API version is never read.
rawset(_G, "AltStable", { PUBLIC_API_VERSION = 2, GetCharacters = function() return {} end })   -- read, it would wipe the list
Spam.RefreshAltStable()
check(Spam.IsOwn("Player-9-NEWALT"), "an unknown API version is left alone (the last good list stays)")
rawset(_G, "AltStable", nil)

-- The log's times are bracketed like the chat's timestamps (owner).
db.mutes = { { phrase = "bracketme" } }
Spam.RebuildMutes()
say(CH, "bracketme please", "Log Format", "Player-1-LF")
check(Spam.LogText(false):find("^%[%d%d:%d%d:%d%d%] %[muted: bracketme%] Log Format: bracketme please"), "the hidden-lines log: [time] [reason]")
check(Spam.LogText(true):find("^%[%d%d:%d%d:%d%d%] %[muted: bracketme%] Log Format %(CHANNEL%)"), "and its debug form")
GC.SpamScore.Record("CHAT_MSG_CHANNEL", "Score Format", GC.SpamScore.Check("see wowhead.com"), "shown")
check(GC.SpamScore.LogText():find("\n%[%d%d:%d%d:%d%d%] %[address%] CHANNEL"), "the score log too")
db.mutes = {}
Spam.RebuildMutes()
-- No stray "|" in what's printed: the client reads "|x" as an escape and
-- drops it ("off|watch|hide" showed as "offatchide", owner's screenshot). Only
-- the escapes we mean: colours, links, textures, atlases, a newline, "||".
local function stray(line)
    local clean = line:gsub("||", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
        :gsub("|[TA].-|[ta]", ""):gsub("|n", "")
    return clean:find("|", 1, true) ~= nil
end
local shown = {}
local realShow = GC.Copy.Show
GC.Copy.Show = function(title, text, status) shown[#shown + 1] = status or "" end
newChat()
for _, cmd in ipairs({ "", "spam", "spam score", "spam score bogus", "spam icon", "spam cjk", "ignore sync",
                       "ignore mirror", "ignores", "mutes", "glass", "stamps maybe" }) do
    SlashCmdList.GLASSCHAT(cmd)
end
GC.Copy.Show = realShow
local bad = {}
for _, l in ipairs(newChat()) do if stray(l) then bad[#bad + 1] = l end end
for _, l in ipairs(shown) do if stray(l) then bad[#bad + 1] = l end end
eq(#bad, 0, "no stray | in printed help or status lines" .. (bad[1] and (": " .. bad[1]) or ""))
check(#shown > 0, "the score log's status line was checked too")
eq(next(GC.failures), nil, "nothing failed")
done("test_spam")
