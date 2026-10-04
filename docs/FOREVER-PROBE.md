# ChatProbe results

Measured with `Tools/ChatProbe` on **1.60.1.70205** (2026-10-03), open world, Prat disabled from item 2 on.
The raw log is `WTF\Account\<account>\SavedVariables\ChatProbe.lua`. Item numbers match
`docs/PLAN.md`.

| # | Question | Result |
|---|---|---|
| 1 | Stock chat state | `chatClassColorOverride = "0"` (always colour by class), so `ShouldColorChatByClass` is true even though every `ChatTypeInfo[t].colorNameByClass` reads false. `MaxLines = 128` on all 10 frames, and General was full. Every `ChatFrameUtil` filter API, `CopyToClipboard`, `C_StringUtil.StripHyperlinks`, `EventRegistry` and `GetPlayerInfoByGUID` are present. `ChatFrame_MessageEventHandler` and `ChatFrame_OnHyperlinkShow` are absent. |
| 2 | `CopyToClipboard` from addon code | **Forbidden.** The game raises `ADDON_ACTION_FORBIDDEN … 'UNKNOWN()'`, blamed on ChatProbe, and the `pcall` still returns ok with nil. Nothing reaches the clipboard. |
| 3 | Drag-select copy (`SetTextCopyable`) | Chat frames are created with `enableMouse="false"` (FloatingChatFrame.xml:443), so nothing can be selected. With `ChatFrame1:EnableMouse(true)` (from `/run`), selecting works, but Blizzard's own `CopyToClipboard` call (ScrollingMessageFrame.lua:403) is **forbidden**, blamed on GlassPanel (the taint holder of that path). |
| 4 | Addon link click | **Works.** A `|Haddon:chatprobe:hello|h` click reaches `EventRegistry "SetItemRef"` with the button (`LeftButton` / `RightButton`), and a `hooksecurefunc("SetItemRef")` sees it too. No error, no tooltip. |
| 5 | Payload secrecy, filters | Open world, in and out of combat (SAY, LOOT): text, sender, lineID and GUID are **plain**, and `InChatMessagingLockdown()` is false. `GetPlayerInfoByGUID` gives the class. The message filter ran once per event (4/4), and the sender-name filter ran (6 calls). **Dungeon: pending.** |
| 6 | Scrollback reads | `GetMessageInfo` works on every frame; 0 secret lines, and `HasSecretValues` is false. **`/reload` empties chat history** (General dropped from 128 to 21 lines). |
| 7 | Who writes to chat | **Attribution works** (after two parser fixes: a frame line names its file twice, `[Interface/AddOns/X/f.lua]:12: in function <Interface/AddOns/X/f.lua:10>`, and `debugstack(2, …)` still lists the caller, so our own frames come first, two deep). **ASProbe doesn't use `print`:** 197 lines came from `DEFAULT_CHAT_FRAME:AddMessage` (`AltStableProbe/Probe.lua:40`), and the whole AltStable family does the same. A print handler alone misses the owner's main case. |
| 8 | Route print output to a tab | **Works.** `FCF_OpenNewWindow("Probe", true)` opened ChatFrame5 with 0 message groups, and the print handler's lines landed there with no blocked action. **Chat tabs are per character:** after switching characters there was no Probe tab. Whether it survives a relog on the *same* character: *pending*. |
| 9 | Move direct `AddMessage` lines | **Works:** 197/197 AltStableProbe lines were moved and removed, with no error or blocked action. A post-hook copies the line to the tab, then removes one copy from the frame it landed in with the public `RemoveMessagesByPredicate` (ScrollingMessageFrame.lua:45). |

## Consequences for the plan

- **Copy goes through a pre-selected edit box + Ctrl+C**, always (Prat's way). Direct clipboard and
  native drag-select are both closed to addons.
- **Class colours:** the client already colours names by class. M1 only has to keep the CVar at
  `"0"`.
- **Smart tabs** must handle direct `AddMessage` too (item 7), and item 9 tests the move. They use `FCF_OpenNewWindow`, plus `setprinthandler` for `print` lines. Tabs are per character, so an "Always" rule is saved account-wide (`GlassChatDB.routes`), and each character opens (or finds, by name) its own tab the first time that addon prints.
- **Keeping lines across `/reload`** matters more than the plan assumed, because a reload is
  exactly when the owner wants the probe output back.

Addon-agnostic findings are also in the porting guide, under "Chat frames: copy, links, filters
and addon output".

Still open: payload secrecy inside a dungeon (item 5), and whether a tab survives a relog on the
character that made it (item 8; its `chat-cache.txt` lists `WINDOW 5 / NAME Probe`).

## Spam & Ignore S0 (items 10-12, 2026-10-03)

| # | Question | Result |
|---|---|---|
| 10 | Line identity per chat type | **Usable.** SAY, WHISPER, WHISPER_INFORM and PARTY_LEADER, with chat shown in two tabs: every line had a plain positive lineID and a `Player-` GUID, and each reached a filter **exactly twice** (once per window). No lineID was reused for a different text. One decision per (event, lineID) is sound. The probe's trace now survives a `/reload` (the first two runs were lost that way). Channel and emote events weren't covered in this run. |
| 11 | Sender names | arg2 is **"First Surname" (2 words, no realm dash)** for SAY, WHISPER, WHISPER_INFORM and PARTY_LEADER (same realm). |
| 11 | Server ignore with surnames | **Works with "First Surname".** On the target, `UnitName` = "Zoruka" / "Mortalis", `GetUnitName("target", true)` = **"Zoruka Mortalis"**, and `RegionalUniqueNamesEnabled()` = true. `AddIgnore("Zoruka Mortalis")` returned true, `GetIgnoreName` read back the exact "Zoruka Mortalis", `IsIgnoredByGuid` was true, and `DelIgnore` removed it. `IGNORELIST_UPDATE` fired on each change, twice per change. |
| 12 | Ignore-list readiness | `GetNumIgnores()` answered **nil at `ADDON_LOADED`** on 3 of 6 loads, and 0 from `PLAYER_LOGIN` on. **Never read the list before `PLAYER_LOGIN`.** |
| 12 | What the server ignore blocks | The ignorer, Karuzo Elegia, ignored the alt (Zoruka Mortalis, on another account).<br>**Whispers: blocked.** The alt gets `CHAT_MSG_IGNORED` ("... is ignoring you"). The first probe logged that event's text instead of its sender (arg2), so its name format is unmeasured (fixed after Codex's review of #16).<br>**Invites: never reach the ignorer.** The alt sent two invites, the ignorer's probe logged no `PARTY_INVITE_REQUEST` after the ignore, and no group formed (owner). The alt's "Looting set to..." lines were its own pending party.<br>**Duels: blocked** (owner, same layer: no duel arrives, and grouping doesn't work either).<br>**Say: not seen** (owner, same layer as the duel test).<br>Before the ignore, invites and a duel did arrive. `PARTY_INVITE_REQUEST`'s name is "First Surname" (2 words), but **`DUEL_REQUESTED`'s is one word with a dash**, so never match by name there. So the server ignore blocks whispers, say, invites and duels, the last two being what a chat filter can't, which makes S2b (mirroring) worth building later. |
| 13 | Atlases for the chat-menu bubble and the friends button (#7) | *Pending.* `/cprobe atlases` asks the client which candidate frameless symbols exist (`chatframe-button-icon-*`, `socialqueuing-icon-group`, `groupfinder-icon-friend`, ...) and shows each one found, numbered, in gold, to choose from by eye. |
