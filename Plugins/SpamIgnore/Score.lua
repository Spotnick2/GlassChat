-- Score.lua (Spam & Ignore, S4): the spam score (docs/PLAN-SPAM.md, "A spam
-- score").
--
-- Shape, never words: every signal is language-neutral (addresses, prices,
-- contacts, broken-up words, look-alike letters), never an English word
-- list. A line is spam when it has a SPAM kind (a real-money price, a
-- broken-up word, look-alike letters) together with any other kind. An
-- address with a contact is players' own advertising (guild recruitment, a
-- stream, an addon's page: Codex review of #46) and never decides.
--
-- Each token (a run between spaces) counts toward at most one token kind
-- (address, contact, price, first match wins), so one discord link is never
-- two kinds. Broken-up words and look-alike letters look at the line itself.
-- Takes plain strings only: the caller checks IsSecret first.

GlassChat = GlassChat or {}
local GC = GlassChat
local Text = GC.SpamText
local Score = {}
GC.SpamScore = Score

Score.FRAGMENTS = 5     -- p.r.o.f.i.t; G G W P (4) and L F M (3) don't count
Score.LOG_SIZE = 100    -- would-hide lines
Score.NEAR_SIZE = 50    -- near misses: their own buffer, so a busy channel's
                        -- links never push out what watch mode is for (review of #47)
Score.ORDER = { "price", "broken-up", "look-alike", "address", "contact" }
Score.SPAM = { price = true, ["broken-up"] = true, ["look-alike"] = true }

-- Endings a bare name.tld counts as an address for, beyond M5's list: the ones
-- spam favours, matched only as typed in lower case (Url.Address's extra), so
-- "tank.Top" (a missing space) isn't one. Not "any 2-6 letters": that took
-- item.level, GlassChat.lua and lol.ok for addresses (Codex review of #46).
Score.TLDS = {}
for t in ("shop top vip xyz club online site store cc biz co ru"):gmatch("%S+") do Score.TLDS[t] = true end

-- The look-alike letters: Cyrillic and Greek letters that are a Latin letter's
-- twin in every font, upper and lower case. Cyrillic т, в and н are left out:
-- they look Latin only in some fonts (Codex review of #46).
local LOOK = {
    [0x0430] = "a", [0x0435] = "e", [0x043E] = "o", [0x0440] = "p", [0x0441] = "c", [0x0443] = "y",
    [0x0445] = "x", [0x0456] = "i", [0x0458] = "j", [0x0455] = "s", [0x043A] = "k", [0x043C] = "m",
    [0x0410] = "a", [0x0412] = "b", [0x0415] = "e", [0x041A] = "k", [0x041C] = "m", [0x041D] = "h",
    [0x041E] = "o", [0x0420] = "p", [0x0421] = "c", [0x0422] = "t", [0x0425] = "x",
    [0x0405] = "s", [0x0406] = "i", [0x0408] = "j", [0x0423] = "y",
    [0x03BF] = "o", [0x03C1] = "p", [0x03B1] = "a", [0x03B5] = "e", [0x03B9] = "i", [0x03BA] = "k",
    [0x03BD] = "v", [0x03C4] = "t", [0x03C7] = "x",
    [0x0391] = "a", [0x0392] = "b", [0x0395] = "e", [0x0396] = "z", [0x0397] = "h", [0x0399] = "i",
    [0x039A] = "k", [0x039C] = "m", [0x039D] = "n", [0x039F] = "o", [0x03A1] = "p", [0x03A4] = "t",
    [0x03A7] = "x", [0x03A5] = "y",
}
Score.LOOK = LOOK
-- The Latin letters that have such a twin: inside a Cyrillic or Greek word
-- they're the same disguise the other way round (гoлд, with a Latin o).
local TWIN = {}
for _, l in pairs(LOOK) do TWIN[l:byte()] = true; TWIN[l:upper():byte()] = true end

local CURRENCY = { "$", "\226\130\172", "\194\163", "\194\165", "\226\130\189" }   -- $ € £ ¥ ₽

local function isLatin(cp) return (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122) end
local function isDigit(cp) return cp >= 48 and cp <= 57 end
local function isGreekOrCyrillic(cp) return (cp >= 0x0370 and cp <= 0x03FF) or (cp >= 0x0400 and cp <= 0x04FF) end
-- A letter or digit, for fragments: ASCII, accented Latin, Greek, Cyrillic.
local function isAlnum(cp)
    return isLatin(cp) or isDigit(cp) or (cp >= 0xC0 and cp <= 0x24F and cp ~= 0xD7 and cp ~= 0xF7)
        or isGreekOrCyrillic(cp)
end
local SEP = { [32] = true, [46] = true, [45] = true, [95] = true, [47] = true, [44] = true, [42] = true, [0xB7] = true }

local function utf8char(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
    end
    return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
        0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

-- A token with its leading brackets and quotes and its trailing punctuation
-- off, as M5's address wrapper does.
local function bare(token)
    return (token:gsub("^[%(%[{\"'<]+", ""):gsub("[%.,;:!%?\"'%)%]}>]+$", ""))
end

-- The token with look-alike letters as their Latin twins (gоldsite.com is
-- still an address).
local function unmask(token)
    if not token:find("[\128-\255]") then return token end
    local out = {}
    for _, cp in ipairs(Text.CodePoints(token)) do
        out[#out + 1] = LOOK[cp] or (cp >= 0 and utf8char(cp)) or "?"
    end
    return table.concat(out)
end

-- An address: M5's own matcher (one grammar for both), with spam's endings
-- added. A host spelled out a character at a time (b.u.y.g.o.l.d.cc) is a
-- broken-up word too: the second return (review of #47).
local function isAddress(token)
    local t = unmask(token)
    if not GC.Url.Address(t, Score.TLDS) then return false end
    local host = t:gsub("^%a+://", ""):match("^([^/:]+)") or ""
    local single = 0
    for label in host:gmatch("[^%.]+") do
        if #label == 1 then single = single + 1 end
    end
    return true, single >= 3
end

local function isContact(token)
    if token:find("^@[%w\128-\255][%w\128-\255]+$") then return true end
    local digits = token:match("^[%a\128-\255][%a\128-\255]+#(%d+)$")
    return digits ~= nil and #digits >= 4 and #digits <= 5
end

-- A currency symbol right before or after a digit, anywhere in the token:
-- $5, 10$, $1,000, 1.000€, 1000g=5$, 5$/1k (review of #47). A symbol on its
-- own next to a number ("5 $") is caught in Score.Check, a token later.
local function isPrice(token)
    for _, sym in ipairs(CURRENCY) do
        local at = 1
        while true do
            local a, b = token:find(sym, at, true)
            if not a then break end
            if token:sub(a - 1, a - 1):find("%d") or token:sub(b + 1, b + 1):find("%d") then return true end
            at = b + 1
        end
    end
    return false
end
local function isLoneSymbol(word)
    for _, sym in ipairs(CURRENCY) do if word == sym then return true end end
    return false
end
local function isNumber(word) return word:find("^%d[%d%.,]*$") ~= nil end

local TOKEN_KINDS = { { "address", isAddress }, { "contact", isContact }, { "price", isPrice } }

-- A maximal run of single letters or digits, each set apart by separators,
-- in the line's code points with the counted tokens blanked out (as "#").
local function brokenUp(cps)
    local run, i, n = 0, 1, #cps
    while i <= n do
        local cp = cps[i]
        if isAlnum(cp) then
            local prev, nxt = cps[i - 1], cps[i + 1]
            local alone = (not prev or SEP[prev]) and (not nxt or SEP[nxt])
            if alone then
                run = run + 1
                if run >= Score.FRAGMENTS then return true end
            else
                run = 0
                while i <= n and isAlnum(cps[i]) do i = i + 1 end   -- the rest of this word
                i = i - 1
            end
        elseif not SEP[cp] then
            run = 0
        end
        i = i + 1
    end
    return false
end

-- One script's letters disguised as the other's, inside a word:
-- - a Latin word (2+ Latin letters) whose only Greek or Cyrillic letters are
--   twins, at least one of them between Latin letters or digits (gоld);
-- - a Cyrillic or Greek word (2+ of those letters) whose only Latin letters
--   are twins, at least one of them between Cyrillic or Greek letters (гoлд,
--   review of #47).
-- An ending on an acronym (Russian MCе, AVке, ZGшку) is never inside the
-- word, so it never counts (Codex review of #46).
local function disguised(cps, own, other, twin)
    local count, inside = 0, false
    for i, cp in ipairs(cps) do
        if own(cp) then
            count = count + 1
        elseif other(cp) then
            if not twin(cp) then return false end
            if not inside then
                local a, b = i - 1, i + 1
                while a >= 1 and other(cps[a]) and twin(cps[a]) do a = a - 1 end
                while b <= #cps and other(cps[b]) and twin(cps[b]) do b = b + 1 end
                local before, after = cps[a], cps[b]
                inside = before ~= nil and after ~= nil and (own(before) or isDigit(before))
                    and (own(after) or isDigit(after))
            end
        end
    end
    return count >= 2 and inside
end
local function isLook(cp) return LOOK[cp] ~= nil end
local function isTwin(cp) return TWIN[cp] == true end
local function lookAlike(word)
    if not word:find("[\128-\255]") then return false end
    local cps = Text.CodePoints(word)
    return disguised(cps, isLatin, isGreekOrCyrillic, isLook) or disguised(cps, isGreekOrCyrillic, isLatin, isTwin)
end

-- Decoration: recorded for the score log, never a kind. Symbols (arrows,
-- shapes, dingbats, emoji) a fifth or more of the line, or 4+ of one
-- punctuation mark in a row.
local function isSymbol(cp)
    return (cp >= 0x2190 and cp <= 0x21FF) or (cp >= 0x2500 and cp <= 0x27BF) or (cp >= 0x2B00 and cp <= 0x2BFF)
        or (cp >= 0x1F300 and cp <= 0x1FAFF)
end
local function decorated(plain)
    if plain:find("([!%?%.%*~=%-])%1%1%1") then return true end
    local sym, total = 0, 0
    for _, cp in ipairs(Text.CodePoints(plain)) do
        if cp > 32 then
            total = total + 1
            if isSymbol(cp) then sym = sym + 1 end
        end
    end
    return sym >= 3 and sym * 5 >= total
end

-- The kinds a line has. Returns { has = {kind=true}, kinds = {...} in
-- Score.ORDER, decor = bool, spam = bool, plain = the text as shown }.
function Score.Check(text)
    local plain = GC.Copy.Plain(text) or ""
    local has, prev = {}, ""
    local rest = plain:gsub("%S+", function(token)
        local word = bare(token)
        local before = prev
        prev = word
        if word == "" then return nil end
        if lookAlike(word) then has["look-alike"] = true end
        for _, k in ipairs(TOKEN_KINDS) do
            local yes, spelled = k[2](word)
            if yes then
                has[k[1]] = true
                if spelled then has["broken-up"] = true end
                return "#"   -- counted: no part of it is a fragment
            end
        end
        -- "5 $" and "$ 5": a lone symbol beside a number.
        if (isLoneSymbol(word) and isNumber(before)) or (isNumber(word) and isLoneSymbol(before)) then
            has.price = true
        end
    end)
    if brokenUp(Text.CodePoints(rest)) then has["broken-up"] = true end
    local kinds, spam = {}, false
    for _, k in ipairs(Score.ORDER) do
        if has[k] then
            kinds[#kinds + 1] = k
            if Score.SPAM[k] then spam = true end
        end
    end
    -- Decoration only matters for a line the score log keeps.
    return { has = has, kinds = kinds, decor = #kinds > 0 and decorated(plain) or false,
             spam = spam and #kinds >= 2, plain = plain }
end

function Score.Label(r) return table.concat(r.kinds, " + ") end

--------------------------------------------------------------------------------
-- The score log: every public line the score saw a kind in, whatever the mode,
-- with what finally happened to it; would-hide lines and near misses in their
-- own buffers. Never the hidden-lines log or the icon's count. Session memory.
--------------------------------------------------------------------------------

local log, near = {}, {}
function Score.Record(event, sender, r, outcome, noid)
    local into, cap = log, Score.LOG_SIZE
    if not r.spam then into, cap = near, Score.NEAR_SIZE end
    into[#into + 1] = { t = date("%H:%M:%S"), event = event:gsub("^CHAT_MSG_", ""), sender = sender or "?",
                        label = Score.Label(r), spam = r.spam, decor = r.decor, outcome = outcome,
                        noid = noid, text = r.plain }
    if #into > cap then table.remove(into, 1) end
end
function Score.Log() return log end
function Score.Near() return near end

local function addLines(list, out)
    for i = #list, 1, -1 do
        local e = list[i]
        local tags = e.label .. (e.decor and ", decorated" or "") .. (e.noid and ", no id" or "")
        out[#out + 1] = string.format("[%s] [%s] %s -> %s  %s: %s", e.t, tags, e.event, e.outcome, e.sender, e.text)
    end
end
-- Spam first, then the near misses; newest first in each.
function Score.LogText()
    local out = {}
    if #log > 0 then out[#out + 1] = "-- spam (" .. #log .. ")"; addLines(log, out) end
    if #near > 0 then out[#out + 1] = "-- near misses (" .. #near .. ")"; addLines(near, out) end
    return table.concat(out, "\n")
end

Score._test = {
    reset = function() log, near = {}, {} end,
    brokenUp = function(s) return brokenUp(Text.CodePoints(s)) end,
    lookAlike = lookAlike, isAddress = isAddress, isContact = isContact, isPrice = isPrice,
}
