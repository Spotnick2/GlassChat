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
"cheap levelling", site adverts) changes its wording, but keeps the same *shape*: somewhere to
go, a price, a way to make contact, and words broken up so filters miss them.

**The rule: shape, never words.** Every signal is language-neutral data: links, digits, symbols,
scripts, the line's structure. **No English word list**, because clients are localised
(CLAUDE.md: IDs, never names) and BadBoy's lists can't be reused (its licence). A word a player
wants gone is a mute.

#### Signals

The line is split into **tokens**, runs of characters between whitespace. Leading brackets and
quotes and trailing punctuation are stripped from a token, as M5's `Url.Wrap` does. **Each token
counts toward at most one kind**, the first that matches in this order (review of #46: one
discord link must not make two kinds). Every token rule matches the **whole** token.

| Kind | A token is it when (no English) |
|---|---|
| **Address** | after mapping look-alike letters to Latin (below), either `Url.Address` matches it, or it is `name.tld[/path]`: a name of 1 or more labels of letters and digits (dashes inside only, never only dashes), and an ending from M5's list (`Url.TLDS`) **plus the endings spam favours**: `shop top vip xyz club online site store cc biz co ru`. **Not "any 2-6 letter ending"**: that took `item.level`, `GlassChat.lua` and `lol.ok` for addresses (Codex, #46). |
| **Contact** | `@name`, where the name is 2 or more letters or digits (any script), **or** `Name#1234`, where the name is 2 or more letters (any script) and is followed by exactly 4 or 5 digits. A bare `#1234`, `group #2` or `rank #1234` is not a contact. |
| **Price** | a currency symbol (`$ € £ ¥ ₽`) directly before or after 1-6 digits (`$5`, `5€`, `10$`, `$4.99`). **Not `%`**: in WoW chat it means drop rates, loot rules and progress. |

Two more kinds look at the line's **original text**, never the aggressive form, which erases what
they need (Codex):

| Kind | Seen when |
|---|---|
| **Broken-up word** | a maximal run of **5 or more fragments**, each a single letter or digit (one decoded code point), each separated by one or more characters from ` . - _ / , * ·`. `p.r.o.f.i.t` and `w w w . g o l d` count; `G G W P` (4) and `L F M` (3) don't. Tokens already counted as an address, contact or price aren't scanned. |
| **Look-alike letters** | a word with at least 2 Latin letters, where **every** non-Latin letter is in the look-alike set below **and at least one sits between two Latin letters** (`gоld`, `g0ldsіte`). A non-Latin ending on a Latin acronym, such as Russian `MCе`, `AVке` or `ZGшку`, never counts, because it isn't inside the word (Codex, #46). |

**The look-alike set (exact code points, upper and lower case):** Cyrillic а е о р с у х і ј ѕ
к м and А В Е К М Н О Р С Т Х; Greek ο ρ α ε ι κ ν τ χ and Α Β Ε Ζ Η Ι Κ Μ Ν Ο Ρ Τ Χ. Lowercase
Cyrillic т, в and н are left out: they only resemble Latin letters in some fonts (Codex).

**Decoration** (a high share of symbols such as `★ ✪ ⚡ → ▶`, or 4+ repeated punctuation marks) is
recorded and shown in watch mode, but it is **not a kind** and never decides.

#### The decision

