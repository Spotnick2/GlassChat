-- M5: web addresses become click-to-copy links; game links, colours and
-- textures are left alone; a click opens the address, selected.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GC = loadAddon()
local Url = GC.Url

-- What counts as a web address.
for _, w in ipairs({ "https://www.wowhead.com/classic/item=19019", "http://example.org", "www.raider.io",
    "wowhead.com", "discord.gg/abc123", "https://youtu.be/dQw4w9WgXcQ", "warcraftlogs.com/reports/x", "WWW.Twitch.TV" }) do
    eq(Url.Address(w), w, "an address: " .. w)
end
for _, w in ipairs({ "e.g.", "1.60.1.70205", "a.b", "file.lua", "Interface\\AddOns", "bob@example.com",
    "192.168.0.1", "ok...", "3.5", "lol.ok", "foo..com", "No.It", "Yes.No", "ok.me", "join.us", "to.be" }) do
    eq(Url.Address(w), nil, "not an address: " .. w)
end
eq(Url.Address("wowhead.com."), "wowhead.com", "a sentence's full stop stays outside")
eq(Url.Address("https://x.com/a,"), "https://x.com/a", "so does a comma")
eq(Url.Address("https://en.wikipedia.org/wiki/Foo_(bar))"), "https://en.wikipedia.org/wiki/Foo_(bar)",
    "a bracket the address opened is kept, an extra one isn't")
eq(Url.Address(string.rep("a", 300) .. ".com"), nil, "an absurdly long word isn't")

-- Wrapping: the address becomes our link; everything else stays exactly.
local L = function(u) return "|cff7fd4ff|Haddon:GlassChat:url:" .. u .. "|h[" .. u .. "]|h|r" end
eq(Url.Wrap("see wowhead.com for that"), "see " .. L("wowhead.com") .. " for that", "an address in a sentence")
eq(Url.Wrap("no address here"), nil, "nothing to wrap: nil")
eq(Url.Wrap("two: a.com/x and https://b.io!"), "two: " .. L("a.com/x") .. " and " .. L("https://b.io") .. "!",
    "two addresses, the ! kept outside")
local item = "|cffa335ee|Hitem:19019::::::::60|h[Thunderfury, Blessed Blade of the Windseeker]|h|r"
eq(Url.Wrap("wts " .. item .. " pst"), nil, "a game link is never touched")
eq(Url.Wrap(item .. " see wowhead.com"), item .. " see " .. L("wowhead.com"), "an address beside a game link")
local tex = "|TInterface\\Icons\\inv_misc_coin_01.blp:14|t"
eq(Url.Wrap(tex .. " 5g"), nil, "a texture path is never an address")
eq(Url.Wrap("|cff00ff00green|r text"), nil, "a colour code is left alone")
eq(Url.Wrap("|cff00ccff|Hurl:wowhead.com|h[wowhead.com]|h|r"), nil, "an address another addon already linked isn't wrapped again")
eq(Url.Wrap("|Tsite.com/icon.blp:14|t ok"), nil, "nor a texture path that looks like one")
eq(Url.Wrap("|Hgarrmission:x|h[guide at wowhead.com/x here]|h"), nil, "nor an address inside another link's text")
eq(Url.Wrap("a||b.com"), "a||" .. L("b.com"), "a literal pipe ends a word")
eq(Url.Wrap(WoW.Secret("x")), nil, "a secret is never read")
-- A colour code right before an address stays a colour code (review of #32).
eq(Url.Wrap(item .. "-wowhead.com"), nil, "an address glued to a link's colour end isn't an address")
eq(Url.Wrap("|cffff0000wowhead.com|r"), "|cffff0000" .. L("wowhead.com") .. "|r", "a coloured address: the colour kept around it")
eq(Url.Wrap(item .. " wowhead.com"), item .. " " .. L("wowhead.com"), "and beside one")
-- Brackets and quotes around an address stay outside it.
eq(Url.Wrap("(wowhead.com)"), "(" .. L("wowhead.com") .. ")", "in round brackets")
eq(Url.Wrap('"https://x.com/a"'), '"' .. L("https://x.com/a") .. '"', "in quotes")
eq(Url.Wrap("<https://raider.io/c>"), "<" .. L("https://raider.io/c") .. ">", "in angle brackets")
eq(Url.Wrap("[wowhead.com]"), "[" .. L("wowhead.com") .. "]", "in typed square brackets")

-- The filter: false plus every argument, the first one wrapped.
local hidden, a1, a2, a12 = Url.Filter(nil, "CHAT_MSG_SAY", "go to wowhead.com", "Bob Smith", "", "", "", "", 0, 0, "", 0, 7, "Player-1-B")
eq(hidden, false, "never hides a line")
eq(a1, "go to " .. L("wowhead.com"), "the text is wrapped")
eq(a2, "Bob Smith", "the other arguments pass through")
local all = { Url.Filter(nil, "CHAT_MSG_SAY", "x.com", "Bob", "", "", "", "", 0, 0, "", 0, 7, "Player-1-B") }
eq(all[13], "Player-1-B", "all of them, the GUID included")
eq(select("#", Url.Filter(nil, "CHAT_MSG_SAY", "plain", "Bob")), 1, "nothing to wrap: just false")
check(WoW.messageFilters.CHAT_MSG_CHANNEL and WoW.messageFilters.CHAT_MSG_WHISPER, "registered on channels and whispers")
check(WoW.messageFilters.CHAT_MSG_EMOTE and WoW.messageFilters.CHAT_MSG_AFK, "and emotes and AFK replies")

-- One scan per line, whatever the number of windows (review of #32).
local scans, realWrap = 0, Url.Wrap
Url.Wrap = function(m) scans = scans + 1; return realWrap(m) end
for _ = 1, 3 do Url.Filter(nil, "CHAT_MSG_CHANNEL", "see x.com", "Bob", "", "", "", "", 0, 0, "", 0, 4242, "Player-1-B") end
eq(scans, 1, "a line shown in three windows is scanned once")
local _, again = Url.Filter(nil, "CHAT_MSG_CHANNEL", "see x.com", "Bob", "", "", "", "", 0, 0, "", 0, 4242, "Player-1-B")
eq(again, "see " .. L("x.com"), "and wrapped the same each time")
Url.Wrap = realWrap

-- Copied text has the address as typed, without the brackets on screen.
eq(GC.Copy.Plain("see " .. L("https://x.com/a") .. " now"), "see https://x.com/a now", "copy and focus get the plain address")
SlashCmdList.GLASSCHAT("urls off")
eq(select("#", Url.Filter(nil, "CHAT_MSG_SAY", "x.com", "Bob")), 1, "/gchat urls off: left alone")
SlashCmdList.GLASSCHAT("urls on")

-- A click opens the address, selected, read-only.
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:url:https://www.wowhead.com/item=19019")
local box = Url._test.box()
check(box and box:IsShown(), "a click opens the box")
eq(box.edit:GetText(), "https://www.wowhead.com/item=19019", "with the address")
check(box.edit._highlighted and box.edit._focused, "selected, for Ctrl+C")
box.edit._text = "typed over"
box.edit._scripts.OnTextChanged(box.edit, true)
eq(box.edit:GetText(), "https://www.wowhead.com/item=19019", "read-only")
box:Hide()
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:layout:no")
check(not box:IsShown(), "another GlassChat link doesn't open it")
WoW.callbacks.SetItemRef(nil, WoW.Secret("link"))
check(not box:IsShown(), "nor a secret one")

eq(next(GC.failures), nil, "nothing failed")
done("test_url")
