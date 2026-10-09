-- #71: a known player's level before their name in chat, "[60:Name]",
-- through the sender-name filter, keyed by GUID.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GC = loadAddon()
local Levels = GC.Levels
WoW.fire("PLAYER_LOGIN")

eq(#WoW.nameFilters, 1, "one sender-name filter is installed")
local COLOR = "|cffffd100"   -- the stub's difficulty colour (1, 0.82, 0)
local function decorated(lvl, name) return COLOR .. lvl .. "|r:" .. name end

-- You, at login.
eq(WoW.decorateName("CHAT_MSG_SAY", "Karuzo", WoW.playerGUID), decorated(60, "Karuzo"), "your own level at login")
-- A stranger we never saw: the stock name.
eq(WoW.decorateName("CHAT_MSG_CHANNEL", "Stranger", "Player-1-BBB"), "Stranger", "an unknown sender keeps the stock name")
eq(WoW.decorateName("CHAT_MSG_CHANNEL", "Stranger", nil), "Stranger", "no GUID: the stock name")

-- Target and mouseover.
WoW.unitGUIDs = { target = "Player-1-T", mouseover = "Player-1-M", party1 = "Player-1-P" }
WoW.unitLevels.target, WoW.unitLevels.mouseover = 23, 41
WoW.fire("PLAYER_TARGET_CHANGED")
WoW.fire("UPDATE_MOUSEOVER_UNIT")
eq(WoW.decorateName("CHAT_MSG_SAY", "Tee", "Player-1-T"), decorated(23, "Tee"), "a target's level")
eq(WoW.decorateName("CHAT_MSG_YELL", "Em", "Player-1-M"), decorated(41, "Em"), "a mouseover's level")

-- A unit that isn't a player (an NPC) is never noted.
WoW.unitGUIDs.target, WoW.unitLevels.target = "Creature-0-1-2-3-4-5", nil
WoW.fire("PLAYER_TARGET_CHANGED")
eq(Levels.Of("Creature-0-1-2-3-4-5"), nil, "an NPC target isn't noted")

-- The group, and a group member levelling up.
WoW.group = { "Karuzo", "Pal" }
WoW.unitLevels.party1 = 30
WoW.fire("GROUP_ROSTER_UPDATE")
eq(Levels.Of("Player-1-P"), 30, "a party member's level")
WoW.unitLevels.party1 = 31
WoW.fire("UNIT_LEVEL", "party1")
eq(Levels.Of("Player-1-P"), 31, "UNIT_LEVEL updates it")

-- Your own level-up: the event's level, not UnitLevel's (which can lag).
WoW.fire("PLAYER_LEVEL_UP", 61)
eq(Levels.Of(WoW.playerGUID), 61, "PLAYER_LEVEL_UP's own level")

-- Friends and guild.
WoW.friendList = { { name = "Fred", guid = "Player-1-F", level = 12, connected = true },
                   { name = "Off", guid = "Player-1-O", level = 0, connected = false } }
WoW.fire("FRIENDLIST_UPDATE")
eq(Levels.Of("Player-1-F"), 12, "a friend's level")
eq(Levels.Of("Player-1-O"), nil, "a level of 0 is unknown")
WoW.guildRoster = { { name = "Gus", level = 55, guid = "Player-1-G" }, { name = "Odd", level = 9, guid = nil } }
WoW.fire("GUILD_ROSTER_UPDATE")
eq(Levels.Of("Player-1-G"), 55, "a guild member's level")

-- Junk and secrets are never noted or read.
Levels.Note("Player-1-X", -1)
Levels.Note("Player-1-Y", 999)
Levels.Note("not-a-guid", 10)
Levels.Note(WoW.Secret("guid"), 10)
Levels.Note("Player-1-Z", WoW.Secret("level"))
eq(Levels.Of("Player-1-X"), nil, "'??' (-1) isn't a level")
eq(Levels.Of("Player-1-Y"), nil, "an absurd level isn't one")
eq(Levels.Of("not-a-guid"), nil, "only player GUIDs")
eq(Levels.Of("Player-1-Z"), nil, "a secret level isn't noted")
eq(Levels.Of(WoW.Secret("guid")), nil, "a secret GUID is never looked up")
-- A secret that is a real string (type() can't tell it apart).
local sguid = "Player-1-S"
Levels.Note(sguid, 20)
WoW.MarkSecret(sguid)
eq(Levels.Of(sguid), nil, "a secret string GUID is never looked up")
eq(WoW.decorateName("CHAT_MSG_SAY", "Ess", sguid), "Ess", "and keeps the stock name")
eq(WoW.decorateName("CHAT_MSG_SAY", "Sec", WoW.Secret("guid")), "Sec", "a secret GUID keeps the stock name")
WoW.unitGUIDs.mouseover, WoW.unitLevels.mouseover = WoW.Secret("guid"), 5
WoW.fire("UPDATE_MOUSEOVER_UNIT")

-- No colour from the client: the level still shows, plain.
local real = GetQuestDifficultyColor
GetQuestDifficultyColor = function() error("no colour") end
eq(WoW.decorateName("CHAT_MSG_SAY", "Fred", "Player-1-F"), "12:Fred", "no colour: a plain level")
GetQuestDifficultyColor = real

-- Off: the stock name.
SlashCmdList.GLASSCHAT("levels off")
eq(GC.db.levels, false, "/gchat levels off")
eq(WoW.decorateName("CHAT_MSG_SAY", "Fred", "Player-1-F"), "Fred", "off: the stock name")
SlashCmdList.GLASSCHAT("levels on")
eq(WoW.decorateName("CHAT_MSG_SAY", "Fred", "Player-1-F"), decorated(12, "Fred"), "on again")

eq(next(GC.failures), nil, "nothing failed")
done("test_levels")
