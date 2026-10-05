-- harness.lua: assertions and the addon loader. dofile it after wow_stubs.lua.

local passed, failed = 0, 0

function check(cond, msg)
    if cond then passed = passed + 1 else
        failed = failed + 1
        io.write("  FAIL: " .. tostring(msg) .. "\n")
    end
end

function eq(actual, expected, msg)
    check(actual == expected, string.format("%s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
end

function done(name)
    io.write(string.format("%s: %d passed, %d failed\n", name, passed, failed))
    os.exit(failed == 0 and 0 or 1)
end

-- Every file line of the core TOC, in load order (our .lua files and the
-- embedded library's .xml).
function tocLines()
    local lines = {}
    for line in io.lines("GlassChat.toc") do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then lines[#lines + 1] = line end
    end
    return lines
end

-- Lua files listed in a TOC, in load order (dir: where the TOC lives).
function tocFiles(toc, dir)
    toc, dir = toc or "GlassChat.toc", dir or ""
    local files = {}
    for line in io.lines(dir .. toc) do
        line = line:gsub("\r", "")
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = dir .. line end
    end
    return files
end

-- The plugins, by folder and TOC (a list, not a directory listing: CI runs on
-- Linux). test_toc checks every Plugins/<Name> is listed here.
PLUGINS = {
    { folder = "SpamIgnore", toc = "GlassChatSpamIgnore.toc", name = "GlassChatSpamIgnore" },
}

-- The embedded libraries come from checkouts, not from Libs\ (gitignored,
-- filled by the packager): $LIBGLASS / $LIBACCOUNTSYNC, else the sibling
-- folder. No checkout fails the run loudly; a silently skipped library would
-- test nothing. (GlassUnitFrames' harness, #64.)
LIBS = {
    ["Libs\\LibGlass-1.0\\LibGlass-1.0.xml"] = { env = "LIBGLASS", dir = "../LibGlass", xml = "LibGlass-1.0.xml" },
    ["Libs\\LibAccountSync-1.0\\LibAccountSync-1.0.xml"] = { env = "LIBACCOUNTSYNC", dir = "../LibAccountSync",
        xml = "LibAccountSync-1.0.xml" },
}
LIBGLASS_XML = "Libs\\LibGlass-1.0\\LibGlass-1.0.xml"
LIBACCOUNTSYNC_XML = "Libs\\LibAccountSync-1.0\\LibAccountSync-1.0.xml"

function libRoot(line)
    local L = LIBS[line]
    local root = (os.getenv(L.env) or L.dir):gsub("\\", "/"):gsub("/$", "")
    local f = io.open(root .. "/" .. L.xml, "rb")
    if not f then
        error(L.xml .. " checkout not found at " .. root .. ": clone it there or set " .. L.env, 0)
    end
    f:close()
    return root
end
function libGlassRoot() return libRoot(LIBGLASS_XML) end

-- The Lua files a library's XML loads, as paths, in order: what the client
-- runs for that TOC line. A listed file that is missing fails here.
function libScripts(line)
    local L, root = LIBS[line], libRoot(line)
    local f = assert(io.open(root .. "/" .. L.xml, "rb"))
    local xml = f:read("*a"):gsub("<!%-%-.-%-%->", "")   -- listed in a comment is not loaded
    f:close()
    local files = {}
    for file in xml:gmatch('<Script%s+file="([^"]+)"') do
        local path = root .. "/" .. file:gsub("\\", "/")
        local src = io.open(path, "rb")
        if not src then error(L.xml .. " at " .. root .. " is missing " .. file, 0) end
        src:close()
        files[#files + 1] = path
    end
    if #files == 0 then error(L.xml .. " at " .. root .. " lists no Script files", 0) end
    return files
end
function libGlassScripts() return libScripts(LIBGLASS_XML) end

-- Load the addon the way the client does: every TOC file with (name, ns),
-- the library's XML expanded in place, then ADDON_LOADED, PLAYER_LOGIN,
-- PLAYER_ENTERING_WORLD (initial login).
function loadAddon(opts)
    opts = opts or {}
    if not rawget(_G, "ChatFrame1") then
        WoW.makeChatFrames(opts.windows or 3)
        DEFAULT_CHAT_FRAME = ChatFrame1
        FCFDock_SetPrimary(GeneralDockManager, ChatFrame1)   -- as FrameXML does before addons load
        GeneralDockManager._docked = { ChatFrame1, ChatFrame2 }
    end
    local ns = {}
    for _, line in ipairs(tocLines()) do
        local files = { line }
        if LIBS[line] then
            files = libScripts(line)
        elseif not line:match("%.lua$") then
            error("the harness can't load TOC line " .. line, 0)
        end
        for _, file in ipairs(files) do
            local chunk = assert(loadfile(file))
            chunk("GlassChat", ns)
        end
    end
    if opts.db then GlassChatDB = opts.db end
    if opts.charDB then GlassChatCharDB = opts.charDB end
    WoW.fire("ADDON_LOADED", "GlassChat")
    -- Then each plugin, as the client does: its files after the core's
    -- ADDON_LOADED, then its own ADDON_LOADED. opts.plugins = false: the core alone.
    if opts.plugins ~= false then
        for _, p in ipairs(PLUGINS) do
            for _, file in ipairs(tocFiles(p.toc, "Plugins/" .. p.folder .. "/")) do
                assert(loadfile(file))(p.name, {})
            end
            if opts.spamDB then GlassChatSpamIgnoreDB = opts.spamDB end
            WoW.fire("ADDON_LOADED", p.name)
        end
    end
    WoW.fire("PLAYER_LOGIN")
    WoW.fire("PLAYER_ENTERING_WORLD", opts.initialLogin ~= false, false)
    WoW.tick()
    return GlassChat
end

-- Chat lines printed since the last call.
local seenChat = 0
function newChat()
    local lines = {}
    for i = seenChat + 1, #WoW.chat do lines[#lines + 1] = WoW.chat[i] end
    seenChat = #WoW.chat
    return lines
end

function chatHas(pattern)
    for _, line in ipairs(WoW.chat) do
        if line:find(pattern) then return true end
    end
    return false
end
