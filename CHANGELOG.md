# Changelog

## Unreleased

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
