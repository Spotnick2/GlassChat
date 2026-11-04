-- Every widget method the addon calls must exist on this client.
--
-- The stub answers any method call (a no-op for ones it does not implement),
-- so a call to a method Forever lacks would otherwise pass silently. This
-- exercises the addon, then Kit.checkMethods checks each recorded
-- "Type:Method" pair against the pinned build's widget methods. It fails,
-- never skips, when the data is missing or nothing was recorded.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Exercise everything so every method is recorded.
loadAddon()
WoW.fireAllRegistered()
WoW.tick()
for _, cmd in ipairs({ "", "failures", "version", "copy", "tune", "spam icon on", "spam log", "spam", "mutes", "ignores", "focus bags", "tabs" }) do
    SlashCmdList.GLASSCHAT(cmd)
end
-- Every options page built (#127).
local O = GlassChat.Options
for _, page in ipairs({ O._test.main, O._test.about, unpack(O._test.pages) }) do page.frame:Show() end
-- A click on a web address opens its box.
WoW.callbacks.SetItemRef(nil, "addon:GlassChat:url:https://wowhead.com")

Kit.checkMethods()
done("test_methods")
