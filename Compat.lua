-- Compat.lua: the one place this addon touches client APIs that moved, may be
-- absent, or behave differently on WoW: Forever. Everything else calls through
-- GlassChat.API. Nothing is injected into _G.
--
-- Lifted in part from GlassRaidFrames' Compat.lua (same measured rules); only
-- what the chat uses is here. Lift more from there when needed.

GlassChat = GlassChat or {}
local GC = GlassChat
local API = {}
GC.API = API

-- The build the notes in docs/ were measured on. Bump only after re-measuring
-- in game; tests/test_toc.lua pins the same literal.
GC.MEASURED_ON_BUILD = "1.60.1.70450"

function API.Print(msg)
    print("|cff7fd4ffGlassChat|r " .. msg)
end

-- True for a Retail secret value. Such a value may be handed back to the
-- client (SetText, AddMessage) but never compared, concatenated, tostring'd,
-- pattern-matched or truth-tested in Lua.
function API.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

function API.ClientBuild()
    local version, build = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build)
end

-- RegisterEvent throws on an unknown name and returns false on a refusal.
-- Both count as failure, and every failure is reported: a silently missing
-- handler is the bug this exists to prevent.
GC.eventFailures = {}

local function report(name, why)
    table.insert(GC.eventFailures, name .. ": " .. why)
    API.Print("|cffff6060could not register|r " .. name .. " (" .. why .. ")")
end

function API.RegisterEvents(frame, events)
    for _, name in ipairs(events) do
        local ok, registered = pcall(frame.RegisterEvent, frame, name)
        if not ok then report(name, tostring(registered))
        elseif registered == false then report(name, "refused") end
    end
end

-- The one place failures are recorded (first error per key), read by
-- /gchat failures and the tests.
GC.failures = GC.failures or {}
function API.Fail(key, err)
    if GC.failures[key] == nil then GC.failures[key] = tostring(err) end
end

-- Class colour from the documented API (RAID_CLASS_COLORS is a FrameXML
-- table the dump cannot confirm). Returns r, g, b or nil.
function API.ClassColor(classFile)
    if API.IsSecret(classFile) then return nil end   -- before ANY test of it
    if not (classFile and C_ClassColor and C_ClassColor.GetClassColor) then return nil end
    local c = C_ClassColor.GetClassColor(classFile)
    if c then return c.r, c.g, c.b end
    return nil
end

-- A frame from a template that may be missing: a missing template doesn't
-- throw, it returns a bare frame, so `proof` (a field the template makes)
-- tells. Returns the frame and whether the template took (GlassActionBars').
function API.SafeFrame(ftype, parent, template, proof)
    local ok, f = pcall(CreateFrame, ftype, nil, parent, template)
    if ok and f then return f, (proof == nil) or f[proof] ~= nil end
    return CreateFrame(ftype, nil, parent), false
end

-- A plain Blizzard button (UIPanelButtonTemplate, as GlassPanel uses it).
function API.Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- UIPanelScrollFrameTemplate shows its bar even with nothing to scroll
-- (seen in GlassPanel, #36): show it only while the content is taller than
-- the view, the range floored like the template's own handler.
function API.AutoHideScrollBar(scroll)
    local bar = scroll.ScrollBar
    if not bar then return end
    local function sync(self, _, yrange)
        bar:SetShown(math.floor(yrange or self:GetVerticalScrollRange() or 0) > 0)
    end
    scroll:HookScript("OnScrollRangeChanged", sync)
    sync(scroll)
end

-- The player's full name, "First Surname", or nil. The client has given it
-- two ways: whole in UnitName's first return, or the first name and the
-- surname split across both (AltStable #56; the split shape is what dropped
-- hellos in LibAccountSync #4). A first return that already holds a space is
-- whole: the second slot is then not its missing half. Lifted from AltStable's
-- API.PlayerFullName (Compat.lua).
function API.PlayerFullName()
    local name, second = UnitName("player")
    if API.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    if name:find(" ") then return name end
    if not API.IsSecret(second) and type(second) == "string" and second ~= "" then
        return name .. " " .. second
    end
    return name
end

-- An addon's TOC Version, or nil (absent API, error, secret, not a string).
function API.AddOnVersion(addon)
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    if not get then return nil end
    local ok, v = pcall(get, addon, "Version")
    if not ok or API.IsSecret(v) or type(v) ~= "string" then return nil end
    return v
end

-- An installed addon's folder name as the client spells it, or nil.
function API.AddOnName(name)
    local info = C_AddOns and C_AddOns.GetAddOnInfo
    if not info then return nil end
    local ok, real = pcall(info, name)
    if not ok or API.IsSecret(real) or type(real) ~= "string" or real == "" then return nil end
    return real
end

-- A right-click menu (Blizzard_Menu's MenuUtil.CreateContextMenu): gen(root)
-- fills it with root:CreateTitle / root:CreateButton. False when there's none.
function API.ContextMenu(gen)
    local menu = rawget(_G, "MenuUtil")
    if not (menu and menu.CreateContextMenu) then return false end
    local ok, err = pcall(menu.CreateContextMenu, nil, function(_, root) gen(root) end)
    if not ok then API.Fail("context menu", err) end
    return ok
end

-- A read-only text box in a window: Esc closes the window, and typing puts
-- host[field] back (selected again when reselect). Copy, focus mode and the
-- address box share it.
function API.ReadOnly(edit, host, field, reselect)
    edit:SetScript("OnEscapePressed", function() host:Hide() end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and host[field] then
            self:SetText(host[field])
            if reselect then self:HighlightText() end
        end
    end)
end

-- A glass dialog window, lifted from GlassPanel's Compat: FULLSCREEN_DIALOG,
-- clamped, Escape closes it (UISpecialFrames, as AltStable does on
-- Forever), an opaque backing under the glass so nothing shows through the
-- text. Fields: glass, backing, title, hint (anchor content below
-- `win.hint`). Hidden: open it with API.ShowWindow.
function API.Window(name, width, height)
    local Glass = GlassChat.Glass
    local win = CreateFrame("Frame", name, UIParent)
    win:SetSize(width, height)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    win:SetToplevel(true)   -- a click brings it to the front, as Blizzard's dialogs
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:Hide()
    local special = rawget(_G, "UISpecialFrames")
    if type(special) == "table" and name then table.insert(special, name) end
    win.glass = Glass.Apply(win, "small")
    win.backing = win:CreateTexture(nil, "BACKGROUND", nil, -7)
    win.backing:SetAllPoints(win)
    win.backing:SetColorTexture(0.05, 0.05, 0.06, 0.96)
    win.backing:AddMaskTexture(win.glass.mask)
    win.title = Glass.Font(win, 14, "LEFT")
    win.title:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -12)
    win.hint = Glass.Font(win, 11, "LEFT")
    win.hint:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -6)
    win.hint:SetPoint("RIGHT", win, "RIGHT", -14, 0)
    win.hint:SetTextColor(0.75, 0.75, 0.75)
    return win
end

-- Every window shares the strata and the level, so the one opened last
-- isn't on top by itself: the address box opened under the copy window
-- (Pearl run, #106). Raise also covers a window already open.
function API.ShowWindow(win)
    win:Show()
    win:Raise()
end
