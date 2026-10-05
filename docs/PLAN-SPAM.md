# Plan: GlassChat Spam & Ignore (plugin)

Status: **revised after Codex's adversarial review** (2026-10-03). It found no P1 and eight P2s,
all taken; see "Review" at the end. Nothing is built yet.

Sources:
- `C:\Projects\References\BadBoy-v12.0.3` and `GlobalIgnoreList_12.0.0` (GIL);
- AltStable's and GlassPanel's plugin patterns;
- Forever's FrameXML and the 70205 API dump.

## What the owner wants

1. **Muted words** that hide any line containing them, like GIL's word filters. The owner's TBC
   Anniversary example: everyone selling "profession kits".
2. **Repeat posting:** the same person posting the same thing 5 times in a row, or a minute apart,
   is "the most annoying". Gold sellers are rare on the Forever beta so far.
3. **One ignore list everywhere:**
   - ideally Blizzard's own list, synced on every character and every account;
   - failing that, their chat and whispers;
   - **between accounts**, like AltStable's Battle.net sync.
4. **Hidden lines can be seen:** an eye icon or similar.
5. **CJK posts hidden, on by default** (owner, 2026-10-03). BadBoy did this: Chinese, Japanese
   and Korean posts are of no use to most NA players, and the CJK font fallback disturbs the chat.

## What the references teach (and why neither is lifted)

