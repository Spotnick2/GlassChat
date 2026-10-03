# GlassChat plan

Status: **draft, milestone 0**. The owner hasn't approved it yet. The open questions are at the
end. Probe items are numbered as in `Tools/ChatProbe` (`/cprobe help`).

## What the owner wants

1. Class colours on player names.
2. Click a link to copy it (and paste it elsewhere).
3. Copy **any** text out of chat.
4. **Search and filter**, mainly for the long probe and addon output that gets pasted into Claude
   sessions. The shape isn't decided yet; a popup window is the leading idea.
5. The look: the liquid glass of the `Glass*` addons.

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

Run with `pwsh Tools\deploy.ps1 -Probe` and a client restart. Then run `/cprobe` items 1-6 and
quit the client fully. The log is at `WTF\Account\<account>\SavedVariables\ChatProbe.lua`.
Results go in `docs/FOREVER-PROBE.md`; addon-agnostic findings also go in the porting guide.

### M1: class colours and the glass skin

- Class colours. The likely implementation is turning on Blizzard's own per-type
  `colorNameByClass` (or the override CVar) at login, after probe item 1 shows what's off. Only
  if that falls short, a sender-name filter colouring by GUID through `API.ClassColor`. Names
  **inside** message text (Prat's PlayerNameGlobalPatterns) are out.
- Glass on the chat background, tabs and edit box (`Glass.lua`), insecure, through
  `hooksecurefunc` on the `FCF_*` functions that rebuild them.
- A longer scrollback: `SetMaxLines` (e.g. 1000; Prat's default is 384).

### M2: copy

- **Any text:** native drag-select (`SetTextCopyable`) if probe item 3 passes.
  - Fallback: a clickable timestamp per line (an addon link) that opens the copy popup with that
    line.
- **URLs:** a message filter wraps them in an addon link. A click opens a small glass box with the
  URL selected (Ctrl+C), or copies it directly if probe item 2 passes.
- **Game links** (item, spell, quest, player): a modifier-click (default Alt) copies the link's
  plain text (`C_StringUtil.StripHyperlinks`), seen through `ChatFrame.OnHyperlinkClick`.
  Shift-click keeps its stock meaning: insert into the edit box.

### M3: the search and copy window

One glass popup (`/gchat find [text]`, plus a button on the chat frame):

- **The source** is the scrollback of every chat frame (`GetMessageInfo`), oldest to newest.
  Secret lines show as "(hidden)" and are never matched or copied.
- **Search:** live, case-insensitive plain text over the colour-stripped line, no patterns. An
  "only matching / show context" toggle.
- **Filters:** one chip per kind (Say/Party/Guild/Whisper/Channel/System, "Addon output" for
  lines without a chat event, which is where probe and error output land). Also a time range: last
  N minutes, or since `/reload`.
- **Copy:** click a line to select it, shift-click for a range, then "Copy". The selection goes to
  the clipboard (probe item 2), or else into a read-only, pre-selected edit box for Ctrl+C. Plain
  text, one line per message, optionally with timestamps.
- **For the Claude workflow:** an **"Export"** button that writes the current filtered view to
  `GlassChatDB.export` (SavedVariables). After a `/reload` or logout, Claude reads it straight
  from `WTF\...\SavedVariables\GlassChat.lua`, with no copy-paste at all.

### Later (only if asked)

- Scrollback kept across `/reload` (Prat Scrollback: lines in SavedVariables, secret lines
  dropped).
- Timestamps, shorter channel names, an options panel.

## Open questions for the owner

1. **Search window:** is the popup above right? The alternative is a filter bar that filters the
   chat frame in place.
2. **"Click links to copy":** do you mean URLs (left-click → copy box), or every game link too (a
   modifier-click)? Which modifier?
3. **What do you paste into Claude most?** Your own addons' `print` output, Lua errors, or chat
   from people? This sets the default filter chips, and whether "Export to SavedVariables" should
   be the main button.
4. **Glass scope:** just the chat background and edit box, or tabs and buttons too?
