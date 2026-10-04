-- Text.lua (Spam & Ignore): the text forms the filters match on.
--
-- Lua 5.1 strings and patterns are bytes, so UTF-8 is decoded by hand
-- (Codex's review of the plan). Malformed bytes decode as nothing, never as
-- a match. Every function here takes plain strings only: callers check
-- IsSecret first.

GlassChat = GlassChat or {}
local GC = GlassChat
local Text = {}
GC.SpamText = Text

-- Code points of a UTF-8 string, in order. A malformed byte gives -1.
function Text.CodePoints(s)
    local out, i, n = {}, 1, #s
    while i <= n do
        local c = s:byte(i)
        local cp, len = -1, 1
        if c < 0x80 then cp = c
        elseif c >= 0xC2 and c <= 0xDF and i + 1 <= n then
            cp, len = (c - 0xC0) * 64 + (s:byte(i + 1) - 0x80), 2
        elseif c >= 0xE0 and c <= 0xEF and i + 2 <= n then
            cp, len = ((c - 0xE0) * 64 + (s:byte(i + 1) - 0x80)) * 64 + (s:byte(i + 2) - 0x80), 3
        elseif c >= 0xF0 and c <= 0xF4 and i + 3 <= n then
            cp, len = (((c - 0xF0) * 64 + (s:byte(i + 1) - 0x80)) * 64 + (s:byte(i + 2) - 0x80)) * 64 + (s:byte(i + 3) - 0x80), 4
        end
        out[#out + 1] = cp
        i = i + len
    end
    return out
end

-- The text as seen on screen: colours, links (text kept), textures out
-- (the core's copy helper), lowercased, spaces collapsed.
function Text.Visible(s)
    local plain = GC.Copy.Plain(s) or ""
    return (plain:lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- A literal phrase match at word edges: "kit" matches "Kit!" and "kits"
-- isn't required to; "kite" never matches "kit" (an ASCII letter or digit
-- right after or before the phrase means it's inside another word). The
-- plain flag of string.find: never a Lua pattern.
local function isWordByte(b) return b and ((b >= 48 and b <= 57) or (b >= 97 and b <= 122)) end
function Text.HasPhrase(visible, phrase, allowPlural)
    local start = 1
    while true do
        local a, b = visible:find(phrase, start, true)
        if not a then return false end
        local before, after = visible:byte(a - 1), visible:byte(b + 1)
        local edgeAfter = not isWordByte(after) or (allowPlural and after == 115 and not isWordByte(visible:byte(b + 2)))
        if not isWordByte(before) and edgeAfter then return true end
        start = a + 1
    end
end

-- The aggressive form (opt-in per mute): homoglyphs and full-width forms
-- mapped to ASCII, lowercase, every ASCII separator dropped. Digits stay
-- digits; unmapped characters stay as they are.
local GLYPHS = {
    -- Cyrillic look-alikes
    [0x0430] = "a", [0x0410] = "a", [0x0435] = "e", [0x0415] = "e", [0x043E] = "o", [0x041E] = "o",
    [0x0440] = "p", [0x0420] = "p", [0x0441] = "c", [0x0421] = "c", [0x0445] = "x", [0x0425] = "x",
    [0x0443] = "y", [0x0423] = "y", [0x043A] = "k", [0x041A] = "k", [0x043C] = "m", [0x041C] = "m",
    [0x0442] = "t", [0x0422] = "t", [0x0432] = "b", [0x0412] = "b", [0x043D] = "h", [0x041D] = "h",
    [0x0456] = "i", [0x0406] = "i", [0x0458] = "j", [0x0405] = "s", [0x0455] = "s",
    -- Greek look-alikes
    [0x03B1] = "a", [0x0391] = "a", [0x03B5] = "e", [0x0395] = "e", [0x03BF] = "o", [0x039F] = "o",
    [0x03C1] = "p", [0x03A1] = "p", [0x03C4] = "t", [0x03A4] = "t", [0x03BA] = "k", [0x039A] = "k",
    [0x03BD] = "v", [0x03B9] = "i", [0x0399] = "i", [0x039C] = "m", [0x039D] = "n", [0x0396] = "z",
    -- Accented Latin
    [0xE0] = "a", [0xE1] = "a", [0xE2] = "a", [0xE3] = "a", [0xE4] = "a", [0xE5] = "a",
    [0xE8] = "e", [0xE9] = "e", [0xEA] = "e", [0xEB] = "e", [0xEC] = "i", [0xED] = "i", [0xEE] = "i", [0xEF] = "i",
    [0xF2] = "o", [0xF3] = "o", [0xF4] = "o", [0xF5] = "o", [0xF6] = "o", [0xF9] = "u", [0xFA] = "u",
    [0xFB] = "u", [0xFC] = "u", [0xE7] = "c", [0xF1] = "n", [0xFD] = "y",
    [0xC0] = "a", [0xC1] = "a", [0xC2] = "a", [0xC4] = "a", [0xC8] = "e", [0xC9] = "e", [0xCA] = "e",
    [0xD3] = "o", [0xD6] = "o", [0xDC] = "u", [0xC7] = "c",
}
function Text.Aggressive(s)
    local out = {}
    for _, cp in ipairs(Text.CodePoints(GC.Copy.Plain(s) or "")) do
        if cp >= 0xFF01 and cp <= 0xFF5E then cp = cp - 0xFEE0 end   -- full-width ASCII
        local g = GLYPHS[cp]
        if g then
            out[#out + 1] = g
        elseif cp >= 65 and cp <= 90 then
            out[#out + 1] = string.char(cp + 32)
        elseif (cp >= 97 and cp <= 122) or (cp >= 48 and cp <= 57) then
            out[#out + 1] = string.char(cp)
        elseif cp >= 128 then
            out[#out + 1] = "\\" .. cp   -- unmapped: kept, as a token that never meets ASCII
        end                              -- ASCII separators and malformed bytes: dropped
    end
    return table.concat(out)
end

-- CJK (owner: on by default): ideographs, extension A, kana, Hangul, CJK
-- punctuation, full-width forms. A line counts when it holds at least
-- CJK_MIN of them AND they're at least a third of its non-space
-- characters, so a stray symbol or a name inside an English line never does.
Text.CJK_MIN = 3
local function isCJK(cp)
    return (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0x3400 and cp <= 0x4DBF) or (cp >= 0x3040 and cp <= 0x30FF)
        or (cp >= 0xAC00 and cp <= 0xD7AF) or (cp >= 0x3000 and cp <= 0x303F) or (cp >= 0xFF00 and cp <= 0xFFEF)
end
function Text.IsCJK(s)
    local cjk, total = 0, 0
    for _, cp in ipairs(Text.CodePoints(GC.Copy.Plain(s) or "")) do
        if cp > 32 then
            total = total + 1
            if isCJK(cp) then cjk = cjk + 1 end
        end
    end
    return cjk >= Text.CJK_MIN and cjk * 3 >= total
end

-- The repeat key: what's seen, with each link's own data kept, so two posts
-- about different items are never one repeat (Codex's review of the plan).
function Text.RepeatKey(s)
    local links = {}
    for data in s:gmatch("|H(.-)|h") do links[#links + 1] = data end
    return Text.Visible(s) .. "|" .. table.concat(links, ",")
end

Text._test = { isCJK = isCJK }