- **Licences.** BadBoy is "All Rights Reserved" (its TOC's `X-License`). GIL ships no licence, so
  it is all rights reserved by default. **Neither is GPL-compatible**, so we take ideas only: no
  code and no pattern lists.
- **BadBoy's good ideas:**
  - normalise before matching (strip links, lowercase, map homoglyphs, drop symbols);
  - weighted scoring with negative "legit" signals;
  - a repeat ring keyed by (GUID, text);
  - skip friends, guild, group and GM.
- **BadBoy's bad ideas:**
  - it unregisters and re-registers every chat frame's events so it runs first (a taint risk);
  - it toggles the `chatBubbles` and `spamFilter` CVars;
  - ~300 unordered `gsub` passes per line;
  - dated lists;
  - reporting is disabled in 12.0.3, and `C_ReportSystem.SendReport` is `HasRestrictions` here.
- **GIL's good ideas:**
  - an account-wide list enforced by **its own chat filter**, so it isn't limited by the server
    cap;
  - user word filters;
  - a flood filter;
  - one decision per `lineID`;
  - a block history.
- **GIL's bad ideas:**
  - It **replaces** `C_FriendList.AddIgnore`, `DelIgnore`, `AddOrDelIgnore`, `DelIgnoreByIndex`
    and `C_PartyInfo.InviteUnit`.
  - **It breaks Forever names:**
    - `M.Proper` strips spaces, so "First Surname" becomes "Firstsurname";
    - `AddIgnore` then fails, and after 3 tries the entry is **deleted**;
    - names are its only key.
  - Its fragile login sync.
  - It auto-whispers ignored players.

## Forever facts this depends on

**Measured:**
- Message filters run for every CHAT_MSG event, in and out of combat (open world).
- Payloads were plain there.
- Addon links reach `EventRegistry "SetItemRef"`.
- Names carry surnames.
- `UnitName` / `GetPlayerInfoByGUID` give the first name only.

**Declared:**
- Filters get arg1-14, with **lineID = arg11** and **GUID = arg12** (ChatFrameOverrides.lua:312,
  546, 608). AFK, DND and TEXT_EMOTE use the same slots (ChatInfoDocumentation.lua:837, 1538,
  2508).
- A filter is skipped silently when `canaccessvalue(...)` fails (ChatFrameFilters.lua:112-160).
- Filters run **before** Blizzard's channel and window routing (ChatFrameOverrides.lua:312-363).
- GM whispers return before filters (line 307).
- `C_FriendList` has `AddIgnore`, `DelIgnore`, `GetIgnoreName` (nullable), `GetNumIgnores`,
  `IsIgnored`, `IsIgnoredByGuid` and `IsOnIgnoredList`.
- The events `IGNORELIST_UPDATE` (no payload) and `CHAT_MSG_IGNORED` exist.
- `RegionalUniqueNamesEnabled()` exists.

**Unmeasured, so probe first (S0):**
- **10. Line identity:** is lineID a plain positive number, unique per line, for every selected
  event? Is it the same in every window that shows the line? Is GUID always `Player-...`?
- **11. Names:** the sender (arg2) format of each chat type ("First Surname", with or without a
  realm suffix). Whether `AddIgnore("First Surname")` adds the right person, and what
  `GetIgnoreName` reads back.
- **12. The server ignore:** its cap, its readiness after login, and what it blocks on Forever
  (whispers, channels, say, invites, duels).

## Design

### Package

A GlassPanel-style plugin addon:
- `Plugins\SpamIgnore\GlassChatSpamIgnore.toc`;
- `## Dependencies: GlassChat`, `## Group: GlassChat`;
- `## SavedVariables: GlassChatSpamIgnoreDB` (per WoW account), and
  `## SavedVariablesPerCharacter: GlassChatSpamIgnoreCharDB` (per character: what was imported);
- **not** LoadOnDemand;
- a `.pkgmeta` `move-folders` line, deployed under the TOC's name, and the TOC test ported.

The core exposes what the plugin uses through `GC.API` (CLAUDE.md: client APIs go through it):
- `IsSecret`, `Fail`, `RegisterEvents`;
- the dialog helpers;
- `GC.RegisterSlash(sub, fn)` under `/gchat`;
- a way to put an icon in the tab strip (`Skin.Panel`, beside the copy icon).

### One filter, two policies

- **Explicit ignores** apply to every player-chat event: CHANNEL, SAY, YELL, EMOTE, TEXT_EMOTE,
  WHISPER, DND, AFK, GUILD, OFFICER, PARTY*, RAID*, INSTANCE*.
  - **An ignored player stays ignored if they join your group or guild.**
  - The allow list doesn't override an ignore; `/gchat unignore` does.
- **Heuristics** (muted words, repeats, a later score) apply only to **public** chat: CHANNEL,
  SAY, YELL, EMOTE. They never apply to WHISPER, TEXT_EMOTE (its text holds the actor's name),
  AFK/DND (status replies), group, guild or instance chat.
  - These players are exempt from heuristics: you, friends, guild members, Battle.net friends,
    group members, and the allow list.
- **Never filtered:** WHISPER_INFORM (your own echo); GM whispers.
- **Guards**, in order:
  1. Every value consumed or stored (text, sender, GUID, lineID, and every lookup result) is
     checked with `IsSecret` before any other use. A secret passes the line through.
  2. A GUID that isn't a plain string starting `Player-` passes.
  3. **The memo:** one decision per (event, lineID), last ~200, `false` cached too.
     - It is used only when lineID is a plain positive number.
     - Without one, only the stateless checks run (ignore, mutes), never the repeat state or the
       counters.
- **Decision order:** ignore, then muted words, then repeats. The reason is kept.

### Muted words (the owner's main ask)

- `/gchat mute profession kit`, `/gchat unmute ...`, `/gchat mutes`.
- **The default is a case-insensitive literal phrase**, with separators preserved.
  - "profession kit" matches "Profession Kit", "profession kits" and "PROFESSION KIT!".
  - A short phrase matches only at word edges (ASCII letters and digits around it), so a mute
    "kit" doesn't hide "kite".
  - It's searched with `string.find(text, phrase, 1, true)`, never as a Lua pattern.
- **Aggressive matching is opt-in per mute** (`/gchat mute ~profession kit`).
  - It decodes UTF-8, maps homoglyphs (Cyrillic, Greek, full-width) and drops separators, so
    "p r 0 f e s s i o n" matches too.
  - Digits aren't rewritten ("10" never becomes "io"), and runs aren't collapsed.
  - Unmapped characters are kept.
- A mute whose matching form is empty is refused. Rule forms are precomputed.

### Repeats (the "same thing 5 times" case)

- Public chat only.
- Keyed by (event, GUID, conservative text):
  - lowercase, with spaces collapsed;
  - numbers kept;
  - links reduced to their text **plus their link data**, so two different items aren't one.
- Expiring keys (default **5 minutes**, `/gchat spam repeat 5m`), with a hard cap of 500 keys
  (oldest dropped). "A minute apart" is covered.
- **Timed from the last shown post:**
  - the first post is shown, and repeats inside the window are hidden;
  - the first post after the window is shown and restarts it.
  - So a sender gets one post per window and is never hidden forever.
- Session memory only.

### CJK posts (on by default)

- **Public chat only**, like every heuristic: CHANNEL, SAY, YELL, EMOTE. Never guild, group,
  instance or whispers, so a guildmate or a friend writing in Chinese is unaffected. The usual
  heuristic exemptions apply (friends, guild, group, the allow list).
- **Detection is on the UTF-8 bytes**, with no font or locale involved. It counts code points in:
  - CJK ideographs (U+4E00-U+9FFF; lead bytes E4-E9);
  - CJK extension A (U+3400-U+4DBF);
  - kana (U+3040-U+30FF);
  - Hangul syllables (U+AC00-U+D7AF);
  - CJK punctuation (U+3000-U+303F);
  - full-width forms (U+FF00-U+FFEF).
- **A line goes when** it holds at least **3** such characters **and** they are at least a third of
  the non-space characters. So one stray symbol, or a name with a CJK character inside an English
  sentence, never hides a line.
- The text is decoded deliberately (Lua 5.1 patterns are bytes). Malformed UTF-8 counts as nothing.
- Hidden lines go to the eye log with the reason `cjk`. `/gchat spam cjk off` turns it off.

### Seeing what was hidden (owner: "an eye icon"; built in S1 as below)

**As built (owner's later choices):**
- The tab-strip icon is **opt-in**: `/gchat spam icon on`, off by default.
- Until the official release, a dev build's icon is a **bug**, and its window lists each blocked
  line with its event. That replaces a "Debug" chat tab, which the owner considered and dropped
  for the window. A release shows an eye.
- `/gchat spam log` opens the window either way.

**The original design:**

- An **eye icon in the tab strip**, beside the copy icon, drawn the same way. It shows a count of
  lines hidden since you last looked, in gold when that's above 0.
- **No line is printed into chat.** Filters run before Blizzard decides which window shows a line,
  so a per-window notice could land in the wrong tab.
- Clicking it opens the **hidden-lines log** in the copy window, as plain text you can select and
  copy: the last 200 lines, with time, sender, reason and rule.
- Actions are slash commands, not links in that plain-text box:
  - `/gchat allow <name>`;
  - `/gchat unmute ...`;
  - `/gchat unignore <name>`.
- The log is session memory.

### Account-wide ignore

**Ours, by GUID, enforced by the filter only:**

```
GlassChatSpamIgnoreDB.ignore[guid] = { name = "First Surname", added = time(), note = "...", expires = <time or nil> }
```

- The name comes from chat's own sender (arg2), stored only as display text.
- **Unlimited, on every character of the WoW account at once**, for chat and whispers.
- Fields are type- and length-checked on load. Saved fields are never secrets, never packed chat
  arguments.

**Never your own characters** (owner: "make sure you don't ignore the character itself when
syncing"):
- **The current character is never ignored**, by GUID, in the filter and in any mirror. The S2b
  mirror never calls `AddIgnore` with its own name.
- **GlassChat knows your own characters.** Each character records its GUID and "First Surname" at
  `PLAYER_LOGIN` in `GlassChatSpamIgnoreDB.own`.
  - Ignoring one of them is refused, with a message saying it's yours.
  - The S3 snapshot carries this list, so characters on your other WoW accounts count as yours too.
- **An entry that turns out to be one of yours** (ignored before that character was ever seen) is
  skipped by the filter and the mirror, and flagged in `/gchat ignores` for you to remove.

**Getting entries in:**
- `/gchat ignore <name>` resolves the GUID from a name→GUID map learned from recent chat (session
  memory, capped).
- **Explicit import** of the character's Blizzard list: `/gchat ignore import`.
  - An entry whose GUID isn't known yet stays visibly **pending**, by name.
  - It's never claimed to work account-wide until resolved.
  - A server-ignored player's chat may never arrive to resolve it.

**Blizzard's server list is not written to (S1).** The review showed why a login mirror is unsafe:
- `IGNORELIST_UPDATE` carries no author;
- a removal made through Blizzard's UI (`DelIgnoreByIndex`, Camelot FriendsFrame.lua:1195) would
  be undone at the next login;
- an old entry on another character would come back;
- readiness at login isn't guaranteed (`GetIgnoreName` is nullable).

**Mirroring (S2b), built** because probe 12 showed the server ignore blocks invites and duels,
which a chat filter can't. `Plugins/SpamIgnore/Mirror.lua`, on by default
(`/gchat ignore mirror on|off`):
- **Linked names.** Names GlassChat itself added to this character's Blizzard list, kept per
  character in `GlassChatSpamIgnoreCharDB.linked`. A sync only ever removes linked names. A name
  that was already on Blizzard's list is the player's own, and is left alone even when it's on
  the account list too (review of #24). The one exception is explicit: `/gchat unignore` on this
  character also takes the name off this character's list.
- **A linked name that leaves Blizzard's list** (removed in Blizzard's UI) **counts as an
  unignore** on every character, and is never added back.
- **A linked name no longer on the account list** (`/gchat unignore`, on any character) is
  removed from this character's list at its next check.
- **A read must be trusted before anything changes** (review of #24: one bad read must never
  unignore the whole list). That means:
  - the list is ready: after an `IGNORELIST_UPDATE` this session, or 20 s after login;
  - every entry from 1 to `GetNumIgnores()` reads as a plain name;
  - an empty list with names linked is trusted only once the list is settled: an update 20 s or
    more after login, or one GlassChat's own write caused. Before that, GlassChat asks for the
    list (`ShowFriends`) and waits;
  - no more than 3 linked names vanish at once (with a warning).
  A distrusted read changes nothing.
- **Writes are throttled** (one per 0.5 s), with one in flight per name, and **checked**: an add
  or a removal counts only once the list shows it. Each attempt is a try, and after 3 tries
  (counted across logins) it's reported in `/gchat ignores` and not retried. A failed add is
  never taken to mean the name is invalid: the player stays ignored in chat. A failed removal
  stays linked. Writes in flight are saved per character, so a reload between an add and its
  check still knows the name is GlassChat's. Turning the mirror off stops the queue.
- **Never your own characters, nor this one**, whether by GUID or by name.
- Blizzard's own lines about GlassChat's writes are hidden for 3 s after each write. These are
  the exact `ERR_IGNORE_*` lines where those strings exist, and lines naming the player
  otherwise. One summary line replaces them.
- **Unmeasured, for the in-game check:**
  - whether `IGNORELIST_UPDATE` fires at login with a non-empty list (the 20 s delay covers it
    if not);
  - the wording of Blizzard's add and remove lines (the name match covers any wording);
  - the list's size limit (a refused add is a bounded try).

### Between WoW accounts (S3)

**Status (#33):**
- **Built:** your characters on other WoW accounts count as your own when AltStable is
  installed. `AltStable.GetCharacters()` (public API v1) lists every character it has synced, by
  GUID and full name. GlassChat reads it at login and on AltStable's `CharactersChanged` callback,
  never per chat line, and only for API version 1. Those characters are never ignored, muted,
  repeat-hidden or added to Blizzard's list.
- **Built (#33, LibAccountSync `r2`; the owner's two-account in-game check passed):**
  `/gchat ignore send`, `Plugins/SpamIgnore/Sync.lua`. Its rules are in CLAUDE.md.
- **The library:** the snapshot copy below goes through **LibAccountSync-1.0**
  (Spotnick2/LibAccountSync), a new embedded library seeded from AltStable's own-account channel.
  GlassChat is its pilot consumer. The owner turned down an AltStable API (AltStable#190, closed)
  because the code is shared, and an embedded library both addons can use is the way to share it
  (`C:\Projects\References\EMBEDDED-LIBRARIES.md`). The plan starts in Spotnick2/LibAccountSync#1.

**The design:**

- `GlassChatSpamIgnoreDB` is per WoW account, so another WoW account on the same Battle.net sees
  none of it.
- **Explicit snapshot copy:**
  - `/gchat ignore send`: this account's full ignore and mute lists, versioned, go to your other
    online accounts;
  - the receiver applies the whole snapshot, removals included. No multi-writer merge, so no
    tombstones or clock skew.
- **Transport: LibAccountSync-1.0**, embedded in GlassChat. It is AltStable's own-account channel
  (authenticated, 255-byte chunks, copes with peers going offline: its SYNC-DISCOVERY.md) made
  into a library, so it works without AltStable installed.

### A spam score (S4, plan: to be reviewed before any code)

**The problem.** Mutes catch the phrases you've already seen. Commercial spam (gold, boosts,
"cheap levelling", site adverts) changes its wording, but keeps the same *shape*: an address to
go to, a price, a way to make contact, and words broken up so filters miss them.

**The rule: shape, never words.** Every signal is language-neutral data: links, digits,
symbols, scripts, the line's structure. **No English word list**, because clients are localised
(CLAUDE.md: IDs, never names) and BadBoy's lists can't be reused (its licence). A word a player
wants gone is a mute.

**Signals** (each counted once per line; weights to be tuned against real lines, see Observe
first):

| Signal | How it's seen (no English) | Weight |
|---|---|---|
| A web address | `Url.Address` on any word (M5's matcher) | +2 |
| A price | a currency symbol (`$ € £ ¥ ₽`), or digits with `%` | +2 |
| A contact handle | `@name`, `name#1234` (a tag shape), or an address of a chat service by its shape | +1 |
| A broken-up word | the aggressive form (`Text.Aggressive`) holds a run of 6+ letters the visible text splits with separators (`p.r.o.f.i.t`) | +2 |
| Mixed scripts in one word | Latin with Cyrillic, Greek or full-width letters inside one word (homoglyph bait) | +3 |
| Decoration | a high share of symbols (`★ ✪ ⚡ → ▶` and others), or long repeated punctuation | +1 |
| **Game links** | `|Hitem`, `|Hachievement`, `|Hquest`, `|Hspell`: a real trade or LFG post | **-2 each, up to -4** |
| **Talking to you** | a line that names you (`UnitName("player")`'s first name) | **-3** |

**The decision.** A line is hidden only when **both** hold:
- the score reaches the threshold (start: **5**);
- at least **two different kinds** of commercial signal are present: address, price, contact,
  broken-up word, mixed scripts.

So a guide link alone (+2), a price alone, or a link plus decoration never hides a line.
"WTS [Thunderfury] 500g" can't reach the threshold, because the item link pulls it down.

**Where it applies:** the S1 policy is unchanged. It runs on public chat only (channels, say,
yell, emote), never for you, friends, guild, group, Battle.net friends or the allow list. It
runs after ignores, mutes, CJK and repeats, so it only judges what those let through.
- **Open question:** whispers from strangers carry the same spam. Should the score apply there
  too, off by default (`/gchat spam score whispers on`)?

**Observe first (the main safety):**
- The score ships **watching, not hiding**. A line that would be hidden is logged (`would hide,
  score 6: address + price + broken-up`) and **shown**.
- `/gchat spam score` lists the last lines that scored high, with their signals, so the owner can
  check the weights against real Forever spam before anything is hidden.
- `/gchat spam score on` turns hiding on, and `/gchat spam score threshold <n>` changes the
  threshold. A hidden line goes to the log with its score and signals, like every other reason.

**Costs:** one pass over the visible text, the aggressive form (computed only when a cheap check
shows separators or non-ASCII letters), and the link scan M5 already does. It runs once per
(event, lineID), through S1's memo.

**Left for later:** other scripts as a whole (Cyrillic was BadBoy's other case; ask first),
learning from what the player hides, and an options page.

**For the review:**
1. Are the signals language-neutral enough?
2. Can a real trade, LFG or guild-recruitment post reach the threshold?
3. Is "two kinds" plus the threshold strict enough, given that one false positive hides a real
   player?
4. Is observe-first enough as the safety, or should hiding stay off until the owner turns it on
   permanently?

### Left out

- Reporting.
- CVar changes.
- Event reordering.
- Function replacement.
- Mirroring into the server list (S2b only if measured worthwhile).
- GIL's filter language, NPC and server ignores, and faction or realm options.
- The rotating-bot detector.
- Per-mute channel restrictions (they would need stable channel IDs, not English names).
- Political filters.
- Learning.

## Milestones

- **S0 (probe):** ChatProbe items 10-12.
- **S1:**
  - the plugin scaffold;
  - the filter path (guards, memo, the two policies);
  - literal muted words (plus opt-in aggressive);
  - public-chat repeats;
  - the CJK filter (on by default);
  - the eye icon and the hidden-lines log;
  - the GUID ignore list, filter-enforced, with `/gchat ignore|unignore|ignores` and explicit
    import.
- **S2b (only if probe 12 makes it worth it):** mirroring into Blizzard's list, with
  reconciliation rules.
- **S3:** cross-account snapshot copy through an AltStable API (an AltStable issue first).
- **S4:** the spam score, see "A spam score" above. It is planned there and reviewed before any
  code. It ships watching first, then hides on the owner's say. Other scripts and an options page
  wait until asked.

## Review (Codex, 2026-10-03)

No P1. Every P2 was taken:

1. A login mirror reverses removals made through Blizzard's UI and resurrects stale entries.
   **Ignore is filter-only, with explicit import; mirroring is S2b.**
2. Exemptions placed before the ignore check let an ignored player through group or guild chat.
   **Explicit ignores now apply to all player chat; exemptions are for heuristics only.**
3. Per-window eye lines could land in the wrong tab, because filters run before routing. **Now
   one eye icon and a log.**
4. Lossy normalisation causes false positives ("kit" in "kite", "gold" in "Goldshire", empty
   rules). **Literal phrases by default; aggressive matching is opt-in; empty rules are refused.**
5. Repeats crossed contexts, and a 100-line ring can't hold 5 minutes. **Public chat only,
   expiring keys with a cap, timed from the last shown post.**
6. "Additive, last writer wins" lacks deletions and catch-up. **An explicit snapshot copy
   instead.**
7. The memo has no fallback for an unusable lineID. **The stateful checks are skipped then.**
8. Underspecified UI and boundary. **S1 is trimmed; actions are slash commands; the API boundary
   goes through `GC.API`; `SavedVariablesPerCharacter` is declared.**

Codex also confirmed what's fine as designed:
- the modern filter entry point;
- the arg11/arg12 indices;
- excluding the outgoing whisper echo;
- GUID identity;
- showing the first repeat;
- the measured addon-link mechanism;
- a bounded log;
- no function replacement, CVar changes or reporting;
- respecting the licences;
- reusing AltStable instead of building another discovery system.
