-- Glass.lua: this addon's instance of the "liquid glass" material.
--
-- The material lives in the embedded library LibGlass-1.0
-- (Libs\LibGlass-1.0, from github.com/Spotnick2/LibGlass through .pkgmeta
-- externals; the TOC loads it first). Its contract, write-up and textures are
-- there: material changes are LibGlass PRs, not edits here.
--
-- An instance, not the library itself: STYLE, EDGE, TUNABLES, the live
-- setters and the font registry are GlassChat's own, so /gchat tune never
-- touches another glass addon's surfaces. Every call site keeps the dot-call
-- shape (Glass.Apply, Glass.SetEdge, Glass.MEDIA, ...); the plugins reach it
-- as GlassChat.Glass.

GlassChat = GlassChat or {}
-- r11 supplies the shared Pearl recipe. Guard the preset for a dev install
-- still loading an older embedded copy; the packaged dependency is r11.
local lib, minor = LibStub:GetLibrary("LibGlass-1.0")
GlassChat.Glass = lib:New(minor >= 11 and { preset = "pearl" } or nil)
-- What was built, for Glass UI's page (Suite.lua's report).
GlassChat.glassPreset, GlassChat.glassMinor = minor >= 11 and "pearl" or "classic", minor
