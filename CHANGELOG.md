# Changelog

## Unreleased

- Smart tabs stay quiet while the game loads: the "loaded" lines every addon prints at login or
  `/reload` no longer open tabs or count toward the "chatty" offer.
- The chat-menu and friends buttons beside the chat are compact glass buttons too, with a gold
  speech bubble and Blizzard's two-person friends symbol, instead of metal frames.
- **Right-click an addon's name in chat** (the coloured `[AltStable]` at the start of its lines)
  for a menu: its own tab for this session, always, or back to the main chat. Also
  `/gchat tabs route <Addon> [always]`.
- Addon authors can ask for a tab with `GlassChat.RequestTab("MyAddon")`: the player is offered
  it once.
- **Copy web addresses:** a web address in chat (`https://...`, `www....`, or a site like
  `wowhead.com/...`) becomes a link. Click it for a small box with the address selected, then
  Ctrl+C. Game links are untouched. `/gchat urls off` turns it off.
- The glass look now comes from LibGlass, a small library shared by the Glass addons and
  included in the download. Nothing changes on screen.
- **Focus mode:** `/gchat focus` (or the magnifier next to the copy icon) freezes the chat window
  in a large glass window so nothing scrolls away while you read.
  - **Search:** as you type, in plain text, with two lines of context around each match if you
    want them.
  - **Filters:** by kind (Say, Party, Guild, Whisper, Channel, System, Addons...) and by the
    addon that wrote a line.
  - **Copy:** Select all, then Ctrl+C.
  - **Export:** writes what's shown to SavedVariables.
  - "N new lines" brings in what arrived since.
- **Smart tabs:** when an addon floods the chat (20 lines in a minute), GlassChat offers it its
  own tab, with clickable choices: for this session, always, or no. Its lines then go to that
  tab instead of the main chat. `/gchat tabs` lists your choices, and `/gchat tabs forget <Addon>`
  drops one.
- **Spam & Ignore** (a plugin, its own entry in the AddOns list):
  - **Muted phrases:** `/gchat mute profession kit` hides public lines containing them. It
    matches whole words, so "kit" doesn't hide "kite". `~phrase` also catches tricks like
    "p.r.o.f.e.s.s.i.o.n".
  - **Repeats:** the same post from the same player is hidden for 5 minutes after it was shown
    (`/gchat spam repeat <minutes>`).
  - **CJK posts:** Chinese, Japanese and Korean posts in public chat are hidden, on by default
    (`/gchat spam cjk off`).
  - **One ignore list for all your characters:** `/gchat ignore First Surname`, `/gchat unignore`,
    `/gchat ignores`, and `/gchat ignore import` for this character's Blizzard list. It covers
    chat and whispers, in guild and group too, and never ignores your own characters.
  - **With AltStable installed, your characters on your other WoW accounts count as yours:**
    they're never ignored, muted or added to Blizzard's ignore list.
  - **Blizzard's ignore list kept in step** on each character, so ignored players can't invite
    or duel you either (`/gchat ignore mirror off` to stop). Removing someone GlassChat added
    from Blizzard's ignore list unignores them everywhere. Names you put on Blizzard's list
    yourself are left alone.
  - **What was hidden:** `/gchat spam log`, or an optional tab-strip icon (`/gchat spam icon on`).
- **Timestamps** (off by default): `/gchat stamps on` puts [HH:MM:SS] on every line, addon output
  and system lines included. It uses Blizzard's own chat timestamps, and turning it off gives
  back what Blizzard's option was set to.
- **One chat layout for every character:** `/gchat layout save` keeps this character's chat
  windows (tabs, chat types, channels, colours, font size). Your other characters get a clickable
  offer to apply it once, or use `/gchat layout apply`. The main window's position stays with
  Edit Mode, and no channel is joined for you.
- The voice buttons beside the chat are compact glass buttons with their gold symbols, instead of
  metal frames.
- **Copy:** a Copy button in each chat window's tab strip (or `/gchat copy`) opens that window's
  text, without colours or link codes and already selected. Press Ctrl+C. The game doesn't let
  addons copy for you.
- A dark, see-through glass panel behind every chat window, its tabs and its input box, replacing
  Blizzard's background. Adjust it with `/gchat alpha 0-1` and `/gchat tune`, or turn it off with `/gchat glass off`.
- Readable tabs: bigger names, the selected tab in gold with an underline, and no fading to near
  invisible when the mouse is away (`/gchat tabsize N`).
- Class-coloured names are kept on (`/gchat colors on|off`).
- Zone channels drop the zone: `[1. General - The Barrens]` becomes `[1. General]`
  (`/gchat channels on|off`).
- A little space between the tabs and the first chat line.
- Each chat window keeps 1000 lines instead of 128 (`/gchat lines N`).
- Up/Down recall what you sent, without Alt. The last 100 lines are kept per character across
  sessions (`/gchat arrows on|off`, `/gchat history N`).
