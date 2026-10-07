# Settings sync: your settings on your other WoW accounts (#52)

**Status: plan, to be reviewed before any code.**

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
  3. **Separate from the lists:** `/gchat settings send` never touches ignores or mutes, and
     `/gchat ignore send` never touches settings.

## Commands

- **`/gchat settings send`** copies this account's settings to your other accounts online.
- **`/gchat settings send layout`** sends the settings plus the saved chat layout
  (`/gchat layout save`). With no layout saved, it says so and sends the settings alone.
- **`/gchat settings undo`** puts back the settings, and the layout, that the last copy replaced.
- **Sending is manual, like the lists.** Nothing sends on its own, and receiving never sends
  anything back, so two accounts can't loop.
- **Status and the on/off switch** stay `/gchat ignore sync [status|on|off]`, the one switch for
  the account link. Its help line says that it covers settings too.

## What's sent

**A registry, not a list in one file.** `GC.SettingsSync.Register(section, spec)`:
- The core registers section `core`. The Spam & Ignore plugin registers section `spam` at its
  `ADDON_LOADED`, so the core never reaches into the plugin's tables.
- **A spec lists each key with its type, its range or allowed values, how to read it, and how to
  set it.** Setting always goes through the same setter the slash command uses (`GC.Settings.*`
  for the core), so a received value is clamped and applied exactly as a typed one.

