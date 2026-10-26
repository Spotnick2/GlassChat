-- The manifest, the pinned build, the event fixture and the lifted material.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local toc = io.open("GlassChat.toc"):read("*a")
check(toc:find("## Interface: 16001", 1, true), "interface 16001 (1.60.1; 11601 is the transposed-digit bug)")
check(toc:find("## Version: @project-version@", 1, true), "packager version token kept")
check(toc:find("## SavedVariables: GlassChatDB", 1, true), "saved variables declared")
check(toc:find("## X-Curse-Project-ID: 1757140", 1, true), "the CurseForge project ID")
check(toc:find("## X-Wago-ID: 5NRg0w63", 1, true), "the Wago project ID")
for _, f in ipairs(tocFiles()) do
    check(io.open(f, "r") ~= nil, "TOC file exists: " .. f)
end
-- The embedded material loads before any of our files: Glass.lua calls
-- LibStub("LibGlass-1.0") at file scope.
eq(tocLines()[1], LIBGLASS_XML, "LibGlass-1.0 loads first")
eq(tocLines()[2], LIBACCOUNTSYNC_XML, "then LibAccountSync-1.0, before any of our files")
eq(tocFiles()[1], "Compat.lua", "Compat is the first of our own files")
local seen = {}
for _, f in ipairs(tocFiles()) do
    check(not seen[f], "TOC lists each file once: " .. f)
    seen[f] = true
end

-- The plugins: each folder under Plugins/ is listed in the harness, has its
-- TOC, depends on the core, and is moved out by .pkgmeta's move-folders.
local moves = {}
do
    local inBlock = false
    for line in io.lines(".pkgmeta") do
        line = line:gsub("\r", "")
        if line:match("^move%-folders:%s*$") then inBlock = true
        elseif line:match("^[^%s#]") then inBlock = false
        elseif inBlock then
            local src, dst = line:match("^  ([^#%s][^:]*):%s*(%S+)%s*$")
            if src then moves[src] = dst end
        end
    end
end
local listed = {}
for _, p in ipairs(PLUGINS) do
    listed[p.folder] = true
    local f = io.open("Plugins/" .. p.folder .. "/" .. p.toc, "r")
    check(f ~= nil, p.name .. ": its TOC exists")
    if f then
        local t = f:read("*a"); f:close()
        check(t:find("## Interface: 16001", 1, true), p.name .. ": interface 16001")
        check(t:find("## Version: @project-version@", 1, true), p.name .. ": version token")
        check(t:find("## Dependencies: GlassChat", 1, true), p.name .. ": depends on the core")
        check(t:find("## Group: GlassChat", 1, true), p.name .. ": grouped under the core")
        for _, file in ipairs(tocFiles(p.toc, "Plugins/" .. p.folder .. "/")) do
            check(io.open(file, "r") ~= nil, p.name .. ": file exists: " .. file)
        end
    end
    eq(moves["GlassChat/Plugins/" .. p.folder], p.name, p.name .. ": .pkgmeta moves it out to its own folder")
end
-- Every Plugins/<Name> on disk is in the list (Windows only: CI lacks dir).
if package.config:sub(1, 1) == "\\" then
    local d = io.popen('dir /b /ad Plugins 2>nul')
    if d then
        for name in d:lines() do check(listed[name], "Plugins/" .. name .. " is listed in tests/harness.lua") end
        d:close()
    end
end

-- Two places that must agree, never derived from each other (porting guide §0).
loadAddon()
eq(GlassChat.MEASURED_ON_BUILD, "1.60.1.70450", "MEASURED_ON_BUILD")

-- The checked-in event list matches the dump, when the dump is here.
if WoW.dumpAvailable then
    local fixture = {}
    for line in io.lines("tests/events-70450.txt") do
        local name = line:match("^([A-Z][A-Z0-9_]+)%s*$")
        if name then fixture[name] = true end
    end
    local missing, extra = 0, 0
    for e in pairs(WoW.KNOWN_EVENTS) do if not fixture[e] then missing = missing + 1 end end
    for e in pairs(fixture) do if not WoW.KNOWN_EVENTS[e] then extra = extra + 1 end end
    eq(missing + extra, 0, "tests/events-70450.txt matches the dump (regenerate it)")
end

-- Every texture the material names ships with the library (Libs\LibGlass-1.0\Media
-- in the package; the checkout's Media/ here). GlassChat has no Media/ of its own.
local root = libGlassRoot()
for size, S in pairs(GlassChat.Glass.SIZES) do
    for _, key in ipairs({ "mask", "rim", "dark", "shadow" }) do
        local f = root .. "/Media/" .. S[key] .. ".tga"
        check(io.open(f, "rb") ~= nil, size .. " texture exists: " .. f)
    end
end
for _, t in ipairs({ "bar_mask", "bar_fill", "gloss", "bar_edge", "grain", "sheen2", "track_fade" }) do
    check(io.open(root .. "/Media/" .. t .. ".tga", "rb") ~= nil, "texture exists: " .. t)
end
-- Glass.MEDIA points into the embedded copy, where the packager puts it.
eq(GlassChat.Glass.MEDIA, "Interface\\AddOns\\GlassChat\\Libs\\LibGlass-1.0\\Media\\", "MEDIA is the embedded copy's")
-- The plugins load after the core, so they share its instance.
-- Every member of the instance GlassChat and its plugin use (a pin bump that
-- drops one fails here, not in game; review of #30).
for _, k in ipairs({ "Apply", "Font", "SetEdge", "MEDIA", "SIZES" }) do
    check(GlassChat.Glass[k] ~= nil, "the instance has Glass." .. k)
end

-- LibAccountSync-1.0 loaded through its XML, with its ChatThrottleLib and LibStub.
local sync = LibStub and LibStub("LibAccountSync-1.0", true)
check(sync and sync.ready ~= nil, "LibAccountSync-1.0 is registered and finished loading")

done("test_toc")
