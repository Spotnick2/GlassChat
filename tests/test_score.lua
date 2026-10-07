-- Spam & Ignore S4: the spam score (docs/PLAN-SPAM.md, "A spam score"). The
-- plan's worked examples, the token grammars, and the three modes: off,
-- watch (logged, still shown) and hide.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.playerGUID = "Player-1-ME"
WoW.playerName = "Karuzo Elegia"
local GC = loadAddon()
local Spam, Score = GC.Spam, GC.SpamScore
local db = GlassChatSpamIgnoreDB
local T = Score._test

local function kinds(text) return Score.Label(Score.Check(text)) end
local function spam(text) return Score.Check(text).spam end

-- The worked examples (the plan's table).
local EXAMPLES = {
    { "Cheap gold $5 = 1000g at goldsite.shop", "price + address", true },
    { "w w w . g o l d . c o m best price 10$", "price + broken-up", true },
    { "Buy gold at gоldsite.com", "look-alike + address", true },              -- Cyrillic о
    { "Buy gold, add Seller#1234, cheapest $", "contact", false },
    { "<Night Watch> recruiting, discord.gg/nw, @Recruiter", "address + contact", false },
    { "Live at twitch.tv/example, follow @Example", "address + contact", false },
    { "Selling Mara carries 20g/run, discord.gg/carries, Runner#1234", "address + contact", false },
    { "Guide for the 5% drop: wowhead.com/guide/x !!!", "address", false },
    { "G G W P, vod twitch.tv/example", "address", false },
    { "Ищем хила в MCе, discord.gg/raid", "address", false },
    { "WTS [Thunderfury] 10$ or 500g, add me Seller#1234", "price + contact", true },   -- owner: hide them
    { "Free addon at github.com/x, optional $5 donation", "price + address", true },    -- the known false positive
}
for _, e in ipairs(EXAMPLES) do
    eq(kinds(e[1]), e[2], "kinds of: " .. e[1])
    eq(spam(e[1]), e[3], (e[3] and "spam: " or "not spam: ") .. e[1])
end

-- One token, one kind: a discord link is an address, never a contact too.
eq(kinds("discord.gg/abc"), "address", "a link is one kind")
eq(kinds("join discord.gg/a/b/c/d/e"), "address", "a counted address is never scanned for fragments")
eq(kinds("LF tank for SM"), "", "plain words: no kind (spaces never make a broken-up word)")
eq(kinds("LFM ZG 50% loot, need heals!!!!"), "", "% is not a price")
check(not Score.Check("LFM ZG 50% loot, need heals!!!!").decor, "decoration is only worked out for a line with a kind")
check(Score.Check("guide at wowhead.com/x !!!!").decor, "where !!!! is decoration")
eq(kinds("WTS [Thunderfury] 500g pst"), "", "game gold is not a price")

-- Addresses: M5's list plus spam's endings, never any 2-6 letters.
for _, w in ipairs({ "goldsite.shop", "gold-site.top", "x1.vip", "wowhead.com", "https://anything.example",
                     "www.foo.bar", "sub.site.co", "raider.io/x" }) do
    check(T.isAddress(w), "an address: " .. w)
end
-- A host spelled out a character at a time is a broken-up word too, so a
-- contact beside it is spam (review of #47).
eq(kinds("b.u.y.g.o.l.d.cc add Seller#1234"), "broken-up + address + contact", "a dotted-out address")
check(spam("g.o.l.d.shop @seller"), "g.o.l.d.shop with a contact is spam")
check(not spam("join a.b.com @x"), "two single letters in a host don't make it spelled out")
-- Spam's extra endings only as typed in lower case: a missing space isn't an address.
eq(kinds("need tank.Top dps 5$"), "price", "tank.Top isn't an address")
check(T.isAddress("goldsite.top"), "goldsite.top is")
check(T.isAddress("WOWHEAD.COM"), "M5's own endings in any case")
for _, w in ipairs({ "item.level", "GlassChat.lua", "lol.ok", "notes.txt", "1.2.3", "---.shop",
                     "me@gmail.com", "shop", ".shop", "gold..shop" }) do
    check(not T.isAddress(w), "not an address: " .. w)
end
-- Contacts.
for _, w in ipairs({ "@Recruiter", "@ab", "Seller#1234", "Name#12345", "Хил#1234" }) do check(T.isContact(w), "a contact: " .. w) end
for _, w in ipairs({ "#1234", "@", "@a", "rank#12", "Name#123456", "group#2", "1a#1234" }) do
    check(not T.isContact(w), "not a contact: " .. w)
end
check(not spam("group #2 needs a tank, rank #1234"), "group and rank numbers are no contact")
-- Prices.
for _, w in ipairs({ "$5", "5$", "10$", "$4.99", "5€", "£10", "¥500", "100₽", "$999999",
                     "$1,000", "1.000€", "1000g=5$", "5$/1k", "$5k" }) do check(T.isPrice(w), "a price: " .. w) end
for _, w in ipairs({ "$", "5%", "500g", "USD5", "$$", "a$b" }) do check(not T.isPrice(w), "not a price: " .. w) end
-- The usual real-money formats (review of #47).
for _, l in ipairs({ "gold $1,000 at goldsite.shop", "1000g=5$ goldsite.shop", "5$/1k goldsite.shop",
                     "cheap gold 5 $ goldsite.shop", "cheap gold $ 5 goldsite.shop" }) do
    eq(kinds(l), "price + address", "a price in: " .. l)
end
eq(kinds("I have 5 apples $"), "", "a lone symbol not beside a number isn't a price")

-- Broken-up words: 5+ single characters set apart by separators.
for _, s in ipairs({ "p.r.o.f.i.t", "g o l d s", "p-r-0-f-i-t", "a_b_c_d_e", "g.o-l d*s", "x · y · z · w · v" }) do
    check(T.brokenUp(s), "broken up: " .. s)
end
for _, s in ipairs({ "G G W P", "L F M", "LF tank for SM", "a b c d", "abc.d.e.f.g", "the way to go", "1.2.3.4" }) do
    check(not T.brokenUp(s), "not broken up: " .. s)
end
check(T.brokenUp("q w e r t y"), "six single letters are")

-- Look-alike letters: only inside a Latin word, only twins.
check(T.lookAlike("gоld"), "a Cyrillic о inside a Latin word")
check(T.lookAlike("g0ldsіte"), "a Cyrillic і between Latin letters")
check(T.lookAlike("gοld"), "a Greek ο")
check(T.lookAlike("gоо d") == false, "a separate word isn't one word")
check(not T.lookAlike("MCе"), "a Cyrillic ending on an acronym isn't inside")
check(not T.lookAlike("AVке"), "nor two")
check(not T.lookAlike("ZGшку"), "ш has no Latin twin")
check(not T.lookAlike("gвld"), "в is left out of the twins (font-dependent)")
check(not T.lookAlike("хорошо"), "plain Russian has no Latin letters")
check(not T.lookAlike("café"), "accented Latin is Latin")
-- Twins M5's aggressive map already had (review of #47).
check(T.lookAlike("GОLDЅITE"), "Cyrillic О and Ѕ in capitals")
eq(kinds("GОLDЅITE.COM 5$"), "price + look-alike + address", "and the address is still found")
check(T.lookAlike("gold-cІty"), "Cyrillic І")
check(T.lookAlike("bУy"), "Cyrillic У")
check(T.lookAlike("bΥy"), "Greek Υ")
-- The other way round: Latin twins inside a Cyrillic word (review of #47).
check(T.lookAlike("гoлд"), "a Latin o inside a Cyrillic word")
check(spam("гoлд дешево 5$"), "Russian spam with a Latin o is spam")
check(not T.lookAlike("гwлд"), "a Latin w has no Cyrillic twin")
check(not T.lookAlike("ZGшку"), "an acronym before a Russian ending still isn't")
check(not T.lookAlike("хилDK"), "nor a Russian word before an acronym")
eq(kinds("Нужен хил на AVке, discord.gg/pvp"), "address", "Russian on a Latin acronym stays a single kind")

--------------------------------------------------------------------------------
-- The filter, in each mode.
--------------------------------------------------------------------------------

local nextLine = 5000
local function line(text, lineID, sender, guid)
    nextLine = nextLine + 1
    return Spam.Filter(nil, "CHAT_MSG_CHANNEL", text, sender or "Gold Seller", "", "", "", "", 0, 0, "", 0,
        lineID or nextLine, guid or "Player-1-GS")
end
local AD = "Cheap gold $5 = 1000g at goldsite.shop"

eq(db.score, "watch", "the score starts by watching")
Spam._test.reset()
check(not line(AD), "watch: a spam line is still shown")
eq(#Spam.Log(), 0, "and isn't in the hidden-lines log")
eq(Spam.unseen, 0, "nor in the icon's count")
local log = Score.Log()
eq(#log, 1, "it's in the score log")
eq(log[1].outcome, "shown (would hide)", "as would hide, shown")
check(log[1].spam and log[1].label == "price + address", "with its kinds")
check(not log[1].noid, "with a lineID")
check(not line("see wowhead.com/guide/x"), "a near miss is shown")
eq(#log, 1, "and isn't in the spam buffer")
eq(#Score.Near(), 1, "but in the near misses, so the owner sees both sides")
eq(Score.Near()[1].outcome, "shown", "as shown")
check(not line("hello there"), "a line with no kind")
eq(#log + #Score.Near(), 2, "isn't logged")
-- Near misses never push out would-hide lines (review of #47).
for i = 1, Score.NEAR_SIZE + 20 do line("guide " .. i .. " at wowhead.com/x" .. i) end
eq(#Score.Near(), Score.NEAR_SIZE, "the near misses are capped")
eq(#log, 1, "and the would-hide line is still there")
check(Score.LogText():find("^%-%- spam %(1%)"), "the log lists spam first")
-- Repeats run after the score in watch mode, and the outcome says so.
check(line(AD), "a repeat of the shown line is hidden by the repeat rule")
eq(log[#log].outcome, "hidden: repeat", "and the score log records that")
eq(Spam.Log()[1].reason, "repeat", "while the hidden-lines log has the repeat")
-- One decision per (event, lineID): a second window doesn't log again.
local n = #log
line("Cheap gold $6 at goldsite.shop", 7777)
line("Cheap gold $6 at goldsite.shop", 7777)
eq(#log, n + 1, "a line shown in two windows is scored once")
-- No lineID: logged, marked.
Spam.Filter(nil, "CHAT_MSG_CHANNEL", "Cheap gold $7 at goldsite.shop", "No Id", "", "", "", "", 0, 0, "", 0, nil, "Player-1-NI")
check(log[#log].noid, "a line with no lineID is logged, marked no id")

-- Hide.
Spam._test.reset()
db.score = "hide"
check(line(AD), "hide: the spam line is hidden")
eq(Spam.Log()[1].reason, "score: price + address", "with its kinds as the reason")
eq(Spam.unseen, 1, "and counted like every other reason")
eq(Score.Log()[1].outcome, "hidden: score: price + address", "the score log has it too")
check(not line("<Night Watch> recruiting, discord.gg/nw, @Recruiter"), "players' own advertising is never hidden")
check(not line("Live at twitch.tv/example, follow @Example"), "nor a stream")
-- A hidden line isn't timed as shown: once the score is off, the same text shows.
db.score = "watch"
check(not line(AD), "hidden by the score, so not a repeat of a shown post")

-- Off.
Spam._test.reset()
db.score = "off"
check(not line(AD), "off: shown")
eq(#Score.Log() + #Score.Near(), 0, "and not even scored")

-- The policy is S1's: never your guild, friends, group, or you.
db.score = "hide"
Spam._test.reset()
local realGuild = IsGuildMember
rawset(_G, "IsGuildMember", function(g) return g == "Player-1-GUILDIE" end)
check(not line(AD, nil, "Guild Mate", "Player-1-GUILDIE"), "a guild member's line is never scored")
rawset(_G, "IsGuildMember", realGuild)
check(not Spam.Filter(nil, "CHAT_MSG_GUILD", AD, "Gold Seller", "", "", "", "", 0, 0, "", 0, 8888, "Player-1-GS"),
    "nor guild chat")

-- /gchat spam collect: real chat on disk, to tune the score (owner).
db.score = "watch"
Spam._test.reset()
-- On by default in a dev build (owner), never in a release.
check(chatHas("collecting spam lines to tune the score %(a dev build's default%)"), "a dev build says at login that it collects")
-- The sections above ran collecting (a dev build's default): nothing failed.
eq(next(GC.failures), nil, "collecting alongside every section above recorded no failure")
check(type(db.collected) == "table" and #db.collected > 0, "and it did collect")
for _, e in ipairs(db.collected) do
    check(not GC.SpamText.IsCJK(e.text), "no CJK line among them: " .. e.text)
end
db.collected = nil
eq(rawget(db, "collect"), nil, "nothing set")
check(Spam.Collecting(), "a dev build collects by default")
WoW.addonVersion = "1.0.0"
Spam._test.reset()
check(not Spam.Collecting(), "a release doesn't")
-- A version that can't be read is a release (review of #59: fail closed).
WoW.addonVersion = nil
check(not Spam.Collecting(), "nor a build whose version can't be read")
WoW.addonVersion = "dev"
GlassChatDB.devMode = false
check(not Spam.Collecting(), "nor a dev build with developer mode turned off")
GlassChatDB.devMode = nil
WoW.addonVersion = "1.0.0"
line("Cheap gold $8 at goldsite.shop")
eq(db.collected, nil, "so nothing is kept")
db.collect = true
check(Spam.Collecting(), "unless the player turned it on")
db.collect = false
WoW.addonVersion = "dev"
Spam._test.reset()
check(not Spam.Collecting(), "and the player's off wins in a dev build")
line("Cheap gold $8 at goldsite.shop")
eq(db.collected, nil, "nothing kept then")
newChat()
SlashCmdList.GLASSCHAT("spam collect on")
check(db.collect == true and chatHas("collecting spam lines: on %(your setting"), "/gchat spam collect on, said to be yours")
line(AD)
local c = db.collected
eq(#c, 1, "a would-hide line is kept")
eq(c[1].kinds, "price + address", "with its kinds")
check(c[1].spam and c[1].out == "shown (would hide)" and c[1].ev == "CHANNEL", "its outcome and event")
eq(c[1].char, "Karuzo Elegia", "and which of your characters saw it")
eq(c[1].text, AD, "as plain text")
check(type(c[1].at) == "number" and c[1].from == "Gold Seller", "when, and who sent it")
line(AD)
eq(c[2].out, "hidden: repeat", "a repeat of it is kept with its outcome")
line("see wowhead.com/guide")
eq(c[3].kinds, "address", "a near miss is kept")
line("just chatting here")
eq(#c, 3, "a line with no kind, shown, isn't")
line("just chatting here")
eq(c[4].out, "hidden: repeat", "but a repeat with no kind is (the score's misses are there)")
check(c[4].kinds == nil and c[4].spam == nil, "with no kinds")
line("|cffff0000red|r words")
line("|cffff0000red|r words")
eq(c[5].text, "red words", "as plain text, colours and links out")
table.remove(c, 5)
db.mutes = { { phrase = "boost" } }
Spam.RebuildMutes()
line("cheap boost now")
eq(c[5].out, "hidden: muted: boost", "a muted line is kept")
-- With no usable lineID too, marked (Codex review of #58).
for _, lid in ipairs({ false, 0 }) do
    local n0 = #c
    Spam.Filter(nil, "CHAT_MSG_CHANNEL", "boost me up " .. tostring(lid), "No Id", "", "", "", "", 0, 0, "", 0,
        lid or nil, "Player-1-NOID")
    eq(#c, n0 + 1, "a muted line with lineID " .. tostring(lid or "nil") .. " is kept")
    check(c[#c].noid and c[#c].out == "hidden: muted: boost", "marked no id")
end
-- A CJK line is never kept, even when a mute hid it first (Codex review of #58).
local n1 = #c
line("boost 你好你好你好世界")
eq(#c, n1, "a CJK line hidden by a mute isn't kept")
db.mutes = {}
Spam.RebuildMutes()
db.cjk = false
line("你好你好你好世界 $5 goldsite.shop")
line("你好你好你好世界 $5 goldsite.shop")
eq(#c, n1, "nor one the score or the repeat rule saw with CJK filtering off")
db.cjk = true
line("你好你好你好世界")
eq(#c, n1, "a CJK line isn't")
db.ignore["Player-1-IGN"] = { name = "Ignored One" }
local n2 = #c
line("$5 gold at goldsite.shop", nil, "Ignored One", "Player-1-IGN")
eq(#c, n2, "nor an ignored player's")
db.ignore["Player-1-IGN"] = nil
-- Plain values only (it's written to disk).
for _, e in ipairs(c) do
    for k, v in pairs(e) do
        local t = type(v)
        check(t == "string" or t == "number" or t == "boolean", "a plain " .. k)
    end
end
-- The cap: oldest dropped.
local keepMax = Spam.COLLECT_MAX
Spam.COLLECT_MAX = 6
for i = 1, 4 do line("guide " .. i .. " at wowhead.com/g" .. i) end
eq(#c, 6, "capped")
eq(c[6].text, "guide 4 at wowhead.com/g4", "the newest kept")
check(c[1].text ~= AD, "the oldest dropped")
Spam.COLLECT_MAX = keepMax
SlashCmdList.GLASSCHAT("spam collect clear")
eq(db.collected, nil, "/gchat spam collect clear empties it")
SlashCmdList.GLASSCHAT("spam collect off")
eq(db.collect, false, "/gchat spam collect off")
-- default: back to the build's (review of #59: a saved off blocked it).
newChat()
SlashCmdList.GLASSCHAT("spam collect default")
eq(rawget(db, "collect"), nil, "/gchat spam collect default clears the setting")
check(Spam.Collecting(), "so a dev build collects again")
local said = false
for _, l in ipairs(newChat()) do if l:find("on %(this build's default") then said = true end end
check(said, "and the status says it's the build's default")
db.collect = false
line("$9 gold at goldsite.shop")
eq(db.collected, nil, "and nothing is kept again")

-- The commands.
newChat()
SlashCmdList.GLASSCHAT("spam score watch")
eq(db.score, "watch", "/gchat spam score watch")
check(chatHas("spam score: watch"), "and says so")
newChat()
SlashCmdList.GLASSCHAT("spam score hdie")
eq(db.score, "watch", "a typo doesn't change the mode")
check(chatHas("unknown mode 'hdie'"), "and says so, instead of opening the log")
SlashCmdList.GLASSCHAT("spam score Hide")
eq(db.score, "hide", "a mode in capitals is taken")
SlashCmdList.GLASSCHAT("spam score watch")
newChat()
SlashCmdList.GLASSCHAT("spam test " .. AD)
check(chatHas("kinds: price %+ address, spam"), "/gchat spam test reports the kinds")
newChat()
SlashCmdList.GLASSCHAT("spam")
check(chatHas("/gchat spam score"), "the help lists it")

eq(next(GC.failures), nil, "no swallowed errors")
done("test_score")