| Section | Keys |
|---|---|
| `core` | `glass`, `alpha`, `lines`, `classColors`, `plainArrows`, `history`, `tabSize`, `shortChannels`, `urls`, `timestamps`; the `/gchat tune` values as `look.<key>` (`Skin.LOOK`'s keys) |
| `spam` | `cjk`, `repeatWindow`, `icon`, `mirror`, `score` |

**Never sent:**
- the household key and anything else in the sync store;
- `devMode`, and the spam plugin's `debug` and `collect`, which are per-install developer
  switches;
- smart-tab rules (`routes`, `routeNever`): they name the addons installed on that account;
- focus mode's export, the sent history, the hidden-lines and score logs;
- the lists, which have their own send.

**"Match" includes defaults.** For each registered key, the sender writes either the value the
player set, or that the key is at its default. The receiver then sets the value, or clears its
own (back to the default). Without this, a receiver that had changed a setting the sender never
touched would keep it, and the accounts wouldn't match.

## The format (`ST1`)

One payload of kind `ST`, through `GC.AccountSync.Send`, as the lists' `SI` is. One record per
line, tab-separated, format line first:

```
ST1
T	<time>
V	<section>	<key>	<b|n|s>	<value>      a value set: boolean (0/1), number, string
D	<section>	<key>                     at its default
L	...                                    the layout, only with "send layout" (below)
```

**Parsing is all-or-nothing**, like `SI1`:
- an unknown format, an unknown record letter, a bad type or value, or a line or count over its
  cap refuses the whole payload;
- an unknown *section or key* is skipped, not refused, so a newer sender's new setting doesn't
  block an older receiver.

**Values:**
- each is checked against the registered spec (type, range, allowed values) before anything is
  set;
- a value out of range is refused, not clamped, because a sender's setter clamps already, so an
  out-of-range value means a bad payload;
- strings are capped at 64 bytes.

### The layout (`L` records)

The layout is the table `/gchat layout save` writes (`GlassChatDB.layout.windows`, Layout.lua),
flattened:

```
L	W	<i>	<field>	<b|n|s>	<value>       a window's plain field: name, fontSize, r/g/b/a, shown,
                                            locked, docked, uninteractable, width, height,
                                            point, x, y
L	M	<i>	<group>                         one of the window's message groups
L	C	<i>	<channel>                       one of its channels (the client's own name)
```

Window numbers run from 1 to `NUM_CHAT_WINDOWS`. The field names and types are an allowlist.

## Applying, on the receiving account

**Settings:**
1. The old values of every received key are saved first, raw (set or not), in
   `GlassChatDB.settingsUndo`. Only a received copy replaces the undo, so one undo goes back one
   copy.
2. Each value goes through its spec's setter, under `pcall`, with failures to `API.Fail`. Then one
   `Chat.Scan` runs: every setting change re-runs the scan anyway.
3. A summary: `settings now match <account>: 3 changed (timestamps on, scrollback 2000, ...)`,
   or `settings already match <account>`.

**The layout is never applied directly. It goes through the existing offer:**
- The received layout replaces `GlassChatDB.layout`, with a new `id` from this account's own
  counter (`layoutRevision`, so an `id` is never reused). `from` is the sending account's
  character name, and `guid` is the sender's GUID.
- **Every character on this account is then offered it** once, through M2's
  `Apply it / Not here` line. The character playing now gets the offer at once (`Layout.Offer()`),
  the others at their next login, as M2 already does.
- **Why not apply directly:** applying moves windows. Positions only carry over well when both
  accounts share a resolution and UI scale, and the main window's place is Edit Mode's, which
  Layout never touches. The offer lets each character decline.
- The old layout goes into the undo too. `/gchat settings undo` puts it back as the saved layout;
  it doesn't move windows a character already applied.

**Order:** the last applied stream id per sender GUID is kept in `GlassChatDB.settingsApplied`,
as `syncApplied` does for the lists. That's a GUID and a number, never a key, so it's safe in
`GlassChat.lua`. An older copy is ignored.

**The sender** comes from the library (Blizzard's sender id), never from the payload.

## Where the code lives

- **`SettingsSync.lua`** (core, after `AccountSync.lua` in the TOC): the registry, `Build`,
  `Parse`, `Apply`, `Undo`, and the `/gchat settings` commands. It registers `ST` with
  `GC.AccountSync.On`.
- **Without the plugin there's no store,** so the library fails closed. `/gchat settings send` then
  says: "settings sync needs the Spam & Ignore plugin (it holds the account link)" (owner: 1a).
- **The plugin** (`SpamIgnore.lua` or `UI.lua`) registers its `spam` section. Its setters
  validate like the slash commands do, and re-run the steps those run: `ReserveIcons` and `Scan`
  for `icon`, `ResetMemo` for `score`, `Mirror.Check` for `mirror`.

## Edge cases

- **Secrets:** the payload comes from the library as a string; `API.IsSecret` is checked first,
  and nothing secret is ever built or stored.
- **Combat:** settings apply anywhere, since chat frames aren't protected. The layout is only
  offered, and `Layout.Apply` already refuses in combat.
- **Glass off on the receiver, and the received copy turns it on:** `Skin.Refresh` already
  handles both ways.
- **Size:** settings are about 1 KB. A layout with 10 windows and their channels is a few KB. The
  32 KB library cap is far off, and the send still checks it, refusing rather than truncating.
- **Two copies at once:** the order rule keeps the newer.

## Tests (`tests/test_settings_sync.lua`)

- **A round trip** between two loaded copies through the real library (the `Peer` helper of
  `test_sync`): every core and spam key arrives, including a key at its default clearing the
  receiver's set value.
- **The parser:** each refusal case, plus unknown sections and keys skipped.
- **Values:** an out-of-range value refuses the payload, and nothing is set.
- **Undo:** puts back raw values, including "was at its default".
- **Never sent:** none of the excluded keys, and no key-shaped value, appears in a built
  payload.
- **The layout:** with `layout`, the receiver's `GlassChatDB.layout` is replaced with a new `id`,
  and the offer shows at once. Without `layout`, the receiver's saved layout is untouched.
- **Without the plugin:** the refusal message, and nothing is sent.
- **Mutation-test** the default-clearing, the out-of-range refusal and the never-sent list.

## For the review

1. Is "match includes defaults" right, or should a receiver keep settings the sender never
   touched?
2. Is going through the layout offer, rather than applying, the right call for windows?
3. Is the registry worth it for two sections, or should the core simply know the plugin's keys?
   The registry keeps the core out of the plugin's tables, as `RegisterSlash` does.
4. Should unknown keys be skipped (forward compatibility) or refuse the payload?
