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
check(Score.Check("LFM ZG 50% loot, need heals!!!!").decor, "but the !!!! is decoration")
eq(kinds("WTS [Thunderfury] 500g pst"), "", "game gold is not a price")

-- Addresses: M5's list plus spam's endings, never any 2-6 letters.
for _, w in ipairs({ "goldsite.shop", "gold-site.top", "x1.vip", "wowhead.com", "https://anything.example",
                     "www.foo.bar", "sub.site.co", "raider.io/x" }) do
    check(T.isAddress(w), "an address: " .. w)
end
for _, w in ipairs({ "item.level", "GlassChat.lua", "lol.ok", "notes.txt", "1.2.3", "---.shop", "a-.shop",
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
for _, w in ipairs({ "$5", "5$", "10$", "$4.99", "5€", "£10", "¥500", "100₽", "$999999" }) do check(T.isPrice(w), "a price: " .. w) end
for _, w in ipairs({ "$", "5%", "500g", "$1234567", "$5k", "USD5", "$4.999" }) do check(not T.isPrice(w), "not a price: " .. w) end

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
eq(#log, 2, "and logged too (one kind), so the owner sees both sides")
eq(log[2].outcome, "shown", "as shown")
check(not line("hello there"), "a line with no kind")
eq(#log, 2, "isn't logged")
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
eq(#Score.Log(), 0, "and not even scored")

-- The policy is S1's: never your guild, friends, group, or you.
db.score = "hide"
Spam._test.reset()
local realGuild = IsGuildMember
rawset(_G, "IsGuildMember", function(g) return g == "Player-1-GUILDIE" end)
check(not line(AD, nil, "Guild Mate", "Player-1-GUILDIE"), "a guild member's line is never scored")
rawset(_G, "IsGuildMember", realGuild)
check(not Spam.Filter(nil, "CHAT_MSG_GUILD", AD, "Gold Seller", "", "", "", "", 0, 0, "", 0, 8888, "Player-1-GS"),
    "nor guild chat")

-- The commands.
newChat()
SlashCmdList.GLASSCHAT("spam score watch")
eq(db.score, "watch", "/gchat spam score watch")
check(chatHas("spam score: watch"), "and says so")
SlashCmdList.GLASSCHAT("spam score bogus")   -- an unknown word opens the log, never changes the mode
eq(db.score, "watch", "an unknown word doesn't change the mode")
newChat()
SlashCmdList.GLASSCHAT("spam test " .. AD)
check(chatHas("kinds: price %+ address, spam"), "/gchat spam test reports the kinds")
newChat()
SlashCmdList.GLASSCHAT("spam")
check(chatHas("/gchat spam score"), "the help lists it")

eq(next(GC.failures), nil, "no swallowed errors")
done("test_score")
