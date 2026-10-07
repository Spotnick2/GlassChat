-- Tools/collected.lua: the lines /gchat spam collect kept, out of the Spam &
-- Ignore plugin's SavedVariables, and nothing else.
--
-- That file also holds the LibAccountSync household key
-- (GlassChatSpamIgnoreSyncDB), so it's never read whole into a Claude session
-- (review of #59): this loads it in an empty environment and writes only
-- GlassChatSpamIgnoreDB.collected, one tab-separated line per entry.
--
--   lua Tools\collected.lua <WTF\Account\<acct>\SavedVariables\GlassChatSpamIgnore.lua> [out.tsv]

local src, out = arg[1], arg[2]
if not src then
    io.stderr:write("usage: lua Tools/collected.lua <GlassChatSpamIgnore.lua> [out.tsv]\n")
    os.exit(1)
end
local chunk, err = loadfile(src)
if not chunk then io.stderr:write(err, "\n"); os.exit(1) end
local env = {}
setfenv(chunk, env)
local ok, e = pcall(chunk)
if not ok then io.stderr:write(e, "\n"); os.exit(1) end

local db = env.GlassChatSpamIgnoreDB
local list = type(db) == "table" and type(db.collected) == "table" and db.collected or {}
local function field(v)
    if v == nil then return "" end
    return (tostring(v):gsub("[\t\r\n]", " "))
end
local lines = { "at\tchar\tev\tfrom\tkinds\tspam\tout\tnoid\ttext" }
for _, x in ipairs(list) do
    if type(x) == "table" then
        lines[#lines + 1] = table.concat({ field(x.at and os.date("%Y-%m-%d %H:%M:%S", x.at)), field(x.char),
            field(x.ev), field(x.from), field(x.kinds), field(x.spam), field(x.out), field(x.noid), field(x.text) }, "\t")
    end
end
local text = table.concat(lines, "\n") .. "\n"
if out then
    local f = assert(io.open(out, "w"))
    f:write(text)
    f:close()
    io.stderr:write(#list, " collected line(s) -> ", out, "\n")
else
    io.write(text)
end
