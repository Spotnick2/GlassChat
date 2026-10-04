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
Url.EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL" }

-- Endings a bare name.tld is taken as an address for (with http(s):// or
-- www. any ending is).
Url.TLDS = {}
for t in ("com net org io gg tv me co uk de fr eu info dev app ly be ca us ru gl nl es it pl " ..
          "se no fi dk cz at ch au nz jp kr cn tw br mx ar xyz"):gmatch("%S+") do Url.TLDS[t] = true end

-- Punctuation that ends a sentence, not an address: "see wowhead.com." keeps
-- the dot outside. A closing bracket is kept when the address opened one.
local function trim(u)
    while true do
        local last = u:sub(-1)
        if last:find("[%.,;:!%?'\"]") then
            u = u:sub(1, -2)
        elseif last == ")" and select(2, u:gsub("%(", "")) < select(2, u:gsub("%)", "")) then
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
    local host = u:match("^([%w%-]+%.[%w%-%.]*%a%a+)[/:]") or u:match("^([%w%-]+%.[%w%-%.]*%a%a+)$")
    if host then
        local tld = host:match("%.(%a+)$")
        if tld and Url.TLDS[tld:lower()] and not host:find("%.%.") then return u end
    end
    return nil
end

local function link(u)
    return "|c" .. Url.COLOR .. "|H" .. Url.LINK .. u .. "|h[" .. u .. "]|h|r"
end

-- Plain text: each address word wrapped; the rest as it was. "||" (a literal
-- pipe) never starts an address: words are split on spaces and pipes.
local function wrapPlain(s)
    return (s:gsub("[^%s|]+", function(word)
        local u = Url.Address(word)
        if not u then return nil end
        local start = word:find(u, 1, true)
        return word:sub(1, start - 1) .. link(u) .. word:sub(start + #u)
    end))
end

-- The message with every address outside game links, colour codes, textures
-- and atlases wrapped; nil when there was none.
function Url.Wrap(msg)
    if API.IsSecret(msg) or type(msg) ~= "string" or not msg:find("[%./]") then return nil end
    local out, pos, changed = {}, 1, false
    while pos <= #msg do
        -- The next escape: a link (|H...|h...|h), a texture or atlas, a colour.
        local s, e = msg:find("|H.-|h.-|h", pos)
        local ts, te = msg:find("|[TA].-|[ta]", pos)
        if ts and (not s or ts < s) then s, e = ts, te end
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

function Url.Filter(_, _, msg, ...)
    if not GC.db.urls then return false end
    local wrapped = Url.Wrap(msg)
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
    edit:SetScript("OnEscapePressed", function() box:Hide() end)
    edit:SetScript("OnEnterPressed", function() box:Hide() end)
    -- Read-only: typing puts the address back, selected.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and box.url then
            self:SetText(box.url)
            self:HighlightText()
        end
    end)
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

local started = false
function Url.Start()
    if started then return end
    started = true
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        for _, e in ipairs(Url.EVENTS) do ChatFrameUtil.AddMessageEventFilter(e, Url.Filter) end
    end
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", Url.OnLink, Url)
    end
end

Url._test = { box = function() return box end }
