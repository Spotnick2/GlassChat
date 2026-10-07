# Settings sync: your settings on your other WoW accounts (#52)

**Status: plan, revised after Codex's review (2026-10-06, below).** It waits on
Spotnick2/LibAccountSync#17 for independent streams; a stopgap covers the meantime.

## What the owner wants

- Owner: "how do we activate the timestamps on my 2nd account? I thought those settings were
  syncing." Settings are saved per WoW account (one `SavedVariables\GlassChat.lua` per account
  folder), so a second WoW account keeps the defaults.
- **"I would use the battlenet sync since we have the lib for it":** the same link as
  `/gchat ignore send` (LibAccountSync-1.0, #33 and #40).
- Decided by the owner (2026-10-06):
  1. **It may require the Spam & Ignore plugin**, which holds the household key's store
     (`GlassChatSpamIgnoreSyncDB`, #40). There's no separate key addon.
  2. **The chat layout goes too, as an option:** `/gchat settings send layout`.
  3. **Separate from the lists:** `/gchat settings send` never copies ignores or mutes, and
     `/gchat ignore send` never copies settings. One exception is spelled out under `mirror`.

## Commands

- **`/gchat settings send`** copies this account's settings to your other accounts online.
- **`/gchat settings send layout`** sends the settings plus the saved chat layout
  (`/gchat layout save`). With no layout saved, it says so and sends the settings alone.
- **`/gchat settings undo`** puts back the settings, and the saved layout, that the last copy
  replaced. What a setter already deleted isn't restored (see Undo).
- **Sending is manual, like the lists.** Nothing sends on its own, and receiving never sends
  anything back, so two accounts can't loop.
- **The send reports results the way `/gchat ignore send` does,** sharing its helpers:
  - results that arrive while `Send` is still running wait until the summary has printed;
  - zero accounts can mean they're still connecting;
  - "sent" means handed to Battle.net, with no delivery receipt.
- **Status and the switch stay `/gchat ignore sync [status|on|off]`.** It's the one switch for
  the account link, and it turns off sending *and* receiving of both settings and lists. Its help
  says so, and the settings messages point to it. The switch itself is never copied.
- **When a send can't go,** the message names the real cause: no plugin loaded ("settings sync
  needs the Spam & Ignore plugin; it holds the account link"), the link turned off, Battle.net
  not ready, or no account online. Only a missing plugin is reported as a missing plugin.

## What's sent

**A small registry.** `GC.SettingsSync.Register(section, keys)` holds two sections and nothing
more general:
- The core registers section `core` at its `ADDON_LOADED`, once `GC.Settings` exists. The plugin
  registers `spam` after `Spam.Load`. The core never reaches into the plugin's tables.
- **Each key gives:**
  - `type`: boolean, integer, number or enum;
  - its range or allowed values;
  - `get()`: the raw saved value, nil when unset (`rawget`, so an explicit `false` stays `false`;
    for `look.<key>` the nested override, never `Skin.Look`'s effective value);
  - `default`;
  - `set(v)`: the **same setter the slash command uses**. In the plugin, the slash commands'
    validation moves into small setters shared by both.

| Section | Keys |
|---|---|
| `core` | `glass`, `alpha`, `lines`, `classColors`, `plainArrows`, `history`, `tabSize`, `shortChannels`, `urls`, `timestamps`; the `/gchat tune` values as `look.<key>` (`Skin.LOOK`'s keys) |
| `spam` | `cjk`, `repeatWindow` (in **seconds**, as saved; never through the command's minutes conversion), `icon`, `mirror`, `score` |

**Never sent:**
- the household key and anything else in the sync store, and the link's on/off switch;
- `devMode`, and the spam plugin's `debug` and `collect`, which are per-install developer
  switches;
- smart-tab rules (`routes`, `routeNever`): they name the addons installed on that account;
- focus mode's export, the sent history, the hidden-lines and score logs;
- the lists, which have their own send.

### Defaults: "use the sender's choices"

For each key, the sender writes either a value (`V`) or "at its default" (`D`). A key is `D`
when it's unset, **or when it's set to its default** (the plugin doesn't drop such values the
way the core's `ensureDefaults` does), so equal settings always travel the same way.

**`D` on the receiver** means a reset, through one path: call `set(default)` (the receiver's own
default, so the setter's side effects run), then clear the raw value. Passing `nil` to a setter
is never relied on: `SetGlass(nil)` would store `false`, and the numeric setters fail on `nil`.

**`D` means "your shipped default", not "the sender's value".** Two versions with different
defaults end up using different values. That's the repository's policy (a changed default
reaches everyone), so the summary says "settings now follow <account>'s choices", never "match".

## The format (`ST1`)

One payload of kind `ST`, through `GC.AccountSync.Send`, as the lists' `SI` is. One record per
line, tab-separated, format line first:

```
ST1
T	<time>
V	<section>	<key>	<b|i|n|e>	<value>   a value set: boolean (0/1), integer, number, enum
D	<section>	<key>                     at its default
L	...                                    the layout, only with "send layout" (below)
```

**Caps:**
- the payload: 16 KB;
- each line: 256 bytes;
- records in total, skipped ones included: 400;
- layout windows: 1 to `NUM_CHAT_WINDOWS`;
- per window: 64 message groups and 32 channels;
- names: 64 bytes, with no tab, newline or control character.

**Parsing is all-or-nothing for the payload's shape.** Any of these refuses the whole payload:
an unknown format or record letter, a field count or type mark that's wrong, a number that's
non-finite or not an integer where an integer is due, a cap exceeded, or a duplicate key
(including a `V` and a `D` for the same key).

**A single value is skipped, not refused, when this account can't take it:** an unknown section
or key, an out-of-range number, or an unknown enum value. The summary names each one, for example
"1 setting skipped: history 600 is over 500 here; update GlassChat on this account". Two
accounts on different versions then still copy everything else (Codex: refusing the whole
payload would block timestamps over one newer range).

### The layout (`L` records)

The layout is the table `/gchat layout save` writes (`GlassChatDB.layout.windows`, Layout.lua),
flattened:

```
L	W	<i>	<field>	<type>	<value>       a window's plain field
L	M	<i>	<group>                         one message group (an API token)
L	C	<i>	<channel>                       one channel (the client's own name)
```

- **Fields:**
  - `name` (string), `fontSize` (integer);
  - `r`, `g`, `b`, `a` (numbers, 0 to 1);
  - `shown`, `locked`, `uninteractable` (booleans);
  - **`docked` (an integer dock index, omitted when undocked).** It's never written as `false`:
    `Layout.Matches` treats any non-nil `docked` as docked.
  - `width`, `height`, `x`, `y` (numbers), and `point` (an anchor token).
- **Each window is rebuilt and checked as a whole before anything is replaced:**
  - `messages` and `channels` are always tables, empty when there were no `M` or `C` records;
  - colour is all of `r/g/b/a` or none, and position is all of `point/x/y` or none;
  - window 1 carries no position, size, dock, lock or shown fields, since those are Edit Mode's;
    a payload that has them for window 1 is refused.

## Applying, on the receiving account

**Settings:**
1. **Only values that change are applied.** A no-op copy runs no setter, so nothing is trimmed and
   nothing is rescanned for nothing.
2. The old raw values of the changed keys go into `GlassChatDB.settingsUndo` first, "was unset"
   included. Only a received copy replaces the undo, so one undo goes back one copy.
3. Each value goes through `set` (or the reset path), under `pcall`, with failures to `API.Fail`.
   Then one `Chat.Scan` runs.
4. **The summary reports what happened:** "settings now follow <account>'s choices: 3 changed
   (timestamps on, scrollback 2000, …)", plus any skipped values, or "already the same".
   **If a setter failed,** it says so: "2 of 3 applied; 1 failed (/gchat failures)". The undo
   is kept. There's no rollback system.

**The layout is never applied directly. It goes through M2's offer:**
- The received layout replaces `GlassChatDB.layout`.
  - Its `id` is new, allocated as `Layout.Save` does: `layoutRevision`, else the current layout's
    `id`, else 0, plus 1. That invalidates every character's `layoutAnswered`.
  - `from` is the sending account's character name. `guid` is the sender's GUID, which is never
    a character here, so no one is excluded as the saver.
- **The character playing now is offered it straight away** (`Layout.Offer()`), and the others at
  their next login, exactly as M2 does:
  - a character that already matches isn't offered it;
  - an offer left unanswered may come back at a later login;
  - Apply or Not here is remembered.
- **Why not apply directly:** positions only carry over well when both accounts share a
  resolution and UI scale, and `Layout.Apply` never touches the main window's place (Edit Mode).
  Window numbers are copied slot by slot, dock order follows M2's rules (docked tabs keep their
  order), and channels this character isn't in are skipped and reported, never joined. These are
  M2's limits; nothing new.

### Undo

`/gchat settings undo` restores:
- the raw values of the keys the last copy changed, through the same set or reset path;
- the saved layout as it was, with its old `id`, so characters that had answered it stay
  answered. `layoutRevision` is never rewound, so a later save still gets a new `id`.

**It can't bring back what a setter already did.** The undo message says so in one line:
- **`history` lower:** `SetHistory` trims the sent history at once.
- **`lines` lower:** the scrollback beyond the new size is gone (the client's buffer keeps only
  what fits).
- **`classColors`:** turning it on sets `chatClassColorOverride` to `"0"`, and off leaves the CVar
  alone (the existing rule), so undoing an "on" doesn't restore the CVar.
- **`mirror`:** whatever a check already wrote to Blizzard's ignore list stays (below).
- **A layout a character already applied:** its windows stay where they are.

`timestamps` is fine: its setter already restores the receiver's own timestamp CVar.

## `mirror`: the exception to "separate from the lists"

`mirror` is copied (the owner wants Blizzard's ignore list kept in step on every account, S2b).
Receiving `mirror` on, as a value or as the default, runs `Mirror.Check` on this account's **own**
lists. That check:
- adds or removes linked names on this character's Blizzard list;
- unignores a linked name that was removed in Blizzard's UI.

So **a settings copy never copies list contents, but turning mirroring on resumes keeping this
account's lists and Blizzard's in step.** The plan says that, rather than promising that a
settings copy never touches an ignore list.

## Order, and LibAccountSync#17

- **Per kind, as the lists:** the last applied stream id per sender GUID is kept in
  `GlassChatDB.settingsApplied`. That's a GUID and a number, never a key, so it's safe in
  `GlassChat.lua`. An older copy is ignored. It's per sender only: two of your accounts sending
  at once win by arrival order (documented, not resolved).
- **The library's own floor is per (tag, sender GUID)** (r3, `LibAccountSync.lua:1370-1374`). With
  one tag, `GlassChat`, a settings copy (about 1 KB) that completes after starting later raises
  the floor, and a list copy still arriving with a lower sid is dropped before GlassChat sees it.
  The reverse happens too.
  - **Filed as Spotnick2/LibAccountSync#17:** a channel in `Send`, or several instances sharing one
    store.
  - **The stopgap until then:** a send of one kind is refused for `KIND_GAP` (30 s) after a send
    of the other, with "wait a moment: your lists are still on their way". It's on the sender
    only, and it's removed once #17 ships.
- **The sender** comes from the library (Blizzard's sender id), never from the payload. Its
  displayed name gets the same safe-field treatment as the list sync's.

## Where the code lives

- **`SettingsSync.lua`** (core, after `AccountSync.lua` in the TOC):
  - the registry, `Build`, `Parse`, `Apply`, `Undo`;
  - the `/gchat settings` commands;
  - registers `ST` with `GC.AccountSync.On`;
  - registers the `core` section at `ADDON_LOADED`.
- **The plugin** registers `spam` after `Spam.Load`, with setters shared with its slash commands:
  - `icon` runs `ReserveIcons` and `Scan`;
  - `score` runs `ResetMemo`;
  - `mirror` runs `Mirror.Check`;
  - `repeatWindow` takes seconds.

## Edge cases

- **Secrets:**
  - `API.IsSecret` is checked on the payload before parsing;
  - every value read for building or for the undo is checked before any truth test, comparison
    or format;
  - nothing secret is ever built or stored;
  - `settingsUndo` and `settingsApplied` hold only allowlisted values and a GUID.
- **Combat:** settings apply anywhere, since chat frames aren't protected. The layout is only
  offered, and `Layout.Apply` already refuses in combat.
- **Glass off on the receiver, and the received copy turns it on:** `Skin.Refresh` already
  handles both ways.
- **Size:** settings are about 1 KB, and a layout of 10 windows a few KB, under the 16 KB cap.

## Tests (`tests/test_settings_sync.lua`)

- **A round trip** between two loaded copies through the real library (`test_sync`'s `Peer`):
  - every core and spam key arrives;
  - `D` resets a set value through the reset path, `glass` and `classColors` included (not
    `false`);
  - a value set to its default is sent as `D`;
  - `repeatWindow` stays in seconds.
- **Only changes apply:** a no-op copy runs no setter, and in particular doesn't trim the sent
  history.
- **The parser:**
  - each refusal: shape, caps, duplicates, non-finite numbers, non-integers;
  - skips: unknown section or key, out-of-range number, unknown enum value, each reported.
- **A setter that throws:** the summary reports it, and the undo is kept.
- **Undo:** raw values, "was unset" included; the layout's old `id` back, while
  `layoutRevision` isn't rewound.
- **The layout:**
  - rebuilt windows are complete (empty `messages` and `channels`, numeric `docked`, all-or-none
    groups), and window 1 with position fields is refused;
  - `layoutAnswered` is invalidated, the offer shows at once, and a matching character isn't
    offered it;
  - without `layout`, the saved layout is untouched.
- **Never sent:** none of the excluded keys, nor the switch, appears in a built payload.
- **Without the plugin:** the precise refusal, and nothing is sent.
- **The stopgap:** a settings send right after a list send is refused, and allowed after
  `KIND_GAP`. **#17:** once the library has it, a real-library test with a reordered SI and ST
  completion.
- **Mutation-test** the reset path, the only-changes rule, the out-of-range skip, the never-sent
  list and the stopgap.

## Codex review (2026-10-06, consult)

No P1. Every finding is taken, and none adds a framework:
1. **Defaults:** `D` is right, but a setter can't take `nil`. There's now one reset path; a value
   set to its default is sent as `D`; and the summary says "follow" rather than "match", since
   defaults can differ between versions.
2. **The layout:** the offer and M2's main-window safeguards are sound. Added: numeric `docked`,
   tables that are always there, windows checked as a whole, `id` allocation as `Save` does,
   undo never rewinding the counter, and honest offer wording.
3. **Undo:** history trims, lost scrollback, the class-colour CVar and mirror writes aren't
   reversible. Undo is now defined as restoring settings and the saved layout, with those limits
   stated. Only changed values apply, and a setter that fails is reported.
4. **The parser:** shape stays all-or-nothing, with real caps and duplicates refused, but a value
   this account can't take is now skipped and reported, not a refusal of the whole payload.
5. **The registry:** kept small (two sections), with the registration timing set out and the
   plugin's setters shared with its slash commands.
6. **The plugin store:** fine, with precise error causes. `mirror` is the stated exception.
7. **Rules:** no conflict. Received names are checked like the list sync's.
8. **The transport:** the library's floor per (tag, sender) drops the other kind. That's
   LibAccountSync#17, verified in r3's source, with a stopgap here.
