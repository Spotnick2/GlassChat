-- harness.lua: the addon loader and GlassChat's test helpers. dofile it after
-- wow_stubs.lua. check / eq / done are WowTestKit's (tests/kit.lua).

-- Every file line of the core TOC, in load order (our .lua files and the
-- embedded library's .xml).
function tocLines() return Kit.tocLines("GlassChat.toc") end

-- Lua files listed in a TOC, in load order (dir: where the TOC lives).
function tocFiles(toc, dir) return Kit.tocFiles(toc or "GlassChat.toc", dir) end

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

-- ForeverProbe, the host ChatProbe depends on, from its checkout
-- ($FOREVERPROBE, else ..\ForeverProbe). It's private and only on the
-- owner's disk, so CI doesn't have it: with FOREVERPROBE_OPTIONAL=1 (CI) a
-- missing checkout skips the calling test file; without it (locally) it's an
-- error, never a silent skip. Loaded into THIS stub environment,
-- the way the client loads a dependency: its files, then its ADDON_LOADED.
function loadForeverProbe()
    local root = (os.getenv("FOREVERPROBE") or "../ForeverProbe"):gsub("\\", "/"):gsub("/$", "")
    local toc = io.open(root .. "/ForeverProbe.toc", "rb")
    if not toc then
        if os.getenv("FOREVERPROBE_OPTIONAL") == "1" then
            io.write("SKIPPED: ForeverProbe isn't here (private, local only); the probe tests run locally\n")
            os.exit(0)
        end
        error("ForeverProbe checkout not found at " .. root .. ": clone it there or set FOREVERPROBE", 0)
    end
    local files = {}
    for line in toc:read("*a"):gmatch("[^\r\n]+") do
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = root .. "/" .. line end
    end
    toc:close()
    for _, file in ipairs(files) do assert(loadfile(file))("ForeverProbe", {}) end
    WoW.fire("ADDON_LOADED", "ForeverProbe")
    return ForeverProbe
end

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

-- Buffer walks: how many times TransformMessages ran on each window since the
-- last walks(f) read of it (#132 H3). The stub's method is wrapped once, after
-- the stub is loaded; Blizzard's TransformIf visits every line of the window
-- with secure calls (CircularBuffer.lua:99-114, 70532), so a walk costs the
-- window's size: this pins how often the AddMessage hook pays it.
local walkCounts = setmetatable({}, { __mode = "k" })
local walkWrapped = false
function walks(f)
    if not walkWrapped then
        walkWrapped = true
        local real = WoW.Methods.TransformMessages
        WoW.Methods.TransformMessages = function(frame, ...)
            walkCounts[frame] = (walkCounts[frame] or 0) + 1
            return real(frame, ...)
        end
    end
    local n = walkCounts[f] or 0
    walkCounts[f] = 0
    return n
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
