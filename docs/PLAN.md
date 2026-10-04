# GlassChat plan

Status: M0 (#2), M1 (#4), copy (#6) and glass buttons (#8) merged; **M2 in progress** (#9).
Probe items are numbered as in `Tools/ChatProbe` (`/cprobe help`).

## What the owner wants

1. Class colours on player names.
2. Click a web address to copy it.
3. Copy **any** text out of chat.
4. **Search and filter**, mainly for the long probe and addon output that gets pasted into Claude
   sessions: smart tabs (M3) and focus mode (M4).
5. The look: the liquid glass of the `Glass*` addons, with readability first.

Everything else Prat does is out unless asked for.

## How Prat does it, and what that means for us

Research notes on `C:\Projects\References\Prat-3.0` and Forever's own FrameXML
(`C:\Projects\wow-ui-source`, branch `forever`):

- **Prat doesn't replace the chat; it extends the stock frames.** It reuses `ChatFrame1..10` and
  creates no windows of its own. What it does replace is the message pipeline. It assigns its own
  function to every frame's `MessageEventHandler` (addon/addon.lua:389-398), splits each event
  into sections, lets ~40 modules edit them, runs Blizzard's handler on a hidden proxy frame to
  capture the formatted line, then calls the real `AddMessage`. On top of that it RawHooks
  `ItemRefTooltip:SetHyperlink`, `ChatEdit_HandleChatType` and `FCF_Close`, and reads the private
  `historyBuffer` / `visibleLines`. On a modern client, **every one of those taints chat**.
- **Prat already runs on Forever.** `Prat-3.0_Camelot.toc` is `## Interface: 16001`, and the code
  switches on `Prat.IsForever` at runtime. "Trim Prat" could mean running Prat with most modules
  off. We write our own because we want the glass look, no Ace3 stack, and no taint-prone
  pipeline replacement.
- **Forever's chat is Retail's** (`ChatFrameMixin`, `ChatFrameUtil`, `ScrollingMessageFrame`), and
  it already has public, taint-free hooks for nearly everything on our list:

  | Feature | Prat's way | The stock hook we can use instead |
  |---|---|---|
  | Class colours | its own copy of `GetDecoratedSenderName` + a name cache | Built in: CVar `chatClassColorOverride` / `ChatTypeInfo[t].colorNameByClass` (`ChatFrameUtil.ShouldColorChatByClass`, ChatFrameUtil.lua:880). Fallback: `ChatFrameUtil.AddSenderNameFilter`. |
  | Clickable URLs | pattern swap to `|Hurl:` + RawHook `SetHyperlink` | `ChatFrameUtil.AddMessageEventFilter` to wrap URLs in `|Haddon:GlassChat:…|h`. The click arrives on `EventRegistry "SetItemRef"` (ItemRefHandlersShared.lua:279-282) with no hook. |
  | Copy a link | n/a (URLs only) | `EventRegistry "ChatFrame.OnHyperlinkClick"` (ChatFrame.lua:19-33) sees every link click; a modifier-click copies its text. |
  | Copy any text | a dialog of `GetMessageInfo` lines | `ScrollingMessageFrame:SetTextCopyable(true)`: native drag-select, straight to `CopyToClipboard` (ScrollingMessageFrame.lua:383-420). Not on by default for chat frames. |
  | Search | re-adds `historyBuffer` matches to the frame (throws on a secret line) | `GetNumMessages` / `GetMessageInfo` (public), shown in our own popup. |
  | Longer scrollback | History: `SetMaxLines` (default 128 on Forever) | the same `SetMaxLines`. |

- **Secret values.** Retail 12.x has a *chat messaging lockdown* (`C_ChatInfo.InChatMessagingLockdown`):
  in it, chat payloads are secret, and **addon message filters are silently skipped**
  (ChatFrameFilters.lua:115-119, `canaccessvalue`). The porting guide hasn't recorded whether
  Forever ever enters it. Probe item 5 measures this. Whatever the answer, every feature must
  degrade to "leave the line alone", never throw. Prat's Search has no guard here.
- **Names have surnames** (porting guide :709-760). `GetPlayerInfoByGUID` returns the first name
  only, so any cache keyed by name mismatches. Class colours go by **GUID**, which Blizzard's own
  path already does.

**Decision: extend the stock chat; don't replace anything.** Only documented hooks
(`ChatFrameUtil` filters, `EventRegistry` callbacks, `hooksecurefunc`, CVars). No `RawHook`, no
replaced handler, no private fields. Frames, tabs, docking, Edit Mode and the edit box stay
Blizzard's. GlassChat skins them and adds the copy/search popup.

## Milestones

Each milestone is one issue and one PR.

### M0: scaffold and ChatProbe (this PR)

The repo and conventions, the glass material, `/gchat`, the tests, CI, and `Tools/ChatProbe`.
Probe items:

1. **State.** `chatClassColorOverride`, `colorNameByClass` per chat type, `MaxLines` per frame,
   which filter APIs exist.
2. **`CopyToClipboard`** called from addon code (`HasRestrictions = true`,
   `SecretArguments = AllowedWhenUntainted` in OsDocumentation.lua). Does it work, and is the
   action blocked?
3. **`SetTextCopyable(true)` on `ChatFrame1`.** Does drag-select copy work? Our tainted flag
   steers Blizzard's mouse-up into `CopyToClipboard`, which may be blocked. Do link clicks and
   frame dragging still work?
4. **An addon link** (`|Haddon:chatprobe:…|h`): does the click arrive on `EventRegistry
   "SetItemRef"`, with which button, and with no error or tooltip?
5. **Payload secrecy**, out of combat, in combat and in a dungeon: are text, sender, lineID and
   GUID secret, is `InChatMessagingLockdown` ever true, and do message and sender-name filters
   still get called?
6. **Scrollback reads.** Does `GetMessageInfo` work on every frame, how many lines are secret,
   and what does `HasSecretValues` say?
7. **Where addon output comes from** (`/cprobe sources`). A wrapping print handler
   (`setprinthandler`, Blizzard_PrintHandler.lua:74) and a `hooksecurefunc` on each frame's
   `AddMessage` name the calling addon from `debugstack`. They count lines per addon and per
   route. Only `print` lines can be re-routed: an addon that calls `DEFAULT_CHAT_FRAME:AddMessage`
   itself bypasses the print handler. This item measures how common that is among the addons you
   actually run.
8. **Routing to a tab** (`/cprobe route`). `FCF_OpenNewWindow("Probe", true)` opens an empty tab,
   and the print handler sends ChatProbe's own lines there. Does it work with no blocked action,
   and does the tab survive a relog?

Run with `pwsh Tools\deploy.ps1 -Probe` and a client restart. Then run `/cprobe` items 1-8 (with
ASProbe and your other addons active during `sources`) and quit the client fully. The log is at
`WTF\Account\<account>\SavedVariables\ChatProbe.lua`. Results go in `docs/FOREVER-PROBE.md`;
addon-agnostic findings also go in the porting guide.

### M1: readable glass, class colours, longer scrollback

- **Readability first** (owner): the chat stays visible at all times. The owner's habit today is a
  darker see-through background behind the text, and we keep that. A **dark, translucent glass
  panel** goes behind each chat frame: darker tint than the other Glass addons, no gloss over the
  text area, opacity adjustable (`/gchat alpha`). An outline/shadow option for the font. The edit
  box gets the same panel. Tabs and buttons stay stock for now, and get styled later only if the
  panel looks right.
- Class colours. The likely implementation is turning on Blizzard's own per-type
  `colorNameByClass` (or the override CVar) at login, after probe item 1 shows what's off. Only
  if that falls short, a sender-name filter colouring by GUID through `API.ClassColor`. Names
  **inside** message text (Prat's PlayerNameGlobalPatterns) are out.
- A longer scrollback: `SetMaxLines` (e.g. 1000; Prat's default is 384).
- **Sent-message history on plain Up/Down** (owner: "clearly a feature I want back from Prat").
  It's the edit box's own history: stock Forever needs Alt+Up/Down.
  `EditBox:SetAltArrowKeyMode(false)` on every chat edit box makes the plain arrows cycle it, as
  Prat's Editbox module does. A longer list comes from `SetHistoryLines`. It's kept across
  sessions per character (`GlassChatCharDB.sent`, filled from a `hooksecurefunc` on
  `AddHistoryLine`, replayed with `AddHistoryLine` at login, Prat History's recipe). All of these
  are widget methods in the 70205 dump.

### M2: one chat layout for every character

Owner: "set it up on every character" was always a chore with Prat. Prat's **Memory** module did
this. Chat windows are **per character** (probe item 8).

- **"Save as my layout"** (`/gchat layout save`) records, per chat window, what the client's own
  chat-window API reports: `GetChatWindowInfo` (name, font size, colour, alpha, shown, locked,
  docked, uninteractable), `GetChatWindowMessages`, `GetChatWindowChannels`,
  `GetChatWindowSavedDimensions` and `GetChatWindowSavedPosition`. It goes in `GlassChatDB.layout`,
  account-wide. Channels are kept by name, because channel numbers differ per character. Our
  smart-tab rules are already account-wide (M3).
- **On a character that hasn't had it**, GlassChat offers it once at login with a clickable
  `[Apply my chat layout]` link, then remembers the answer (`GlassChatCharDB.layoutApplied`).
  `/gchat layout apply` does it at any time. Applying uses the matching `SetChatWindow*` calls,
  `FCF_OpenNewWindow` for missing tabs (your Whispers tab), and
  `RemoveAllMessageGroups`/`AddMessageGroup` and `AddChannel` on the frame. The recipe is Prat
  Memory.lua:145-240.
- **Position of the main window:** `ChatFrame1` is an Edit Mode system. Its spot may already follow
  you if your Edit Mode layout is an *Account* layout rather than a *Character* one. Check that
  first. Otherwise, measure whether `SetChatWindowSavedPosition` sticks or Edit Mode overrides it.
- The glass options from M1 (opacity, font outline) live in the same account-wide table.

### M3: smart tabs (the owner's main pain: probe output)

- **As built (#25), after probe items 7-9:** ASProbe and the AltStable family write with
  `DEFAULT_CHAT_FRAME:AddMessage`, not `print`, so a print handler alone would miss the owner's
  main case. Instead, **one `AddMessage` post-hook per window** (in `Chat.lua`, shared with the
  timestamps) handles every line that has no chat event:
  - It names the writer from `debugstack`: the first frame below our own that isn't
    `Blizzard_*` plumbing. `print` reaches `AddMessage` through `Blizzard_PrintHandler`, so it is
    covered too.
  - A routed line is copied to its tab, then the newest matching copy is removed where it landed,
    with the public `RemoveMessagesByPredicate`. Its `RemoveIf` walks oldest to newest, so older
    identical lines are safe.
  - Routing runs before the timestamp, because stamping rewrites the line in the buffer.
- *Original design:* a **wrapping print handler** (probe item 7) that names the addon behind each
  `print` line from the stack. The handler passes every line on unchanged unless a rule moves it.
- **When an addon gets chatty** (e.g. 20 lines in a minute), GlassChat offers, once, in chat:
  "ASProbe printed 40 lines. [Own tab for this session] [Always] [No]". Those are clickable addon
  links, so there is no popup.
- **Session:** route for this session only. **Always:** a saved rule
  (`GlassChatDB.routes[addonFolder]`), reapplied at login. **No:** never ask again for that
  addon. `/gchat tabs` lists the rules and removes them.
- The tab is a stock chat window (`FCF_OpenNewWindow(name, true)`, no message groups), named after
  the addon. Chat tabs are **per character** (measured), so rules are account-wide and each
  character opens its own tab on that addon's first line. An existing window with that name is
  reused, so a permanent tab isn't duplicated after a relog.
- Every routed line is also kept in GlassChat's own buffer, with its source addon and time, for
  M4. *(Deferred to M4, which will need it; M3 doesn't.)*
- **Never offered:** Blizzard's own lines, GlassChat and its plugins, and lines carrying a chat
  event. A tab the player closes sends that addon's lines back to the main chat for the session,
  with one line saying so. With no room for another tab, the lines stay in the main chat.
- Limits: only `print` output can be moved (probe item 7 says how much that covers). Blizzard
  caps chat windows at 10. Lua errors go to the error frame, not chat, and are out of scope.

### M4: focus mode (freeze, maximise, search, filter, copy)

The owner's picture: freeze and maximise the current tab, which reveals search and filters.

**As built (#27):** `Focus.lua`.
- **Opening it:** `/gchat focus [text]` (the window it was typed in), or the magnifier left of
  the copy icon.
- **The view** is a frozen snapshot in a read-only EditBox, like the copy window, so what's shown
  is already copyable: **Select all**, then Ctrl+C.
- **Filters:**
  - search: plain text, any case, with matches only or with two lines of context;
  - kind chips: none selected means all;
  - **From**, which cycles through the addons in view. M3's attribution remembers who wrote
    each recent addon line (`Tabs.SourceFor`).
- **"N new lines"** refreshes the snapshot.
- **Export** writes the view to `GlassChatDB.export`.
- **Left for later, since nobody needs them yet:** double-click on a tab, click / shift-click line
  selection, the time filter, and a timestamps option. With `/gchat stamps on`, the lines carry
  their time anyway.

- **Open** it from a button on the chat frame, a double-click on a tab, or `/gchat focus [text]`.
  It opens a large glass window (most of the screen) over the chat. Blizzard's chat frame isn't
  moved or resized: Edit Mode owns it.
- **Frozen.** It shows a snapshot of that tab's lines (`GetMessageInfo`, plus GlassChat's buffer
  for addon output), so nothing scrolls away while you read. A "N new lines" bar adds them on a
  click. Secret lines show as "(hidden)" and are never matched or copied.
- **Search:** live, case-insensitive plain text over the colour-stripped line, no patterns. A
  "matches only / with context" toggle.
- **Filters:** chips by kind (Say, Party, Guild, Whisper, Channel, System), **by source addon**
  (from M3's attribution, e.g. only ASProbe), and by time (last N minutes, since `/reload`).
- **Copy:** drag-select (probe item 3), or click / shift-click lines, then Copy. The text goes to
  the clipboard (probe item 2) or into a pre-selected edit box for Ctrl+C. It's plain text, one
  line per message, with optional timestamps.
- **Export:** writes the filtered view to `GlassChatDB.export`. After a `/reload` or logout,
  Claude reads it straight from `WTF\...\SavedVariables\GlassChat.lua`.
- Esc closes it, and the chat behind it was never touched.

### M5: copy web addresses

**As built (#31):** `Url.lua`, on by default (`/gchat urls on|off`).
- Probe items 2 and 3 failed: there's no clipboard write and no drag-select copy. So a click
  opens a small glass box with the address selected, for Ctrl+C.
- **What counts as an address:** `http(s)://`, `www.`, and a bare `name.tld/path` for a short
  list of endings (`Url.TLDS`). E-mail addresses and bare IPs, which Prat's UrlCopy also takes,
  are left out.
- **Only the plain text** between game links, colour codes, textures and atlases is scanned. An
  address another addon already linked stays as it is. A sentence's full stop stays outside the
  address.

- **URLs only** (owner). A message filter wraps them in an addon link (`|Haddon:GlassChat:url:…|h`).
  A click opens a small glass box with the URL selected (Ctrl+C), or copies it directly if probe
  item 2 passes.
- Drag-select copy in the normal chat (not only in focus mode), if probe item 3 passes.
- Game links keep their stock behaviour.

### Later (only if asked)

- Scrollback kept across `/reload` (Prat Scrollback: lines in SavedVariables, secret lines
  dropped).
- Glass tabs and buttons, timestamps, shorter channel names, an options panel.

## Owner answers (2026-10-03)

1. **Search:** freeze and maximise the current tab to reveal search and filters (M4), plus smart
   tabs for chatty addons, per session or permanent (M3).
2. **Copy links:** web addresses only.
3. **What gets pasted into Claude:** probe output today. Smart tabs, plus focus mode filtered by
   source and Export, should cover it.
4. **Glass:** readability first. The chat stays visible, on a darker see-through background.

## Still open

- *(Settled in M3.)* A "session" tab isn't closed at logout: Blizzard saves chat windows, so it
  stays as an ordinary tab, but nothing routes to it in the next session. "Chatty" means 20 lines
  within 60 s (`Tabs.CHATTY`, `Tabs.WINDOW`). Blizzard's own lines are never offered.
