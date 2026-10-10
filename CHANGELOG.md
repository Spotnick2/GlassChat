# Changelog

## Unreleased

- **Alerts when chat mentions you:** when someone writes your character's first name in public,
  guild, party or raid chat, a sound plays (LFG Bulletin Board's notification sound) and the game
  blinks in the taskbar.
  - **The alerts button:** a new `!` beside the chat, above the chat-menu bubble. It's gold like
    its neighbours, and turns green and pulses with a count when something mentions you. Click it
    to see what did.
  - **Your name:** a player link to another character with your first name doesn't count.
    `/gchat alert name full` waits for your full name.
  - **Your own words:** add them with `/gchat alert add <words>` (one list for all your
    characters).
  - **Settings:**
    - `/gchat alert sound raid|ready|tell|lfg|off` picks the sound (`lfg` is the one LFG
      Bulletin Board plays);
    - `/gchat alert flash off` stops the blinking;
    - `/gchat alert off` turns it all off.
  - **What doesn't alert:** whispers, which already have their sound, your own lines and hidden
    spam.
- **One addon's lines, without the chat in between:** click an addon's name at the start of its
  lines (the coloured `[AltStable]`) to open focus mode with only that addon's lines from that
  window. Select all, then Ctrl+C, to copy them. Right-click the name for the same, as "Show its
  lines", next to the tab choices, or type `/gchat focus from AltStable`. It covers that window's
  recent lines (the newest 1000): for a long session, give the addon its own tab first.
- **Spam & Ignore's icon** (`/gchat spam icon on`) moved from the tab strip to beside the chat,
  just above the alerts button, in the same colours: gold at rest, green and pulsing while hidden
  lines wait. The tab strip gets its room back.

## v0.1.0-beta

- **Player levels in chat:** a player's level now shows before their name, `[60:Name]`, coloured
  by how it compares with yours. Levels come from players GlassChat has seen: you, your group,
  your target or mouseover, your friends and your guild. Anyone else keeps the plain name until
  you target them, mouse over them or group with them. Emotes and Battle.net messages are left
  as they are. `/gchat levels off` turns it off.

- **Spam & Ignore:** an advert reposted every minute is now shown once per repeat window, as
  intended. In a busy channel it could get through a second time a minute or two after being
  shown. Only a flood of more than 2000 different posts within one window can still push it out.

- **Your settings on your other WoW accounts:** `/gchat settings send` copies your GlassChat and
  Spam & Ignore settings (timestamps, glass, scrollback, the spam score and so on) to your other
  accounts online, through the same account link as your lists. `/gchat settings send layout`
  adds your saved chat layout, which each character there is offered once. `/gchat settings undo`
  puts back what a copy changed. It needs the Spam & Ignore plugin.
- **Spam & Ignore: a spam score** for public chat. It looks at a line's shape, never its words, so
  it isn't tied to English: a real-money price (`$5`, `10€`, `$1,000`), a word broken up to slip
  past filters (`g.o.l.d`), or letters from another alphabet disguised as Latin ones (`gоld`) or
  the other way round (`гoлд`), each together with an address, a contact or another of them. Guild recruitment, a stream or a guide link (an
  address and a contact) is never hidden. It starts by **watching**: lines it would hide are still
  shown, and `/gchat spam score` lists them with what it found. `/gchat spam score hide` turns
  hiding on, `off` turns it off, and `/gchat spam test <text>` shows what it finds in a line.
  `/gchat spam collect on` keeps what it saw (and what was hidden) on disk across characters, to help
  tune it; it's off by default.
- Ships LibGlass r4 (the shared glass library; nothing changes on screen).
- Ships LibAccountSync r5: copying your lists to your other accounts hashes about four times
  faster, and the first time you use it, your other account is found at once instead of after
  Battle.net fills in. Your lists and your settings travel separately, so you can send both
  one after the other without either being lost on the way.
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
  - **The same lists on all your WoW accounts:** `/gchat ignore send` copies this account's ignore
    list, pending names and muted phrases to your other accounts online on the same Battle.net
    account, and they replace their lists with it. `/gchat ignore sync` shows which accounts count
    as yours; `/gchat ignore sync off` turns it off. `/gchat ignore sync undo` puts back the lists a
    copy replaced. Empty lists are only sent if you ask (`/gchat ignore send empty`), or when you emptied
    them yourself: removing your last ignore or mute and sending empties the others too. It works without AltStable: the account link
    is LibAccountSync, a small library included in the download, with each account proven yours
    before anything is sent or accepted.
  - **With AltStable installed, your characters on your other WoW accounts count as yours:**
    they're never ignored, muted or added to Blizzard's ignore list.
  - **Blizzard's ignore list kept in step** on each character, so ignored players can't invite
    or duel you either (`/gchat ignore mirror off` to stop). Removing someone GlassChat added
    from Blizzard's ignore list unignores them everywhere. Names you put on Blizzard's list
    yourself are left alone.
  - **What was hidden:** `/gchat spam log`, or an optional icon (`/gchat spam icon on`).
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
