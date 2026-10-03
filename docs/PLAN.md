# GlassChat plan

Status: **draft, milestone 0**, revised with the owner's answers (end of file); not yet approved.
Probe items are numbered as in `Tools/ChatProbe` (`/cprobe help`).

## What the owner wants

1. Class colours on player names.
2. Click a web address to copy it.
3. Copy **any** text out of chat.
4. **Search and filter**, mainly for the long probe and addon output that gets pasted into Claude
   sessions: smart tabs (M2) and focus mode (M3).
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

### M2: smart tabs (the owner's main pain: probe output)

- GlassChat installs a **wrapping print handler** (probe item 7) that names the addon behind each
  `print` line from the stack. The handler passes every line on unchanged unless a rule moves it.
- **When an addon gets chatty** (e.g. 20 lines in a minute), GlassChat offers, once, in chat:
  "ASProbe printed 40 lines. [Own tab for this session] [Always] [No]". Those are clickable addon
  links, so there is no popup.
- **Session:** route for this session only. **Always:** a saved rule
  (`GlassChatDB.routes[addonFolder]`), reapplied at login. **No:** never ask again for that
  addon. `/gchat tabs` lists the rules and removes them.
- The tab is a stock chat window (`FCF_OpenNewWindow(name, true)`, no message groups), named after
  the addon. An existing window with that name is reused, so a permanent tab isn't duplicated
  after a relog.
- Every routed line is also kept in GlassChat's own buffer, with its source addon and time, for
  M3.
- Limits: only `print` output can be moved (probe item 7 says how much that covers). Blizzard
  caps chat windows at 10. Lua errors go to the error frame, not chat, and are out of scope.

### M3: focus mode (freeze, maximise, search, filter, copy)

The owner's picture: freeze and maximise the current tab, which reveals search and filters.

- **Open** it from a button on the chat frame, a double-click on a tab, or `/gchat focus [text]`.
  It opens a large glass window (most of the screen) over the chat. Blizzard's chat frame isn't
  moved or resized: Edit Mode owns it.
- **Frozen.** It shows a snapshot of that tab's lines (`GetMessageInfo`, plus GlassChat's buffer
  for addon output), so nothing scrolls away while you read. A "N new lines" bar adds them on a
  click. Secret lines show as "(hidden)" and are never matched or copied.
- **Search:** live, case-insensitive plain text over the colour-stripped line, no patterns. A
  "matches only / with context" toggle.
- **Filters:** chips by kind (Say, Party, Guild, Whisper, Channel, System), **by source addon**
  (from M2's attribution, e.g. only ASProbe), and by time (last N minutes, since `/reload`).
- **Copy:** drag-select (probe item 3), or click / shift-click lines, then Copy. The text goes to
  the clipboard (probe item 2) or into a pre-selected edit box for Ctrl+C. It's plain text, one
  line per message, with optional timestamps.
- **Export:** writes the filtered view to `GlassChatDB.export`. After a `/reload` or logout,
  Claude reads it straight from `WTF\...\SavedVariables\GlassChat.lua`.
- Esc closes it, and the chat behind it was never touched.

### M4: copy web addresses

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

1. **Search:** freeze and maximise the current tab to reveal search and filters (M3), plus smart
   tabs for chatty addons, per session or permanent (M2).
2. **Copy links:** web addresses only.
3. **What gets pasted into Claude:** probe output today. Smart tabs, plus focus mode filtered by
   source and Export, should cover it.
4. **Glass:** readability first. The chat stays visible, on a darker see-through background.

## Still open

- Smart tabs, "session": should the tab close at logout? It's simplest to leave it, because
  Blizzard saves chat windows. Closing it means calling `FCF_Close` at logout.
- The threshold for "chatty" (lines per minute), and whether Blizzard's own system spam (loot,
  XP) should ever be offered a tab.
