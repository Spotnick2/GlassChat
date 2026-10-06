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

Score.FRAGMENTS = 5   -- p.r.o.f.i.t; G G W P (4) and L F M (3) don't count
Score.LOG_SIZE = 100
Score.ORDER = { "price", "broken-up", "look-alike", "address", "contact" }
Score.SPAM = { price = true, ["broken-up"] = true, ["look-alike"] = true }

-- Endings a bare name.tld counts as an address for, beyond M5's list: the ones
-- spam favours. Not "any 2-6 letters": that took item.level, GlassChat.lua
-- and lol.ok for addresses (Codex review of #46).
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
    [0x03BF] = "o", [0x03C1] = "p", [0x03B1] = "a", [0x03B5] = "e", [0x03B9] = "i", [0x03BA] = "k",
    [0x03BD] = "v", [0x03C4] = "t", [0x03C7] = "x",
    [0x0391] = "a", [0x0392] = "b", [0x0395] = "e", [0x0396] = "z", [0x0397] = "h", [0x0399] = "i",
    [0x039A] = "k", [0x039C] = "m", [0x039D] = "n", [0x039F] = "o", [0x03A1] = "p", [0x03A4] = "t",
    [0x03A7] = "x",
}
Score.LOOK = LOOK

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

local function isAddress(token)
    local t = unmask(token)
    if GC.Url and GC.Url.Address(t) == t then return true end
    local host = t:match("^([^/]+)")
    if not host or not host:find("%.") then return false end
    local labels = {}
    for label in (host .. "."):gmatch("([^%.]*)%.") do
        if not label:find("^%w[%w%-]*$") or label:find("%-$") then return false end
        labels[#labels + 1] = label
    end
    if #labels < 2 then return false end
    local tld = labels[#labels]:lower()
    return tld:find("^%a+$") ~= nil and (Score.TLDS[tld] or (GC.Url and GC.Url.TLDS[tld])) and true or false
end

local function isContact(token)
    if token:find("^@[%w\128-\255][%w\128-\255]+$") then return true end
    local digits = token:match("^[%a\128-\255][%a\128-\255]+#(%d+)$")
    return digits ~= nil and #digits >= 4 and #digits <= 5
end

-- 1-6 digits, with cents allowed: 5, 10, 4.99, 1,50.
local function isAmount(s)
    local int = s:match("^(%d+)$") or s:match("^(%d+)[%.,]%d%d?$")
    return int ~= nil and #int <= 6
end
local function isPrice(token)
    for _, sym in ipairs(CURRENCY) do
        local n = #sym
        if token:sub(1, n) == sym and isAmount(token:sub(n + 1)) then return true end
        if token:sub(-n) == sym and isAmount(token:sub(1, -n - 1)) then return true end
    end
    return false
end

local TOKEN_KINDS = { { "address", isAddress }, { "contact", isContact }, { "price", isPrice } }

-- A maximal run of single letters or digits, each set apart by separators.
-- Code points of the line with the counted tokens blanked out (-2).
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

-- A word with at least two Latin letters whose only Greek or Cyrillic letters
-- are look-alikes, at least one of them inside the word, between Latin
-- letters or digits (gоld). An ending on a Latin acronym (Russian MCе, AVке,
-- ZGшку) is never inside the word, so it never counts (Codex review of #46).
local function lookAlike(word)
    if not word:find("[\128-\255]") then return false end
    local cps = Text.CodePoints(word)
    local latin, inside = 0, false
    for i, cp in ipairs(cps) do
        if isLatin(cp) then
            latin = latin + 1
        elseif isGreekOrCyrillic(cp) then
            if not LOOK[cp] then return false end
            if not inside then
                local a, b = i - 1, i + 1
                while a >= 1 and LOOK[cps[a]] do a = a - 1 end
                while b <= #cps and LOOK[cps[b]] do b = b + 1 end
                local before, after = cps[a], cps[b]
                inside = before ~= nil and after ~= nil and (isLatin(before) or isDigit(before))
                    and (isLatin(after) or isDigit(after))
            end
        end
    end
    return latin >= 2 and inside
end

-- Decoration: recorded for the score log, never a kind. Symbols (arrows,
-- shapes, dingbats, emoji) a fifth or more of the line, or 4+ of one
-- punctuation mark in a row.
local function isSymbol(cp)
    return (cp >= 0x2190 and cp <= 0x21FF) or (cp >= 0x2500 and cp <= 0x27BF) or (cp >= 0x2B00 and cp <= 0x2BFF)
        or (cp >= 0x1F300 and cp <= 0x1FAFF)
end
local function decorated(plain, cps)
    if plain:find("([!%?%.%*~=%-])%1%1%1") then return true end
    local sym, total = 0, 0
    for _, cp in ipairs(cps) do
        if cp > 32 then
            total = total + 1
            if isSymbol(cp) then sym = sym + 1 end
        end
    end
    return sym >= 3 and sym * 5 >= total
end

-- The kinds a line has. Returns { has = {kind=true}, kinds = {...} in
-- Score.ORDER, decor = bool, spam = bool }.
function Score.Check(text)
    local plain = GC.Copy.Plain(text) or ""
    local has = {}
    local rest = plain:gsub("%S+", function(token)
        local word = bare(token)
        if word ~= "" and lookAlike(word) then has["look-alike"] = true end
        for _, k in ipairs(TOKEN_KINDS) do
            if word ~= "" and k[2](word) then
                has[k[1]] = true
                return "#"   -- counted: no part of it is a fragment
            end
        end
    end)
    local cps = Text.CodePoints(rest)
    if brokenUp(cps) then has["broken-up"] = true end
    local kinds, spam = {}, false
    for _, k in ipairs(Score.ORDER) do
        if has[k] then
            kinds[#kinds + 1] = k
            if Score.SPAM[k] then spam = true end
        end
    end
    return { has = has, kinds = kinds, decor = decorated(plain, Text.CodePoints(plain)),
             spam = spam and #kinds >= 2, plain = plain }
end

function Score.Label(r) return table.concat(r.kinds, " + ") end

--------------------------------------------------------------------------------
-- The score log: every public line the score saw a kind in, whatever the mode,
-- with what finally happened to it. Never the hidden-lines log or the icon's
-- count (session memory, like the hidden-lines log).
--------------------------------------------------------------------------------

local log = {}
function Score.Record(event, sender, r, outcome, noid)
    log[#log + 1] = { t = date("%H:%M:%S"), event = event:gsub("^CHAT_MSG_", ""), sender = sender or "?",
                      label = Score.Label(r), spam = r.spam, decor = r.decor, outcome = outcome,
                      noid = noid, text = r.plain }
    if #log > Score.LOG_SIZE then table.remove(log, 1) end
end
function Score.Log() return log end

function Score.LogText()
    local lines = {}
    for i = #log, 1, -1 do
        local e = log[i]
        local tags = (e.spam and "SPAM " or "") .. e.label .. (e.decor and ", decorated" or "") .. (e.noid and ", no id" or "")
        lines[#lines + 1] = string.format("%s  [%s] %s -> %s  %s: %s", e.t, tags, e.event, e.outcome, e.sender, e.text)
    end
    return table.concat(lines, "\n")
end

Score._test = {
    reset = function() log = {} end,
    brokenUp = function(s) return brokenUp(Text.CodePoints(s)) end,
    lookAlike = lookAlike, isAddress = isAddress, isContact = isContact, isPrice = isPrice,
}
