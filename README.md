# Glass Chat

A liquid-glass chat for **World of Warcraft: Forever**: Blizzard's own chat windows on a dark,
see-through glass panel, with class-coloured names, a focus mode to search and copy what was said,
click-to-copy web addresses, and a tab of their own for addons that flood chat. A much smaller
take on Prat-3.0.

> **Alpha.** It is in daily use, but young: expect rough edges, and please report them.

It extends the stock chat and never replaces it: frames, tabs, docking, Edit Mode and the edit
box stay Blizzard's.

## Install

Install **Glass Chat** from [CurseForge](https://www.curseforge.com/projects/1757140) or
[Wago Addons](https://addons.wago.io/addons/5NRg0w63), or unzip a release from
[GitHub](https://github.com/Spotnick2/GlassChat/releases) into the `Interface\AddOns` folder
inside your Forever game folder. Then `/reload`, or start the game. There is nothing to set up.
Every setting is under Esc > Options > AddOns > Glass Chat, or `/gchat options`.

## What it does

**The look.** A glass panel behind each chat window, its tabs and its input box, replacing
Blizzard's background. Readability comes first: the chat stays on a dark panel. The default is
Glass UI's clear glass, with `/gchat body smoked`, `class` or the older dark `chat` look; the
selected tab is gold (`/gchat accent ice` for blue). When nothing is left to read, the panel
fades to a faint veil and wakes when a line arrives or the mouse comes near (`/gchat idle`).
With **Glass UI** installed, the chat can follow its look. The voice buttons beside the chat
become compact glass buttons.

**Focus mode.** Freeze the current window in a glass window (`/gchat focus [text]`, or the
magnifier on the tab strip), then search it, filter by kind of message, source addon and time,
copy it, or export the view to SavedVariables so a file can be read directly. Click an addon's
`[Name]` in chat to see only its lines. It works on the window's newest 1000 messages, a
snapshot rather than a session log.

**Copy.** A Copy button on each tab strip (or `/gchat copy`) opens the window's text without
colours or link codes, already selected, so Ctrl+C copies it. The game doesn't let addons write
the clipboard for you.

**Smart tabs.** An addon that prints 20 lines within a minute is offered its own tab, for the
session or for good, with a clickable offer in chat. Right-click an addon's name for the same
choices. `/gchat tabs` lists the saved rules. While the game loads, every addon's "loaded" line is
ignored, so no tabs open at login.

**Names and links.**
- Class colours on player names (`/gchat colors`).
- Zone channels drop the zone: `[1. General - The Barrens]` becomes `[1. General]`.
- A known player's level before their name, `[60:Name]` (`/gchat levels`).
- Click a web address to copy it (`/gchat urls`).
- A time on every line (`/gchat stamps`).

**History.** Up and Down recall what you sent, with no Alt, and an unfinished whisper stays a
whisper. Each window keeps 1000 lines instead of 128 (`/gchat lines`). `/gchat keep on` brings
back what players said after a `/reload` or the next login, above a "previous session" line: up
to 200 lines per window, a day old at most, never addon or system lines. It is off by default.

**Alerts.** A sound and a flashing taskbar icon when public, guild, party or raid chat mentions
your first name or words you add; every whisper plays the tell sound, not only the first after a
quiet spell. A green `!` beside the chat lists what you missed (`/gchat alert`).

**One layout for every character.** `/gchat layout save` records this character's chat windows;
your other characters get a clickable offer to apply it. The main window's place and size stay
with Edit Mode.

**Spam & Ignore** (a plugin, installed with it). An ignore list by character, not by name, that
covers all player chat; mutes and a spam score for public chat only, which never touch you, your
friends, guild, group or your own characters. It can share its lists, and Glass Chat's settings,
with your other WoW accounts through `/gchat ignore send` and `/gchat settings send`.

## Commands

`/gchat help` lists them all. The settings are also on the options page.

- `/gchat options` - the options page
- `/gchat glass on|off` - the glass panels
- `/gchat body chat|clear|smoked|class`, `/gchat accent ice|gold` - the look
- `/gchat alpha 0-1|reset`, `/gchat shellalpha 0-1`, `/gchat idle 0-1` - darkness
- `/gchat focus [text]`, `/gchat focus from <Addon>`, `/gchat copy`
- `/gchat tabs` - addons with their own tab
- `/gchat keep on|off`, `/gchat lines N`, `/gchat history N`, `/gchat arrows on|off`
- `/gchat colors`, `/gchat channels`, `/gchat urls`, `/gchat levels`, `/gchat stamps` (`on|off`)
- `/gchat alert` - mention alerts
- `/gchat layout` - the saved chat layout
- `/gchat tune` - the panel's edge, shadow and sheen
- `/gchat failures`, `/gchat version` - for bug reports

## Good to know

- **The glass is painted, not real.** The game gives addons no blur, so it doesn't blur what's
  behind it.
- **Some chat can be hidden from addons.** Forever may hide a message's contents from addons
  (a "secret" line). Such a line shows as hidden in focus mode and Copy, and is never searched,
  copied, exported or kept.
- **Focus mode and Copy read the newest 1000 messages** of a window. For a long diagnostic
  session, give the addon its own tab first.
- **Some parts are tested offline only.** The kept chat's Battle.net names, the guild level
  roster and the side buttons' stacking inside Blizzard's alert frame are not yet checked in
  game. Reports welcome.
- **Small on purpose.** No module zoo, no Ace3 and no profiles: Prat's other modules are out.

## Bugs and ideas

Open an issue on [GitHub](https://github.com/Spotnick2/GlassChat/issues). With
`/console scriptErrors 1` on, the error text helps a lot, and `/gchat failures` lists what failed
to build or register.

## Credits

- The design follows [Prat-3.0](https://www.curseforge.com/wow/addons/prat-3-0). Glass Chat is a
  much smaller addon with its own code.
- The glass comes from [LibGlass-1.0](https://github.com/Spotnick2/LibGlass), and the messaging
  between your accounts from [LibAccountSync-1.0](https://github.com/Spotnick2/LibAccountSync),
  both included in the download.

## Development

Lua 5.1, no build step. The tests run with a plain Lua 5.1 and checkouts of LibGlass,
LibAccountSync and ForeverProbe next to this one (`..\LibGlass`, `..\LibAccountSync`,
`..\ForeverProbe`, or `$env:LIBGLASS`, `$env:LIBACCOUNTSYNC`, `$env:FOREVERPROBE`):

```powershell
pwsh tests\run.ps1        # syntax check plus every tests\test_*.lua
pwsh Tools\deploy.ps1     # the addon and its libraries into your AddOns folder
```

## Licence

GPL-3.0; see [LICENSE](LICENSE). LibGlass-1.0, LibAccountSync-1.0, LibStub and ChatThrottleLib
ship under their own terms (listed there).
