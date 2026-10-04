-- M2: one chat layout for every character. Saved on one, offered once and
-- applied on another through Blizzard's own setters; the main window's
-- place is never touched; nothing is joined.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GC = loadAddon({ windows = 10 })   -- the client has all ten
local Layout = GC.Layout

-- Character A: General (say, guild; General and Trade), Combat Log, and a
-- Whispers tab docked third; a floating window 4.
WoW.chatWindows[1] = { name = "General", size = 18, r = 0, g = 0, b = 0, a = 0.4, shown = true, locked = true,
    docked = 1, uninteractable = false, messages = { "SAY", "GUILD" }, channels = { "General", "Trade" },
    point = "BOTTOMLEFT", x = 0.1, y = 0.1, width = 400, height = 200 }
WoW.chatWindows[3] = { name = "Whispers", size = 16, r = 0, g = 0, b = 0, a = 0.4, shown = true, locked = false,
    docked = 3, uninteractable = false, messages = { "WHISPER", "BN_WHISPER" }, channels = {} }
WoW.chatWindows[4] = { name = "Loot", size = 14, r = 0, g = 0, b = 0, a = 0.2, shown = true, locked = false,
    docked = nil, uninteractable = false, messages = { "LOOT" }, channels = {},
    point = "CENTER", x = 0.2, y = -0.1, width = 300, height = 150 }
WoW.joined = { General = true, Trade = true }

Layout.Save()
local saved = GlassChatDB.layout
check(saved and saved.windows[3].name == "Whispers", "the layout is saved account-wide")
eq(table.concat(saved.windows[1].messages, ","), "SAY,GUILD", "with each window's chat types")
eq(table.concat(saved.windows[1].channels, ","), "General,Trade", "and channel names (zone IDs dropped)")
eq(saved.windows[1].point, nil, "the main window's place is never saved (Edit Mode owns it)")
eq(saved.windows[4].point, "CENTER", "a floating window's place is")
eq(saved.from, "Karuzo (Doomhowl)", "it says where it came from")
GlassChatCharDB.layoutAnswered = nil   -- the GUID alone must keep it from asking,
WoW.chatWindows[3].shown = false        -- even after its windows changed since
check(not Layout.Offer(), "the character that saved it isn't offered it")
WoW.chatWindows[3].shown = true

-- Character B: a new character with the stock windows, and only General joined.
WoW.chatWindows = {}
WoW.playerGUID, WoW.playerName = "Player-1-BBB", "Kaleid"
WoW.joined = { General = true }
GlassChatCharDB = {}
GC.charDB = GlassChatCharDB
newChat()
check(Layout.Offer(), "another character is offered the layout")
local offer = newChat()[1] or ""
check(offer:find("|Haddon:GlassChat:layout:apply|h", 1, true), "as a clickable [Apply it] link")
check(offer:find("|Haddon:GlassChat:layout:no|h", 1, true), "and a [Not here] one")

-- Even a saved place for the main window (an older save, or edited by
-- hand) is never applied: Edit Mode owns it.
saved.windows[1].point, saved.windows[1].x, saved.windows[1].y = "TOP", 0, 0
saved.windows[1].width, saved.windows[1].height = 900, 900

-- The click, through EventRegistry "SetItemRef" (no hook).
WoW.layoutCalls, WoW.windowUpdates = {}, {}
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:layout:apply")
eq(WoW.window(3).name, "Whispers", "the Whispers tab is set up")
eq(WoW.window(3).docked, 3, "docked third")
eq(table.concat(WoW.window(3).messages, ","), "WHISPER,BN_WHISPER", "with its chat types")
eq(select(2, ChatFrame1:GetFont()), 18, "General's font size is applied")
eq(table.concat(WoW.window(1).channels, ","), "General", "a joined channel is added")
check(chatHas("1 channel%(s%) skipped"), "Trade (not joined here) is skipped and said so")
eq(WoW.window(4).point, "CENTER", "the floating window gets its place")
local touchedMain = false
for _, c in ipairs(WoW.layoutCalls) do if c == "pos1" or c == "dims1" then touchedMain = true end end
check(not touchedMain, "the main window's place and size are left to Edit Mode")
eq(#WoW.windowUpdates, GC.Chat.MaxWindows(), "Blizzard's FloatingChatFrame_Update applies every window")
eq(GlassChatCharDB.layoutAnswered, "applied", "and the character remembers it")
check(not Layout.Offer(), "so it isn't offered again")

-- "Not here" is remembered too.
GlassChatCharDB = {}
GC.charDB = GlassChatCharDB
WoW.chatWindows = {}
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:layout:no")
eq(GlassChatCharDB.layoutAnswered, "no", "[Not here] is remembered")
check(not Layout.Offer(), "and not asked again")

-- A character that already matches isn't asked.
GlassChatCharDB = {}
GC.charDB = GlassChatCharDB
for i, w in pairs(saved.windows) do
    WoW.chatWindows[i] = { name = w.name, size = w.fontSize, r = 0, g = 0, b = 0, a = w.a, shown = w.shown,
        locked = w.locked, docked = w.docked, uninteractable = false, messages = { unpack(w.messages) }, channels = {} }
end
check(not Layout.Offer(), "a character whose windows already match isn't asked")

-- Never in combat; a secret window name is never saved.
WoW.combat = true
check(not Layout.Apply(), "no layout changes in combat")
WoW.combat = false
WoW.MarkSecret("Secret Tab Name")
WoW.chatWindows[5] = { name = "Secret Tab Name", size = 14, shown = false, messages = {}, channels = {} }
Layout.Save()
eq(GlassChatDB.layout.windows[5].name, nil, "a secret window name is never saved")

-- /gchat layout.
SlashCmdList.GLASSCHAT("layout forget")
eq(GlassChatDB.layout, nil, "/gchat layout forget drops it")
SlashCmdList.GLASSCHAT("layout apply")
check(chatHas("no chat layout saved yet"), "apply with nothing saved says how to save one")

eq(next(GC.failures), nil, "nothing failed")
done("test_layout")
