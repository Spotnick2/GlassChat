-- Never write a global this addon doesn't own (GlassRaidFrames' and
-- AltStableSync's test_taint; #132 H2).
--
-- Assigning a global Blizzard owns, even to itself (`SlashCmdList =
-- SlashCmdList or {}`), marks the slot tainted by this addon: every secure
-- macro that later reads it runs tainted, its protected calls are blocked and
-- blamed on us (measured on 70235, PORTING-TBC-TO-FOREVER.md "Never reassign
-- a Blizzard global"). A field write (SlashCmdList.FOO = fn) is the supported
-- pattern. This loads every file of the core and the plugin under an
-- environment that records every global write, however spelled, at load time;
-- runtime paths and field writes have their own targeted tests.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- The globals GlassChat owns (anything else written is a failure).
local OURS = {
    GlassChat = true, GlassChatDB = true, GlassChatCharDB = true, GlassChatSyncDB = true,
    GlassChatSpamIgnoreDB = true, GlassChatSpamIgnoreSyncDB = true, GlassChatSpamIgnoreCharDB = true,
    SLASH_GLASSCHAT1 = true, SLASH_GLASSCHAT2 = true, SLASH_GLASSCHATRELOAD1 = true,
}

-- Load `chunk` in an environment that records every global write: `G =`,
-- `_G.G =`, rawset(_G, ...), multi-assignment, inside a branch. Same-table
-- writes count: the client taints the SLOT on any addon write.
local function writesOf(chunk, env, name)
    local writes = {}
    env = env or setmetatable({}, { __index = _G })
    getmetatable(env).__newindex = function(t, k, v)
        if not OURS[k] then writes[#writes + 1] = tostring(k) end
        rawset(t, k, v)
    end
    -- Installed raw, so the recorder doesn't count its own two writes.
    rawset(env, "_G", env)
    rawset(env, "rawset", function(t, k, v)
        if t == env and not OURS[k] then writes[#writes + 1] = tostring(k) end
        return rawset(t, k, v)
    end)
    setfenv(chunk, env)
    chunk(name or "GlassChat", {})
    return writes, env
end

-- The recorder catches every spelling (mutation check, in memory).
for _, src in ipairs({
    "SlashCmdList = SlashCmdList or {}",
    "_G.SlashCmdList = SlashCmdList",
    "rawset(_G, 'SlashCmdList', SlashCmdList)",
    "local a; a, SlashCmdList = 1, SlashCmdList",
    "if true then SlashCmdList = SlashCmdList end",
    "UISpecialFrames = UISpecialFrames",
}) do
    local writes = writesOf(assert(loadstring(src)))
    eq(#writes, 1, "recorder catches: " .. src)
end
eq(#(writesOf(assert(loadstring("GlassChat = GlassChat or {}")))), 0, "our own global is allowed")
eq(#(writesOf(assert(loadstring("SlashCmdList.GLASSCHAT_T = function() end")))), 0, "a field write is not a global write")

-- The libraries first, as the client loads the TOC's XML lines (their own
-- repos test them), then every core file in TOC order and the plugin's after
-- it, under one recording environment, the way the client runs them.
WoW.makeChatFrames(3)
DEFAULT_CHAT_FRAME = ChatFrame1
for _, line in ipairs(tocLines()) do
    if LIBS[line] then
        for _, file in ipairs(libScripts(line)) do assert(loadfile(file))("GlassChat", {}) end
    end
end
local env = setmetatable({}, { __index = _G })
local all = {}
local function loadAll(files, name)
    for _, file in ipairs(files) do
        local writes = writesOf(assert(loadfile(file)), env, name)
        for _, w in ipairs(writes) do all[#all + 1] = file .. ": " .. w end
    end
end
loadAll(tocFiles(), "GlassChat")
for _, p in ipairs(PLUGINS) do loadAll(tocFiles(p.toc, "Plugins/" .. p.folder .. "/"), p.name) end
eq(#all, 0, "no addon file writes a global it doesn't own: " .. table.concat(all, ", "))
check(type(env.GlassChat) == "table", "the namespace was made in the recorder")
check(rawget(env, "SlashCmdList") == nil and type(SlashCmdList.GLASSCHAT) == "function",
    "the slash command is registered as a field, never by reassigning SlashCmdList")
check(rawget(env, "UISpecialFrames") == nil, "UISpecialFrames is never reassigned (Compat inserts into it)")

done("test_taint")
