# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GlassChat is a **chat addon for World of Warcraft: Forever 1.60.1** (Interface `16001`), written
in **Lua 5.1**. It has a single owner (Spotnick) and uses the same stack and conventions as the
sibling Forever addons `..\GlassRaidFrames` (the closest sibling in workflow and tests),
`..\GlassUnitFrames` (the glass material's pilot consumer) and `..\GlassXp` (GlassPanel). When this
file doesn't cover something, check how those handle it before you invent a new idiom.

**Goal:** a much smaller, glass-styled take on Prat-3.0.
- **The look.** The chat in the "liquid glass" material of the `Glass*` addons (`Glass.lua`).
  **Readability comes first** (owner): the chat stays visible, on a dark see-through glass panel.
- **Class colours** on player names.
- **Smart tabs:** an addon that floods chat (the owner's probes, e.g. ASProbe) is offered its own
  tab, for the session or permanently. Routing goes through a wrapping print handler.
- **Focus mode, the headline feature:** freeze and maximise the current tab in a glass window,
  with search, filters (by kind, by source addon, by time), copy, and an export to SavedVariables
  that Claude can read directly. It's mainly for the probe output the owner pastes into Claude
  sessions.
- **Copy web addresses** by clicking them (URLs only; game links keep their stock behaviour).
- **Streamlined.** No Prat module zoo, no Ace3, no profiles. Prat's other ~40 modules are out
  unless the owner asks.

**Extend the stock chat; never replace it.** Forever's chat is Retail's (`ChatFrameMixin`,
`ChatFrameUtil`, `ScrollingMessageFrame`). Frames, tabs, docking, Edit Mode and the edit box stay
Blizzard's. GlassChat uses only documented hooks:
- `ChatFrameUtil.AddMessageEventFilter` / `AddSenderNameFilter`;
- `EventRegistry` callbacks (`"SetItemRef"` for our `|Haddon:GlassChat:…|h` links,
  `"ChatFrame.OnHyperlinkClick"`);
- `hooksecurefunc`;
- `setprinthandler` wrapping (never replacing) the previous handler;
- `FCF_OpenNewWindow` for smart tabs;
- CVars and public `ScrollingMessageFrame` methods (`GetMessageInfo`, `SetMaxLines`,
  `SetTextCopyable`).

**Never** a `RawHook`, a replaced `MessageEventHandler`, a hook on `ItemRefTooltip:SetHyperlink`,
or a read of private fields (`historyBuffer`, `visibleLines`). Reading a template's
**`parentKey`** child (`FontStringContainer`, a tab's `Left`/`ActiveMiddle`) is fine, because the
XML declares it. Runtime state set by Blizzard's Lua (`isDocked`, `hasBeenFaded`, `dock.primary`)
is not: use an accessor (`FCFDock_GetChatFrames`), a hook's own arguments, or the widget
(`tab:GetAlpha()`) instead. The one exception is `AutoCompleteBox.parent`, which is Blizzard's own
test (AutoComplete.lua:360). That is how Prat works, and on
this client each one taints chat. The research behind this is in `docs/PLAN.md`.

**Status: M0-M3 done (readable glass, class colours, scrollback, sent history, one layout,
smart tabs), plus timestamps and the Spam & Ignore plugin.** The probe results are in
`docs/FOREVER-PROBE.md`; the plan is `docs/PLAN.md`. M0-M5 are built; what's left is in the
plan's "Later" and the Spam & Ignore S3/S4. Work goes through
GitHub issues and PRs at `github.com/Spotnick2/GlassChat` (private), one issue per milestone.

## Layout

TOC load order: `Libs\LibGlass-1.0\LibGlass-1.0.xml` (the embedded material) →
`Libs\LibAccountSync-1.0\LibAccountSync-1.0.xml` (own-account messaging) → `Compat.lua` → `Glass.lua` → `Chat.lua` → `Skin.lua` → `History.lua` →
`Copy.lua` → `Buttons.lua` → `Layout.lua` → `Tabs.lua` → `Focus.lua` → `Url.lua` → `Levels.lua` →
`AccountSync.lua` → `SettingsSync.lua` → `GlassChat.lua`.

- **`Compat.lua`**: `GlassChat.API` is the only route to client APIs that moved or may be
  absent. It holds:
  - `IsSecret`;
  - event registration that reports failures;
  - `ClassColor`;
  - `Fail(key, err)`, the **one** failure recorder (`GlassChat.failures`, read by
    `/gchat failures`);
  - `MEASURED_ON_BUILD`;
  - the dialog helpers lifted from GlassPanel's Compat (`Window`, `Button`, `AutoHideScrollBar`).
    They use `GlassChat.Glass` at call time, never at load.

  It is a subset of GlassRaidFrames' `Compat.lua`; lift more from there when needed rather than
  rewriting.
- **`Glass.lua`**: GlassChat's instance of the material,
  `GlassChat.Glass = LibStub("LibGlass-1.0"):New()` (see "The glass material" below). Chat-specific
  tuning (darker tint, less grain and wash) is applied **on the regions `Glass.Apply` returns**, in
  `Skin.lua`: the library never repaints existing regions. The window's directional edge is the
  material's own optional edge (`g.edge`), set per window with `Glass.SetEdge` from `/gchat
  tune`'s values.

## The glass material

The material is **LibGlass-1.0**, an embedded LibStub library (`..\LibGlass`,
github.com/Spotnick2/LibGlass, public, MIT) that every glass addon embeds. Its repo owns the code,
the textures, the generator and the write-up (`docs/GLASS-MATERIAL.md`), and its `CLAUDE.md`
holds the contract. The migration notes are `C:\Projects\WoW\References\LIBGLASS-MIGRATION.md`.

- **Material changes are LibGlass PRs**, never edits here, and never edits to `..\LibGlass` from a
  GlassChat session: a bug or a need found here goes on a LibGlass issue.
- **How it's embedded:**
  - `.pkgmeta` externals put it in `Libs\LibGlass-1.0\`. That's the only supported path:
    `MEDIA` is derived from it.
  - The TOC loads its XML first.
  - `Libs/` is gitignored. A dev copy comes from the LibGlass checkout (`$env:LIBGLASS`,
    default `..\LibGlass`) through its own `Tools\deploy.ps1`, which `Tools\deploy.ps1` here
    calls first.
  - The tests load the same checkout, and fail loudly without one.
- **The pin:** `.pkgmeta` pins a tag (read the tag there: it is written only once), **never `tag: latest`**.
  - Bump it only in a release made anyway: players get library fixes earlier through whichever
    glass addon ships the newest copy, since LibStub runs that one.
  - CI reads the pin from `.pkgmeta` (`tests/fetch_external.sh <Libs/Name-1.0> <dest>`) and tests against it.
  - CI also asserts that the zip's `Libs/LibGlass-1.0/` is exactly that commit's shipped files.
  - `tests\run.ps1` and the deploy warn when the local checkout isn't at the pin.
- **`GlassChat.Glass` is an instance**: `STYLE`, `EDGE`, the `TUNABLES` setters and the font
  registry are GlassChat's own, so `/gchat tune` never touches another glass addon.
  - The plugins use the core's instance, `GlassChat.Glass`.
  - `Glass.MEDIA` resolves to the winning copy's `Media\`. Use it only for library textures:
    GlassChat has no art of its own.
- **Colours passed to a glass bar's `SetStatusBarColor` must be plain** (the library's hook
  compares them): never a secret.
- **`Chat.lua`**: the stock windows. `Chat.Frames()` is every `ChatFrameN` that exists (read
  with `rawget`). `Chat.OnEachFrame(key, fn)` registers an idempotent per-window setup.
  `Chat.Scan()` runs every setup on every window, each one under `pcall` (failures go to
  `API.Fail`), then the `Chat.AfterScan` steps (the dock, the side buttons). **Every setting
  change re-runs the scan** (`Skin.Refresh` is `Chat.Scan`), so a module never needs its own
  refresh wiring. Scans run at `ADDON_LOADED` (so login lines get the longer scrollback), at
  `PLAYER_LOGIN`, on `UPDATE_CHAT_WINDOWS` / `UPDATE_FLOATING_CHAT_WINDOWS`, and after
  `FCF_OpenNewWindow` / `FCF_OpenTemporaryWindow` (hooksecurefunc). It also holds:
  - **scrollback**: `SetMaxLines(db.lines)`, which keeps the existing lines (CircularBuffer.lua:29);
  - **class colours**: `chatClassColorOverride` kept at `"0"` at login. Turning the option off
    leaves the CVar alone.
  - **short channel names**: a `CHAT_MSG_CHANNEL` message filter (`Chat.ShortChannel`) rewrites
    arg4 `"1. General - The Barrens"` to `"1. General"`, for zone channels only (arg7 > 0), by
    returning `false` plus every argument. Blizzard builds the label from arg4
    (ChatFrameOverrides.lua:657) and the click link from arg8.
- **`Skin.lua`**: one dark glass container per window, after the owner's mockup.
  - **The window panel is a child of `UIParent`, pinned to `BACKGROUND`**. It follows the chat
    frame through `HookScript("OnShow"/"OnHide")`. As a child of the chat frame it drew over the
    `MEDIUM`-strata tabs, even with its own strata set (measured): the chat frame's strata change
    is applied to its children.
  - It covers `ChatFrameNBackground`'s rectangle plus `PAD_X/PAD_Y`, and reaches `TAB_STRIP` px
    up over the tabs, with a separator line.
  - Blizzard's `CHAT_FRAME_TEXTURES` are **hidden**, not faded: the hover fade skips hidden
    textures (FloatingChatFrame.lua:1336-1340; measured, nothing comes back on hover).
  - **Edit box:** its panel is a child of the box (`DIALOG` strata). Its border and focus art go
    to **alpha 0**, because focus toggles them with `SetShown`. Focus shows as a brighter rim.
  - **The tab strip is raised `TAB_GAP` px** to leave space above the first line: chat lines are
    clipped to the chat frame, which Edit Mode owns. `GeneralDockManager` is re-anchored after
    `FCFDock_SetPrimary`, and a floating window's tab after `FCF_SetTabPosition`. Docked tabs
    are left to the dock.
  - **Tabs:**
    - The name is 14 pt with a shadow, set at `ADDON_LOADED`, before Blizzard names and sizes
      the tabs. The text box is grown from its 8 px.
    - The stock art (background, selected and highlight pieces) is at alpha 0.
    - The selected tab gets a faint fill and a gold underline: textures created on the tab, under
      the name, repainted after `FCFTab_UpdateColors`. The other names are grey.
    - Resting opacity goes through `ChatFrameUtil.SetTabAlphas` after `FCFTab_UpdateAlpha`. Never
      write the `CHAT_FRAME_TAB_*_ALPHA` globals (that taints).
  - `Skin.Refresh()` applies setting changes, and glass off restores the stock look.
  - No Lua field or global is ever written on a Blizzard frame: state lives in weak-keyed tables.
    Creating regions on a tab and calling widget methods is fine.
- **`History.lua`**: plain Up/Down cycle **our own list**, `GlassChatCharDB.sent`. The edit
  box's native history ignores plain arrows here, even with `SetAltArrowKeyMode(false)`, because
  the template has `ignoreArrows="true"` (measured).
  - Alt mode is turned off so `OnArrowPressed` fires, and a `HookScript` on it walks the list
    with `SetText`. Down past the newest line restores the draft.
  - **The draft is its text and its destination.** `SetText` re-parses the box (OnTextChanged →
    ParseText), so recalling `/s …` switches it to SAY. The `chatType` / `tellTarget` /
    `channelTarget` / `stickyType` attributes are saved when browsing starts, restored after the
    draft's text, and the header is redrawn (Codex review of #4: an unfinished whisper was sent
    publicly).
  - Browsing resets on a send and on focus loss. There's no `SetText` during chat messaging
    lockdown.
  - Sends are recorded from `hooksecurefunc(edit, "AddHistoryLine")`, installed **after** the
    login replay into the native history, so replayed lines aren't recorded again.
  - `record` skips secrets, empty lines and a repeat of the last line, and trims to the cap.
- **`Copy.lua`** (#5): a window's lines as plain text, in a read-only glass window (`API.Window`,
  lifted from GlassPanel), **selected for Ctrl+C**. Addons can't write the clipboard here.
  - `Copy.Lines(f)` reads `GetMessageInfo` 1..N (1 = oldest). A secret line is never read: it
    becomes `Copy.HIDDEN` and is counted.
  - `Copy.Plain` strips colours, links (keeping their text), textures, atlases and `|K` names:
    the client's `StripHyperlinks` first, then our patterns.
  - A grey **Copy** button sits at the right end of each window's tab strip, on its glass panel
    (`Skin.Panel(f)`), in `MEDIUM` strata. The dock stops `Skin.DOCK_RESERVE` px short of it, so
    no tab or overflow arrow sits under it. With glass off there's no button (the stock look);
    `/gchat copy` copies the window the command was typed in, else the dock's selected one.
  - At most the newest `Copy.MAX` (1000) lines: 5000 in one EditBox froze the client
    (review of #6). `||` is set aside before stripping, so `a||rb` stays `a|rb`.
    `StripHyperlinks` keeps brackets, and `|K` names are replaced before it runs.
  - Focus mode (M4) builds on this window.
- **`Buttons.lua`** (#7): the buttons beside the chat as compact glass buttons.
  - **Voice-style buttons** (`VoiceToggleButtonTemplate`: channel, TTS, deafen, mute): the metal
    frame is the button's normal and pushed art, set to alpha 0. TTS's own black `Background`
    square goes too.
  - Behind them, a small glass pill from `Skin.NewPanel` / `Skin.Tune`, our own child one level
    under. Its `g.top` (the rims) is lowered with it, since `Glass.Apply` puts it at +10, over the
    gold `Icon`. The level re-syncs every scan.
  - The highlight is softened, and softened again after Blizzard's `UpdateHighlight`.
  - A button never styled (glass off from login) is never touched.
  - Parent keys and mixin methods are read with `rawget`: they are plain fields on the frame.
  - **The chat menu and the friends button** (#7) have their frame baked into one texture. Probe
    13 checked which frameless symbols the client has:
    - **friends:** `socialqueuing-icon-group` (owner's pick) is set on the button's own
      `FriendsButton` texture, and set again after Blizzard's `OnMouseDown` / `OnMouseUp` (which
      swap in the framed art). The friend count stays.
    - **chat menu:** no frameless bubble exists, so a small gold bubble is drawn from fills, like
      the copy icon. The file art (normal, pushed, disabled) goes to alpha 0.
    - The queue toast (`QueueButton`) is left as it is.
    - **Every button runs the shared steps** (pill, frame art, softened highlight), then its own
      `symbol[name]` step: the bubble, pressed (1 px down) and disabled (dimmed); or the friends
      symbol, applied once per glass change so a scan never overrides Blizzard's pressed art.
  - Run after every scan through `Chat.AfterScan`.
- **`Layout.lua`** (M2, #9): one chat layout for every character. Chat windows are saved per
  character (measured).
  - `/gchat layout save` records each window through `FCF_GetChatWindowInfo`, which maps the
    client's "default size" 0 to the real default (a raw 0 sets an invisible font). It also records
    `Messages` / `Channels` (names only) and, except for window 1, the saved size and place. All of
    it goes into `GlassChatDB.layout`: account-wide, with the saver's GUID and a new `id` per save.
    Plain values only, never a secret.
  - **Applying** (Prat Memory's recipe, trimmed): the `SetChatWindow*` setters, the font through
    `FCF_SetChatWindowFontSize`, then Blizzard's `FloatingChatFrame_Update(i, 1)` per window
    (it names, colours, docks, shows or closes), then chat types and channels through the
    window's own methods, then `FCF_DockUpdate`.
  - **The main window (an Edit Mode system) gets only its name, font, colour and chat contents**:
    no `FloatingChatFrame_Update`, lock, dock or shown state, and never its place or size (review of
    #10; Prat warns that this recipe taints Edit Mode). Its name, colour and opacity are shown
    through `FCF_SetWindowName` / `Color` / `Alpha` with doNotSave (Codex, #10).
  - Save ids come from an account-level counter (`GlassChatDB.layoutRevision`), so forget + save
    never reuses an id. `Matches` compares a floating window's size and place too.
  - Tabs that are already docked keep their order: `FCF_DockFrame` / `FCFDock_AddChatFrame`
    return early for them, and reordering would mean undocking. `FCF_SaveDock` records the real
    order afterwards.
  - A channel is added only if `GetChannelName(name) > 0`. `AddChannel`'s own return is 0,
    which is truthy, for a channel the character isn't in. Nothing is joined, and the skips are
    counted and reported. Channel names are the client's own strings, replayed on the same
    client, never compared to English.
  - Never in combat. Each window runs in its own `pcall`.
  - **The offer:** once per save and character. `GlassChatCharDB.layoutAnswered` holds the save's
    `id`, and an apply only counts when no window failed. It runs from the boot frame's
    first-login branch, after `OFFER_DELAY`, as a clickable `|Haddon:GlassChat:layout:apply|h` /
    `:no` line through `EventRegistry "SetItemRef"`. It's never offered to the saver (GUID), nor
    to a character that already matches. Closed windows don't count towards a match, while an open
    window's font and channels do.
- **`Tabs.lua`** (M3): smart tabs.
  - An addon that writes `Tabs.CHATTY` (20) lines within `Tabs.WINDOW` (60 s) is offered, once a
    session, its own tab. The offer is clickable `|Haddon:GlassChat:tabs:<session|always|never>:
    <Addon>|h` links. Always and never are saved account-wide (`GlassChatDB.routes` /
    `routeNever`); `/gchat tabs` lists and forgets them.
  - **One `AddMessage` post-hook per window, in `Chat.lua`**, sees each line with no chat event.
    It calls `Chat.Route` (set by Tabs) first and stamps only a line that stays.
    `Tabs.SourceOf` names the writer from `debugstack`: it skips the leading `GlassChat` frames
    (and the `pcall` / tail-call frames between them, which name no addon), then any `Blizzard_*`
    plumbing and standalone `Ace*` / `Lib*` library folders, so `print` (via `Blizzard_PrintHandler`) and direct
    `AddMessage` are both covered. Probe 7: ASProbe uses `AddMessage`.
  - **A move** copies the line to the tab (`FCF_OpenNewWindow(addon, true)`, or the open window
    of that name), then removes the newest match from where it landed with
    `RemoveMessagesByPredicate` (oldest to newest, so older identical lines stay).
  - **Click an addon's name** (#35, #78):
    - For a line that stays, the shared hook rewrites it once (`decorateLine`): the leading
      coloured prefix becomes `|Haddon:GlassChat:src:<Addon>|h...|h` (`Tabs.Linkify`, only for
      the line `Route` just attributed), then the timestamp is added.
    - A right-click (`SetItemRef`'s button) opens a `MenuUtil.CreateContextMenu` menu. The
      offer's links, the menu and `/gchat tabs route <Addon> [always]` all go through
      `Tabs.SetRule`.
    - **A plain left-click opens focus mode filtered to that addon** (#78). Shift, Ctrl and Alt
      clicks do nothing. The menu's first item, "Show its lines", does the same.
    - **The window** is `SetItemRef`'s 4th argument (ChatFrame.lua:19 passes the clicked frame),
      used only if it's one of `Chat.Frames()` (another addon's message frame isn't), else the
      window in view. The menu captures it when it opens, not when an item is picked. Without
      `MenuUtil`, the fallback links include `tabs:show:<Addon>`.
  - **Developer mode** (`GC.IsDev()`: version "dev" or the unreplaced token;
    `GlassChatDB.devMode` overrides it):
    - an addon named `*Probe` gets its tab at its first line, once a session;
    - **`GlassChat.RequestTab(addon)`** (public) is granted at once in developer mode, and
      outside it brings the one-time offer;
    - a player's No always wins.
  - **Notices printed while a line is handled** (the developer-mode tab, the offer, "tab was
    closed") are held and printed once that line is done (`Tabs.LineDone`, from the hook). They
    go through the same hook, so printed straight away they would land before the line's move
    and leave it in both windows (Codex, #36).
  - **Quiet while the game loads** (owner): from GlassChat's start until `Tabs.LOAD_QUIET` (15 s)
    after the loading screen of a login or `/reload` (`PLAYER_ENTERING_WORLD` isInitialLogin or
    isReloadingUi; zoning doesn't count), every addon prints its "loaded" line. Those lines:
    - open no tab, route no probe by name, and count toward no offer;
    - still go to a tab that is already open;
    - still have their writer noted (focus mode's From).
    - **It always ends:** a backstop armed first in `Tabs.Start` ends it after `LOAD_BACKSTOP`
      (60 s), even if no loading screen is seen. A secret argument counts as a login. Each quiet
      has a generation, so an older timer never ends a newer quiet.
  - It never walks the stack for the combat log (`COMBATLOG`, every entry is a plain
    `AddMessage`). Opening a tab puts back the selected tab and active edit box, because
    `FCF_OpenNewWindow` selects the new one. **No new tab while the player is typing**
    (`ChatFrameUtil.GetActiveWindow()`): in the IM chat style, making the new box the last
    active one hides the box being typed in, and its `OnHide` clears the draft (Codex, #26).
  - It never offers Blizzard, GlassChat or its plugins, and never moves a secret line. A closed
    tab sends that addon's lines back to the main chat for the session.
  - **An open tab named after an addon keeps catching its lines** (owner, #81; `db.tabsCatch`,
    `/gchat tabs catch on|off`, on by default), while the game loads too. Blizzard saves chat
    windows per character, so a session tab comes back at the next login with no rule behind it
    and sat empty. It's adopted at the addon's first line (`adopted`, kept apart from session
    rules so `catch off` stops it at once; Codex, #82). A Never, "Back to the
    main chat" or `forget` (`released`, this session) and a closed tab stop it.
- **`Focus.lua`** (M4): focus mode.
  - **Opening it:** `/gchat focus [text]`, or the magnifier on the tab strip, slot 2 after the
    copy icon. `Skin.CORE_ICONS = 2`, and a plugin's icon comes after them.
  - **One addon's lines** (#78): click its `[Name]` (Tabs above), or `/gchat focus from <Addon>`.
    The name is the folder name, resolved in any case through `API.AddOnName`. Only an exact
    `from` or `from <one word>` is the command; a word that isn't an installed addon falls back
    to the search it always was (`from Bob`), with a note. Anything else is a search.
    - **A requested source stays chosen with no lines** (Codex): falling back to "any" would show,
      copy and export everything. The status then reads "No attributed X lines in this window's
      newest N messages".
    - The status names a source with no lines only when the source alone matches nothing: a
      search or a kind that empties the view is a count. From, from a source with no lines here,
      goes to the first source present.
    - It's the window's newest `Copy.MAX` messages of every kind, not a session log. For a long
      diagnostic session, route the addon to a tab first.
  - **A frozen snapshot of the window** (`Focus.Snapshot`, through `Copy.Read`, the one
    secret-safe reader both windows use). Each line keeps its kind, from the chat event Blizzard
    passed to `AddMessage`. A line with no event is System when it carries a chat-type id
    (Blizzard's system, loot, money and XP lines: ChatFrameOverrides.lua:211-537), else Addons.
    **A line with no event also keeps the addon that wrote it**:
    - first from our own `src` link, **only when it is the line's decorated prefix**: the line
      starts with Linkify's colour and link, after nothing but a timestamp, the **whole** lead
      (`Tabs.LinkedSource`, the one reader of the link's grammar). It outlives the map. Text
      before it (`Forwarded: …`, stamped or not) or a literal `||` makes it a quote, credited to nobody (Codex,
      #79);
    - then, **only for a line with no chat-type id**, `Tabs.SourceFor`: a two-generation
      text → source map that `Tabs.Route` fills, re-keyed by `Chat.Restamped` when the line is
      stamped. An addon wrapping `AddMessage` is on the stack for Blizzard's own id lines, so
      the map would credit loot and system lines to it (review of #79).
    - A line with an id and our link is Addons (Codex, #78).
  - **`Focus.Filter`:**
    - kinds: a set, empty = all;
    - one source;
    - a plain, case-insensitive search, optionally with ±`CONTEXT` lines.
  - The view is a read-only EditBox, so Select all + Ctrl+C copies what's shown. "N new lines"
    comes from `Chat.LineCount` (counted in the shared `AddMessage` hook).
  - **Export** writes the view's plain lines to `GlassChatDB.export`.
  - **Secret lines** are `Copy.HIDDEN`, never matched or exported. The chat behind it is never
    touched.
- **`Url.lua`** (M5): click a web address to copy it (`db.urls`, on by default).
  - **The filter:** a message filter on the player-chat events (`Url.EVENTS`) rewrites arg1,
    returning false plus every argument. Each web address becomes
    `|Haddon:GlassChat:url:<address>|h[<address>]|h`.
  - **What counts:** `http(s)://`, `www.`, or a bare `name.tld[/...]` whose ending is in
    `Url.TLDS`. Never e-mail addresses or bare IPs.
  - `Url.Wrap` scans only the plain text between escapes: links, textures and atlases, colour
    codes (`|c`, `|cn`, `|r`) and `||`. Leading brackets and quotes, and trailing punctuation,
    stay outside the address.
  - **The filter goes in at `PLAYER_LOGIN`**, after the spam plugin's, because filters run in
    the order they were added and mutes must see the text as typed. There's one decision per
    (event, lineID).
  - `Copy.Plain` turns our address links back into the plain address, without the brackets.
  - **The click:** `EventRegistry "SetItemRef"` opens a small read-only box with the address
    selected for Ctrl+C. There is no clipboard API here (probe items 2-3).
- **`Levels.lua`** (#71): a known player's level before their name, `[60:Name]` (`db.levels`, on by
  default, as in Prat's PlayerNames).
  - **A session cache keyed by GUID**, filled from you (`PLAYER_LEVEL_UP`'s own level), the group
    (`UNIT_LEVEL`), target, mouseover, friends (`FriendInfo.guid`) and the guild
    (`GetGuildRosterInfo`'s 4th and 17th returns, Retail's order, unmeasured here: each value is
    checked). No `/who` queries: their answers carry no GUID. **A cached level never goes down**:
    the sources lag, and an older reading must never replace a newer one (Codex, #72).
  - **The guild roster is requested** (`C_GuildInfo.GuildRoster`, at most every `ROSTER_EVERY`
    120 s) at login, on `PLAYER_GUILD_UPDATE` (guild info often lands after login) and on a guild
    line, so levels don't go stale. Your own level comes only from login and your level events:
    `UnitLevel("player")` can lag `PLAYER_LEVEL_UP`.
  - **The display is a sender-name filter** (`ChatFrameUtil.AddSenderNameFilter`): arg12 is the
    sender's GUID, and the returned name goes inside the player link's brackets
    (ChatFrameOverrides.lua:576-585). Emotes print it without brackets, so they get no level, and
    Battle.net lines (`CHAT_MSG_BN_*`) name the account, so neither do they. An unknown sender, a
    secret or the setting off returns nil, which keeps the stock name. The level is coloured with
    `GetQuestDifficultyColor`, plain when that fails.
- **`AccountSync.lua`**: GlassChat's link to the player's other WoW accounts, through the embedded
  **LibAccountSync-1.0** (Spotnick2/LibAccountSync; GlassChat is its pilot consumer).
  - **One instance per snapshot kind, on one store** (`AS.insts`, tag → instance): `GlassChat`
    for the lists, `GlassChatST` for the settings (`AS.TAGS`; a kind not listed goes on
    `AS.TAG`). Tags are wire-visible and permanent: never change them. The library's replay floor
    is per (tag, sender), so on one tag a settings copy finishing first dropped a list copy sent
    before it (LibAccountSync#17, settled this way in r5). `AS.inst` is `GlassChat`'s, used for
    peers and the readout; `AS.SetEnabled` flips every instance.
  - **The store holds the household key, so it is never written into `SavedVariables\GlassChat.lua`**,
    the file focus mode's export goes to, which is meant to be shared. The client writes **one file
    per addon**, whatever the number of variables (Codex, #40), so the store is
    **`GlassChatSpamIgnoreSyncDB`, declared by the Spam & Ignore plugin**, which every sending
    feature needs. It lands in `GlassChatSpamIgnore.lua`.
    - Without the plugin there's no store, and the library fails closed.
    - A store an earlier build left in `GlassChat.lua` (`GlassChatDB.accountSync`, `GlassChatSyncDB`)
      is taken out at GlassChat's `ADDON_LOADED` and adopted at the plugin's, with its key.
    - The getter reads it raw, nil until the SavedVariables load.
  - **A payload is `"<kind>\n<body>"`.** Features register a kind with `AccountSync.On`;
    Spam & Ignore's snapshot is `SI`. The kind alone picks the handler, on either tag. An unknown
    kind is ignored.
  - **The sender comes from the library** (Blizzard's sender id), never from the payload.
  - Library reports: `error` goes to `API.Fail` and chat; `info` is kept for
    `/gchat ignore sync` and printed only in developer mode.
  - **Embedding** follows LibGlass's pattern:
    - `.pkgmeta` external at `tag: r5` (r2 passed GlassChat's two-account check, r3 the
      library's own; r4's `SendTo` and r5's messages mode are unused);
    - the TOC's XML line;
    - `tests/fetch_external.sh`, `$env:LIBACCOUNTSYNC` (default `..\LibAccountSync`), and the
      deploy calling the library's own deploy;
    - CI's allowlist and pinned-content checks for both libraries.

    Never edit `..\LibAccountSync` from here: a bug goes on a LibAccountSync issue.
- **`SettingsSync.lua`** (#52; plan: `docs/PLAN-SETTINGS.md`, reviewed by Codex): your settings,
  and optionally the saved chat layout, on your other WoW accounts. Payload kind `ST`, through
  `GC.AccountSync`.
  - **Commands:** `/gchat settings send [layout]` and `/gchat settings undo`. Sending is manual,
    and receiving never sends back. The on/off switch stays `/gchat ignore sync`.
  - **It needs the Spam & Ignore plugin** (owner), since the plugin holds the store
    (`AS.HasStore`).
  - **A small registry:** `SS.Register(section, keys)`. Section `core` is registered here,
    section `spam` by the plugin's `UI.Start`. Each key has a type, its range or allowed values,
    a raw `get` (nil when unset), a `default` and the slash command's own setter. The plugin's
    setters are `UI.Set`, shared with its slash commands.
  - **Never sent:** `devMode`, `debug`, `collect`, smart-tab rules, the export, the logs, the lists
    and the key.
  - **Defaults:** a key unset or set to its default travels as `D`. The receiver resets it
    through `set(default)` and then clears it; a setter never takes nil.
  - **Format `ST1`:** the shape is all-or-nothing, with caps and duplicates refused. A value this
    copy can't take (an unknown key, out of range, an unknown choice) is skipped and reported.
  - **Applying:** only changed values are applied. The old raw values go to
    `GlassChatDB.settingsUndo`, and the summary says "follow", never "match". A failed setter is
    reported.
  - **Undo** can't bring back a trimmed sent history, lost scrollback, the class-colour CVar or
    mirror writes, and says so.
  - **The layout is never applied.** It replaces the saved layout with a new id from
    `layoutRevision` and goes through `Layout.Offer`. The main window's place and size never
    travel; its `docked` does, since `Matches` compares it.
  - **Order:** `GlassChatDB.settingsApplied[guid]`. It travels on its own tag, `GlassChatST`, so
    it never races the lists (LibAccountSync#17).
- **`GlassChat.lua`**: bootstrap. Account-wide settings live in `GlassChatDB` (owner: no
  per-character setup); only the sent history is per character, in `GlassChatCharDB`.
  `GC.Settings.*` is the one place settings change (`/gchat` today, an options panel later). It
  also holds `/gchat` and the login warning when the build differs from `MEASURED_ON_BUILD` (dev builds only).
  There's no combat queue: chat frames aren't protected. If a feature ever needs one, lift
  GlassRaidFrames' `WhenOutOfCombat` (one queue only).
- **Plugins** (`Plugins/<Name>/`, GlassPanel's pattern): each is its own addon, with
  `## Dependencies: GlassChat` and `## Group: GlassChat`. The packager moves it out to a
  top-level folder named after its TOC (`.pkgmeta` `move-folders`), and `deploy.ps1` does the
  same. `tests/harness.lua`'s `PLUGINS` list loads it after the core's `ADDON_LOADED`, as the
  client does, and `test_toc` checks the list, the TOC and the `move-folders` line. A plugin uses:
  - `GC.RegisterSlash(sub, fn, help)` for `/gchat <sub>`;
  - `GC.Chat.OnEachFrame` / `Chat.Scan`;
  - `GC.Skin.Panel(f)`, `Skin.ReserveIcons(n)` and `STRIP_ICON_STEP` for a tab-strip icon;
  - `GC.Copy.Show(title, text, status)` for a text window.
- **`Plugins/SpamIgnore/`** (Spam & Ignore, S1, #19; plan: `docs/PLAN-SPAM.md`):
  - **One filter, two policies.** Explicit GUID ignores apply to every player-chat event, guild
    and group included. Heuristics (literal mutes at word edges, `~` aggressive, CJK, the spam
    score, repeats)
    apply to public chat only: CHANNEL, SAY, YELL, EMOTE. They never touch you, friends, guild,
    group, Battle.net friends or the allow list.
  - **One decision per (event, lineID)**, the memo (measured: each line reaches the filter once
    per window).
  - Repeats are timed from the last *shown* post.
  - **Never your own characters:** `db.own`, recorded at `PLAYER_LOGIN`.
  - Import reads Blizzard's list after `PLAYER_LOGIN` only.
  - **`Mirror.lua` (S2b) keeps each character's Blizzard list in step**, using linked names
    (`charDB.linked`, only names GlassChat added):
    - removing a linked name in Blizzard's UI unignores it everywhere;
    - an unignore anywhere removes the linked name at that character's next check;
    - a name that was already on Blizzard's list is never touched by a sync;
    - **nothing changes on an untrusted read**: not ready, an unreadable entry, empty with
      names linked, or more than `MASS_LOSS` linked names gone at once;
    - writes are throttled, checked against the list, and bounded (`MAX_TRIES` across logins);
    - never your own characters.

    The rules are in `docs/PLAN-SPAM.md`.
  - **`Sync.lua` (S3 part 2): the lists to your other accounts.**
    - `/gchat ignore send` sends a snapshot through `GC.AccountSync`: the ignores (by GUID), the
      pending names, the mutes, and your own characters.
    - **Format `SI1`:** one record per line, tab-separated fields, the format first. The parser is
      all-or-nothing: an unknown format or line, a bad GUID, length or count refuses the whole
      snapshot.
    - **The receiver replaces** its ignores, pending names and mutes, removals included, and keeps
      the old ones for `/gchat ignore sync undo`. Your own characters are only ever added, and an
      ignore naming one of yours is dropped.
    - **The sender** never sends an ignore naming one of its own characters (AltStable's
      included, sent as own). It refuses an empty snapshot (counted from what is sent, not the
      raw lists) unless you run `/gchat ignore send empty`, or the last change on this account was
      a removal (`Spam.Edited`, `db.lastEdit`: unignore, unmute, a linked name removed in
      Blizzard's list; any add, import, received copy or undo resets it, #48). It checks the
      receiver's caps first.
    - **Order:** the last applied stream id is kept per sender GUID, in
      `GlassChatSpamIgnoreDB.syncApplied`. The library already drops older streams within a
      session; this check also covers across sessions.
    - `/gchat ignore sync [on|off]` shows the library's diagnostics and switches it. Sizes: 50
      ignores is about 2.5 KB and 500 about 23 KB, under `AccountSync.MAX` (32 KB). Over that,
      the send refuses with the size rather than truncating.
  - **Your characters on other WoW accounts** come from AltStable when it's installed
    (`## OptionalDeps: AltStable`). `AltStable.GetCharacters()` (public API **v1 only**) is read
    at login and on its `CharactersChanged` callback (which also re-runs the mirror's check)
    into a GUID/name cache that `isOwn` / `ownByName` consult.
    - Names count only while `RegionalUniqueNamesEnabled()` is true (measured on Forever) and
      only with a surname.
    - **A known GUID always decides.** `ownByName` is only the fallback for a pending entry
      that has no GUID yet. The list sync between accounts goes through the
    LibAccountSync-1.0 library (Spotnick2/LibAccountSync#1).
  - **`Score.lua` (S4): the spam score**, on public chat, after ignores, mutes and CJK and
    before repeats (so a line it hides is never timed as the last shown post).
    - **Shape, never words.** Token kinds (each token counts toward one, first match):
      - address: `Url.Address(word, Score.TLDS)`, one grammar with M5's, look-alikes mapped first.
        Spam's extra endings match only as typed in lower case (`tank.Top` is a missing space).
        A host with 3+ single-character labels (`b.u.y.g.o.l.d.cc`) is broken-up too.
      - contact: `@name`, `Name#1234` with 4-5 digits.
      - price: a currency symbol right next to a digit anywhere in the token (`$1,000`,
        `1000g=5$`), or a lone symbol beside a number (`5 $`); never `%`.

      Line kinds: broken-up (5+ single characters set apart by separators, counted tokens
      skipped) and look-alike (a twin from the other script *inside* a word: Cyrillic `о` in
      `gоld`, Latin `o` in `гoлд`; `MCе` and `ZGшку` never count).
    - **Spam** = a spam kind (price, broken-up, look-alike) plus any other kind. An address with
      a contact is players' own advertising and never decides. Decoration is logged only.
    - **`db.score` is off, watch (the default) or hide.** `Judge` returns the finding as a
      second value, never as a reason, so the memo's "reason or false" is unchanged and watch
      can't hide. The score log (session memory, `/gchat spam score`) holds every scored line with
      its final outcome, lines with no lineID included and marked. Would-hide lines
      (`Score.LOG_SIZE`) and near misses (`Score.NEAR_SIZE`) have separate buffers, so a busy
      channel's links never push out the lines watch mode is for. It never touches the
      hidden-lines log or the icon's count.
  - **`/gchat spam collect on/off/clear`** (temporary, until the score's weights are settled; on by
    default in a dev build only, `Spam.Collecting`, never in a release; the player's setting wins): every scored line and every line the repeat rule, a mute or the score hid goes
    into `GlassChatSpamIgnoreDB.collected` (`Spam.COLLECT_MAX` 3000, oldest dropped), with its
    kinds, outcome, event, sender, the character that saw it and the plain text. Never CJK lines
    (judged by the content, since a mute can hide one first) or an ignored player's. Lines with no lineID are kept, marked `noid`. After a full exit, read it **only through
    `Tools\collected.lua`**, which writes out the collected lines alone: that file also holds the
    household key, so it's never read whole into a session (review of #59). The default comes from
    `GC.IsDev()` (fails closed); `/gchat spam collect default` clears a saved on/off, and a dev
    build collecting by default says so at login.
  - The hidden-lines log is session memory: `/gchat spam log`, or the **opt-in** tab-strip icon
    (`/gchat spam icon on`, off by default). The icon is a bug in a dev build (`Version` "dev" or
    unreplaced) and an eye in a release, and the debug log shows the event too.
- **`Tools/ChatProbe/`**: the throwaway measurement addon (`/cprobe help`). It logs every line to
  `ChatProbeDB.log` in SavedVariables, so after a full client exit the session is on disk at
  `WTF\Account\<account>\SavedVariables\ChatProbe.lua` for review. **It never logs what anyone
  said**, only the type and length of each value and whether it was secret (`test_probe` pins
  this).

Forever is **Vanilla content running on Blizzard's Retail (Mainline) codebase**: assume Vanilla
content and the Retail API. Advice that cites a TBC or Classic chat API (`ChatFrame_OnEvent`,
`ChatFrame_MessageEventHandler`, `ChatFrame_OnHyperlinkShow`) is stale: none of those globals
exists here.

## References: read these before touching an unfamiliar API

- `C:\Projects\WoW\References\PORTING-TBC-TO-FOREVER.md` holds the canonical addon-agnostic field
  notes, measured on the live client. Treat them as fact; don't re-derive them. Other sessions
  edit this file, so write new addon-agnostic findings there (it has no chat section yet; the
  probe results belong in one), not into a copy in this repo.
- `C:\Projects\WoW\References\forever-api-1.60.1.70338.md` is the full API dump for the current
  build. It lists documented functions and events, enums, **widget methods** (the only list of
  those) and the `_G` walk. FrameXML tables such as `ChatTypeInfo` aren't in it. It proves a name
  exists, not that it works. **Presence is not a contract.**
- For a live check in game: `/api search <name>`, `/api system list`, `/api <system> list`.
- **`C:\Projects\WoW\wow-ui-source` is Forever's own FrameXML** (branch `forever`). Read Blizzard code
  there first: line numbers in in-game error traces match it. For chat:
  - `Blizzard_ChatFrameBase/Shared/ChatFrame.lua`: `OnEvent`, `OnHyperlinkClick` firing
    `EventRegistry`;
  - `Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua`: `MessageEventHandler`, the default
    `SetMaxLines(128)`;
  - `Blizzard_ChatFrameBase/Shared/ChatFrameFilters.lua`: filters run through
    `securecallfunction`, and **only while `canaccessvalue(...)`**;
  - `Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua`: `ShouldColorChatByClass` at 880 and
    `GetDecoratedSenderName` at 1061;
  - `Blizzard_SharedXML/ScrollingMessageFrame.lua`: `SetTextCopyable` and drag-select →
    `CopyToClipboard`;
  - `Blizzard_UIPanels_Game/Shared/ItemRefHandlersShared.lua`: the `addon` link type →
    `EventRegistry "SetItemRef"`.
- `..\LibGlass\docs\GLASS-MATERIAL.md` is the write-up of the glass material.

## Reference addon

**`C:\Projects\WoW\References\Prat-3.0` is the design reference** for *what* a chat addon does. It is
Forever-aware (`Prat-3.0_Camelot.toc`, `Prat.IsForever`), but its *mechanism* (above) is the one
we don't use. Worth reading:
- `modules\UrlCopy.lua`: URL patterns and the TLD list;
- `modules\CopyChat.lua`: the `GetMessageInfo` loop, secret lines → `<SECRET>`, and
  `C_StringUtil.StripHyperlinks`;
- `modules\Search.lua`: a search box per frame (no secret guard);
- `modules\History.lua`: `SetMaxLines` with a range of 300-5000;
- `modules\Scrollback.lua`: history kept across sessions in SavedVariables;
- `services\classcolor.lua` and `services\helpers.lua`: name colouring by GUID.

Prat is **GPL-3.0, like this repo**, so lifting code is allowed with attribution in the file
header. Prefer our own code anyway: Prat's is written for its Ace3 pipeline.

Keep a `MEASURED_ON_BUILD` constant in the source, matching the dump's build (`1.60.1.70338`),
and warn at login when `GetBuildInfo()` differs, in a dev build only (owner: a player can't act on
it; `/gchat version` shows both). Bump it only after re-measuring in game.

## Toolchain and commands

There is no build system, compiler or package manager; the client interprets the Lua directly.
The Lua 5.1 toolchain is at `C:\Program Files (x86)\Lua\5.1\` (`lua.exe`, `luac.exe`). Use it,
not a newer Lua that may be first on `PATH`.

```powershell
& 'C:\Program Files (x86)\Lua\5.1\luac.exe' -p File.lua             # syntax check; silent on success
pwsh tests\run.ps1                                                   # luac -p on our files + probe + every tests\test_*.lua (needs ..\LibGlass or $env:LIBGLASS)
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_boot.lua      # one test, run from the repo root
pwsh Tools\deploy.ps1 -Probe                                         # copy the addon (+ ChatProbe) into AddOns
```

- **Default AddOns path:** `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns`.
  The deploy script takes `-AddOnsPath`.
- **Deploy** rewrites `## Version: @project-version@` to `dev` in the deployed copy only. Never
  commit a literal version over that token; the packager needs it.
- **In game:**
  - Run `/console scriptErrors 1` first, because errors are off by default. Then `/reload`.
  - A brand-new addon folder needs a full client restart.
  - Check the AddOns list shows the addon enabled **and not flagged out of date**.
  - Error delivery stops after 100 errors in a session.

## Addon basics

- One plain `GlassChat.toc`, with no `_Forever` or `_Camelot` suffix. Use `## Interface: 16001`;
  **`11601` is a transposed-digit bug**.
- One global namespace table, `GlassChat`. Files start `GlassChat = GlassChat or {}` and alias it
  `local GC = GlassChat`. The TOC order is the load order. Slash commands: `/gchat`, `/glasschat`.
- Consumers reach client APIs through `GC.API`, never by injecting globals into `_G`. Read the
  porting guide's "False friends" section before aliasing anything.
- **IDs, never names (owner rule: support localized clients).** Never compare against, or save,
  an English display name. Chat-type tokens (`SAY`, `CHANNEL`), event names and link types are API
  values, not display text, and are fine. Channel *names* are display text.
- Keep a `_test` seam table at the bottom of a file to expose file-local internals to tests.
  Don't promote internals to globals.

## Forever facts that matter for chat

- **Secret values.** Some values come back as values you can hold but not read. Arithmetic,
  comparison, `tostring`, concatenation, `string.find`/`gsub` and **truth-testing** all throw,
  and a `x or ""` guard doesn't help. Test with `issecretvalue(v)` **before** any other use. A
  secret may go straight back to the client (`FontString:SetText`, `AddMessage`).
  - **Chat messaging lockdown** (`C_ChatInfo.InChatMessagingLockdown`, Retail 12.x) makes chat
    payloads secret, and Blizzard then **skips addon filters without telling you**. Whether and
    when Forever enters it is unmeasured (probe item 5).
  - Scrollback lines can be secret (`ScrollingMessageFrame:HasSecretValues`). Every
    `GetMessageInfo` read goes inside `pcall` and an `issecretvalue` check. A secret line is
    shown as hidden, and is never matched, copied or saved.
  - Never put a secret in SavedVariables. Copy only `type(v) == "string"` values that pass
    `issecretvalue`.
- **Taint.** Our code runs tainted. A flag we set on a Blizzard frame (e.g. `textIsCopyable`)
  taints whatever Blizzard code reads it. That can get a restricted call (`CopyToClipboard`
  has `HasRestrictions`) blocked, with `ADDON_ACTION_BLOCKED` blamed on us. Measure before relying
  on such a path (probe items 2-3).
- **Names have surnames**, space-separated ("Example Surname"). `UnitName` and
  `GetPlayerInfoByGUID` return the first name only. Key anything per player on the **GUID**, never
  the name.
- **`RegisterEvent` throws on unknown names and returns `false` for refusals.** Wrap it
  (`API.RegisterEvents`), treat both as failures, and report them. Registering
  `COMBAT_LOG_EVENT_UNFILTERED` is forbidden.
- `MouseIsOver` is absent (use `frame:IsMouseOver()`). `ReloadUI()` is protected.
- Options use the Retail `Settings.RegisterAddOnCategory`, not `InterfaceOptions_AddCategory`.
  **Edit Mode is live**, and the chat frame is an Edit Mode system: don't move or resize
  `ChatFrame1` ourselves.
- **SavedVariables persist as of 70009** (broken through 69977). Code may read them but must cope
  when they're absent. **Verify persistence only with a full client exit**, never `/reload` or by
  reading the SV file. Count loads inside the addon (the probe does: `ChatProbeDB.loads`).

## Testing

The `tests\` harness follows the siblings': plain Lua 5.1 scripts with no dependencies, a
`tests\wow_stubs.lua` API mock driven through an exported `WoW` table, `tests\harness.lua`
(`check` / `eq` / `loadAddon` / `newChat` / `chatHas`), and `tests\run.ps1` to run them all. The
stub does three more things:
- It validates event names against the API dump, or against `tests\events-70338.txt` when the
  dump is absent (CI). `test_toc` fails if the two drift.
- It models `FontString:SetFormattedText` taking secrets without formatting them in Lua.
- It records every widget method called. `test_methods.lua` checks each one exists in the dump.

`GlassChat.failures` collects the errors that handlers swallow, so a secrets test should assert
it stays empty. Before trusting a new test, **mutation-test it**: break the behaviour and confirm
it goes red.

- **The stub is an allowlist and must model the client's absences.** It fails on any read of an
  unstubbed global. Before stubbing one, confirm it exists in the current API dump (or in
  Forever's FrameXML for tables like `ChatTypeInfo`) and copy its exact signature. A test can add
  its own with `rawset(_G, …)` (see `test_probe.lua`).
- **Stub secrets as `newproxy(true)` userdata** (`WoW.Secret(label)`) with metamethods that
  error. `WoW.MarkSecret(v)` marks a real string, to reach `type(x) == "string"` branches. **No
  Lua 5.1 value can make a truth test or `==` throw**, so the stub can't catch `if secret then`
  or `secret == x`. Only in-game testing and review catch those.
- **Strict globals don't cover methods.** A catch-all `__index` swallows calls to widget methods
  this client lacks. Run the handler, assert what it produced, and check the method against the
  dump's widget-method section.
- Offline tests can't cover taint, real secret behaviour, the clipboard or rendering. Those need
  an in-game checklist and `Tools\ChatProbe`.

## Workflow and releasing (sibling conventions)

- Issue → branch off `main` → PR with `Closes #N` → review (owner-launched) → squash-merge (by
  the owner). Never commit to `main`.
  Commit or push only when asked. Before committing, `luac -p` must be clean and the tests green.
  **After pushing, check the PR's `package-check` run** (`gh run list`, then `gh run view`). CI
  has no API dump, so run a new test once with `GLASSCHAT_API_DUMP` pointing at a missing file.
- Review policy: use the shared `$wow-addon-review` skill for PR reviews.
- **The owner merges and closes PRs, and launches reviews.** Claude opens the issue, branch and
  PR, runs the tests, and stops there: never `gh pr merge` or close a PR, and never start a Codex
  or Fable review on its own. When the owner posts or points to a review, reconcile it (below)
  and push the fixes to the PR.
- **Adversarial review is mandatory** for plans and significant diffs, **launched by the owner**.
  When asked, run it through the project's `/codex-consult` skill
  (`.claude/skills/codex-consult/`), because Codex is a different model family and so has
  different blind spots. Always hand it `CLAUDE.md`, `docs/PLAN.md` and the porting guide. If
  Codex is unavailable, fall back to Fable. Then reconcile:
  - Verify its claims before acting. It has been right, and it has been confidently wrong.
  - Take its bug-catching seriously.
  - Push back when it adds complexity to a single-owner addon, or grows scope back toward Prat.
- **CurseForge releases** are built by **CurseForge's own packager from the tag webhook**, reading
  `.pkgmeta`. CI (`package-check.yml`) dry-runs `BigWigsMods/packager` with `-d`: its `check` job
  builds and checks the zip. The packager derives the `forever` flavor from `## Interface: 16001`.
- **A GitHub Release for every `v*` tag** (#70, AltStable's job from its #209): `package-check.yml`'s
  `release` job, the only one with `contents: write`.
  - It publishes the zip `check` built and checked, never a second build. The zip must be named
    `GlassChat-<tag>-forever.zip`.
  - The notes are the tag's `## vX.Y.Z` section of `CHANGELOG.md`. A missing section fails the job
    rather than publishing. Never the packager's own GitHub upload, which posts the whole changelog.
  - `gh release create --verify-tag` refuses to overwrite an existing release.
  - **Retrying a failed release:** fix the cause on `main`, delete any half-made release, then run
    **Actions → Package check → Run workflow** with the tag. That run reads the notes from `main`,
    so the tag never moves (a moved tag re-fires CurseForge).
- **Every tag needs a `CHANGELOG.md` entry committed first**, written for players, headed exactly
  `## vX.Y.Z` (the tag name; rename `## Unreleased`). Tags are `v`-prefixed. The tag name sets
  the channel: `alpha` / `beta` (any case) → pre-release on GitHub, alpha / beta on CurseForge;
  anything else → Release.
- `.pkgmeta` ignores `.github`, `.claude`, `docs`, `tests`, `Tools`, `CLAUDE.md`, `README.md` and
  `CHANGELOG.md`.

## Conventions

- **Right-size for a single maintainer.** Do the simplest thing that works, with no speculative
  abstraction or config.
- **Measured beats reasoned.** If a claim about the client can be checked in game, check it.
- Match the surrounding code's idiom. Keep pure refactors in their own commit.
