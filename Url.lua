-- Url.lua (M5): click a web address in chat to copy it.
--
-- Web addresses only (owner): http(s)://..., www...., and a bare
-- name.tld/path for a short list of endings players paste (wowhead.com,
-- raider.io, discord.gg...). Not e-mail addresses, not bare IPs: Prat's
-- UrlCopy (modules\UrlCopy.lua) matches those too, with the whole IANA list,
-- and the false positives follow.
--
-- A message filter on the player-chat events wraps each address in our own
-- link (|Haddon:GlassChat:url:<address>|h), returning false plus the new
-- arguments (ChatFrameFilters.lua:145-160). Game links, colours, textures and
-- atlases are never touched: only the plain text between them is scanned.
-- A click reaches EventRegistry "SetItemRef" (the addon link type,
-- ItemRefHandlersShared.lua) and opens a small glass box with the address
-- selected: addons can't write the clipboard here (probe items 2-3), so the
-- player presses Ctrl+C.

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local Url = {}
GC.Url = Url

Url.LINK = "addon:GlassChat:url:"
Url.COLOR = "ff7fd4ff"
Url.MAX = 255   -- longer runs aren't addresses anyone pastes; never build a huge link
Url.EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_AFK", "CHAT_MSG_DND",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL" }

-- Endings a bare name.tld is taken as an address for (with http(s):// or
-- www. any ending is). No ending that is also a short English word (it, me,
-- us, no, be, at, co...): "No.It drops" would become a link (review of #32);
-- youtu.be and friends are pasted with https:// anyway.
Url.TLDS = {}
for t in ("com net org io gg tv uk eu info dev app ca ru gl nl fr pl se fi dk cz ch au nz jp " ..
          "kr cn tw br mx ar xyz"):gmatch("%S+") do Url.TLDS[t] = true end

-- Punctuation that ends a sentence, not an address: "see wowhead.com." keeps
-- the dot outside. A closing bracket is kept when the address opened one.
-- A closing bracket, round or square, stays when the address opened it
-- (?q=[foo] keeps its ], Codex review of #32); an unmatched one goes.
local OPEN = { [")"] = "%(", ["]"] = "%[" }
local function trim(u)
    while true do
        local last = u:sub(-1)
        local open = OPEN[last]
        if last:find("[%.,;:!%?'\">]") then
            u = u:sub(1, -2)
        elseif open and select(2, u:gsub(open, "")) < select(2, u:gsub("%" .. last, "")) then
            u = u:sub(1, -2)
        else
            return u
        end
    end
end

-- Is this word (no spaces) a web address? Returns the address, or nil.
function Url.Address(word)
    if #word > Url.MAX then return nil end
    local u = trim(word)
    if u:find("^[Hh][Tt][Tt][Pp][Ss]?://[%w%-_%.~]+") then return u end
    if u:find("^[Ww][Ww][Ww]%.[%w%-]+%.%a%a+") then return u end
    -- A host name starts with a letter or digit, never "-".
    local host = u:match("^(%w[%w%-]*%.[%w%-%.]*%a%a+)[/:]") or u:match("^(%w[%w%-]*%.[%w%-%.]*%a%a+)$")
    if host then
        local tld = host:match("%.(%a+)$")
        if tld and Url.TLDS[tld:lower()] and not host:find("%.%.") then return u end
    end
    return nil
end

local function link(u)
    return "|c" .. Url.COLOR .. "|H" .. Url.LINK .. u .. "|h[" .. u .. "]|h|r"
end

-- Plain text (no escapes in it): each address word wrapped; the rest as it
-- was. Brackets and quotes before an address stay outside it, as trailing
-- punctuation does: "(wowhead.com)" links wowhead.com (review of #32).
local function wrapPlain(s)
    return (s:gsub("%S+", function(word)
        local lead, rest = word:match("^([%(%[\"'<]*)(.*)$")
        local u = Url.Address(rest)
        if not u then return nil end
        return lead .. link(u) .. rest:sub(#u + 1)   -- trim only shortens the end: u prefixes rest
    end))
end

-- The escapes that are never scanned: links (|H...|h...|h), textures and
-- atlases, colour codes (|cAARRGGBB, |cn...:, |r) and a literal pipe (||).
-- A colour right before an address must not join it (review of #32).
local ESCAPES = { "|H.-|h.-|h", "|[TA].-|[ta]", "|c%x%x%x%x%x%x%x%x", "|cn[^:]*:", "|r", "||" }
local function nextEscape(msg, pos)
    local bs, be
    for _, p in ipairs(ESCAPES) do
        local s, e = msg:find(p, pos)
        if s and (not bs or s < bs) then bs, be = s, e end
    end
    return bs, be
end

-- The message with every address outside those escapes wrapped; nil when
-- there was none.
function Url.Wrap(msg)
    if API.IsSecret(msg) or type(msg) ~= "string" or not msg:find("[%./]") then return nil end
    local out, pos, changed = {}, 1, false
    while pos <= #msg do
        local s, e = nextEscape(msg, pos)
        local plain = msg:sub(pos, s and s - 1 or #msg)
        local wrapped = wrapPlain(plain)
        if wrapped ~= plain then changed = true end
        out[#out + 1] = wrapped
        if not s then break end
        out[#out + 1] = msg:sub(s, e)
        pos = e + 1
    end
    return changed and table.concat(out) or nil
end

-- One decision per (event, lineID): each line reaches a filter once per
-- window that shows it (measured, FOREVER-PROBE 10), so the scan runs once.
Url.MEMO_SIZE = 200
local memo, memoOrder = {}, {}
local function remember(key, v)
    if memo[key] == nil then
        memoOrder[#memoOrder + 1] = key
        if #memoOrder > Url.MEMO_SIZE then memo[table.remove(memoOrder, 1)] = nil end
    end
    memo[key] = v
end

function Url.Filter(_, event, msg, ...)
    if not GC.db.urls then return false end
    local lineID = select(10, ...)   -- arg11
    local key
    if not API.IsSecret(lineID) and type(lineID) == "number" and lineID > 0 and type(event) == "string" then
        key = event .. "#" .. lineID
    end
    local wrapped
    if key and memo[key] ~= nil then
        wrapped = memo[key] or nil
    else
        wrapped = Url.Wrap(msg)
        if key then remember(key, wrapped or false) end
    end
    if not wrapped then return false end
    return false, wrapped, ...
end

--------------------------------------------------------------------------------
-- The box
--------------------------------------------------------------------------------

local box

local function build()
    box = API.Window("GlassChatUrlBox", 520, 104)
    box.title:SetText("Web address")
    box.hint:SetText("Selected. Press Ctrl+C to copy, then Esc to close.")
    local edit = CreateFrame("EditBox", nil, box)
    edit:SetFontObject("ChatFontNormal")
    edit:SetAutoFocus(false)
    edit:SetHeight(22)
    edit:SetPoint("TOPLEFT", box.hint, "BOTTOMLEFT", 0, -10)
    edit:SetPoint("RIGHT", box, "RIGHT", -14, 0)
    API.ReadOnly(edit, box, "url", true)   -- typing puts the address back, selected
    edit:SetScript("OnEnterPressed", function() box:Hide() end)
    box.edit = edit
end

function Url.Show(u)
    if API.IsSecret(u) or type(u) ~= "string" or u == "" then return end
    if not box then build() end
    box.url = u
    box:Show()
    box.edit:SetText(u)
    box.edit:SetFocus()
    box.edit:HighlightText()
end

function Url.OnLink(_, l)
    if API.IsSecret(l) or type(l) ~= "string" then return end
    if l:sub(1, #Url.LINK) == Url.LINK then Url.Show(l:sub(#Url.LINK + 1)) end
end

-- The filter goes in at PLAYER_LOGIN, after every addon's ADDON_LOADED:
-- filters run in the order they were added, and the Spam & Ignore plugin
-- (loaded after GlassChat) must judge the text as typed, not our links
-- (review of #32: a mute of "cheapgold.com" would stop matching).
local started, filtered = false, false
function Url.AddFilters()
    if filtered then return end
    filtered = true
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        for _, e in ipairs(Url.EVENTS) do ChatFrameUtil.AddMessageEventFilter(e, Url.Filter) end
    end
end

function Url.Start()
    if started then return end
    started = true
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function() Url.AddFilters() end)
    API.RegisterEvents(f, { "PLAYER_LOGIN" })
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", Url.OnLink, Url)
    end
end

Url._test = { box = function() return box end, reset = function() memo, memoOrder = {}, {} end }
