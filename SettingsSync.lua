-- SettingsSync.lua: your settings, and optionally your chat layout, on your
-- other WoW accounts (#52; plan: docs/PLAN-SETTINGS.md, reviewed by Codex).
--
-- Through GlassChat's LibAccountSync-1.0 link (AccountSync.lua), payload kind
-- "ST", separate from Spam & Ignore's lists ("SI"). Sending is manual
-- (/gchat settings send [layout]); receiving never sends anything back.
--
-- A small registry holds what may travel: section "core" (registered here)
-- and "spam" (the plugin's). Each key has a type, a range or allowed values,
-- its raw getter (nil when unset), its default and the SAME setter its slash
-- command uses, so a received value is applied exactly as a typed one.
-- A key at its default travels as D ("at its default"): the receiver resets
-- its own through set(default), then clears it (a setter never takes nil).
--
-- The payload is data from another client: never run, every field checked.
-- Its shape is all-or-nothing (format, record letters, field counts, type
-- marks, caps, duplicates); a single value this copy can't take (an unknown
-- key, out of range, an unknown choice) is skipped and reported, so two
-- versions still copy everything else.
--
-- Format "ST1": one record per line, fields split by tabs:
--   ST1                                  the format, first
--   T  <time()>                          when it was sent
--   V  <section> <key> <b|i|n|e> <value> a value set
--   D  <section> <key>                   at its default
--   L  W <i> <field> <b|i|n|e|s> <value> the layout: a window's field
--   L  M <i> <group>                     one of its message groups
--   L  C <i> <channel>                   one of its channels

GlassChat = GlassChat or {}
local GC = GlassChat
local API = GC.API
local SS = {}
GC.SettingsSync = SS

SS.KIND = "ST"
SS.FORMAT = "ST1"
-- Caps a real layout fits (a main window has 40+ message groups), up to what
-- the link carries; a send is checked against them first (Codex review of #62).
SS.MAX = 32768
SS.LINE_MAX = 256
SS.RECORDS_MAX = 2000
SS.GROUPS_MAX = 128
SS.CHANNELS_MAX = 32
SS.NAME_MAX = 64

local function say(msg) API.Print(msg) end

local function plainString(v)
    if API.IsSecret(v) or type(v) ~= "string" then return nil end
    return v
end
local function plainName(s)
    return type(s) == "string" and not API.IsSecret(s) and #s >= 1 and #s <= SS.NAME_MAX
        and not s:find("[%c|]") and true or false
end
local function finite(n) return type(n) == "number" and n == n and n > -1e15 and n < 1e15 end

--------------------------------------------------------------------------------
-- The registry
--------------------------------------------------------------------------------

local sections, order = {}, {}

-- keys: an array of { key, type = "b"|"i"|"n"|"e", lo, hi (numbers, or
-- functions for call-time ranges), values = {..} (for "e"), default =
-- function, get = function (raw, nil when unset), set = function(v),
-- reset = optional function (else set(default) then clear), clear = function,
-- label = optional display name }.
function SS.Register(name, keys)
    if not sections[name] then order[#order + 1] = name end
    local byKey = {}
    for _, k in ipairs(keys) do byKey[k.key] = k end
    sections[name] = { keys = keys, byKey = byKey }
end

local function bound(v) if type(v) == "function" then return v() end return v end

-- A value this spec accepts: nil, or why not.
local function rejects(spec, v)
    if spec.type == "b" then return type(v) ~= "boolean" and "not on/off" or nil end
    if spec.type == "e" then
        for _, ok in ipairs(spec.values) do if v == ok then return nil end end
        return "not a choice here"
    end
    if not finite(v) then return "not a number" end
    if spec.type == "i" and v ~= math.floor(v) then return "not a whole number" end
    local lo, hi = bound(spec.lo), bound(spec.hi)
    if lo and v < lo then return "under " .. lo .. " here" end
    if hi and v > hi then return "over " .. hi .. " here" end
    return nil
end

local function same(spec, a, b)
    if spec.type == "n" and type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-9 end
    return a == b
end

local function encode(spec, v)
    if spec.type == "b" then return v and "1" or "0" end
    if spec.type == "i" then return string.format("%d", v) end
    if spec.type == "n" then return string.format("%.10g", v) end
    return v
end

local function decode(mark, s)
    if mark == "b" then
        if s == "1" then return true elseif s == "0" then return false end
        return nil
    elseif mark == "i" then
        if not s:find("^%-?%d+$") then return nil end
        return tonumber(s)
    elseif mark == "n" then
        if not s:find("^%-?%d+%.?%d*$") and not s:find("^%-?%d*%.%d+$") and not s:find("^%-?%d+%.?%d*e[%+%-]?%d+$") then
            return nil
        end
        local n = tonumber(s)
        return finite(n) and n or nil
    elseif mark == "e" then
        return s:find("^[%w_%-]+$") and #s <= 32 and s or nil
    elseif mark == "s" then
        return plainName(s) and s or nil
    end
    return nil
end

-- The core's keys, read and set at call time (GC.db and GC.Settings exist
-- from GlassChat's ADDON_LOADED on).
local function coreKey(key, typ, setter, lo, hi, label)
    return {
        key = key, type = typ, lo = lo, hi = hi, label = label or key,
        default = function() return GC.DEFAULTS[key] end,
        get = function() return rawget(GC.db, key) end,
        set = function(v) GC.Settings[setter](v) end,
        clear = function() GC.db[key] = nil end,
    }
end
local function lookKey(key)
    return {
        key = "look." .. key, type = "n", lo = 0, hi = function() return GC.Skin.LOOK_MAX[key] or 1 end,
        label = "tune " .. key,
        default = function() return GC.Skin.LOOK[key] end,
        get = function() local look = rawget(GC.db, "look"); return type(look) == "table" and look[key] or nil end,
        set = function(v) GC.Settings.SetLook(key, v) end,
        reset = function() GC.Settings.SetLook(key, nil) end,
        clear = function() local look = rawget(GC.db, "look"); if type(look) == "table" then look[key] = nil end end,
    }
end
function SS.RegisterCore()
    local keys = {
        coreKey("glass", "b", "SetGlass"),
        coreKey("alpha", "n", "SetAlpha", 0, 1, "darkness"),
        coreKey("lines", "i", "SetLines", function() return GC.Chat.MIN_LINES end, function() return GC.Chat.MAX_LINES end, "scrollback"),
        coreKey("classColors", "b", "SetClassColors", nil, nil, "class colours"),
        coreKey("plainArrows", "b", "SetPlainArrows", nil, nil, "arrow recall"),
        coreKey("history", "i", "SetHistory", function() return GC.History.MIN end, function() return GC.History.MAX end, "sent history"),
        coreKey("tabSize", "i", "SetTabSize", 10, 20, "tab size"),
        coreKey("shortChannels", "b", "SetShortChannels", nil, nil, "short channel names"),
        coreKey("urls", "b", "SetUrls", nil, nil, "click-to-copy addresses"),
        coreKey("timestamps", "b", "SetTimestamps"),
    }
    local looks = {}
    for k in pairs(GC.Skin.LOOK) do looks[#looks + 1] = k end
    table.sort(looks)
    for _, k in ipairs(looks) do keys[#keys + 1] = lookKey(k) end
    SS.Register("core", keys)
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function line(...) return table.concat({ ... }, "\t") end

-- The layout's windows as L records (Layout.lua's saved table).
local W_FIELDS = {
    name = "s", fontSize = "i", r = "n", g = "n", b = "n", a = "n", shown = "b", locked = "b",
    uninteractable = "b", docked = "i", width = "n", height = "n", x = "n", y = "n", point = "e",
}
SS.W_FIELDS = W_FIELDS
-- Never for the main window: its place and size are Edit Mode's.
local MAIN_NEVER = { width = true, height = true, point = true, x = true, y = true }

local function layoutRecords(out, windows)
    local nums = {}
    for i in pairs(windows) do if type(i) == "number" then nums[#nums + 1] = i end end
    table.sort(nums)
    for _, i in ipairs(nums) do
        local w = windows[i]
        local fields = {}
        for f in pairs(W_FIELDS) do fields[#fields + 1] = f end
        table.sort(fields)
        for _, f in ipairs(fields) do
            local v, mark = w[f], W_FIELDS[f]
            if v ~= nil and not API.IsSecret(v) and not (i == 1 and MAIN_NEVER[f]) then
                local text
                if mark == "b" then text = v and "1" or "0"
                elseif mark == "i" and type(v) == "number" then text = string.format("%d", v)
                elseif mark == "n" and finite(v) then text = string.format("%.10g", v)
                elseif (mark == "s" or mark == "e") and type(v) == "string" then text = v end
                if text and decode(mark, text) ~= nil then out[#out + 1] = line("L", "W", i, f, mark, text) end
            end
        end
        for _, g in ipairs(type(w.messages) == "table" and w.messages or {}) do
            if plainString(g) and decode("e", g) then out[#out + 1] = line("L", "M", i, g) end
        end
        for _, c in ipairs(type(w.channels) == "table" and w.channels or {}) do
            if plainName(c) then out[#out + 1] = line("L", "C", i, c) end
        end
    end
end

-- This account's payload, and whether a layout went in.
function SS.Build(withLayout)
    local out = { SS.FORMAT, line("T", time()) }
    for _, name in ipairs(order) do
        for _, spec in ipairs(sections[name].keys) do
            local raw = spec.get()
            if not API.IsSecret(raw) then
                -- A value set to its default travels as "at its default" too.
                if raw == nil or same(spec, raw, spec.default()) or rejects(spec, raw) then
                    out[#out + 1] = line("D", name, spec.key)
                else
                    out[#out + 1] = line("V", name, spec.key, spec.type, encode(spec, raw))
                end
            end
        end
    end
    local saved = rawget(GC.db, "layout")
    local hasLayout = withLayout and type(saved) == "table" and type(saved.windows) == "table"
    if hasLayout then layoutRecords(out, saved.windows) end
    return table.concat(out, "\n"), hasLayout
end

--------------------------------------------------------------------------------
-- Parsing: all-or-nothing for the shape, a skip per value this copy can't take
--------------------------------------------------------------------------------

local function split(s)
    local f = {}
    for field in (s .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = field end
    return f
end

-- Returns { items = { {section, key, spec, value|nil (D)} }, layout = windows
-- or nil, skipped = { "why" } }, or nil and why.
function SS.Parse(body)
    if API.IsSecret(body) or type(body) ~= "string" then return nil, "not text" end
    if #body > SS.MAX then return nil, "too large" end
    local lines = {}
    for l in (body .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
    if lines[1] ~= SS.FORMAT then return nil, "unknown format" end
    if #lines - 1 > SS.RECORDS_MAX then return nil, "too many records" end
    local snap, seen, windows = { items = {}, skipped = {} }, {}, nil
    local maxWin = GC.Chat.MaxWindows()
    for n = 2, #lines do
        local l = lines[n]
        if #l > SS.LINE_MAX then return nil, "line too long" end
        if l ~= "" then
            local f = split(l)
            local r = f[1]
            if r == "T" then
                if #f ~= 2 or not tonumber(f[2]) then return nil, "bad T line" end
            elseif r == "V" or r == "D" then
                if (r == "V" and #f ~= 5) or (r == "D" and #f ~= 3) then return nil, "bad " .. r .. " line" end
                local sec, key = f[2], f[3]
                if not (decode("e", sec) and key:find("^[%w_%.]+$") and #key <= 32) then return nil, "bad " .. r .. " line" end
                local id = sec .. "." .. key
                if seen[id] then return nil, "duplicate " .. id end
                seen[id] = true
                local value
                if r == "V" then
                    if not ({ b = true, i = true, n = true, e = true })[f[4]] then return nil, "bad type" end
                    value = decode(f[4], f[5])
                    if value == nil then return nil, "bad value for " .. id end
                end
                local section = sections[sec]
                local spec = section and section.byKey[key]
                if not spec then
                    snap.skipped[#snap.skipped + 1] = id .. " isn't a setting here"
                elseif r == "V" and spec.type ~= f[4] then
                    snap.skipped[#snap.skipped + 1] = (spec.label or key) .. " is a different kind of setting here"
                elseif r == "V" and rejects(spec, value) then
                    snap.skipped[#snap.skipped + 1] = string.format("%s %s is %s", spec.label or key,
                        tostring(f[5]), rejects(spec, value))
                else
                    snap.items[#snap.items + 1] = { section = sec, key = key, spec = spec, value = value, default = r == "D" }
                end
            elseif r == "L" then
                windows = windows or {}
                local kind, i = f[2], tonumber(f[3])
                if not (i and i == math.floor(i) and i >= 1 and i <= maxWin) then return nil, "bad window" end
                local w = windows[i] or { messages = {}, channels = {} }
                windows[i] = w
                if kind == "W" then
                    local field, mark = f[4], f[5]
                    if #f ~= 6 or W_FIELDS[field] ~= mark then return nil, "bad window field" end
                    if i == 1 and MAIN_NEVER[field] then return nil, "the main window's place is Edit Mode's" end
                    if w[field] ~= nil then return nil, "duplicate window field" end
                    local v = decode(mark, f[6])
                    if v == nil then return nil, "bad window value" end
                    if (field == "r" or field == "g" or field == "b" or field == "a") and (v < 0 or v > 1) then
                        return nil, "bad colour"
                    end
                    if field == "point" and not v:find("^%u+$") then return nil, "bad anchor" end
                    w[field] = v
                elseif kind == "M" then
                    if #f ~= 4 or not decode("e", f[4]) then return nil, "bad message group" end
                    if #w.messages >= SS.GROUPS_MAX then return nil, "too many message groups" end
                    w.messages[#w.messages + 1] = f[4]
                elseif kind == "C" then
                    if #f ~= 4 or not plainName(f[4]) then return nil, "bad channel" end
                    if #w.channels >= SS.CHANNELS_MAX then return nil, "too many channels" end
                    w.channels[#w.channels + 1] = f[4]
                else
                    return nil, "unknown layout line"
                end
            else
                return nil, "unknown line"
            end
        end
    end
    -- Each window whole: colour and place all or nothing, and a size both ways.
    for _, w in pairs(windows or {}) do
        local c = (w.r and 1 or 0) + (w.g and 1 or 0) + (w.b and 1 or 0)
        if c ~= 0 and c ~= 3 then return nil, "incomplete colour" end
        local p = (w.point and 1 or 0) + (w.x and 1 or 0) + (w.y and 1 or 0)
        if p ~= 0 and p ~= 3 then return nil, "incomplete position" end
        if (w.width == nil) ~= (w.height == nil) then return nil, "incomplete size" end
        if w.shown == nil then w.shown = false end
        if w.locked == nil then w.locked = false end
        if w.uninteractable == nil then w.uninteractable = false end
    end
    snap.layout = windows
    return snap
end

--------------------------------------------------------------------------------
-- Applying, undo
--------------------------------------------------------------------------------

local function shown(spec, v)
    if v == nil then return "default" end
    if spec.type == "b" then return v and "on" or "off" end
    return tostring(v)
end

-- Reset to this copy's own default: through the setter (its side effects
-- run), then cleared, so a changed default reaches this account later.
local function reset(spec)
    if spec.reset then spec.reset() else spec.set(spec.default()); spec.clear() end
end

-- Returns changed, failed, labels.
function SS.Apply(snap, from, guid)
    local undo = { values = {}, at = time() }
    local changed, failed, labels = 0, 0, {}
    for _, item in ipairs(snap.items) do
        local spec = item.spec
        local raw = spec.get()
        if not API.IsSecret(raw) then
            local apply
            if item.default then
                if raw ~= nil then apply = function() reset(spec) end end
            elseif raw == nil and same(spec, item.value, spec.default()) then
                apply = nil
            elseif raw == nil or not same(spec, raw, item.value) then
                apply = function() spec.set(item.value) end
            end
            if apply then
                -- An explicit value equal to the default, cleared: nothing visible changes.
                local visible = not (item.default and same(spec, raw, spec.default()))
                undo.values[item.section .. "." .. item.key] = { raw = raw, unset = raw == nil }
                local ok, err = pcall(apply)
                if ok then
                    if visible then
                        changed = changed + 1
                        labels[#labels + 1] = (spec.label or spec.key) .. " " .. shown(spec, item.default and nil or item.value)
                    end
                else
                    failed = failed + 1
                    API.Fail("settings sync " .. item.key, err)
                end
            end
        end
    end
    if snap.layout then
        local old = rawget(GC.db, "layout")
        undo.layout = old or false
        local id = (tonumber(GC.db.layoutRevision) or (type(old) == "table" and tonumber(old.id)) or 0) + 1
        GC.db.layoutRevision = id
        GC.db.layout = { id = id, windows = snap.layout, from = (from or "your other account") .. " (another account)", guid = guid }
    end
    if next(undo.values) or snap.layout then GC.db.settingsUndo = undo end
    return changed, failed, labels
end

-- What can't be restored now (a setter failed, or its section isn't loaded:
-- the plugin turned off) is kept for another undo, never lost (Codex review
-- of #62).
function SS.Undo()
    local u = rawget(GC.db, "settingsUndo")
    if type(u) ~= "table" or type(u.values) ~= "table" then say("nothing to undo"); return end
    local n, left, missing = 0, {}, 0
    for id, old in pairs(u.values) do
        local sec, key = id:match("^([^%.]+)%.(.+)$")
        local section = sec and sections[sec]
        local spec = section and section.byKey[key]
        if spec and type(old) == "table" then
            local ok, err = pcall(function()
                if old.unset then reset(spec) else spec.set(old.raw) end
            end)
            if ok then n = n + 1 else left[id] = old; API.Fail("settings undo " .. key, err) end
        elseif type(old) == "table" then
            left[id] = old
            missing = missing + 1
        end
    end
    local layout = u.layout ~= nil
    if layout then GC.db.layout = u.layout or nil end   -- its old id: answers stand; the counter isn't rewound
    local kept = 0
    for _ in pairs(left) do kept = kept + 1 end
    if kept > 0 then
        GC.db.settingsUndo = { values = left, at = u.at }
    else
        GC.db.settingsUndo = nil
    end
    say(string.format("settings back as they were before the last copy (%d)%s. A shorter sent history or "
        .. "scrollback, and what mirroring already changed, can't come back.", n,
        layout and ", and the saved chat layout" or ""))
    if kept > 0 then
        say(string.format("|cffff6060%d couldn't be put back%s; they're kept: /gchat settings undo again|r", kept,
            missing > 0 and (" (" .. missing .. " belong to an addon that isn't loaded, such as Spam & Ignore)") or
            " (/gchat failures)"))
    end
end

--------------------------------------------------------------------------------
-- Receiving, sending, the commands
--------------------------------------------------------------------------------

function SS.Receive(body, sender, sid)
    if type(sender) ~= "table" then return end
    local guid = plainString(sender.guid)
    local n = tonumber(sid)
    if not (guid and guid:find("^Player%-%d+%-%x+$") and n) then return end
    local who = plainName(sender.name) and sender.name or "your other account"
    if type(GC.db.settingsApplied) ~= "table" then GC.db.settingsApplied = {} end
    local last = tonumber(GC.db.settingsApplied[guid])
    if last and n <= last then
        say("ignored an older copy of your settings from " .. who)
        return
    end
    local snap, why = SS.Parse(body)
    if not snap then
        say("|cffff6060refused a copy of your settings from " .. who .. " (" .. why .. "): yours are unchanged|r")
        return
    end
    GC.db.settingsApplied[guid] = n
    local changed, failed, labels = SS.Apply(snap, who, guid)
    if failed > 0 then
        say(string.format("|cffff6060settings from %s: %d of %d applied; %d failed (/gchat failures)|r",
            who, changed, changed + failed, failed))
    elseif changed > 0 then
        say(string.format("settings now follow %s's choices: %d changed (%s) (/gchat settings undo puts yours back)",
            who, changed, table.concat(labels, ", ")))
    else
        say("settings already the same as " .. who .. "'s")
    end
    if #snap.skipped > 0 then
        say(#snap.skipped .. " setting(s) skipped: " .. table.concat(snap.skipped, "; ") .. " (update GlassChat on both accounts)")
    end
    if snap.layout then
        say("the chat layout from " .. who .. " is now this account's saved layout")
        local ok, err = pcall(GC.Layout.Offer)
        if not ok then API.Fail("settings layout offer", err) end
    end
end

function SS.Send(withLayout)
    if not GC.AccountSync.HasStore() then
        say("settings sync needs the Spam & Ignore plugin (it holds the account link)")
        return nil, "no-store"
    end
    local body, hasLayout = SS.Build(withLayout)
    if withLayout and not hasLayout then say("no chat layout saved (/gchat layout save); sending the settings alone") end
    -- The receiver's own parser first: a copy every receiver would refuse
    -- whole is never sent (Codex review of #62; the lists check their caps too).
    local ok, why = SS.Parse(body)
    if not ok then
        say("|cffff6060can't send this copy: your other accounts would refuse it (" .. why .. ")|r"
            .. (hasLayout and "; /gchat settings send copies the settings without the layout" or ""))
        return nil, "refused"
    end
    return GC.AccountSync.SendReported(SS.KIND, body, hasLayout and "your settings and chat layout" or "your settings",
        "/gchat settings send")
end

function SS.Command(arg)
    arg = (arg or ""):lower()
    if arg == "send" then SS.Send(false)
    elseif arg == "send layout" then SS.Send(true)
    elseif arg == "undo" then SS.Undo()
    else
        say("/gchat settings send - copy these settings to your other accounts online")
        say("/gchat settings send layout - and the saved chat layout (each character is offered it)")
        say("/gchat settings undo - put back what the last copy received here changed")
        say("account sync on/off and status: /gchat ignore sync (it covers settings and lists)")
    end
end

function SS.Start()
    SS.RegisterCore()
    GC.AccountSync.On(SS.KIND, SS.Receive)
    GC.RegisterSlash("settings", SS.Command, {
        "/gchat settings send [layout], /gchat settings undo - your settings on your other accounts",
    })
end

SS._test = { sections = sections, decode = decode }