Players advertise too. Guild recruitment, a streamer's link, an addon's page or a gold-paid carry
service all pair an **address with a contact** (Codex, #46: seven real examples). What marks
**spam** is a **real-money price**, or text **disguised** to get past filters. So:

**A line is hidden when it has one of the spam kinds, price, broken-up word or look-alike
letters, together with any other kind.** An address with a contact, however many of each, never
hides a line.

**No negative signals in r1.** Game links and "names you" were planned to count against a line,
but both are in the sender's control: two `[Linen Cloth]` links would buy any advert through.

**Accepted misses:** spam that carries a single kind (`Cheap gold, instant delivery,
goldsite.shop`; `1000 gold for $5, whisper me`). A mute, the repeat rule or an ignore covers
those. The score is for the shapes words can't name.

#### Worked examples

| Line | Kinds | Result |
|---|---|---|
| `Cheap gold $5 = 1000g at goldsite.shop` | price, address | hidden |
| `w w w . g o l d . c o m best price 10$` | broken-up, price | hidden |
| `Buy gold at gоldsite.com` (Cyrillic о) | look-alike, address (found after mapping) | hidden |
| `Buy gold, add Seller#1234, cheapest $` | contact only (a bare `$` isn't a price) | shown |
| `<Night Watch> recruiting, discord.gg/nw, @Recruiter` | address, contact (no spam kind) | shown |
| `Live at twitch.tv/example, follow @Example` | address, contact | shown |
| `Selling Mara carries 20g/run, discord.gg/carries, Runner#1234` | address, contact | shown |
| `Guide for the 5% drop: wowhead.com/guide/x !!!` | address | shown |
| `G G W P, vod twitch.tv/example` | address (4 fragments isn't broken-up) | shown |
| `Ищем хила в MCе, discord.gg/raid` | address (the Cyrillic е is an ending, not inside) | shown |
| `WTS [Thunderfury] 10$ or 500g, add me Seller#1234` | price, contact | **hidden: real money for game goods (owner, 2026-10-05: hide them).** |
| `Free addon at github.com/x, optional $5 donation` | price, address | **hidden: the known false positive; watch mode will say how often it happens.** |

#### Where it applies

- **The S1 policy is unchanged:** public chat only (channels, say, yell, emote), never you,
  friends, guild, group, Battle.net friends or the allow list.
- **The order:** ignores, mutes, CJK, **score**, repeats. The score comes before repeats, so a
  line it hides is never timed as the "last shown" post.
- **It's stateless,** a function of the line alone, so it also runs on the no-lineID path.

#### Watch first (the main safety)

- **Three states:** `/gchat spam score off | watch | hide`, **watch** by default.
  - **In watch mode** a spam-kind line is evaluated as if shown. It goes into a separate **score
    log** (the last 100) with its kinds, its decoration and its **final outcome**: shown, or
    hidden by the repeat rule that runs after it (Codex). Neither the hidden-lines log nor the
    eye icon's count is touched, unless a later rule hides the line, as it does today.
  - **Lines with no usable lineID are logged too, marked "no id",** so watch mode sees the
    traffic that would otherwise go unmeasured (Codex: probe 10 covered SAY, WHISPER,
    WHISPER_INFORM and PARTY_LEADER, not CHANNEL or EMOTE). Such a line may then appear once per
    window. Before hide mode is offered, `/cprobe lines` is run in General and Trade to measure
    CHANNEL lineIDs.
  - **In hide mode** the line is hidden with the reason `score: price + address`, like every other
    reason.
- **The score's state lives with the decision, not in it:** `Judge` still returns a reason or
  nil, so the memo's "reason or false" is unchanged. A watch-mode observation is written on the
  memo miss only, never returned as a reason, so it can never hide a line.
- **`/gchat spam score`** lists the score log, near misses (one kind) included. **`/gchat spam
  test <text>`** reports the kinds found.

#### Whispers (an open question, off by default)

Strangers' whispers carry the same spam. If they are ever scored (`/gchat spam score whispers
on`), anyone you whispered this session is exempt (`CHAT_MSG_WHISPER_INFORM`). A seller you asked
"how much?" replies with exactly the price and contact a score looks for.

#### Costs

- **Measured, so no shared context (built, #45):** `Score.Check` costs about 38 µs a line in
  desktop Lua 5.1 (a mix of plain, trade, spam and Russian lines). It runs once per line (the
  memo), only on public chat from players who aren't exempt, and only after the ignores, mutes
  and CJK let the line through. The per-line context planned here would save a few `Copy.Plain`
  calls, which isn't worth the refactor.
- **The score has its own address check:** M5's filter runs after the plugin's, by design, and
  not at all when click-to-copy is off.

#### Left for later

- other scripts as a whole (Cyrillic was BadBoy's other case; ask first);
- weights, if watch mode shows two kinds isn't enough;
- an options page.

#### For the review

1. Does "a spam kind plus any other" separate players' own advertising (address and contact)
   from spam well enough?
2. Are the grammars now complete: the token stripping, the address endings, the contact shapes,
   the fragment run and the look-alike set?
3. Is a real-money price plus a contact something to hide? **Owner: yes (2026-10-05).**

**Codex review (2026-10-05, consult):** no P1 found; six P2s, all taken. Address plus contact is
players' advertising, so a spam kind is now required. The address ending is a list, not any 2-6
letters. Contact, fragment and look-alike grammars are exact (look-alikes only inside a word, an
exact code-point set). Watch mode records the final outcome and logs lines with no lineID. The
look-alike address example is resolved by mapping before the address check. The context is
built lazily. Codex called the separate score log, off/watch/hide, watch by default, the order,
the memo contract and the shared context sound.

### Left out

- Reporting.
- CVar changes.
- Event reordering.
- Function replacement.
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
- **S2b (built):** mirroring into Blizzard's list, with reconciliation rules.
- **S3 (built):** the cross-account snapshot copy, through LibAccountSync-1.0.
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
